#include <stdio.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "ui_priv.h"

#define FACE_PX 160
#define SLEEP_CARDS_DY 90

void ui_bar_create(lv_obj_t *scr)
{
    lv_obj_t *bar = ui.bar = ui_box(scr);
    lv_obj_set_size(bar, SCREEN, 54);
    lv_obj_set_style_pad_hor(bar, 30, 0);
    lv_obj_set_flex_flow(bar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(bar, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ui.clock = ui_label(bar, &font_mono_semi_18, C_FG, "--:--");

    lv_obj_t *pills = ui_box(bar);
    lv_obj_set_size(pills, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(pills, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(pills, 8, 0);
    for (int i = 0; i < BM_MAX_HOSTS; i++) {
        lv_obj_t *p = ui_box(pills);
        ui.pill[i] = p;
        lv_obj_set_size(p, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_style_pad_ver(p, 2, 0);
        lv_obj_set_style_pad_hor(p, 10, 0);
        lv_obj_set_style_radius(p, 20, 0);
        lv_obj_set_style_border_width(p, 2, 0);
        lv_obj_set_flex_flow(p, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(p, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(p, 6, 0);
        ui.pill_dot[i] = ui_box(p);
        lv_obj_set_size(ui.pill_dot[i], 8, 8);
        lv_obj_set_style_radius(ui.pill_dot[i], 4, 0);
        lv_obj_set_style_bg_opa(ui.pill_dot[i], LV_OPA_COVER, 0);
        lv_obj_set_style_shadow_color(ui.pill_dot[i], ui_hex(BM_C_BLE), 0);
        ui.pill_lbl[i] = ui_label(p, &font_mono_15, C_FG, "");
    }

    lv_obj_t *batt = ui_box(bar);
    lv_obj_set_size(batt, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(batt, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(batt, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(batt, 6, 0);
    ui.batt_charge = ui_label(batt, &lv_font_montserrat_16, C_DIM, LV_SYMBOL_CHARGE);
    ui.batt_pct = ui_label(batt, &font_mono_18, C_DIM, "--");
    lv_obj_t *cell = ui_box(batt);
    lv_obj_set_size(cell, 28, 14);
    lv_obj_set_style_border_width(cell, 2, 0);
    lv_obj_set_style_border_color(cell, ui_hex(C_DIM), 0);
    lv_obj_set_style_radius(cell, 3, 0);
    lv_obj_set_style_pad_all(cell, 2, 0);
    ui.batt_lvl = ui_box(cell);
    lv_obj_set_height(ui.batt_lvl, LV_PCT(100));
    lv_obj_set_style_radius(ui.batt_lvl, 1, 0);
    lv_obj_set_style_bg_opa(ui.batt_lvl, LV_OPA_COVER, 0);
    lv_obj_t *nub = ui_box(batt);
    lv_obj_set_size(nub, 2, 5);
    lv_obj_set_style_margin_left(nub, -6, 0);
    lv_obj_set_style_bg_color(nub, ui_hex(C_DIM), 0);
    lv_obj_set_style_bg_opa(nub, LV_OPA_COVER, 0);
}

void ui_bar_update(uint32_t now_ms)
{
    char buf[16];
    if (ui.m->clock_known) {
        bm_fmt_clock(bm_wall_ms(ui.m, now_ms), ui.m->settings.tz_offset_min, buf, sizeof(buf));
        lv_label_set_text(ui.clock, buf);
        lv_label_set_text(ui.sleep_clock, buf);
    }
    for (int i = 0; i < BM_MAX_HOSTS; i++) {
        const bm_host_t *h = &ui.m->hosts[i];
        bool any = ui.m->hosts[0].used || ui.m->hosts[1].used;
        ui_show(ui.pill[i], h->used || (!any && i == 0));
        bool on = h->used && h->connected;
        char label[17];
        if (h->used) bm_host_label(h->name, label, sizeof(label));
        else snprintf(label, sizeof(label), "No Mac");
        lv_label_set_text(ui.pill_lbl[i], label);
        lv_obj_set_style_text_color(ui.pill_lbl[i], ui_hex(on ? C_FG : 0x55504a), 0);
        lv_obj_set_style_border_color(ui.pill[i], ui_hex(on ? 0x3d6bff : 0x2f2c28), 0);
        lv_obj_set_style_border_opa(ui.pill[i], on ? 0x66 : LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(ui.pill_dot[i], ui_hex(on ? BM_C_BLE : 0x3a3631), 0);
        lv_obj_set_style_shadow_width(ui.pill_dot[i], on ? 6 : 0, 0);
    }
    ui_show(ui.batt_charge, ui.m->charging);
    if (ui.m->battery_known) lv_label_set_text_fmt(ui.batt_pct, "%u%%", ui.m->battery_pct);
    lv_obj_set_width(ui.batt_lvl, LV_PCT(ui.m->battery_known ? ui.m->battery_pct : 0));
    lv_obj_set_style_bg_color(ui.batt_lvl, ui_hex(ui.m->battery_pct <= 20 ? BM_C_ERR : BM_C_DONE), 0);
}

static void face_scale(const bm_face_t *f)
{
    if (!ui.face_px) return;
    for (int y = 0; y < FACE_PX; y++) {
        const uint16_t *src = &f->px[y * f->h / FACE_PX * f->w];
        for (int x = 0; x < FACE_PX; x++) ui.face_px[y * FACE_PX + x] = src[x * f->w / FACE_PX];
    }
    lv_obj_invalidate(ui.sleep_face);
}

static int connected_count(void)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_HOSTS; i++) n += ui.m->hosts[i].used && ui.m->hosts[i].connected;
    return n;
}

static int known_count(void)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_HOSTS; i++) n += ui.m->hosts[i].used;
    return n;
}

static void sleep_card_update(uint32_t now_ms)
{
    int card = ui.m->sleep_card;
    bool face = card >= 0, computers = card == BM_CARD_COMPUTERS;
    ui_show(ui.sleep_face, face);
    ui_show(ui.sleep_name, face);
    ui_show(ui.sleep_pet->img, computers);
    ui_show(ui.sleep_clock, !face && !computers);
    ui_show(ui.sleep_ago, face || computers);
    ui_show(ui.sleep_hint, !face);
    if (face) {
        const bm_host_t *h = &ui.m->hosts[card];
        if (card != ui.face_card || ui.m->faces_rev != ui.face_rev) face_scale(&h->face);
        char label[17], ago[24];
        bm_host_label(h->name, label, sizeof(label));
        lv_label_set_text(ui.sleep_name, label);
        int64_t at = h->connected ? h->connected_at : h->disconnected_at;
        if (at) {
            bm_fmt_ago(bm_wall_ms(ui.m, now_ms) - at * 1000, ago, sizeof(ago));
            lv_label_set_text_fmt(ui.sleep_ago, "%s %s", h->connected ? "connected" : "seen", ago);
        } else {
            lv_label_set_text(ui.sleep_ago, h->connected ? "connected" : "not seen yet");
        }
    } else if (computers) {
        int n = connected_count();
        if (n) lv_label_set_text_fmt(ui.sleep_ago, "%d Mac%s connected", n, n == 1 ? "" : "s");
        else lv_label_set_text(ui.sleep_ago, "no Mac connected");
    }
    ui.face_card = (int8_t)card;
    ui.face_rev = ui.m->faces_rev;
}

static void sleep_tap_cb(lv_event_t *e)
{
    (void)e;
    bm_touch_wake(ui.m, lv_tick_get());
}

void ui_misc_create(lv_obj_t *scr)
{
    ui.toast = ui_box(scr);
    lv_obj_set_size(ui.toast, SCREEN - 48, LV_SIZE_CONTENT);
    lv_obj_align(ui.toast, LV_ALIGN_TOP_MID, 0, 60);
    lv_obj_set_style_pad_ver(ui.toast, 10, 0);
    lv_obj_set_style_pad_hor(ui.toast, 14, 0);
    lv_obj_set_style_radius(ui.toast, 12, 0);
    lv_obj_set_style_bg_opa(ui.toast, LV_OPA_COVER, 0);
    ui.toast_lbl = ui_label(ui.toast, &font_mono_semi_17, 0x000000, "");
    lv_obj_set_width(ui.toast_lbl, LV_PCT(100));
    lv_label_set_long_mode(ui.toast_lbl, LV_LABEL_LONG_MODE_DOTS);
    ui_show(ui.toast, false);

    ui.sleep = ui_box(scr);
    lv_obj_set_size(ui.sleep, SCREEN, SCREEN);
    lv_obj_set_style_bg_color(ui.sleep, ui_hex(UI_EMBER), 0);
    lv_obj_set_style_bg_opa(ui.sleep, LV_OPA_COVER, 0);
    lv_obj_set_clickable(ui.sleep, true);
    lv_obj_add_event_cb(ui.sleep, sleep_tap_cb, LV_EVENT_CLICKED, NULL);
    ui_eyes_sleep_create(ui.sleep);
    ui.sleep_inner = ui_box(ui.sleep);
    lv_obj_set_size(ui.sleep_inner, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_center(ui.sleep_inner);
    lv_obj_set_flex_flow(ui.sleep_inner, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(ui.sleep_inner, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ui.sleep_name = ui_label(ui.sleep_inner, &font_mono_bold_18, UI_ORANGE, "");
    lv_obj_set_style_margin_bottom(ui.sleep_name, 12, 0);
    ui.sleep_pet = ui_pet_create(ui.sleep_inner, 128);
    lv_obj_set_style_opa(ui.sleep_pet->img, 179, 0);
    ui.face_px = heap_caps_calloc_prefer(FACE_PX * FACE_PX, 2, 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    ui.face_dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    ui.face_dsc.header.cf = LV_COLOR_FORMAT_RGB565;
    ui.face_dsc.header.w = FACE_PX;
    ui.face_dsc.header.h = FACE_PX;
    ui.face_dsc.header.stride = FACE_PX * 2;
    ui.face_dsc.data = (const uint8_t *)ui.face_px;
    ui.face_dsc.data_size = FACE_PX * FACE_PX * 2;
    ui.sleep_face = lv_image_create(ui.sleep_inner);
    lv_image_set_src(ui.sleep_face, &ui.face_dsc);
    lv_obj_set_style_radius(ui.sleep_face, 28, 0);
    lv_obj_set_style_clip_corner(ui.sleep_face, true, 0);
    lv_obj_set_style_opa(ui.sleep_face, 200, 0);
    ui.sleep_clock = ui_label(ui.sleep_inner, &font_pixel_92, UI_ORANGE, "--:--");
    ui.sleep_ago = ui_label(ui.sleep_inner, &font_mono_17, UI_ORANGE, "");
    lv_obj_set_style_text_opa(ui.sleep_ago, 179, 0);
    lv_obj_set_style_margin_top(ui.sleep_ago, 14, 0);
    ui.sleep_hint = ui_label(ui.sleep_inner, &font_mono_16, UI_ORANGE, "tap to wake");
    lv_obj_set_style_text_opa(ui.sleep_hint, 115, 0);
    lv_obj_set_style_margin_top(ui.sleep_hint, 4, 0);
    ui.face_card = BM_CARD_CLOCK;
    ui_show(ui.sleep, false);
}

void ui_misc_update(uint32_t now_ms)
{
    bool toast = ui.m->toast[0] != '\0';
    ui_show(ui.toast, toast);
    if (toast) {
        char text[160];
        ui_symbolize(text, sizeof(text), ui.m->toast);
        lv_label_set_text(ui.toast_lbl, text);
        lv_obj_set_style_bg_color(ui.toast, ui_hex(ui.m->toast_color), 0);
    }
    ui_show(ui.sleep, ui.m->sleeping);
    if (ui.m->sleeping) sleep_card_update(now_ms);
    lv_obj_align(ui.sleep_inner, LV_ALIGN_CENTER, ui.m->sleep_dx, SLEEP_CARDS_DY + ui.m->sleep_dy);
}

void ui_misc_frame(uint32_t now_ms)
{
    (void)now_ms;
    if (ui.m->sleeping && ui.m->sleep_card == BM_CARD_COMPUTERS)
        ui_pet_computers(ui.sleep_pet, known_count(), connected_count());
}
