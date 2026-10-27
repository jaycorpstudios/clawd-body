#include <math.h>
#include <stdio.h>

#include "ui_priv.h"

#define BTN_H 58
#define ATTN_W (SCREEN - 56)

#define FRAME_W 5

static lv_obj_t *frame[4];

static lv_obj_t *button(lv_obj_t *parent, uint32_t border, uint32_t bg, uint32_t fg, const char *text, lv_obj_t **lbl)
{
    lv_obj_t *b = ui_box(parent);
    lv_obj_set_height(b, BTN_H);
    lv_obj_set_style_radius(b, 15, 0);
    lv_obj_set_style_border_width(b, 2, 0);
    lv_obj_set_style_border_color(b, ui_hex(border), 0);
    lv_obj_set_style_bg_color(b, ui_hex(bg), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_clip_corner(b, true, 0);
    lv_obj_t *l = ui_label(b, &font_mono_bold_18, fg, text);
    lv_obj_center(l);
    if (lbl) *lbl = l;
    return b;
}

static void hold_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_PRESSED) bm_hold_begin(ui.m, lv_tick_get());
    else bm_hold_cancel(ui.m);
}

void ui_attn_create(lv_obj_t *scr)
{
    ui.attn = ui_box(scr);
    lv_obj_set_size(ui.attn, SCREEN, SCREEN);
    lv_obj_set_style_pad_top(ui.attn, 26, 0);
    lv_obj_set_style_pad_bottom(ui.attn, 22, 0);
    lv_obj_set_style_pad_hor(ui.attn, 28, 0);
    lv_obj_set_style_pad_row(ui.attn, 12, 0);
    lv_obj_set_style_bg_color(ui.attn, ui_hex(0x3a2a00), 0);
    lv_obj_set_style_bg_opa(ui.attn, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_grad_dir(ui.attn, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_bg_grad_color(ui.attn, ui_hex(C_BG), 0);
    lv_obj_set_style_bg_grad_stop(ui.attn, 180, 0);
    lv_obj_set_flex_flow(ui.attn, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_clickable(ui.attn, true);

    lv_obj_t *head = ui_box(ui.attn);
    lv_obj_set_size(head, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(head, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(head, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(head, 12, 0);
    ui_eyes_tile_create(head);
    lv_obj_t *ht = ui_box(head);
    lv_obj_set_flex_grow(ht, 1);
    lv_obj_set_height(ht, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(ht, LV_FLEX_FLOW_COLUMN);
    ui.ap_k = ui_label(ht, &font_mono_bold_15, BM_C_WAIT, "");
    lv_obj_set_style_text_letter_space(ui.ap_k, 1, 0);
    ui.ap_p = ui_label(ht, &font_pixel_26, 0xffeec4, "");
    lv_obj_set_width(ui.ap_p, LV_PCT(100));
    lv_label_set_long_mode(ui.ap_p, LV_LABEL_LONG_MODE_DOTS);
    ui.ap_h = ui_label(ht, &font_mono_15, 0xb9a77a, "");

    lv_obj_t *cmd = ui_box(ui.attn);
    lv_obj_set_size(cmd, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_max_height(cmd, 96, 0);
    lv_obj_set_style_bg_color(cmd, ui_hex(0x120e05), 0);
    lv_obj_set_style_bg_opa(cmd, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(cmd, 2, 0);
    lv_obj_set_style_border_color(cmd, ui_hex(0x3b2f10), 0);
    lv_obj_set_style_radius(cmd, 12, 0);
    lv_obj_set_style_pad_ver(cmd, 11, 0);
    lv_obj_set_style_pad_hor(cmd, 14, 0);
    ui.ap_cmd = ui_label(cmd, &font_mono_semi_18, 0xfff4d6, "");
    lv_obj_set_width(ui.ap_cmd, LV_PCT(100));
    lv_label_set_long_mode(ui.ap_cmd, LV_LABEL_LONG_MODE_WRAP);

    ui.ap_why = ui_label(ui.attn, &font_mono_16, 0xe8d8ad, "");
    lv_obj_set_width(ui.ap_why, LV_PCT(100));
    lv_label_set_long_mode(ui.ap_why, LV_LABEL_LONG_MODE_WRAP);
    lv_obj_set_style_max_height(ui.ap_why, 66, 0);

    lv_obj_t *spacer = ui_box(ui.attn);
    lv_obj_set_width(spacer, 1);
    lv_obj_set_flex_grow(spacer, 1);

    ui.ap_opts = ui_box(ui.attn);
    lv_obj_set_size(ui.ap_opts, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(ui.ap_opts, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(ui.ap_opts, 8, 0);
    for (int i = 0; i < BM_MAX_OPTIONS; i++) {
        ui.ap_opt[i] = button(ui.ap_opts, 0x4a3d1d, 0x0f0c06, C_FG, "", &ui.ap_opt_lbl[i]);
        lv_obj_set_size(ui.ap_opt[i], LV_PCT(100), 50);
        lv_obj_set_style_text_font(ui.ap_opt_lbl[i], &font_mono_17, 0);
        lv_obj_align(ui.ap_opt_lbl[i], LV_ALIGN_LEFT_MID, 14, 0);
        ui_on_tap(ui.ap_opt[i], BM_TAP_ANSWER, i);
    }

    ui.ap_actions = ui_box(ui.attn);
    lv_obj_set_size(ui.ap_actions, LV_PCT(100), BTN_H);
    lv_obj_set_flex_flow(ui.ap_actions, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(ui.ap_actions, 10, 0);
    int32_t unit = (ATTN_W - 10) * 10 / 24;
    ui.ap_deny = button(ui.ap_actions, 0x5a2427, 0x0f0c06, 0xffb3b5, "Deny", NULL);
    lv_obj_set_width(ui.ap_deny, unit);
    ui_on_tap(ui.ap_deny, BM_TAP_DENY, 0);

    lv_obj_t *ok_lbl;
    ui.ap_ok = button(ui.ap_actions, BM_C_WAIT, 0x6a5216, 0x1a1200, "Hold to approve", &ok_lbl);
    lv_obj_set_flex_grow(ui.ap_ok, 1);
    lv_obj_set_clickable(ui.ap_ok, true);
    lv_obj_add_event_cb(ui.ap_ok, hold_cb, LV_EVENT_PRESSED, NULL);
    lv_obj_add_event_cb(ui.ap_ok, hold_cb, LV_EVENT_RELEASED, NULL);
    lv_obj_add_event_cb(ui.ap_ok, hold_cb, LV_EVENT_PRESS_LOST, NULL);
    ui.ap_ok_fill = ui_box(ui.ap_ok);
    lv_obj_set_size(ui.ap_ok_fill, 0, LV_PCT(100));
    lv_obj_set_style_bg_color(ui.ap_ok_fill, ui_hex(BM_C_WAIT), 0);
    lv_obj_set_style_bg_opa(ui.ap_ok_fill, LV_OPA_COVER, 0);
    lv_obj_move_to_index(ui.ap_ok_fill, 0);

    ui.ap_locked = button(ui.ap_actions, 0x5a2427, 0x140708, 0xff9a9d, "", &ui.ap_locked_lbl);
    lv_obj_set_flex_grow(ui.ap_locked, 1);
    lv_obj_set_style_border_opa(ui.ap_locked, LV_OPA_50, 0);
    lv_obj_set_style_text_font(ui.ap_locked_lbl, &font_mono_bold_15, 0);
    lv_obj_set_style_text_align(ui.ap_locked_lbl, LV_TEXT_ALIGN_CENTER, 0);

    lv_obj_t *links = ui_box(ui.attn);
    lv_obj_set_size(links, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_t *details = ui_label(links, &font_mono_16, 0xc9b88d, "View details \xE2\x80\xBA");
    lv_obj_set_style_pad_ver(details, 4, 0);
    ui_on_tap(details, BM_TAP_DETAILS, 0);
    lv_obj_t *later = ui_label(links, &font_mono_16, 0xc9b88d, "Later");
    lv_obj_set_style_pad_ver(later, 4, 0);
    lv_obj_set_style_pad_left(later, 24, 0);
    lv_obj_align(later, LV_ALIGN_RIGHT_MID, 0, 0);
    ui_on_tap(later, BM_TAP_LATER, 0);

    // Four edges instead of one bordered box: a box's style change invalidates the whole screen.
    static const int16_t edges[4][4] = {{0, 0, SCREEN, FRAME_W},
                                        {0, SCREEN - FRAME_W, SCREEN, FRAME_W},
                                        {0, FRAME_W, FRAME_W, SCREEN - 2 * FRAME_W},
                                        {SCREEN - FRAME_W, FRAME_W, FRAME_W, SCREEN - 2 * FRAME_W}};
    for (int i = 0; i < 4; i++) {
        frame[i] = ui_box(ui.attn);
        lv_obj_set_ignore_layout(frame[i], true);
        lv_obj_set_pos(frame[i], edges[i][0] - 28, edges[i][1] - 26);
        lv_obj_set_size(frame[i], edges[i][2], edges[i][3]);
    }
    ui_show(ui.attn, false);
}

void ui_attn_update(uint32_t now_ms)
{
    const bm_session_t *s = bm_attn_session(ui.m);
    ui_show(ui.attn, s != NULL);
    if (!s) return;
    const bm_request_t *r = &s->req;
    bool risk = r->high_risk, q = r->is_question;
    uint32_t accent = risk ? BM_C_ERR : BM_C_WAIT;

    char k[64], host[17], ago[24];
    snprintf(k, sizeof(k), "%s \xC2\xB7 %s", q ? "Question" : risk ? "Permission \xC2\xB7 high risk" : "Permission",
             r->tool);
    ui_upper(k, sizeof(k), k);
    lv_label_set_text(ui.ap_k, k);
    lv_obj_set_style_text_color(ui.ap_k, ui_hex(accent), 0);
    lv_label_set_text(ui.ap_p, s->project);
    bm_host_label(ui.m->hosts[s->host].name, host, sizeof(host));
    bm_fmt_ago(bm_wall_ms(ui.m, now_ms) - s->since * 1000, ago, sizeof(ago));
    int pending = bm_live_waiting_count(ui.m);
    if (pending > 1) lv_label_set_text_fmt(ui.ap_h, "%s Mac \xC2\xB7 %s \xC2\xB7 %d pending", host, ago, pending);
    else lv_label_set_text_fmt(ui.ap_h, "%s Mac \xC2\xB7 %s", host, ago);
    lv_label_set_text(ui.ap_cmd, r->detail);
    lv_label_set_text(ui.ap_why, r->why);
    ui_show(ui.ap_why, r->why[0]);

    ui_show(ui.ap_opts, q);
    ui_show(ui.ap_actions, !q);
    for (int i = 0; i < BM_MAX_OPTIONS; i++) {
        ui_show(ui.ap_opt[i], q && i < r->n_options);
        if (q && i < r->n_options) lv_label_set_text_fmt(ui.ap_opt_lbl[i], "%d. %s", i + 1, r->options[i]);
    }
    bool approvable = bm_request_approvable(r);
    ui_show(ui.ap_ok, !q && approvable);
    ui_show(ui.ap_locked, !q && !approvable);
    lv_label_set_text(ui.ap_locked_lbl, risk ? "High risk:\nMac only" : "Approve on\nthe Mac");
    for (int i = 0; i < 4; i++) lv_obj_set_style_bg_color(frame[i], ui_hex(accent), 0);
}

void ui_attn_frame(uint32_t now_ms)
{
    const bm_session_t *s = bm_attn_session(ui.m);
    if (!s) return;
    float k = (cosf(ui.t * 2 * 3.14159f / 1.1f) + 1) / 2;
    for (int i = 0; i < 4; i++) lv_obj_set_style_bg_opa(frame[i], (lv_opa_t)(k * 255), 0);
    int32_t fill = (int32_t)(bm_hold_progress(ui.m, now_ms) * lv_obj_get_width(ui.ap_ok));
    if (fill != lv_obj_get_style_width(ui.ap_ok_fill, 0)) lv_obj_set_width(ui.ap_ok_fill, fill);
}
