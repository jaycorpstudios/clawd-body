#include <stdio.h>
#include <string.h>

#include "ui_priv.h"

static lv_obj_t *body_label(const lv_font_t *font, uint32_t color, const char *text)
{
    lv_obj_t *l = ui_label(ui.sh_body, font, color, text);
    lv_obj_set_width(l, LV_PCT(100));
    lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_WRAP);
    return l;
}

static void section(const char *title)
{
    char up[64];
    ui_upper(up, sizeof(up), title);
    lv_obj_t *l = body_label(&font_mono_15, C_DIM, up);
    lv_obj_set_style_text_letter_space(l, 1, 0);
    lv_obj_set_style_margin_top(l, 16, 0);
    lv_obj_set_style_margin_bottom(l, 8, 0);
}

static lv_obj_t *kv_table(void)
{
    lv_obj_t *t = ui_box(ui.sh_body);
    lv_obj_set_size(t, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(t, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(t, 6, 0);
    lv_obj_set_style_margin_bottom(t, 14, 0);
    return t;
}

static lv_obj_t *kv(lv_obj_t *table, const char *key, const char *value, uint32_t color)
{
    lv_obj_t *row = ui_box(table);
    lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
    ui_label(row, &font_mono_17, C_DIM, key);
    lv_obj_t *v = ui_label(row, &font_mono_semi_17, color, value);
    lv_obj_set_style_max_width(v, 260, 0);
    lv_label_set_long_mode(v, LV_LABEL_LONG_MODE_DOTS);
    lv_obj_align(v, LV_ALIGN_TOP_RIGHT, 0, 0);
    return v;
}

static void box(const char *text, uint32_t bg, uint32_t fg)
{
    lv_obj_t *b = ui_box(ui.sh_body);
    lv_obj_set_size(b, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_radius(b, 12, 0);
    lv_obj_set_style_pad_ver(b, 11, 0);
    lv_obj_set_style_pad_hor(b, 14, 0);
    lv_obj_set_style_margin_bottom(b, 6, 0);
    lv_obj_set_style_bg_color(b, ui_hex(bg), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_t *l = ui_label(b, &font_mono_16, fg, text);
    lv_obj_set_width(l, LV_PCT(100));
    lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_WRAP);
}

static lv_obj_t *wide_button(const char *text, bool primary)
{
    lv_obj_t *b = ui_box(ui.sh_body);
    lv_obj_set_size(b, LV_PCT(100), 58);
    lv_obj_set_style_margin_top(b, primary ? 6 : 14, 0);
    lv_obj_set_style_margin_bottom(b, 4, 0);
    lv_obj_set_style_radius(b, 15, 0);
    lv_obj_set_style_border_width(b, 2, 0);
    lv_obj_set_style_border_color(b, ui_hex(primary ? BM_C_WAIT : 0x4a3d1d), 0);
    lv_obj_set_style_bg_color(b, ui_hex(primary ? 0x6a5216 : 0x0f0c06), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_center(ui_label(b, &font_mono_bold_18, primary ? 0x1a1200 : C_FG, text));
    return b;
}

static void diff(const bm_request_t *r)
{
    if (!r->n_diff) return;
    section("Proposed change");
    lv_obj_t *b = ui_box(ui.sh_body);
    lv_obj_set_size(b, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_radius(b, 10, 0);
    lv_obj_set_style_pad_ver(b, 8, 0);
    lv_obj_set_style_pad_hor(b, 12, 0);
    lv_obj_set_style_bg_color(b, ui_hex(0x0d0d0d), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_flex_flow(b, LV_FLEX_FLOW_COLUMN);
    for (int i = 0; i < r->n_diff; i++) {
        char line[140];
        snprintf(line, sizeof(line), "%s %s", r->diff[i].added ? "+" : "\xE2\x88\x92", r->diff[i].line);
        lv_obj_t *l = ui_label(b, &font_mono_15, r->diff[i].added ? 0x7ee2a8 : 0xff8f93, line);
        lv_obj_set_width(l, LV_PCT(100));
        lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_WRAP);
    }
}

static void timeline_row(lv_obj_t *tl, uint32_t dot, const char *text, const char *when)
{
    lv_obj_t *row = ui_box(tl);
    lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(row, 12, 0);
    lv_obj_t *d = ui_box(row);
    lv_obj_set_size(d, 10, 10);
    lv_obj_set_style_margin_top(d, 5, 0);
    lv_obj_set_style_radius(d, 3, 0);
    lv_obj_set_style_bg_color(d, ui_hex(dot), 0);
    lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0);
    lv_obj_t *t = ui_label(row, &font_mono_16, C_FG, text);
    lv_obj_set_flex_grow(t, 1);
    lv_label_set_long_mode(t, LV_LABEL_LONG_MODE_WRAP);
    ui_label(row, &font_mono_15, C_DIM, when);
}

static lv_obj_t *timeline(void)
{
    lv_obj_t *tl = ui_box(ui.sh_body);
    lv_obj_set_size(tl, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(tl, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(tl, 9, 0);
    return tl;
}

static void chip_label(lv_obj_t *parent, const char *text, uint32_t color, bool live)
{
    lv_obj_t *c = ui_box(parent);
    lv_obj_set_size(c, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_pad_ver(c, 3, 0);
    lv_obj_set_style_pad_hor(c, 10, 0);
    lv_obj_set_style_radius(c, 9, 0);
    lv_obj_set_style_bg_color(c, ui_hex(live ? color : 0x222222), 0);
    lv_obj_set_style_bg_opa(c, live ? 0x22 : LV_OPA_COVER, 0);
    ui_label(c, &font_mono_bold_15, live ? color : 0x888888, text);
}

static void look_arrow(lv_obj_t *parent, const char *symbol, int dir)
{
    lv_obj_t *b = ui_box(parent);
    lv_obj_set_size(b, 40, 40);
    lv_obj_set_style_radius(b, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(b, ui_hex(0x1f1c19), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_ext_click_area(b, 8);
    ui_on_tap(b, BM_TAP_SESSION_ACC, dir);
    lv_obj_center(ui_label(b, &lv_font_montserrat_16, C_FG, symbol));
}

static void look_row(const bm_session_t *s)
{
    static const char *const names[] = {"None", "Wizard hat", "Shades", "Headphones", "Crown", "Party hat", "Headband", "Heart"};
    uint16_t hue;
    bm_acc_t acc;
    bm_session_look(s, &hue, &acc);
    lv_obj_t *row = ui_box(ui.sh_body);
    lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_margin_bottom(row, 12, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, 10, 0);
    lv_obj_set_flex_grow(ui_label(row, &font_mono_17, C_DIM, "Pet"), 1);
    look_arrow(row, LV_SYMBOL_LEFT, -1);
    lv_obj_t *name = ui_label(row, &font_mono_semi_17, C_FG, names[acc]);
    lv_obj_set_width(name, 124);
    lv_obj_set_style_text_align(name, LV_TEXT_ALIGN_CENTER, 0);
    look_arrow(row, LV_SYMBOL_RIGHT, 1);
}

static void build_agent(const bm_session_t *s, uint32_t now_ms)
{
    char buf[64], host[17];
    bool live = bm_live(ui.m, s);
    bm_host_label(ui.m->hosts[s->host].name, host, sizeof(host));
    lv_label_set_text(ui.sh_title, s->project);

    lv_obj_t *dh = ui_box(ui.sh_body);
    lv_obj_set_size(dh, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(dh, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(dh, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(dh, 14, 0);
    lv_obj_set_style_margin_bottom(dh, 12, 0);
    ui.sh_pet = ui_pet_create(dh, 72);
    ui.sh_pet_session = (int8_t)(s - ui.m->sessions);
    lv_obj_t *col = ui_box(dh);
    lv_obj_set_size(col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    chip_label(col, bm_session_label(ui.m, s), bm_status_color(s->status), live);
    snprintf(buf, sizeof(buf), "%s Mac", host);
    lv_obj_set_style_margin_top(ui_label(col, &font_mono_15, C_DIM, buf), 6, 0);

    look_row(s);
    lv_obj_t *t = kv_table();
    kv(t, "Task", s->task, C_FG);
    bm_fmt_dur(bm_wall_ms(ui.m, now_ms) - s->since * 1000, buf, sizeof(buf));
    kv(t, "Time in state", buf, C_FG);
    if (s->tokens >= 0) {
        snprintf(buf, sizeof(buf), "%ld k", (long)(s->tokens / 1000));
        kv(t, "Session tokens", buf, C_FG);
    }

    if (s->has_request) {
        lv_obj_t *b = wide_button(s->req.is_question ? "Review question" : "Review permission", true);
        ui_on_tap(b, BM_TAP_OPEN_PERM, ui.sh_pet_session);
        diff(&s->req);
    } else if (s->status == BM_WAITING) {
        box("Answer it on the Mac.", 0x14120f, 0xd9d1c6);
    }
    if (s->status == BM_ERROR) box(s->error[0] ? s->error : "The task failed", 0x2a0a0c, 0xffc7c9);
    if (s->status == BM_DONE) box(s->summary[0] ? s->summary : "Task finished.", 0x06231a, 0xc9ffe6);

    section("Recent activity");
    lv_obj_t *tl = timeline();
    for (int i = s->n_steps - 1; i >= 0; i--) {
        bm_fmt_ago(bm_wall_ms(ui.m, now_ms) - s->steps[i].ts * 1000, buf, sizeof(buf));
        timeline_row(tl, bm_step_color(s->steps[i].kind), s->steps[i].text, buf);
    }
}

static void build_perm(const bm_session_t *s, uint32_t now_ms)
{
    const bm_request_t *r = &s->req;
    char buf[48], host[17];
    lv_label_set_text(ui.sh_title, r->is_question ? "Question" : "Permission");
    bm_host_label(ui.m->hosts[s->host].name, host, sizeof(host));
    lv_obj_t *t = kv_table();
    kv(t, "Session", s->project, C_FG);
    kv(t, "Mac", host, C_FG);
    kv(t, "Tool", r->tool, C_FG);
    kv(t, "Risk", r->is_question ? "\xE2\x80\x94" : r->high_risk ? "high" : "low",
       r->is_question ? C_FG : r->high_risk ? BM_C_ERR : BM_C_DONE);
    if (r->cwd[0]) kv(t, "Directory", r->cwd, C_FG);
    bm_fmt_ago(bm_wall_ms(ui.m, now_ms) - s->since * 1000, buf, sizeof(buf));
    kv(t, "Requested", buf, C_FG);

    section(r->is_question ? "Question" : "Requested action");
    box(r->detail, 0x120e05, 0xfff4d6);
    if (r->why[0]) {
        section("Why it asks");
        box(r->why, 0x14120f, 0xd9d1c6);
    }
    diff(r);
    if (r->high_risk)
        box("High-risk actions are only approved on the Mac. From here you can only deny them.", 0x2a0a0c, 0xffc7c9);
    else if (!r->is_question && !r->remote_allowed)
        box("This action is only approved on the Mac. From here you can only deny it.", 0x2a0a0c, 0xffc7c9);
    ui_on_tap(wide_button("Back to the decision", false), BM_TAP_BACK, 0);
}

static void build_usage(uint32_t now_ms)
{
    char buf[48], host[17];
    lv_label_set_text(ui.sh_title, "Usage breakdown");
    for (int i = 0; i < BM_MAX_HOSTS; i++) {
        const bm_host_t *h = &ui.m->hosts[i];
        if (!h->used || !h->usage.known) continue;
        bm_host_label(h->name, host, sizeof(host));
        section(host);
        lv_obj_t *t = kv_table();
        snprintf(buf, sizeof(buf), "%d%%", bm_usage_pct(&h->usage));
        kv(t, "5 h window", buf, C_FG);
        bm_fmt_dur((int64_t)bm_usage_reset_s(&h->usage, now_ms) * 1000, buf, sizeof(buf));
        kv(t, "Resets in", buf, C_FG);
        snprintf(buf, sizeof(buf), "%d%%", (int)(h->usage.weekly_pct + .5f));
        kv(t, "Week", buf, C_FG);
        if (h->usage.tokens_today >= 0) {
            snprintf(buf, sizeof(buf), "%.2f M", (double)h->usage.tokens_today / 1e6);
            kv(t, "Tokens today", buf, C_FG);
        }
    }

    int64_t total = 0;
    for (int i = 0; i < BM_MAX_SESSIONS; i++)
        if (ui.m->sessions[i].used && ui.m->sessions[i].tokens > 0) total += ui.m->sessions[i].tokens;
    section("Per open session");
    int8_t order[BM_MAX_SESSIONS];
    int n = bm_agent_order(ui.m, order, BM_MAX_SESSIONS);
    for (int i = 0; i < n; i++) {
        const bm_session_t *s = &ui.m->sessions[order[i]];
        if (s->tokens < 0) continue;
        lv_obj_t *row = ui_box(ui.sh_body);
        lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_margin_bottom(row, 10, 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_COLUMN);
        lv_obj_t *head = ui_box(row);
        lv_obj_set_size(head, LV_PCT(100), LV_SIZE_CONTENT);
        ui_label(head, &font_mono_16, C_FG, s->project);
        snprintf(buf, sizeof(buf), "%ld k", (long)(s->tokens / 1000));
        lv_obj_align(ui_label(head, &font_mono_16, C_FG, buf), LV_ALIGN_RIGHT_MID, 0, 0);
        uint16_t hue;
        bm_acc_t acc;
        bm_session_look(s, &hue, &acc);
        lv_obj_t *track = ui_track(row, LV_PCT(100), 0);
        lv_obj_set_style_margin_top(track, 2, 0);
        lv_obj_set_style_bg_color(lv_obj_get_child(track, 0), lv_color_hsv_to_rgb(hue, 66, 100), 0);
        ui_track_set(track, total ? (int)(s->tokens * 100 / total) : 0);
    }
}

static void build_hilo(uint32_t now_ms)
{
    lv_label_set_text(ui.sh_title, "Current task");
    int hi = bm_hilo_host(ui.m);
    const bm_hilo_t *h = hi < 0 ? NULL : &ui.m->hosts[hi].hilo;
    if (!h || !h->has_current) {
        body_label(&font_mono_17, C_DIM, "No current task.");
        return;
    }
    lv_obj_t *title = body_label(&font_pixel_26, C_FG, h->current.title);
    lv_obj_set_style_margin_bottom(title, 10, 0);
    lv_obj_t *t = kv_table();
    kv(t, "Project", h->current.project, C_FG);
    if (h->current.jira[0]) kv(t, "Jira", h->current.jira, C_FG);
    char buf[24];
    bm_fmt_hms(bm_wall_ms(ui.m, now_ms) - h->started_at * 1000, buf, sizeof(buf));
    kv(t, "Active time", buf, C_FG);

    section("Agreements");
    if (!h->n_agreements) body_label(&font_mono_16, C_DIM, "No agreements yet.");
    lv_obj_t *tl = timeline();
    for (int i = 0; i < h->n_agreements; i++) timeline_row(tl, BM_C_DONE, h->agreements[i], "");

    section("Linked sessions");
    lv_obj_t *chips = ui_box(ui.sh_body);
    lv_obj_set_size(chips, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(chips, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_gap(chips, 6, 0);
    int linked = 0;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &ui.m->sessions[i];
        if (!s->used || s->host != hi || strcmp(s->project, h->current.project) != 0) continue;
        lv_obj_t *c = ui_box(chips);
        lv_obj_set_size(c, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_style_pad_ver(c, 5, 0);
        lv_obj_set_style_pad_hor(c, 11, 0);
        lv_obj_set_style_radius(c, 10, 0);
        lv_obj_set_style_bg_color(c, ui_hex(0x15130f), 0);
        lv_obj_set_style_bg_opa(c, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(c, 2, 0);
        lv_obj_set_style_border_color(c, ui_hex(0x2a2520), 0);
        char text[96];
        snprintf(text, sizeof(text), "%s \xC2\xB7 %s", s->project, bm_session_label(ui.m, s));
        ui_label(c, &font_mono_15, C_FG, text);
        ui_on_tap(c, BM_TAP_AGENT, i);
        linked++;
    }
    if (!linked) body_label(&font_mono_16, C_DIM, "No open sessions for this project.");
}

void ui_sheet_create(lv_obj_t *scr)
{
    ui.sheet = ui_box(scr);
    lv_obj_set_size(ui.sheet, SCREEN, SCREEN);
    lv_obj_set_style_bg_color(ui.sheet, ui_hex(0x060606), 0);
    lv_obj_set_style_bg_opa(ui.sheet, LV_OPA_COVER, 0);
    lv_obj_set_clickable(ui.sheet, true);
    lv_obj_set_flex_flow(ui.sheet, LV_FLEX_FLOW_COLUMN);

    lv_obj_t *head = ui_box(ui.sheet);
    lv_obj_set_size(head, LV_PCT(100), 66);
    lv_obj_set_style_pad_top(head, 6, 0);
    lv_obj_set_style_pad_hor(head, 24, 0);
    lv_obj_set_style_pad_column(head, 14, 0);
    lv_obj_set_style_border_side(head, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_width(head, 2, 0);
    lv_obj_set_style_border_color(head, ui_hex(C_LINE), 0);
    lv_obj_set_flex_flow(head, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(head, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_t *back = ui_box(head);
    lv_obj_set_size(back, 42, 42);
    lv_obj_set_style_radius(back, 12, 0);
    lv_obj_set_style_bg_color(back, ui_hex(0x171512), 0);
    lv_obj_set_style_bg_opa(back, LV_OPA_COVER, 0);
    lv_obj_center(ui_label(back, &lv_font_montserrat_24, C_FG, LV_SYMBOL_LEFT));
    ui_on_tap(back, BM_TAP_BACK, 0);
    ui.sh_title = ui_label(head, &font_pixel_26, C_FG, "");
    lv_obj_set_flex_grow(ui.sh_title, 1);
    lv_label_set_long_mode(ui.sh_title, LV_LABEL_LONG_MODE_DOTS);

    ui.sh_body = ui_box(ui.sheet);
    lv_obj_set_width(ui.sh_body, LV_PCT(100));
    lv_obj_set_flex_grow(ui.sh_body, 1);
    lv_obj_set_style_pad_top(ui.sh_body, 16, 0);
    lv_obj_set_style_pad_hor(ui.sh_body, 26, 0);
    lv_obj_set_style_pad_bottom(ui.sh_body, 32, 0);
    lv_obj_set_flex_flow(ui.sh_body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scrollable(ui.sh_body, true);
    lv_obj_set_scroll_dir(ui.sh_body, LV_DIR_VER);
    lv_obj_set_clickable(ui.sh_body, true);
    ui_show(ui.sheet, false);
}

void ui_sheet_update(uint32_t now_ms)
{
    bm_sheet_t kind = ui.m->sheet;
    ui_show(ui.sheet, kind != BM_SHEET_NONE);
    if (kind == BM_SHEET_NONE) return;
    int32_t scroll = lv_obj_get_scroll_y(ui.sh_body);
    lv_obj_clean(ui.sh_body);
    ui.sh_pet = NULL;
    int idx = ui.m->sheet_session;
    const bm_session_t *s = idx >= 0 ? &ui.m->sessions[idx] : NULL;
    switch (kind) {
    case BM_SHEET_AGENT:
        if (s && s->used) build_agent(s, now_ms);
        break;
    case BM_SHEET_PERM:
        if (s && s->used && s->has_request) build_perm(s, now_ms);
        break;
    case BM_SHEET_USAGE: build_usage(now_ms); break;
    case BM_SHEET_HILO: build_hilo(now_ms); break;
    case BM_SHEET_NONE: break;
    }
    lv_obj_update_layout(ui.sh_body);
    lv_obj_scroll_to_y(ui.sh_body, scroll, LV_ANIM_OFF);
}

void ui_sheet_frame(void)
{
    if (ui.m->sheet == BM_SHEET_AGENT && ui.sh_pet && ui.sh_pet_session >= 0)
        ui_session_pet(ui.sh_pet, &ui.m->sessions[ui.sh_pet_session]);
}
