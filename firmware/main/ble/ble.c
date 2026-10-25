#include "ble.h"

#include <string.h>

#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/message_buffer.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "nvs_flash.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "bm_frame.h"

#define EVENTS_BYTES (2 * BM_FRAME_MAX_MESSAGE + 4096)
#define SECURE_WITHIN_MS 10000
#define PAIRING_SECURE_WITHIN_MS 45000
#define SLOW_ADV_ITVL BLE_GAP_ADV_ITVL_MS(1000)
#define MAX_ATT_VALUE 514

typedef struct {
    volatile bool used;
    volatile bool secure;
    volatile bool subscribed;
    volatile uint16_t mtu;
    uint16_t handle;
    bool pairing;
    uint32_t opened_ms;
    uint8_t tx_seq;
    bm_reasm_t *rx;
} link_t;

void ble_store_config_init(void);

static const char *TAG = "ble";
static const ble_uuid128_t SVC_UUID = BLE_UUID128_INIT(0xeb, 0x61, 0xc9, 0x26, 0xa7, 0x83, 0xab, 0xaa, 0xc1, 0x49, 0x36,
                                                       0x8b, 0x83, 0x92, 0x36, 0xb7);
static const ble_uuid128_t RX_UUID = BLE_UUID128_INIT(0x23, 0x36, 0xbf, 0x38, 0x73, 0x1f, 0x60, 0x99, 0xaf, 0x48, 0x12,
                                                      0x36, 0x75, 0xd6, 0x7b, 0xff);
static const ble_uuid128_t TX_UUID = BLE_UUID128_INIT(0x9f, 0xfc, 0x44, 0x9c, 0x58, 0x21, 0x4d, 0x9c, 0xc8, 0x42, 0xdf,
                                                      0x85, 0x0d, 0x87, 0x76, 0x20);

static link_t links[BLE_LINKS];
static MessageBufferHandle_t events;
static StaticMessageBuffer_t events_struct;
static uint16_t tx_handle;
static uint8_t own_addr_type;
static volatile bool pairing_mode;
static volatile bool synced;
static char event_scratch[sizeof(ble_ev_t) + BM_FRAME_MAX_MESSAGE];

static int gap_event(struct ble_gap_event *event, void *arg);

static uint32_t now_ms(void)
{
    return (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
}

static void post(ble_ev_kind_t kind, int link, uint32_t value, const char *payload, size_t len)
{
    ble_ev_t ev = {.kind = (uint8_t)kind, .link = (uint8_t)link, .value = value};
    memcpy(event_scratch, &ev, sizeof(ev));
    if (len) memcpy(event_scratch + sizeof(ev), payload, len);
    if (xMessageBufferSend(events, event_scratch, sizeof(ev) + len, 0) == 0)
        ESP_LOGW(TAG, "event %d dropped: queue full", kind);
}

static link_t *find(uint16_t handle, int *index)
{
    for (int i = 0; i < BLE_LINKS; i++) {
        if (links[i].used && links[i].handle == handle) {
            if (index) *index = i;
            return &links[i];
        }
    }
    return NULL;
}

static int free_link(void)
{
    for (int i = 0; i < BLE_LINKS; i++)
        if (!links[i].used) return i;
    return -1;
}

static void advertise(void)
{
    if (!synced) return;
    ble_gap_adv_stop();
    if (free_link() < 0) return;

    bool open = pairing_mode;
    struct ble_hs_adv_fields fields = {
        .flags = (uint8_t)((open ? BLE_HS_ADV_F_DISC_GEN : 0) | BLE_HS_ADV_F_BREDR_UNSUP),
        .uuids128 = &SVC_UUID,
        .num_uuids128 = 1,
        .uuids128_is_complete = 1,
    };
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc == 0) {
        const char *name = ble_svc_gap_device_name();
        struct ble_hs_adv_fields rsp = {
            .name = (const uint8_t *)name, .name_len = (uint8_t)strlen(name), .name_is_complete = 1};
        rc = ble_gap_adv_rsp_set_fields(&rsp);
    }
    struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = open ? BLE_GAP_DISC_MODE_GEN : BLE_GAP_DISC_MODE_NON,
        .itvl_min = open ? BLE_GAP_ADV_FAST_INTERVAL1_MIN : SLOW_ADV_ITVL,
        .itvl_max = open ? BLE_GAP_ADV_FAST_INTERVAL1_MAX : SLOW_ADV_ITVL,
    };
    if (rc == 0) rc = ble_gap_adv_start(own_addr_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL);
    if (rc != 0) ESP_LOGE(TAG, "advertising failed: %d", rc);
}

