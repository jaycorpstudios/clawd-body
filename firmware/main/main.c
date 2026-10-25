#include "bsp/esp-bsp.h"
#include "bsp/display.h"
#include "driver/gpio.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_random.h"
#include "lvgl.h"

#include "bm.h"
#include "demo.h"
#include "ui/ui.h"

#define SIDE_BUTTON GPIO_NUM_18
#define IO_PERIOD_MS 20

static const char *TAG = "buddy";
static bm_model_t *model;
static demo_t demo;

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

static void io_cb(lv_timer_t *t)
{
    (void)t;
    static bool pressed;
    static uint8_t stable;
    uint32_t now = lv_tick_get();
    bool level_pressed = gpio_get_level(SIDE_BUTTON) == 0;
    stable = level_pressed == pressed ? 0 : stable + 1;
    if (stable >= 2) {
        pressed = level_pressed;
        stable = 0;
        bm_button(model, pressed, now);
    }

    demo_tick(&demo, now);

    bm_out_t out;
    while (bm_out_pop(model, &out)) {
        ESP_LOGI(TAG, "out[%02x] %s", out.hosts, out.json);
        demo_on_outgoing(&demo, &out, now);
    }
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
    demo_start(&demo, model, esp_random32, NULL, now);
    side_button_init();
    lv_timer_create(io_cb, IO_PERIOD_MS, NULL);
    bsp_display_unlock();
    ESP_LOGI(TAG, "model %u bytes", (unsigned)sizeof(*model));
}
