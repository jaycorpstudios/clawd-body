#include "audio.h"

#include "bsp/esp-bsp.h"
#include "esp_codec_dev.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "bm_synth.h"

#define QUEUE_LEN 4
#define MAX_SOUND_S 1
#define CLOSE_AFTER_MS 2000
#define TASK_STACK 4096

static const char *TAG = "audio";
static QueueHandle_t queue;
static esp_codec_dev_handle_t codec;
static volatile int out_volume;
static float *mix;
static int16_t *pcm;

static void audio_task(void *arg)
{
    (void)arg;
    const size_t cap = BM_SYNTH_RATE * MAX_SOUND_S;
    bool open = false;
    for (;;) {
        bm_sound_t snd;
        if (xQueueReceive(queue, &snd, open ? pdMS_TO_TICKS(CLOSE_AFTER_MS) : portMAX_DELAY) != pdTRUE) {
            esp_codec_dev_close(codec);
            open = false;
            continue;
        }
        size_t n = bm_synth_render(snd, BM_SYNTH_RATE, mix, pcm, cap);
        if (!n) continue;
        if (!open) {
            esp_codec_dev_sample_info_t fs = {.bits_per_sample = 16, .channel = 1, .sample_rate = BM_SYNTH_RATE};
            if (esp_codec_dev_open(codec, &fs) != ESP_CODEC_DEV_OK) {
                ESP_LOGW(TAG, "codec open failed");
                continue;
            }
            esp_codec_dev_set_out_vol(codec, out_volume);
            open = true;
        }
        esp_codec_dev_set_out_vol(codec, out_volume);
        int64_t t0 = esp_log_timestamp();
        int err = esp_codec_dev_write(codec, pcm, (int)(n * sizeof(int16_t)));
        ESP_LOGI(TAG, "sound %d: %u samples in %lld ms at volume %d (%d)", snd, (unsigned)n,
                 (long long)(esp_log_timestamp() - t0), out_volume, err);
    }
}

bool audio_init(int volume)
{
    const size_t cap = BM_SYNTH_RATE * MAX_SOUND_S;
    mix = heap_caps_malloc(cap * sizeof(float), MALLOC_CAP_SPIRAM);
    pcm = heap_caps_malloc(cap * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    codec = bsp_audio_codec_speaker_init();
    queue = xQueueCreate(QUEUE_LEN, sizeof(bm_sound_t));
    if (!mix || !pcm || !codec || !queue) {
        ESP_LOGE(TAG, "init failed");
        return false;
    }
    out_volume = volume;
    if (xTaskCreate(audio_task, "audio", TASK_STACK, NULL, 4, NULL) != pdPASS) return false;
    ESP_LOGI(TAG, "ES8311 ready, volume %d", volume);
    return true;
}

void audio_set_volume(int volume)
{
    out_volume = volume;
}

void audio_play(bm_sound_t snd)
{
    if (queue) xQueueSend(queue, &snd, 0);
}
