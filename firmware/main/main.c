#include "bsp/esp-bsp.h"
#include "bsp/display.h"
#include "driver/gpio.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_random.h"
#include "lvgl.h"

#include "ble/ble.h"
#include "bm.h"
#include "bm_conn.h"
#include "bm_frame.h"
#include "demo.h"
#include "ui/ui.h"

#define SIDE_BUTTON GPIO_NUM_18
#define IO_PERIOD_MS 20

static const char *TAG = "buddy";
static bm_model_t *model;
#if CONFIG_BUDDY_DEMO
static demo_t demo;
#else
static bm_conn_t conns[BLE_LINKS];
static char inbound[BM_FRAME_MAX_MESSAGE + 1];
#endif

static uint32_t esp_random32(void *ctx)
{
    (void)ctx;
    return esp_random();
}

static void side_button_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << SIDE_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&cfg));
}

static void poll_button(uint32_t now)
{
    static bool pressed;
    static uint8_t stable;
    bool level_pressed = gpio_get_level(SIDE_BUTTON) == 0;
    stable = level_pressed == pressed ? 0 : stable + 1;
    if (stable >= 2) {
        pressed = level_pressed;
        stable = 0;
        bm_button(model, pressed, now);
    }
}

#if CONFIG_BUDDY_DEMO
static void pump_link(uint32_t now)
{
    demo_tick(&demo, now);
    bm_out_t out;
    while (bm_out_pop(model, &out)) {
        ESP_LOGI(TAG, "out[%02x] %s", out.hosts, out.json);
        demo_on_outgoing(&demo, &out, now);
    }
}
#else
static void on_ble_event(const ble_ev_t *ev, size_t len, uint32_t now)
{
    bm_conn_t *c = &conns[ev->link];
    switch (ev->kind) {
    case BLE_EV_OPEN: bm_conn_open(c); break;
    case BLE_EV_CLOSE: bm_conn_close(model, c, now); break;
    case BLE_EV_PASSKEY: bm_pairing_passkey(model, ev->value, now); break;
    case BLE_EV_PAIRED: bm_pairing_end(model, BM_PAIR_OK, now); break;
    case BLE_EV_PAIR_FAILED: bm_pairing_end(model, BM_PAIR_FAILED, now); break;
    case BLE_EV_MESSAGE: {
        bm_err_t err = bm_conn_deliver(model, c, inbound, len - 1, now);
        if (err != BM_OK) ESP_LOGW(TAG, "link %d: message rejected (%d)", ev->link, err);
        break;
    }
    }
}

static void pump_link(uint32_t now)
{
    ble_ev_t ev;
    size_t len;
    while ((len = ble_poll(&ev, inbound, sizeof(inbound))) > 0) on_ble_event(&ev, len, now);
    ble_set_pairing(model->pairing);
    ble_tick();

    bm_out_t out;
    while (bm_out_pop(model, &out)) {
        for (int i = 0; i < BLE_LINKS; i++)
            if (bm_conn_wants(&conns[i], &out)) ble_send(i, out.json, strlen(out.json));
    }
}
#endif

static void io_cb(lv_timer_t *t)
{
    (void)t;
    uint32_t now = lv_tick_get();
    poll_button(now);
    pump_link(now);
    bm_sound_t snd;
    while (bm_sound_pop(model, &snd)) ESP_LOGD(TAG, "sound %d", snd);
}

void app_main(void)
{
    bsp_display_start();
    model = heap_caps_calloc_prefer(1, sizeof(*model), 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    bm_config_t cfg = {.random32 = esp_random32, .tz_offset_min = CONFIG_BUDDY_TZ_OFFSET_MIN};

    bsp_display_lock(-1);
    uint32_t now = lv_tick_get();
    bm_init(model, &cfg, now);
    ui_init(model);
#if CONFIG_BUDDY_DEMO
    demo_start(&demo, model, esp_random32, NULL, now);
#else
    if (!ble_start()) ESP_LOGE(TAG, "BLE did not start");
#endif
    side_button_init();
    lv_timer_create(io_cb, IO_PERIOD_MS, NULL);
    bsp_display_unlock();
    ESP_LOGI(TAG, "model %u bytes", (unsigned)sizeof(*model));
}
