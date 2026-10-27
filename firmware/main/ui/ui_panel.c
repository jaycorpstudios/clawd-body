#include <stdio.h>

#include "ui_priv.h"

#define PANEL_H 330
#define SLIDE_MS 220

static lv_obj_t *backdrop, *panel, *sound_btn, *sound_icon, *sound_state, *vol_val, *bri_val;
static lv_obj_t *vol_slider, *bri_slider;
static bool shown;

static void change(bool sound, int volume, int brightness)
{
    bm_settings_t s = {.sound = sound, .volume = (uint8_t)volume, .brightness = (uint8_t)brightness};
    bm_settings_change(ui.m, &s, lv_tick_get());
}

static void sound_cb(lv_event_t *e)
{
    (void)e;
    const bm_settings_t *s = &ui.m->settings;
    change(!s->sound, s->volume, s->brightness);
}

static void slider_cb(lv_event_t *e)
{
    const bm_settings_t *s = &ui.m->settings;
    int v = (int)lv_slider_get_value(lv_event_get_target(e));
    if (lv_event_get_target(e) == vol_slider) change(s->sound, v, s->brightness);
    else change(s->sound, s->volume, v);
}

static void close_cb(lv_event_t *e)
{
    (void)e;
    bm_panel(ui.m, false, lv_tick_get());
}

