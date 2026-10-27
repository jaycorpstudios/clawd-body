#include "ui.h"

#include "ui_priv.h"

#define FRAME_MS 33

ui_t ui;

static void gesture_cb(lv_event_t *e)
{
    (void)e;
    lv_indev_t *indev = lv_indev_active();
    lv_dir_t dir = lv_indev_get_gesture_dir(indev);
    lv_indev_wait_release(indev);
    if (dir == LV_DIR_BOTTOM || dir == LV_DIR_TOP) bm_panel(ui.m, dir == LV_DIR_BOTTOM, lv_tick_get());
    else bm_swipe(ui.m, dir == LV_DIR_LEFT ? 1 : -1, lv_tick_get());
}

static void refresh(uint32_t now_ms)
{
    ui_views_update();
    ui_overlay_update(now_ms);
    ui_attn_update(now_ms);
    ui_sheet_update(now_ms);
    ui_panel_update(now_ms);
    ui_misc_update(now_ms);
    ui_pair_update(now_ms);
    ui_bar_update(now_ms);
}

static void frame_cb(lv_timer_t *t)
{
    (void)t;
    uint32_t now_ms = lv_tick_get();
    ui.t = (float)now_ms / 1000.0f;
    bm_tick(ui.m, now_ms);

    if (ui.m->rev != ui.rev) {
        ui.rev = ui.m->rev;
        refresh(now_ms);
    }
    int64_t sec = now_ms / 1000;
    if (sec != ui.sec) {
        ui.sec = sec;
        ui_views_tick(now_ms);
        ui_bar_update(now_ms);
        if (ui.m->ov.type == BM_OV_WARN || ui.m->ov.type == BM_OV_LIMIT) ui_overlay_update(now_ms);
        if (bm_attn_session(ui.m)) ui_attn_update(now_ms);
        if (ui.m->pairing) ui_pair_update(now_ms);
    }

    ui_views_frame();
    ui_overlay_frame();
    ui_attn_frame(now_ms);
    ui_sheet_frame();
    ui_misc_frame(now_ms);
    ui_pair_frame();
}

void ui_init(bm_model_t *m)
{
    ui.m = m;
    ui.rev = m->rev - 1;
    ui.sh_pet_session = -1;
    ui.scr = lv_screen_active();
    lv_obj_set_style_bg_color(ui.scr, ui_hex(C_BG), 0);
    lv_obj_set_style_bg_opa(ui.scr, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(ui.scr, false);
    lv_obj_add_event_cb(ui.scr, gesture_cb, LV_EVENT_GESTURE, NULL);

    ui_views_create(ui.scr);
    ui_bar_create(ui.scr);
    ui_overlay_create(ui.scr);
    ui_attn_create(ui.scr);
    ui_sheet_create(ui.scr);
    ui_panel_create(ui.scr);
    ui_misc_create(ui.scr);
    ui_pair_create(ui.scr);
    for (int i = 0; i < BM_AGENT_ROWS; i++) ui.rows[i].session = -1;

    lv_timer_create(frame_cb, FRAME_MS, NULL);
}
