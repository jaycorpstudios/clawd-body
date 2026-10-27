#include "settings_store.h"

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

/* Own namespace: NimBLE keeps its bonds in "nimble_bond" and nothing here touches them. */
#define NAMESPACE "buddy_ui"
#define KEY "settings"
#define VERSION 1

static const char *TAG = "settings";

typedef struct {
    uint8_t version, sound, volume, brightness;
} stored_t;

static bool ready(void)
{
    static int state;
    if (!state) state = nvs_flash_init() == ESP_OK ? 1 : -1;
    return state > 0;
}

bool settings_store_load(bm_settings_t *out)
{
    nvs_handle_t h;
    if (!ready() || nvs_open(NAMESPACE, NVS_READONLY, &h) != ESP_OK) return false;
    stored_t st;
    size_t len = sizeof(st);
    esp_err_t err = nvs_get_blob(h, KEY, &st, &len);
    nvs_close(h);
    if (err != ESP_OK || len != sizeof(st) || st.version != VERSION) return false;
    *out = (bm_settings_t){.sound = st.sound != 0, .volume = st.volume, .brightness = st.brightness};
    return true;
}

bool settings_store_save(const bm_settings_t *s)
{
    nvs_handle_t h;
    if (!ready() || nvs_open(NAMESPACE, NVS_READWRITE, &h) != ESP_OK) return false;
    stored_t st = {VERSION, s->sound, s->volume, s->brightness};
    esp_err_t err = nvs_set_blob(h, KEY, &st, sizeof(st));
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    if (err != ESP_OK) ESP_LOGW(TAG, "save failed (%d)", err);
    return err == ESP_OK;
}