static lv_obj_t *slider(lv_obj_t *parent, int32_t min, uint32_t color)
{
    lv_obj_t *s = lv_slider_create(parent);
    lv_obj_remove_style_all(s);
    lv_obj_set_size(s, LV_PCT(100), 14);
    lv_obj_set_style_margin_top(s, 10, 0);
    lv_obj_set_style_margin_bottom(s, 6, 0);
    lv_obj_set_style_radius(s, 7, LV_PART_MAIN);
    lv_obj_set_style_bg_color(s, ui_hex(C_TRACK), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(s, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(s, 7, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(s, ui_hex(color), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(s, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(s, LV_RADIUS_CIRCLE, LV_PART_KNOB);
    lv_obj_set_style_bg_color(s, ui_hex(C_FG), LV_PART_KNOB);
    lv_obj_set_style_bg_opa(s, LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_pad_all(s, 9, LV_PART_KNOB);
    lv_obj_set_ext_click_area(s, 16);
    lv_obj_set_gesture_bubble(s, false);
    lv_slider_set_range(s, min, 100);
    lv_obj_add_event_cb(s, slider_cb, LV_EVENT_VALUE_CHANGED, NULL);
    return s;
}

static lv_obj_t *label_row(lv_obj_t *parent, const char *name, lv_obj_t **value)
{
    lv_obj_t *row = ui_box(parent);
    lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ui_label(row, &font_mono_17, C_DIM, name);
    *value = ui_label(row, &font_mono_semi_18, C_FG, "");
    return row;
}

void ui_panel_create(lv_obj_t *scr)
{
    backdrop = ui_box(scr);
    lv_obj_set_size(backdrop, SCREEN, SCREEN);
    lv_obj_set_style_bg_color(backdrop, ui_hex(C_BG), 0);
    lv_obj_set_style_bg_opa(backdrop, LV_OPA_60, 0);
    lv_obj_set_clickable(backdrop, true);
    lv_obj_add_event_cb(backdrop, close_cb, LV_EVENT_CLICKED, NULL);
    ui_show(backdrop, false);

    panel = ui_box(scr);
    lv_obj_set_size(panel, SCREEN, PANEL_H);
    lv_obj_set_y(panel, -PANEL_H);
    lv_obj_set_style_bg_color(panel, ui_hex(0x0d0c0b), 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_side(panel, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_width(panel, 2, 0);
    lv_obj_set_style_border_color(panel, ui_hex(C_LINE), 0);
    lv_obj_set_style_radius(panel, 28, 0);
    lv_obj_set_style_pad_top(panel, 64, 0);
    lv_obj_set_style_pad_hor(panel, 40, 0);
    lv_obj_set_style_pad_bottom(panel, 14, 0);
    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(panel, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_clickable(panel, true);

    sound_btn = ui_box(panel);
    lv_obj_set_size(sound_btn, LV_PCT(100), 56);
    lv_obj_set_style_radius(sound_btn, 15, 0);
    lv_obj_set_style_border_width(sound_btn, 2, 0);
    lv_obj_set_style_bg_opa(sound_btn, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_hor(sound_btn, 16, 0);
    lv_obj_set_flex_flow(sound_btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(sound_btn, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(sound_btn, 12, 0);
    lv_obj_set_clickable(sound_btn, true);
    lv_obj_add_event_cb(sound_btn, sound_cb, LV_EVENT_CLICKED, NULL);
    sound_icon = ui_label(sound_btn, &lv_font_montserrat_24, C_FG, LV_SYMBOL_MUTE);
    lv_obj_t *name = ui_label(sound_btn, &font_mono_bold_18, C_FG, "Sound");
    lv_obj_set_flex_grow(name, 1);
    sound_state = ui_label(sound_btn, &font_mono_bold_18, C_DIM, "Off");

    lv_obj_t *vol = label_row(panel, "Volume", &vol_val);
    lv_obj_set_style_margin_top(vol, 14, 0);
    vol_slider = slider(panel, 0, BM_C_DONE);
    label_row(panel, "Brightness", &bri_val);
    bri_slider = slider(panel, 10, BM_C_WAIT);

    lv_obj_t *grab = ui_box(panel);
    lv_obj_set_size(grab, 44, 5);
    lv_obj_set_style_margin_top(grab, 4, 0);
    lv_obj_set_style_radius(grab, 3, 0);
    lv_obj_set_style_bg_color(grab, ui_hex(0x3a3631), 0);
    lv_obj_set_style_bg_opa(grab, LV_OPA_COVER, 0);
}

static void slide(int32_t to)
{
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, panel);
    lv_anim_set_values(&a, lv_obj_get_y(panel), to);
    lv_anim_set_duration(&a, SLIDE_MS);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_out);
    lv_anim_set_exec_cb(&a, (lv_anim_exec_xcb_t)lv_obj_set_y);
    lv_anim_start(&a);
}

void ui_panel_update(uint32_t now_ms)
{
    (void)now_ms;
    const bm_settings_t *s = &ui.m->settings;
    bool open = ui.m->panel && !ui.m->sleeping;
    if (open != shown) {
        shown = open;
        ui_show(backdrop, open);
        if (open) lv_obj_move_foreground(panel);
        slide(open ? 0 : -PANEL_H);
    }
    lv_label_set_text(sound_icon, s->sound ? LV_SYMBOL_VOLUME_MAX : LV_SYMBOL_MUTE);
    lv_label_set_text(sound_state, s->sound ? "On" : "Off");
    lv_obj_set_style_text_color(sound_state, ui_hex(s->sound ? BM_C_DONE : C_DIM), 0);
    lv_obj_set_style_border_color(sound_btn, ui_hex(s->sound ? 0x1f5a43 : 0x2f2c28), 0);
    lv_obj_set_style_bg_color(sound_btn, ui_hex(s->sound ? 0x0f2a20 : 0x161412), 0);
    lv_label_set_text_fmt(vol_val, "%u", s->volume);
    lv_label_set_text_fmt(bri_val, "%u%%", s->brightness);
    lv_obj_set_style_opa(vol_slider, s->sound ? LV_OPA_COVER : LV_OPA_50, 0);
    if (!lv_slider_is_dragged(vol_slider)) lv_slider_set_value(vol_slider, s->volume, LV_ANIM_OFF);
    if (!lv_slider_is_dragged(bri_slider)) lv_slider_set_value(bri_slider, s->brightness, LV_ANIM_OFF);
}
