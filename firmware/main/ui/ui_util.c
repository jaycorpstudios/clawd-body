#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "ui_priv.h"

lv_color_t ui_hex(uint32_t rgb)
{
    return lv_color_hex(rgb);
}

lv_obj_t *ui_box(lv_obj_t *parent)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_scrollable(o, false);
    lv_obj_set_clickable(o, false);
    return o;
}

lv_obj_t *ui_label(lv_obj_t *parent, const lv_font_t *font, uint32_t color, const char *text)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, ui_hex(color), 0);
    lv_label_set_text(l, text ? text : "");
    return l;
}

lv_obj_t *ui_track(lv_obj_t *parent, int32_t w, uint32_t color)
{
    lv_obj_t *track = ui_box(parent);
    lv_obj_set_size(track, w, 9);
    lv_obj_set_style_radius(track, 5, 0);
    lv_obj_set_style_bg_color(track, ui_hex(C_TRACK), 0);
    lv_obj_set_style_bg_opa(track, LV_OPA_COVER, 0);
    lv_obj_set_style_clip_corner(track, true, 0);
    lv_obj_t *fill = ui_box(track);
    lv_obj_set_height(fill, LV_PCT(100));
    lv_obj_set_width(fill, 0);
    lv_obj_set_style_radius(fill, 5, 0);
    lv_obj_set_style_bg_color(fill, ui_hex(color), 0);
    lv_obj_set_style_bg_opa(fill, LV_OPA_COVER, 0);
    return track;
}

void ui_track_set(lv_obj_t *track, int pct)
{
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    lv_obj_set_width(lv_obj_get_child(track, 0), LV_PCT(pct));
}

typedef struct {
    bm_tap_t target;
    int arg;
} tap_t;

static void tap_cb(lv_event_t *e)
{
    const tap_t *tap = lv_event_get_user_data(e);
    bm_tap(ui.m, tap->target, tap->arg, lv_tick_get());
}

static void free_cb(lv_event_t *e)
{
    free(lv_event_get_user_data(e));
}

void ui_on_tap(lv_obj_t *obj, bm_tap_t target, int arg)
{
    tap_t *tap = malloc(sizeof(*tap));
    tap->target = target;
    tap->arg = arg;
    lv_obj_set_clickable(obj, true);
    lv_obj_add_event_cb(obj, tap_cb, LV_EVENT_CLICKED, tap);
    lv_obj_add_event_cb(obj, free_cb, LV_EVENT_DELETE, tap);
}

void ui_set_tap_arg(lv_obj_t *obj, int arg)
{
    for (uint32_t i = 0; i < lv_obj_get_event_count(obj); i++) {
        lv_event_dsc_t *dsc = lv_obj_get_event_dsc(obj, i);
        if (lv_event_dsc_get_cb(dsc) == tap_cb) ((tap_t *)lv_event_dsc_get_user_data(dsc))->arg = arg;
    }
}

void ui_show(lv_obj_t *obj, bool show)
{
    lv_obj_set_hidden(obj, !show);
}

void ui_upper(char *dst, size_t n, const char *src)
{
    size_t i = 0;
    for (; src[i] && i + 1 < n; i++) dst[i] = (char)toupper((unsigned char)src[i]);
    dst[i] = '\0';
}

void ui_symbolize(char *dst, size_t n, const char *src)
{
    static const struct {
        const char *from, *to;
    } map[] = {{"\xE2\x99\xAA", LV_SYMBOL_AUDIO}, {"\xE2\x9A\xA1", LV_SYMBOL_CHARGE}};
    size_t o = 0;
    while (*src && o + 4 < n) {
        bool replaced = false;
        for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++) {
            size_t len = strlen(map[i].from);
            if (strncmp(src, map[i].from, len) == 0) {
                size_t tl = strlen(map[i].to);
                memcpy(dst + o, map[i].to, tl);
                o += tl;
                src += len;
                replaced = true;
                break;
            }
        }
        if (!replaced) dst[o++] = *src++;
    }
    dst[o] = '\0';
}

static void pet_free_cb(lv_event_t *e)
{
    free(lv_event_get_user_data(e));
}

ui_pet_t *ui_pet_create(lv_obj_t *parent, int32_t size)
{
    ui_pet_t *p = heap_caps_calloc_prefer(1, sizeof(*p), 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    p->dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    p->dsc.header.cf = LV_COLOR_FORMAT_ARGB8888;
    p->dsc.header.w = BM_PET_GRID;
    p->dsc.header.h = BM_PET_GRID;
    p->dsc.header.stride = BM_PET_GRID * 4;
    p->dsc.data_size = sizeof(p->px);
    p->dsc.data = (const uint8_t *)p->px;
    p->img = lv_image_create(parent);
    lv_image_set_src(p->img, &p->dsc);
    lv_image_set_inner_align(p->img, LV_IMAGE_ALIGN_STRETCH);
    lv_image_set_antialias(p->img, false);
    lv_obj_set_size(p->img, size, size);
    lv_obj_add_event_cb(p->img, pet_free_cb, LV_EVENT_DELETE, p);
    return p;
}

void ui_pet_draw(ui_pet_t *p, bm_pet_state_t state, uint16_t hue, bm_acc_t acc, float seed)
{
    bm_pet_render(p->px, state, ui.t, hue, acc, seed);
    lv_obj_invalidate(p->img);
}

void ui_session_pet(ui_pet_t *p, const bm_session_t *s)
{
    uint16_t hue;
    bm_acc_t acc;
    bm_project_look(s->project, &hue, &acc);
    ui_pet_draw(p, bm_agent_pet(ui.m, s), hue, acc, (float)(s - ui.m->sessions) * 1.7f);
}
