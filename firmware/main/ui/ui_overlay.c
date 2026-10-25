#include <stdio.h>

#include "ui_priv.h"

static void overlay_tap_cb(lv_event_t *e)
{
    (void)e;
    bm_tap_overlay(ui.m, lv_tick_get());
}

void ui_overlay_create(lv_obj_t *scr)
{
    ui.ov = ui_box(scr);
    lv_obj_set_size(ui.ov, SCREEN, SCREEN);
    lv_obj_set_style_pad_ver(ui.ov, 40, 0);
    lv_obj_set_style_pad_hor(ui.ov, 36, 0);
    lv_obj_set_style_bg_opa(ui.ov, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_grad_dir(ui.ov, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_bg_grad_color(ui.ov, ui_hex(C_BG), 0);
    lv_obj_set_style_bg_main_stop(ui.ov, 60, 0);
    lv_obj_set_style_bg_grad_stop(ui.ov, 230, 0);
    lv_obj_set_flex_flow(ui.ov, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(ui.ov, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_clickable(ui.ov, true);
    lv_obj_add_event_cb(ui.ov, overlay_tap_cb, LV_EVENT_CLICKED, NULL);

    ui.ov_pet = ui_pet_create(ui.ov, 192);
    ui.ov_big = ui_label(ui.ov, &font_pixel_35, C_FG, "");
    lv_obj_set_style_margin_top(ui.ov_big, 4, 0);
    lv_obj_set_width(ui.ov_big, LV_PCT(100));
    lv_obj_set_style_text_align(ui.ov_big, LV_TEXT_ALIGN_CENTER, 0);
    ui.ov_det = ui_label(ui.ov, &font_mono_18, C_FG, "");
    lv_obj_set_style_margin_top(ui.ov_det, 12, 0);
    lv_obj_set_style_pad_ver(ui.ov_det, 7, 0);
    lv_obj_set_style_pad_hor(ui.ov_det, 14, 0);
    lv_obj_set_style_radius(ui.ov_det, 10, 0);
    lv_obj_set_style_bg_color(ui.ov_det, ui_hex(C_BG), 0);
    lv_obj_set_style_bg_opa(ui.ov_det, 115, 0);
    lv_obj_set_style_max_width(ui.ov_det, LV_PCT(100), 0);
    lv_label_set_long_mode(ui.ov_det, LV_LABEL_LONG_MODE_DOTS);
    ui.ov_hint = ui_label(ui.ov, &font_mono_16, C_FG, "");
    lv_obj_set_style_margin_top(ui.ov_hint, 12, 0);
    lv_obj_set_style_text_opa(ui.ov_hint, 191, 0);

    for (int i = 0; i < CONFETTI_MAX; i++) {
        lv_obj_t *c = ui_box(ui.ov);
        lv_obj_set_ignore_layout(c, true);
        lv_obj_set_hidden(c, true);
        lv_obj_set_style_bg_opa(c, LV_OPA_COVER, 0);
        ui.confetti[i].obj = c;
    }
    ui_show(ui.ov, false);
}

static void burst(int n)
{
    static const uint32_t colors[] = {BM_C_DONE, BM_C_WORK, BM_C_WAIT, BM_C_INFO, 0xff7aa8};
    ui.n_confetti = n;
    for (int i = 0; i < CONFETTI_MAX; i++) {
        ui_confetti_t *c = &ui.confetti[i];
        ui_show(c->obj, i < n);
        if (i >= n) continue;
        c->x = 240 - 36;
        c->y = 200 - 40;
        c->vx = ((float)lv_rand(0, 1000) / 1000 - .5f) * 9;
        c->vy = -(float)lv_rand(0, 1000) / 1000 * 9 - 3;
        int32_t s = 6 + (int32_t)lv_rand(0, 2) * 3;
        lv_obj_set_size(c->obj, s, s);
        lv_obj_set_style_bg_color(c->obj, ui_hex(colors[lv_rand(0, 4)]), 0);
    }
}

static void texts(char *big, char *det, char *hint, size_t n, uint32_t now_ms, uint32_t *fg, uint32_t *tint)
{
    const bm_overlay_state_t *o = &ui.m->ov;
    char host[17] = "", dur[16] = "";
    if (o->host < BM_MAX_HOSTS && ui.m->hosts[o->host].used) {
        bm_host_label(ui.m->hosts[o->host].name, host, sizeof(host));
        bm_fmt_dur((int64_t)bm_usage_reset_s(&ui.m->hosts[o->host].usage, now_ms) * 1000, dur, sizeof(dur));
    }
    big[0] = det[0] = hint[0] = '\0';
    switch (o->type) {
    case BM_OV_DONE:
        snprintf(big, n, "Task done!");
        snprintf(det, n, "%s \xC2\xB7 %s", o->name, o->text);
        snprintf(hint, n, "Tap to see the summary");
        *fg = 0xc9ffe6, *tint = 0x00331f;
        break;
    case BM_OV_ERROR:
        snprintf(big, n, "Something failed");
        snprintf(det, n, "%s \xC2\xB7 %s", o->name, o->text);
        snprintf(hint, n, "Tap to see details");
        *fg = 0xffd0d1, *tint = 0x3a0608;
        break;
    case BM_OV_APPROVED:
        snprintf(big, n, o->question ? "Answer sent" : "Approved");
        if (o->question) snprintf(det, n, "%s", o->text);
        else snprintf(det, n, "%s continues", o->name);
        *fg = 0xc9ffe6, *tint = 0x00331f;
        break;
    case BM_OV_DENIED:
        snprintf(big, n, "Denied");
        snprintf(det, n, "%s will try another way", o->name);
        *fg = C_FG, *tint = C_BG;
        break;
    case BM_OV_WARN:
        snprintf(big, n, "At 80 %%");
        snprintf(det, n, "of your 5 h window \xC2\xB7 %s", host);
        snprintf(hint, n, "Resets in %s", dur);
        *fg = 0xffe2a0, *tint = 0x2f2200;
        break;
    case BM_OV_LIMIT:
        snprintf(big, n, "Limit reached");
        snprintf(det, n, "Back in %s", dur);
        snprintf(hint, n, "Your agents are paused");
        *fg = C_FG, *tint = C_BG;
        break;
    case BM_OV_CONN:
        snprintf(big, n, "%s Mac %s", host, o->on ? "connected" : "disconnected");
        snprintf(det, n, "%s", o->on ? "BLE paired" : "Out of range");
        *fg = 0xd6e6ff, *tint = 0x0b1a33;
        break;
    case BM_OV_BATT:
        snprintf(big, n, "Low battery");
        snprintf(det, n, "%u%% left", ui.m->battery_pct);
        snprintf(hint, n, "Plug in the USB-C cable");
        *fg = 0xffd0d1, *tint = 0x3a0608;
        break;
    case BM_OV_NONE: break;
    }
}

void ui_overlay_update(uint32_t now_ms)
{
    bm_overlay_t type = ui.m->ov.type;
    ui_show(ui.ov, type != BM_OV_NONE);
    if (type != ui.ov_shown) {
        if (type == BM_OV_DONE) burst(46);
        else if (type == BM_OV_APPROVED) burst(20);
        else burst(0);
        ui.ov_shown = type;
    }
    if (type == BM_OV_NONE) return;
    char big[400], det[400], hint[400];
    uint32_t fg = C_FG, tint = C_BG;
    texts(big, det, hint, sizeof(big), now_ms, &fg, &tint);
    lv_label_set_text(ui.ov_big, big);
    lv_label_set_text(ui.ov_det, det);
    lv_label_set_text(ui.ov_hint, hint);
    ui_show(ui.ov_det, det[0]);
    ui_show(ui.ov_hint, hint[0]);
    lv_obj_set_style_text_color(ui.ov_big, ui_hex(fg), 0);
    lv_obj_set_style_text_color(ui.ov_det, ui_hex(fg), 0);
    lv_obj_set_style_text_color(ui.ov_hint, ui_hex(fg), 0);
    lv_obj_set_style_bg_color(ui.ov, ui_hex(tint), 0);
}

void ui_overlay_frame(void)
{
    if (ui.m->ov.type == BM_OV_NONE) return;
    ui_pet_draw(ui.ov_pet, bm_main_pet(ui.m), BM_PET_MAIN_HUE, ui.m->acc, 0);
    for (int i = 0; i < ui.n_confetti; i++) {
        ui_confetti_t *c = &ui.confetti[i];
        if (c->y >= 500) continue;
        for (int step = 0; step < 2; step++) {
            c->vy += .32f;
            c->x += c->vx;
            c->y += c->vy;
        }
        if (c->y >= 500) {
            ui_show(c->obj, false);
            continue;
        }
        lv_obj_set_pos(c->obj, (int32_t)(c->x / 3) * 3, (int32_t)(c->y / 3) * 3);
    }
}