static void drop_link(int i)
{
    link_t *l = &links[i];
    if (l->secure) post(BLE_EV_CLOSE, i, 0, NULL, 0);
    else if (l->pairing) post(BLE_EV_PAIR_FAILED, i, 0, NULL, 0);
    bm_reasm_t *rx = l->rx;
    memset(l, 0, sizeof(*l));
    l->rx = rx;
    bm_reasm_reset(rx);
}

static void on_security(uint16_t handle, int status)
{
    int i;
    link_t *l = find(handle, &i);
    if (!l) return;
    struct ble_gap_conn_desc desc;
    bool ok = status == 0 && ble_gap_conn_find(handle, &desc) == 0 && desc.sec_state.encrypted &&
              desc.sec_state.authenticated && desc.sec_state.bonded;
    if (!ok) {
        ESP_LOGW(TAG, "link %d: security failed (%d)", i, status);
        ble_gap_terminate(handle, BLE_ERR_AUTH_FAIL);
        return;
    }
    if (l->secure) return;
    l->secure = true;
    if (l->pairing) {
        l->pairing = false;
        post(BLE_EV_PAIRED, i, 0, NULL, 0);
    }
    post(BLE_EV_OPEN, i, 0, NULL, 0);
}

static void on_passkey(uint16_t handle, const struct ble_gap_passkey_params *params)
{
    int i;
    link_t *l = find(handle, &i);
    if (!l || !pairing_mode || params->action != BLE_SM_IOACT_DISP) {
        ble_gap_terminate(handle, BLE_ERR_AUTH_FAIL);
        return;
    }
    struct ble_sm_io io = {.action = BLE_SM_IOACT_DISP, .passkey = esp_random() % 1000000};
    if (ble_sm_inject_io(handle, &io) != 0) {
        ble_gap_terminate(handle, BLE_ERR_AUTH_FAIL);
        return;
    }
    l->pairing = true;
    post(BLE_EV_PASSKEY, i, io.passkey, NULL, 0);
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    int i;
    link_t *l;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status != 0) {
            advertise();
            return 0;
        }
        i = free_link();
        if (i < 0) {
            ble_gap_terminate(event->connect.conn_handle, BLE_ERR_CONN_LIMIT);
            return 0;
        }
        links[i].used = true;
        links[i].handle = event->connect.conn_handle;
        links[i].mtu = BLE_ATT_MTU_DFLT;
        links[i].opened_ms = now_ms();
        bm_reasm_reset(links[i].rx);
        ble_gap_security_initiate(event->connect.conn_handle);
        advertise();
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        if (find(event->disconnect.conn.conn_handle, &i)) drop_link(i);
        advertise();
        return 0;

    case BLE_GAP_EVENT_ENC_CHANGE:
        on_security(event->enc_change.conn_handle, event->enc_change.status);
        return 0;

    case BLE_GAP_EVENT_PASSKEY_ACTION:
        on_passkey(event->passkey.conn_handle, &event->passkey.params);
        return 0;

    case BLE_GAP_EVENT_REPEAT_PAIRING: {
        struct ble_gap_conn_desc desc;
        if (!pairing_mode || ble_gap_conn_find(event->repeat_pairing.conn_handle, &desc) != 0)
            return BLE_GAP_REPEAT_PAIRING_IGNORE;
        ble_store_util_delete_peer(&desc.peer_id_addr);
        return BLE_GAP_REPEAT_PAIRING_RETRY;
    }

    case BLE_GAP_EVENT_SUBSCRIBE:
        l = find(event->subscribe.conn_handle, NULL);
        if (l && event->subscribe.attr_handle == tx_handle) l->subscribed = event->subscribe.cur_notify;
        return 0;

    case BLE_GAP_EVENT_MTU:
        l = find(event->mtu.conn_handle, NULL);
        if (l) l->mtu = event->mtu.value;
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        return 0;
    }
    return 0;
}

static int rx_access(uint16_t handle, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)attr;
    (void)arg;
    static uint8_t frame[MAX_ATT_VALUE];
    int i;
    link_t *l = find(handle, &i);
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    if (!l || !l->secure) return BLE_ATT_ERR_INSUFFICIENT_AUTHEN;
    uint16_t n = OS_MBUF_PKTLEN(ctxt->om);
    if (n > sizeof(frame) || ble_hs_mbuf_to_flat(ctxt->om, frame, sizeof(frame), &n) != 0)
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    size_t len;
    const char *msg = bm_reasm_push(l->rx, frame, n, &len);
    if (msg) post(BLE_EV_MESSAGE, i, 0, msg, len);
    return 0;
}

