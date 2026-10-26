#include "esp_heap_caps.h"
#include "lvgl.h"

// Objects and styles go to PSRAM to leave internal RAM for the panel's DMA bounce buffer
// and the BT controller; render-time buffers stay internal, PSRAM halves the frame rate.
#define SMALL_ALLOC 1024

static uint32_t first_caps(size_t size)
{
    return size < SMALL_ALLOC ? MALLOC_CAP_SPIRAM : MALLOC_CAP_INTERNAL;
}

static uint32_t fallback_caps(size_t size)
{
    return size < SMALL_ALLOC ? MALLOC_CAP_INTERNAL : MALLOC_CAP_SPIRAM;
}

void lv_mem_init(void)
{
}

void lv_mem_deinit(void)
{
}

lv_mem_pool_t lv_mem_add_pool(void *mem, size_t bytes)
{
    LV_UNUSED(mem);
    LV_UNUSED(bytes);
    return NULL;
}

void lv_mem_remove_pool(lv_mem_pool_t pool)
{
    LV_UNUSED(pool);
}

void *lv_malloc_core(size_t size)
{
    return heap_caps_malloc_prefer(size, 2, first_caps(size), fallback_caps(size));
}

void *lv_realloc_core(void *p, size_t new_size)
{
    return heap_caps_realloc_prefer(p, new_size, 2, first_caps(new_size), fallback_caps(new_size));
}

void lv_free_core(void *p)
{
    heap_caps_free(p);
}

void lv_mem_monitor_core(lv_mem_monitor_t *mon_p)
{
    LV_UNUSED(mon_p);
}

lv_result_t lv_mem_test_core(void)
{
    return LV_RESULT_OK;
}
