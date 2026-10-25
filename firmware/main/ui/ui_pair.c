#include <stdio.h>

#include "ui_priv.h"

static void cancel_cb(lv_event_t *e)
{
    (void)e;
    bm_pairing_end(ui.m, BM_PAIR_CANCELLED, lv_tick_get());
}

void ui_pair_create(lv_obj_t *scr)
{
    ui.pair = ui_box(scr);
    lv_obj_set_size(ui.pair, SCREEN, SCREEN);
    lv_obj_set_style_bg_color(ui.pair, ui_hex(C_BG), 0);
    lv_obj_set_style_bg_opa(ui.pair, LV_OPA_COVER, 0);
    lv_obj_set_clickable(ui.pair, true);
    lv_obj_set_flex_flow(ui.pair, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(ui.pair, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(ui.pair, 14, 0);

    ui.pair_pet = ui_pet_create(ui.pair, 96);
    ui_label(ui.pair, F_TITLE, C_FG, "Pair a Mac");
    ui.pair_hint = ui_label(ui.pair, F_SMALL, C_DIM, "");
    lv_obj_set_style_text_align(ui.pair_hint, LV_TEXT_ALIGN_CENTER, 0);

    ui.pair_code = ui_box(ui.pair);
    lv_obj_set_size(ui.pair_code, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(ui.pair_code, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(ui.pair_code, 22, 0);
    for (int i = 0; i < 2; i++) ui.pair_digits[i] = ui_label(ui.pair_code, &font_pixel_58, BM_C_BLE, "");

    ui.pair_left = ui_label(ui.pair, F_SMALL, 0x5c564f, "");

    lv_obj_t *cancel = ui_box(ui.pair);
    lv_obj_set_size(cancel, 180, 52);
    lv_obj_set_style_radius(cancel, 26, 0);
    lv_obj_set_style_border_width(cancel, 2, 0);
    lv_obj_set_style_border_color(cancel, ui_hex(0x2f2c28), 0);
    lv_obj_set_clickable(cancel, true);
    lv_obj_add_event_cb(cancel, cancel_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_center(ui_label(cancel, &font_mono_semi_17, C_FG, "Cancel"));
    ui_show(ui.pair, false);
}

void ui_pair_update(uint32_t now_ms)
{
    ui_show(ui.pair, ui.m->pairing);
    if (!ui.m->pairing) return;
    bool code = ui.m->passkey_shown;
    lv_label_set_text(ui.pair_hint, code ? "Type this code on the Mac" : "On the Mac, open Hilo\nand choose Add buddy");
    ui_show(ui.pair_code, code);
    if (code) {
        lv_label_set_text_fmt(ui.pair_digits[0], "%03u", (unsigned)(ui.m->passkey / 1000));
        lv_label_set_text_fmt(ui.pair_digits[1], "%03u", (unsigned)(ui.m->passkey % 1000));
    }
    int32_t left = (int32_t)(ui.m->pairing_until_ms - now_ms);
    lv_label_set_text_fmt(ui.pair_left, "closes in %d s", left > 0 ? (int)((left + 999) / 1000) : 0);
}

void ui_pair_frame(void)
{
    if (ui.m->pairing)
        ui_pet_draw(ui.pair_pet, ui.m->passkey_shown ? BM_PET_ALERT : BM_PET_IDLE, BM_PET_MAIN_HUE, ui.m->acc, 0);
}