static int tx_access(uint16_t handle, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)handle;
    (void)attr;
    (void)ctxt;
    (void)arg;
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static const struct ble_gatt_svc_def services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &SVC_UUID.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {
                    .uuid = &RX_UUID.u,
                    .access_cb = rx_access,
                    .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC | BLE_GATT_CHR_F_WRITE_AUTHEN,
                },
                {
                    .uuid = &TX_UUID.u,
                    .access_cb = tx_access,
                    .val_handle = &tx_handle,
                    .flags = BLE_GATT_CHR_F_NOTIFY | BLE_GATT_CHR_F_NOTIFY_INDICATE_ENC |
                             BLE_GATT_CHR_F_NOTIFY_INDICATE_AUTHEN,
                },
                {0},
            },
    },
    {0},
};

static void on_sync(void)
{
    if (ble_hs_util_ensure_addr(0) != 0 || ble_hs_id_infer_auto(0, &own_addr_type) != 0) {
        ESP_LOGE(TAG, "no identity address");
        return;
    }
    synced = true;
    advertise();
}

static void on_reset(int reason)
{
    synced = false;
    ESP_LOGE(TAG, "host reset: %d", reason);
}

static void host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

bool ble_start(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    uint8_t *storage = heap_caps_malloc(EVENTS_BYTES, MALLOC_CAP_SPIRAM);
    events = storage ? xMessageBufferCreateStatic(EVENTS_BYTES, storage, &events_struct) : NULL;
    for (int i = 0; i < BLE_LINKS; i++) {
        links[i].rx = heap_caps_malloc(sizeof(bm_reasm_t), MALLOC_CAP_SPIRAM);
        if (!links[i].rx) return false;
        bm_reasm_reset(links[i].rx);
    }
    if (!events || nimble_port_init() != ESP_OK) return false;

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_DISP_ONLY;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_mitm = 1;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_sc_only = 1;
    ble_hs_cfg.sm_our_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;

    ble_svc_gap_init();
    ble_svc_gatt_init();
    if (ble_gatts_count_cfg(services) != 0 || ble_gatts_add_svcs(services) != 0) return false;
    ble_store_config_init();
    nimble_port_freertos_init(host_task);
    return true;
}

size_t ble_poll(ble_ev_t *ev, char *payload, size_t cap)
{
    static char buf[sizeof(ble_ev_t) + BM_FRAME_MAX_MESSAGE];
    size_t n = events ? xMessageBufferReceive(events, buf, sizeof(buf), 0) : 0;
    if (n < sizeof(*ev)) return 0;
    memcpy(ev, buf, sizeof(*ev));
    size_t len = n - sizeof(*ev);
    if (len >= cap) len = cap - 1;
    memcpy(payload, buf + sizeof(*ev), len);
    payload[len] = '\0';
    return len + 1;
}

void ble_set_pairing(bool on)
{
    if (pairing_mode == on) return;
    pairing_mode = on;
    advertise();
}

void ble_tick(void)
{
    uint32_t t = now_ms();
    for (int i = 0; i < BLE_LINKS; i++) {
        link_t *l = &links[i];
        uint32_t limit = pairing_mode ? PAIRING_SECURE_WITHIN_MS : SECURE_WITHIN_MS;
        if (l->used && !l->secure && t - l->opened_ms > limit) ble_gap_terminate(l->handle, BLE_ERR_REM_USER_CONN_TERM);
    }
}

bool ble_send(int link, const char *json, size_t len)
{
    link_t *l = &links[link];
    if (!l->used || !l->secure || !l->subscribed) return false;
    uint8_t frame[MAX_ATT_VALUE];
    size_t frame_size = l->mtu - 3u < sizeof(frame) ? l->mtu - 3u : sizeof(frame);
    int count;
    if (bm_frame_count(len, frame_size, &count) != BM_FRAME_OK) return false;
    for (int i = 0; i < count; i++) {
        size_t n = bm_frame_build((const uint8_t *)json, len, l->tx_seq, frame_size, i, frame);
        struct os_mbuf *om = ble_hs_mbuf_from_flat(frame, (uint16_t)n);
        if (!om || ble_gatts_notify_custom(l->handle, tx_handle, om) != 0) {
            ESP_LOGW(TAG, "link %d: notify failed at frame %d/%d", link, i, count);
            l->tx_seq++;
            return false;
        }
    }
    l->tx_seq++;
    return true;
}
