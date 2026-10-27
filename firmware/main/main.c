#include "bsp/esp-bsp.h"
#include "bsp/display.h"
#include "driver/gpio.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_memory_utils.h"
#include "esp_random.h"
#include "lvgl.h"

#include "ble/ble.h"
#include "bm.h"
#include "bm_conn.h"
#include "bm_frame.h"
#include "demo.h"
#include "hw/power.h"
#include "hw/audio.h"
#include "hw/ext_rtc.h"
#include "settings_store.h"
#include "ui/ui.h"

#define SIDE_BUTTON GPIO_NUM_18
#define IO_PERIOD_MS 20
#define HEAP_LOG_MS 60000
#define POWER_POLL_MS 5000
#define BATTERY_LOG_MS 60000
#define SETTINGS_SAVE_MS 2000

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
        else ESP_LOGI(TAG, "link %d: rx %u bytes", ev->link, (unsigned)(len - 1));
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

static void sync_rtc(void)
{
    static uint32_t written;
    if (model->clock_synced == written) return;
    written = model->clock_synced;
    int64_t unix_s = bm_wall_ms(model, lv_tick_get()) / 1000;
    if (ext_rtc_write(unix_s)) ESP_LOGI(TAG, "rtc set to %lld", (long long)unix_s);
}

static void power_cb(lv_timer_t *t)
{
    (void)t;
    power_state_t p;
    if (!power_read(&p)) return;
    static power_state_t last;
    static uint32_t logged_at;
    uint32_t now = lv_tick_get();
    bool changed = p.battery != last.battery || p.usb != last.usb || p.charging != last.charging || p.pct != last.pct;
    if (changed || now - logged_at >= BATTERY_LOG_MS) {
        ESP_LOGI(TAG, "battery %s %u%% %u mV, usb %d, charging %d, up %u min, sleeping %d", p.battery ? "present" : "absent",
                 p.pct, p.mv, p.usb, p.charging, (unsigned)(now / 60000), model->sleeping);
        logged_at = now;
    }
    last = p;
    if (p.battery) bm_set_battery(model, p.pct, p.charging, now);
}

static void follow_brightness(void)
{
    static int applied = -1;
    int awake = bm_alarm_ringing(model) ? 100 : model->settings.brightness;
    int pct = model->sleeping && CONFIG_BUDDY_SLEEP_BRIGHTNESS < awake ? CONFIG_BUDDY_SLEEP_BRIGHTNESS : awake;
    if (pct == applied) return;
    applied = pct;
    if (bsp_display_brightness_set(pct) == ESP_OK) ESP_LOGI(TAG, "brightness %d%%", pct);
}

static uint32_t settings_saved_rev;

static void follow_settings(uint32_t now)
{
    static uint32_t applied_rev, changed_at;
    const bm_settings_t *s = &model->settings;
    if (model->settings_rev != applied_rev) {
        applied_rev = model->settings_rev;
        changed_at = now;
        ESP_LOGI(TAG, "settings sound %d, volume %u, brightness %u%%", s->sound, s->volume, s->brightness);
    }
    if (settings_saved_rev != applied_rev && now - changed_at >= SETTINGS_SAVE_MS) {
        settings_saved_rev = applied_rev;
        if (settings_store_save(s)) ESP_LOGI(TAG, "settings saved");
    }
}

static void follow_volume(void)
{
    static int applied = -1;
    int volume = model->settings.volume;
    if (bm_alarm_ringing(model) && volume < BM_ALARM_MIN_VOLUME) volume = BM_ALARM_MIN_VOLUME;
    if (volume == applied) return;
    applied = volume;
    audio_set_volume(volume);
}

static void follow_faces(void)
{
    static uint32_t seen_rev;
    if (model->faces_rev == seen_rev) return;
    seen_rev = model->faces_rev;
    for (int i = 0; i < BM_MAX_HOSTS; i++) {
        const bm_host_t *h = &model->hosts[i];
        if (h->used) ESP_LOGI(TAG, "face host %d %s %s", i, h->name, h->has_face ? h->face.hash : "none");
    }
}

static void follow_cover(void)
{
    static uint32_t seen_rev;
    if (model->covers_rev == seen_rev) return;
    seen_rev = model->covers_rev;
    ESP_LOGI(TAG, "cover %s %ux%u", model->cover.hash, model->cover.w, model->cover.h);
}

static void io_cb(lv_timer_t *t)
{
    (void)t;
    uint32_t now = lv_tick_get();
    poll_button(now);
    pump_link(now);
    follow_volume();
    bm_sound_t snd;
    while (bm_sound_pop(model, &snd))
        if (model->settings.sound) audio_play(snd);
    sync_rtc();
    follow_settings(now);
    follow_faces();
    follow_cover();
    follow_brightness();
}

static void heap_log_cb(lv_timer_t *t)
{
    (void)t;
    ESP_LOGI(TAG, "heap internal %u (min %u), psram %u (min %u)",
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL),
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
             (unsigned)heap_caps_get_minimum_free_size(MALLOC_CAP_SPIRAM));
}

void app_main(void)
{
    bsp_display_start();
    model = heap_caps_calloc_prefer(1, sizeof(*model), 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    bm_config_t cfg = {.random32 = esp_random32, .tz_offset_min = CONFIG_BUDDY_TZ_OFFSET_MIN};

    bsp_display_lock(-1);
    uint32_t now = lv_tick_get();
    bm_init(model, &cfg, now);
    bm_settings_t saved;
    if (settings_store_load(&saved)) bm_settings_load(model, &saved);
    settings_saved_rev = model->settings_rev;
    ui_init(model);
    follow_brightness();
    int64_t rtc_s;
    if (ext_rtc_init() && ext_rtc_read(&rtc_s)) {
        bm_clock_from_rtc(model, rtc_s, now);
        ESP_LOGI(TAG, "clock from rtc %lld", (long long)rtc_s);
    }
#if CONFIG_BUDDY_DEMO
    demo_start(&demo, model, esp_random32, NULL, now);
#else
    if (!ble_start()) ESP_LOGE(TAG, "BLE did not start");
    if (power_init()) {
        power_cb(NULL);
        lv_timer_create(power_cb, POWER_POLL_MS, NULL);
    }
#endif
    audio_init(model->settings.volume);
    side_button_init();
    lv_timer_create(io_cb, IO_PERIOD_MS, NULL);
    lv_timer_create(heap_log_cb, HEAP_LOG_MS, NULL);
    bsp_display_unlock();
    ESP_LOGI(TAG, "model %u bytes in %s", (unsigned)sizeof(*model),
             esp_ptr_external_ram(model) ? "psram" : "internal");
    heap_log_cb(NULL);
}
