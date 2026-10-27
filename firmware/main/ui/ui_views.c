#include <math.h>
#include <stdio.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "ui_priv.h"

#define PAD_TOP 62
#define PAD_SIDE 30
#define PAD_BOTTOM 46
#define CONTENT_W (SCREEN - 2 * PAD_SIDE)
#define UBAR_W ((CONTENT_W - 18) / 2)
#define SPARK_H 44
#define COVER_SIDE 150

static const int32_t RING_SINGLE = 216, RING_DUAL = 168;

static lv_obj_t *view_box(int i)
{
    lv_obj_t *v = ui_box(ui.strip);
    lv_obj_set_size(v, SCREEN, SCREEN);
    lv_obj_set_pos(v, i * SCREEN, 0);
    lv_obj_set_style_pad_top(v, PAD_TOP, 0);
    lv_obj_set_style_pad_bottom(v, PAD_BOTTOM, 0);
    lv_obj_set_style_pad_hor(v, PAD_SIDE, 0);
    lv_obj_set_flex_flow(v, LV_FLEX_FLOW_COLUMN);
    return v;
}

static lv_obj_t *title_row(lv_obj_t *parent, const char *title, lv_obj_t **small)
{
    lv_obj_t *row = ui_box(parent);
    lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_pad_bottom(row, 12, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_END);
    ui_label(row, F_TITLE, C_FG, title);
    *small = ui_label(row, F_SMALL, C_DIM, "");
    return row;
}

static void create_home(lv_obj_t *v)
{
    lv_obj_set_flex_align(v, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ui.home_pet = ui_pet_create(v, 224);
    lv_obj_set_style_margin_top(ui.home_pet->img, -8, 0);

    lv_obj_t *texts = ui_box(v);
    lv_obj_set_size(texts, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(texts, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(texts, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_margin_top(texts, -8, 0);
    ui.home_msg = ui_label(texts, &font_pixel_32, C_FG, "");
    lv_obj_set_width(ui.home_msg, LV_PCT(100));
    lv_obj_set_style_text_align(ui.home_msg, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(ui.home_msg, LV_LABEL_LONG_MODE_DOTS);
    ui_on_tap(ui.home_msg, BM_TAP_OPEN_PERM, -1);
    ui.home_sub = ui_label(texts, &font_mono_18, C_DIM, "");
    lv_obj_set_style_margin_top(ui.home_sub, 6, 0);

    lv_obj_t *stats = ui_box(v);
    lv_obj_set_size(stats, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(stats, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(stats, 10, 0);
    lv_obj_set_style_margin_top(stats, 10, 0);
    static const char *const names[3] = {"5 H SESSION", "WEEK", "RESET"};
    for (int i = 0; i < 3; i++) {
        lv_obj_t *s = ui_box(stats);
        lv_obj_set_flex_grow(s, 1);
        lv_obj_set_height(s, LV_SIZE_CONTENT);
        lv_obj_set_style_border_side(s, LV_BORDER_SIDE_TOP, 0);
        lv_obj_set_style_border_width(s, 2, 0);
        lv_obj_set_style_border_color(s, ui_hex(C_LINE), 0);
        lv_obj_set_style_pad_top(s, 8, 0);
        lv_obj_set_flex_flow(s, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(s, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        ui.stat_val[i] = ui_label(s, &font_mono_bold_23, C_FG, "--");
        lv_obj_t *n = ui_label(s, &font_mono_15, C_DIM, names[i]);
        lv_obj_set_style_text_letter_space(n, 1, 0);
    }
}

static void create_agents(lv_obj_t *v)
{
    title_row(v, "Agents", &ui.ag_count);
    lv_obj_set_style_pad_row(v, 6, 0);
    for (int i = 0; i < BM_AGENT_ROWS; i++) {
        lv_obj_t *row = ui_box(v);
        ui.rows[i].row = row;
        lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_pad_ver(row, 6, 0);
        lv_obj_set_style_pad_hor(row, 10, 0);
        lv_obj_set_style_pad_column(row, 12, 0);
        lv_obj_set_style_radius(row, 14, 0);
        lv_obj_set_style_bg_color(row, ui_hex(0x0d0c0b), 0);
        lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(row, 2, 0);
        lv_obj_set_style_border_opa(row, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_color(row, ui_hex(BM_C_WAIT), 0);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        ui_on_tap(row, BM_TAP_AGENT, -1);

        ui.rows[i].pet = ui_pet_create(row, 48);
        lv_obj_t *mid = ui_box(row);
        lv_obj_set_flex_grow(mid, 1);
        lv_obj_set_height(mid, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(mid, LV_FLEX_FLOW_COLUMN);
        ui.rows[i].name = ui_label(mid, &font_mono_semi_20, C_FG, "");
        ui.rows[i].task = ui_label(mid, &font_mono_15, C_DIM, "");
        lv_obj_set_width(ui.rows[i].name, LV_PCT(100));
        lv_obj_set_width(ui.rows[i].task, LV_PCT(100));
        lv_label_set_long_mode(ui.rows[i].name, LV_LABEL_LONG_MODE_DOTS);
        lv_label_set_long_mode(ui.rows[i].task, LV_LABEL_LONG_MODE_DOTS);

        lv_obj_t *rt = ui_box(row);
        lv_obj_set_size(rt, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(rt, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(rt, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_END);
        ui.rows[i].chip = ui_box(rt);
        lv_obj_set_size(ui.rows[i].chip, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_style_pad_ver(ui.rows[i].chip, 3, 0);
        lv_obj_set_style_pad_hor(ui.rows[i].chip, 10, 0);
        lv_obj_set_style_radius(ui.rows[i].chip, 9, 0);
        lv_obj_set_style_bg_opa(ui.rows[i].chip, 0x22, 0);
        ui.rows[i].chip_lbl = ui_label(ui.rows[i].chip, &font_mono_bold_15, C_FG, "");
        ui.rows[i].el = ui_label(rt, &font_mono_15, C_DIM, "");
        lv_obj_set_style_margin_top(ui.rows[i].el, 2, 0);
    }
    ui.ag_empty = ui_label(v, &font_mono_18, C_DIM, "No active sessions.\nYour buddy is relaxed.");
    lv_obj_set_width(ui.ag_empty, LV_PCT(100));
    lv_obj_set_style_text_align(ui.ag_empty, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_margin_top(ui.ag_empty, 80, 0);
}

static void create_usage(lv_obj_t *v)
{
    lv_obj_t *small;
    title_row(v, "Usage", &small);
    lv_label_set_text(small, "tap for breakdown");
    lv_obj_set_flex_align(v, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lv_obj_t *rings = ui_box(v);
    lv_obj_set_size(rings, LV_PCT(100), RING_SINGLE);
    lv_obj_set_flex_flow(rings, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(rings, LV_FLEX_ALIGN_SPACE_EVENLY, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    for (int i = 0; i < BM_MAX_HOSTS; i++) {
        lv_obj_t *box = ui_box(rings);
        ui.rings[i].box = box;
        lv_obj_set_size(box, RING_SINGLE, RING_SINGLE);
        ui_on_tap(box, BM_TAP_USAGE, 0);
        lv_obj_t *arc = lv_arc_create(box);
        ui.rings[i].arc = arc;
        lv_obj_set_size(arc, LV_PCT(100), LV_PCT(100));
        lv_obj_center(arc);
        lv_arc_set_rotation(arc, 270);
        lv_arc_set_bg_angles(arc, 0, 360);
        lv_arc_set_range(arc, 0, 100);
        lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
        lv_obj_set_clickable(arc, false);
        lv_obj_set_style_arc_color(arc, ui_hex(C_TRACK), LV_PART_MAIN);
        lv_obj_set_style_arc_rounded(arc, true, LV_PART_INDICATOR);
        lv_obj_t *ctr = ui_box(box);
        lv_obj_set_size(ctr, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_center(ctr);
        lv_obj_set_flex_flow(ctr, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(ctr, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        ui.rings[i].pct = ui_label(ctr, &font_pixel_58, C_FG, "0%");
        ui.rings[i].lbl = ui_label(ctr, &font_mono_15, C_DIM, "5 H WINDOW");
        lv_obj_set_style_text_letter_space(ui.rings[i].lbl, 1, 0);
        lv_obj_set_style_margin_top(ui.rings[i].lbl, 6, 0);
    }

    ui.reset = ui_label(v, &font_mono_17, C_DIM, "");
    lv_label_set_recolor(ui.reset, true);
    lv_obj_set_style_margin_top(ui.reset, 6, 0);
    lv_obj_set_style_margin_bottom(ui.reset, 12, 0);

    lv_obj_t *bars = ui_box(v);
    lv_obj_set_size(bars, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(bars, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(bars, 18, 0);
    const char *names[2] = {"WEEK", "TOKENS TODAY"};
    lv_obj_t **vals[2] = {&ui.week_val, &ui.tok_val};
    for (int i = 0; i < 2; i++) {
        lv_obj_t *col = ui_box(bars);
        lv_obj_set_size(col, UBAR_W, LV_SIZE_CONTENT);
        lv_obj_t *head = ui_box(col);
        lv_obj_set_size(head, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_t *n = ui_label(head, &font_mono_15, C_DIM, names[i]);
        lv_obj_set_style_text_letter_space(n, 1, 0);
        *vals[i] = ui_label(head, &font_mono_16, C_FG, "--");
        lv_obj_align(*vals[i], LV_ALIGN_RIGHT_MID, 0, 0);
        lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
        if (i == 0) {
            ui.week_bar = ui_track(col, UBAR_W, BM_C_INFO);
            lv_obj_set_style_margin_top(ui.week_bar, 6, 0);
        } else {
            lv_obj_t *wrap = ui_box(col);
            lv_obj_set_size(wrap, UBAR_W, SPARK_H);
            lv_obj_set_style_margin_top(wrap, 4, 0);
            ui.spark = lv_line_create(wrap);
            lv_obj_set_style_line_color(ui.spark, ui_hex(BM_C_INFO), 0);
            lv_obj_set_style_line_width(ui.spark, 2, 0);
            ui.spark_dot = ui_box(wrap);
            lv_obj_set_size(ui.spark_dot, 6, 6);
            lv_obj_set_style_radius(ui.spark_dot, 3, 0);
            lv_obj_set_style_bg_color(ui.spark_dot, ui_hex(BM_C_INFO), 0);
            lv_obj_set_style_bg_opa(ui.spark_dot, LV_OPA_COVER, 0);
        }
    }
}

static void create_hilo(lv_obj_t *v)
{
    title_row(v, "Hilo", &ui.hilo_day);
    lv_obj_t *card = ui_box(v);
    ui.hilo_card = card;
    lv_obj_set_size(card, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_radius(card, 18, 0);
    lv_obj_set_style_bg_color(card, ui_hex(0x0e0c0a), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(card, 2, 0);
    lv_obj_set_style_border_color(card, ui_hex(0x2a241e), 0);
    lv_obj_set_style_pad_ver(card, 16, 0);
    lv_obj_set_style_pad_hor(card, 18, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    ui_on_tap(card, BM_TAP_HILO, 0);

    lv_obj_t *k = ui_box(card);
    lv_obj_set_size(k, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_text_letter_space(ui_label(k, &font_mono_15, BM_C_WORK, "NOW"), 1, 0);
    lv_obj_align(ui_label(k, &font_mono_15, BM_C_WORK, "DETAILS \xE2\x80\xBA"), LV_ALIGN_RIGHT_MID, 0, 0);
    ui.hilo_now = ui_label(card, F_TITLE, C_FG, "");
    lv_obj_set_width(ui.hilo_now, LV_PCT(100));
    lv_label_set_long_mode(ui.hilo_now, LV_LABEL_LONG_MODE_WRAP);
    lv_obj_set_style_margin_top(ui.hilo_now, 6, 0);
    lv_obj_set_style_margin_bottom(ui.hilo_now, 10, 0);
    lv_obj_t *meta = ui_box(card);
    lv_obj_set_size(meta, LV_PCT(100), LV_SIZE_CONTENT);
    ui.hilo_proj = ui_label(meta, &font_mono_16, C_DIM, "");
    ui.hilo_time = ui_label(meta, &font_mono_16, C_FG, "");
    lv_obj_align(ui.hilo_time, LV_ALIGN_RIGHT_MID, 0, 0);

    lv_obj_t *next = ui_box(v);
    lv_obj_set_size(next, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(next, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(next, 9, 0);
    lv_obj_set_style_margin_top(next, 16, 0);
    for (int i = 0; i < BM_MAX_NEXT; i++) {
        lv_obj_t *row = ui_box(next);
        lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_column(row, 12, 0);
        lv_obj_t *check = ui_box(row);
        lv_obj_set_size(check, 16, 16);
        lv_obj_set_style_border_width(check, 2, 0);
        lv_obj_set_style_border_color(check, ui_hex(0x4a443d), 0);
        lv_obj_set_style_radius(check, 3, 0);
        ui.hilo_next[i] = ui_label(row, &font_mono_17, 0xcfc8bf, "");
        lv_obj_set_flex_grow(ui.hilo_next[i], 1);
        lv_label_set_long_mode(ui.hilo_next[i], LV_LABEL_LONG_MODE_DOTS);
    }
    ui.hilo_agree = ui_label(v, &font_mono_15, C_DIM, "");
    lv_label_set_recolor(ui.hilo_agree, true);
    lv_obj_set_style_margin_top(ui.hilo_agree, 14, 0);
}

static lv_obj_t *round_button(lv_obj_t *parent, int32_t size, const lv_font_t *font, const char *symbol, bm_tap_t tap,
                              int arg)
{
    lv_obj_t *b = ui_box(parent);
    lv_obj_set_size(b, size, size);
    lv_obj_set_style_radius(b, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(b, 2, 0);
    lv_obj_set_style_border_color(b, ui_hex(0x2f2c28), 0);
    lv_obj_set_style_bg_color(b, ui_hex(0x161412), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_ext_click_area(b, 8);
    lv_obj_t *l = ui_label(b, font, C_FG, symbol);
    lv_obj_center(l);
    ui_on_tap(b, tap, arg);
    return l;
}

static void create_music(lv_obj_t *v)
{
    lv_obj_set_flex_align(v, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ui.cover_px = heap_caps_calloc_prefer(COVER_SIDE * COVER_SIDE, 2, 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    ui.cover_dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    ui.cover_dsc.header.cf = LV_COLOR_FORMAT_RGB565;
    ui.cover_dsc.header.w = COVER_SIDE;
    ui.cover_dsc.header.h = COVER_SIDE;
    ui.cover_dsc.header.stride = COVER_SIDE * 2;
    ui.cover_dsc.data_size = COVER_SIDE * COVER_SIDE * 2;
    ui.cover_dsc.data = (const uint8_t *)ui.cover_px;
    ui.cover = lv_image_create(v);
    lv_image_set_src(ui.cover, &ui.cover_dsc);
    lv_obj_set_size(ui.cover, COVER_SIDE, COVER_SIDE);
    lv_obj_set_style_radius(ui.cover, 16, 0);
    lv_obj_set_style_clip_corner(ui.cover, true, 0);

    ui.song = ui_label(v, F_TITLE, C_FG, "");
    lv_obj_set_width(ui.song, LV_PCT(100));
    lv_obj_set_style_text_align(ui.song, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(ui.song, LV_LABEL_LONG_MODE_DOTS);
    lv_obj_set_style_margin_top(ui.song, 12, 0);
    ui.artist = ui_label(v, &font_mono_17, C_DIM, "");

    lv_obj_t *prog = ui_box(v);
    lv_obj_set_size(prog, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_margin_top(prog, 12, 0);
    lv_obj_set_flex_flow(prog, LV_FLEX_FLOW_COLUMN);
    ui.song_bar = ui_track(prog, CONTENT_W, C_FG);
    lv_obj_t *times = ui_box(prog);
    lv_obj_set_size(times, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_margin_top(times, 6, 0);
    ui.song_cur = ui_label(times, &font_mono_15, C_DIM, "");
    ui.song_len = ui_label(times, &font_mono_15, C_DIM, "");
    lv_obj_align(ui.song_len, LV_ALIGN_RIGHT_MID, 0, 0);

    ui.song_ctl = ui_box(v);
    lv_obj_set_size(ui.song_ctl, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(ui.song_ctl, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(ui.song_ctl, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(ui.song_ctl, 28, 0);
    lv_obj_set_style_margin_top(ui.song_ctl, 10, 0);
    round_button(ui.song_ctl, 72, &lv_font_montserrat_24, LV_SYMBOL_PREV, BM_TAP_MEDIA, BM_MEDIA_PREVIOUS);
    ui.song_play =
        round_button(ui.song_ctl, 96, &lv_font_montserrat_32, LV_SYMBOL_PAUSE, BM_TAP_MEDIA, BM_MEDIA_PLAY_PAUSE);
    round_button(ui.song_ctl, 72, &lv_font_montserrat_24, LV_SYMBOL_NEXT, BM_TAP_MEDIA, BM_MEDIA_NEXT);
}

static lv_obj_t *stepper(lv_obj_t *parent, const char *name, bm_tap_t tap)
{
    lv_obj_t *col = ui_box(parent);
    lv_obj_set_size(col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(col, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_text_letter_space(ui_label(col, &font_mono_15, C_DIM, name), 1, 0);
    lv_obj_t *row = ui_box(col);
    lv_obj_set_size(row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_margin_top(row, 6, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, 10, 0);
    round_button(row, 40, &lv_font_montserrat_16, LV_SYMBOL_MINUS, tap, -1);
    lv_obj_t *value = ui_label(row, &font_mono_bold_23, C_FG, "");
    lv_obj_set_width(value, 64);
    lv_obj_set_style_text_align(value, LV_TEXT_ALIGN_CENTER, 0);
    round_button(row, 40, &lv_font_montserrat_16, LV_SYMBOL_PLUS, tap, 1);
    return value;
}

static void create_pomodoro(lv_obj_t *v)
{
    title_row(v, "Focus", &ui.pomo_cycle);
    lv_obj_set_flex_align(v, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_t *mid = ui_box(v);
    lv_obj_set_size(mid, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(mid, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(mid, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(mid, 18, 0);
    lv_obj_set_style_pad_ver(mid, 14, 0);
    ui.pomo_pet = ui_pet_create(mid, 96);
    ui.pomo_ring = ui_box(mid);
    lv_obj_add_flag(ui.pomo_ring, LV_OBJ_FLAG_FLOATING);
    lv_obj_set_size(ui.pomo_ring, 124, 124);
    lv_obj_set_style_radius(ui.pomo_ring, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(ui.pomo_ring, 6, 0);
    ui_show(ui.pomo_ring, false);
    lv_obj_t *texts = ui_box(mid);
    lv_obj_set_size(texts, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(texts, LV_FLEX_FLOW_COLUMN);
    ui.pomo_phase = ui_label(texts, &font_mono_bold_18, BM_C_WORK, "");
    lv_obj_set_style_text_letter_space(ui.pomo_phase, 2, 0);
    ui.pomo_time = ui_label(texts, &font_pixel_58, C_FG, "25:00");

    ui.pomo_bar = ui_track(v, CONTENT_W, BM_C_WORK);
    lv_obj_set_style_margin_top(ui.pomo_bar, 10, 0);

    ui.pomo_steps = ui_box(v);
    lv_obj_set_size(ui.pomo_steps, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_style_margin_top(ui.pomo_steps, 14, 0);
    lv_obj_set_flex_flow(ui.pomo_steps, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(ui.pomo_steps, LV_FLEX_ALIGN_SPACE_AROUND, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ui.pomo_work = stepper(ui.pomo_steps, "WORK", BM_TAP_POMO_WORK);
    ui.pomo_break = stepper(ui.pomo_steps, "BREAK", BM_TAP_POMO_BREAK);

    lv_obj_t *ctl = ui_box(v);
    lv_obj_set_size(ctl, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_margin_top(ctl, 14, 0);
    lv_obj_set_flex_flow(ctl, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(ctl, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(ctl, 28, 0);
    round_button(ctl, 52, &lv_font_montserrat_24, LV_SYMBOL_REFRESH, BM_TAP_POMO_RESET, 0);
    ui.pomo_play = round_button(ctl, 68, &lv_font_montserrat_32, LV_SYMBOL_PLAY, BM_TAP_POMO_TOGGLE, 0);
}

static void alarm_catch_cb(lv_event_t *e)
{
    (void)e;
    bm_alarm_stop(ui.m, lv_tick_get());
}

/* Above the views and below alerts, so any touch on the screen silences the alarm without acting. */
void ui_alarm_create(lv_obj_t *scr)
{
    ui.alarm_catch = ui_box(scr);
    lv_obj_set_size(ui.alarm_catch, SCREEN, SCREEN);
    lv_obj_add_flag(ui.alarm_catch, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(ui.alarm_catch, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_event_cb(ui.alarm_catch, alarm_catch_cb, LV_EVENT_PRESSED, NULL);
    ui_show(ui.alarm_catch, false);
}

void ui_views_create(lv_obj_t *scr)
{
    ui.strip = ui_box(scr);
    lv_obj_set_size(ui.strip, SCREEN * BM_VIEWS, SCREEN);
    for (int i = 0; i < BM_VIEWS; i++) ui.views[i] = view_box(i);
    create_home(ui.views[BM_VIEW_HOME]);
    create_agents(ui.views[BM_VIEW_AGENTS]);
    create_usage(ui.views[BM_VIEW_USAGE]);
    create_hilo(ui.views[BM_VIEW_HILO]);
    create_music(ui.views[BM_VIEW_MUSIC]);
    create_pomodoro(ui.views[BM_VIEW_POMODORO]);

    lv_obj_t *dots = ui_box(scr);
    lv_obj_set_size(dots, SCREEN, 8);
    lv_obj_align(dots, LV_ALIGN_BOTTOM_MID, 0, -18);
    lv_obj_set_flex_flow(dots, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(dots, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(dots, 9, 0);
    for (int i = 0; i < BM_VIEWS; i++) {
        ui.dots[i] = ui_box(dots);
        lv_obj_set_size(ui.dots[i], 8, 8);
        lv_obj_set_style_radius(ui.dots[i], 4, 0);
        lv_obj_set_style_bg_opa(ui.dots[i], LV_OPA_COVER, 0);
    }
}

static void strip_x_cb(void *obj, int32_t v)
{
    lv_obj_set_x(obj, v);
}

static void update_strip(void)
{
    static int shown = -1;
    int view = ui.m->view;
    for (int i = 0; i < BM_VIEWS; i++) {
        lv_obj_set_width(ui.dots[i], i == view ? 24 : 8);
        lv_obj_set_style_bg_color(ui.dots[i], ui_hex(i == view ? C_FG : 0x34302b), 0);
    }
    if (shown == view) return;
    int32_t target = -view * SCREEN;
    if (shown < 0) {
        lv_obj_set_x(ui.strip, target);
    } else {
        lv_anim_t a;
        lv_anim_init(&a);
        lv_anim_set_var(&a, ui.strip);
        lv_anim_set_values(&a, lv_obj_get_x(ui.strip), target);
        lv_anim_set_duration(&a, 380);
        lv_anim_set_path_cb(&a, lv_anim_path_ease_out);
        lv_anim_set_exec_cb(&a, strip_x_cb);
        lv_anim_start(&a);
    }
    shown = view;
}

static const bm_usage_t *main_usage(void)
{
    int h = bm_usage_host(ui.m);
    return h < 0 ? NULL : &ui.m->hosts[h].usage;
}

static void update_home(void)
{
    bm_home_t h;
    bm_home(ui.m, lv_tick_get(), &h);
    lv_label_set_text(ui.home_msg, h.msg);
    lv_obj_set_style_text_color(ui.home_msg, ui_hex(h.colored ? h.color : C_FG), 0);
    lv_label_set_text(ui.home_sub, h.sub);
    ui_set_tap_arg(ui.home_msg, h.tap_session);

    const bm_usage_t *u = main_usage();
    if (!u) {
        lv_label_set_text(ui.stat_val[0], "--");
        lv_label_set_text(ui.stat_val[1], "--");
        return;
    }
    int pct = bm_usage_pct(u);
    lv_label_set_text_fmt(ui.stat_val[0], "%d%%", pct);
    lv_obj_set_style_text_color(ui.stat_val[0], ui_hex(pct >= 80 ? bm_usage_color(pct) : C_FG), 0);
    lv_label_set_text_fmt(ui.stat_val[1], "%d%%", (int)lroundf(u->weekly_pct));
}

static void update_agents(void)
{
    int8_t order[BM_MAX_SESSIONS];
    int total = bm_session_count(ui.m);
    int n = bm_agent_order(ui.m, order, BM_AGENT_ROWS);
    lv_label_set_text_fmt(ui.ag_count, "%d %s", total, total == 1 ? "session" : "sessions");
    ui_show(ui.ag_empty, total == 0);
    for (int i = 0; i < BM_AGENT_ROWS; i++) {
        ui_show(ui.rows[i].row, i < n);
        ui.rows[i].session = i < n ? order[i] : -1;
        if (i >= n) continue;
        const bm_session_t *s = &ui.m->sessions[order[i]];
        bool live = bm_live(ui.m, s);
        char host[17];
        bm_host_label(ui.m->hosts[s->host].name, host, sizeof(host));
        lv_label_set_text(ui.rows[i].name, s->project);
        lv_label_set_text_fmt(ui.rows[i].task, "%s \xC2\xB7 %s", host, s->task);
        uint32_t c = live ? bm_status_color(s->status) : 0x888888;
        lv_label_set_text(ui.rows[i].chip_lbl, live ? bm_status_label(s->status) : "offline");
        lv_obj_set_style_text_color(ui.rows[i].chip_lbl, ui_hex(c), 0);
        lv_obj_set_style_bg_color(ui.rows[i].chip, ui_hex(live ? c : 0x222222), 0);
        lv_obj_set_style_bg_opa(ui.rows[i].chip, live ? 0x22 : LV_OPA_COVER, 0);
        lv_obj_set_style_opa(ui.rows[i].row, live ? LV_OPA_COVER : 97, 0);
        ui_set_tap_arg(ui.rows[i].row, order[i]);
    }
}

static void update_rings(uint32_t now_ms)
{
    int shown = 0, idx[BM_MAX_HOSTS];
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (ui.m->hosts[i].used && ui.m->hosts[i].usage.known) idx[shown++] = i;
    int32_t size = shown > 1 ? RING_DUAL : RING_SINGLE;
    for (int r = 0; r < BM_MAX_HOSTS; r++) {
        ui_show(ui.rings[r].box, r < (shown ? shown : 1));
        lv_obj_set_size(ui.rings[r].box, size, size);
        lv_obj_set_style_arc_width(ui.rings[r].arc, size * 9 / 100, LV_PART_MAIN);
        lv_obj_set_style_arc_width(ui.rings[r].arc, size * 9 / 100, LV_PART_INDICATOR);
        if (r >= shown) {
            lv_arc_set_value(ui.rings[r].arc, 0);
            lv_label_set_text(ui.rings[r].pct, "--");
            continue;
        }
        const bm_host_t *h = &ui.m->hosts[idx[r]];
        int pct = bm_usage_pct(&h->usage);
        uint32_t col = bm_usage_color(pct);
        lv_arc_set_value(ui.rings[r].arc, pct);
        lv_obj_set_style_arc_color(ui.rings[r].arc, ui_hex(col), LV_PART_INDICATOR);
        lv_label_set_text_fmt(ui.rings[r].pct, "%d%%", pct);
        lv_obj_set_style_text_color(ui.rings[r].pct, ui_hex(pct >= 80 ? col : C_FG), 0);
        char label[24], host[17];
        bm_host_label(h->name, host, sizeof(host));
        if (shown > 1) {
            snprintf(label, sizeof(label), "%s \xC2\xB7 5 H", host);
            ui_upper(label, sizeof(label), label);
        } else {
            snprintf(label, sizeof(label), "5 H WINDOW");
        }
        lv_label_set_text(ui.rings[r].lbl, label);
        lv_obj_set_style_opa(ui.rings[r].box, h->connected ? LV_OPA_COVER : 97, 0);
    }
    (void)now_ms;
}

static void update_spark(void)
{
    const bm_usage_t *u = main_usage();
    if (!u || u->tokens_today < 0) {
        lv_label_set_text(ui.tok_val, "--");
        return;
    }
    if (u->tokens_today != ui.spark_last) {
        int64_t delta = ui.spark_last && u->tokens_today > ui.spark_last ? u->tokens_today - ui.spark_last : 0;
        memmove(ui.spark_tokens, ui.spark_tokens + 1, sizeof(ui.spark_tokens[0]) * (SPARK_POINTS - 1));
        ui.spark_tokens[SPARK_POINTS - 1] = delta;
        ui.spark_last = u->tokens_today;
    }
    lv_label_set_text_fmt(ui.tok_val, "%.2f M", (double)u->tokens_today / 1e6);
    int64_t max = 1;
    for (int i = 0; i < SPARK_POINTS; i++)
        if (ui.spark_tokens[i] > max) max = ui.spark_tokens[i];
    for (int i = 0; i < SPARK_POINTS; i++) {
        ui.spark_pts[i].x = (lv_value_precise_t)(i * (UBAR_W - 6) / (SPARK_POINTS - 1) + 3);
        ui.spark_pts[i].y = (lv_value_precise_t)(SPARK_H - 3 - ui.spark_tokens[i] * (SPARK_H - 8) / max);
    }
    lv_line_set_points(ui.spark, ui.spark_pts, SPARK_POINTS);
    lv_obj_set_pos(ui.spark_dot, (int32_t)ui.spark_pts[SPARK_POINTS - 1].x - 3,
                   (int32_t)ui.spark_pts[SPARK_POINTS - 1].y - 3);
}

static void update_usage(uint32_t now_ms)
{
    update_rings(now_ms);
    const bm_usage_t *u = main_usage();
    if (u) {
        lv_label_set_text_fmt(ui.week_val, "%d%%", (int)lroundf(u->weekly_pct));
        ui_track_set(ui.week_bar, (int)lroundf(u->weekly_pct));
    } else {
        lv_label_set_text(ui.week_val, "--");
        ui_track_set(ui.week_bar, 0);
    }
    update_spark();
}

static const bm_hilo_t *current_hilo(void)
{
    int h = bm_hilo_host(ui.m);
    return h < 0 ? NULL : &ui.m->hosts[h].hilo;
}

static void update_hilo(void)
{
    const bm_hilo_t *h = current_hilo();
    if (!h || !h->has_current) {
        lv_label_set_text(ui.hilo_now, "No current task");
        lv_label_set_text(ui.hilo_proj, "");
    } else {
        lv_label_set_text(ui.hilo_now, h->current.title);
        if (h->current.jira[0]) lv_label_set_text_fmt(ui.hilo_proj, "%s \xC2\xB7 %s", h->current.project, h->current.jira);
        else lv_label_set_text(ui.hilo_proj, h->current.project);
    }
    for (int i = 0; i < BM_MAX_NEXT; i++) {
        bool has = h && i < h->n_next;
        ui_show(lv_obj_get_parent(ui.hilo_next[i]), has);
        if (has) lv_label_set_text(ui.hilo_next[i], h->next[i].title);
    }
    lv_label_set_text_fmt(ui.hilo_agree, "Agreements logged today: #5ee3a8 %d#", h ? h->n_agreements : 0);
}

static uint16_t rgb565_mix(uint16_t a, uint16_t b, uint32_t t)
{
    uint32_t r = ((a >> 11) * (256 - t) + (b >> 11) * t) >> 8;
    uint32_t g = (((a >> 5) & 63) * (256 - t) + ((b >> 5) & 63) * t) >> 8;
    uint32_t bl = ((a & 31) * (256 - t) + (b & 31) * t) >> 8;
    return (uint16_t)(r << 11 | g << 5 | bl);
}

/* Scaled once per cover so LVGL draws it unscaled: its corner clip only holds for unscaled images. */
static void art_scale(const bm_cover_t *c)
{
    for (int y = 0; y < COVER_SIDE; y++) {
        uint32_t fy = (uint32_t)y * (uint32_t)(c->h - 1) * 256 / (COVER_SIDE - 1);
        int y0 = (int)(fy >> 8), y1 = y0 + 1 < c->h ? y0 + 1 : y0;
        for (int x = 0; x < COVER_SIDE; x++) {
            uint32_t fx = (uint32_t)x * (uint32_t)(c->w - 1) * 256 / (COVER_SIDE - 1);
            int x0 = (int)(fx >> 8), x1 = x0 + 1 < c->w ? x0 + 1 : x0;
            uint16_t top = rgb565_mix(c->px[y0 * c->w + x0], c->px[y0 * c->w + x1], fx & 255);
            uint16_t bottom = rgb565_mix(c->px[y1 * c->w + x0], c->px[y1 * c->w + x1], fx & 255);
            ui.cover_px[y * COVER_SIDE + x] = rgb565_mix(top, bottom, fy & 255);
        }
    }
}

static void grid_cover(void)
{
    for (int y = 0; y < COVER_SIDE; y++)
        for (int x = 0; x < COVER_SIDE; x++) {
            uint32_t c = ui.cover_grid[y * BM_COVER_GRID / COVER_SIDE * BM_COVER_GRID + x * BM_COVER_GRID / COVER_SIDE];
            ui.cover_px[y * COVER_SIDE + x] = (uint16_t)((c >> 19 & 31) << 11 | (c >> 10 & 63) << 5 | (c >> 3 & 31));
        }
}

static void pixel_cover(const char *title)
{
    bm_cover_render(ui.cover_grid, title);
    grid_cover();
}

/* Runs only while the Music view is on screen; 10 steps a second keep the redraw to the cover. */
static void cover_frame(uint32_t now_ms)
{
    int mh = bm_media_host(ui.m);
    if (!ui.cover_px || mh < 0) return;
    const char *title = ui.m->hosts[mh].media.title;
    if (bm_cover_waiting(ui.m, now_ms)) {
        uint32_t step = now_ms / 100;
        if (ui.cover_anim && step == ui.cover_step) return;
        ui.cover_anim = true;
        ui.cover_step = step;
        bm_cover_shimmer(ui.cover_grid, title, step);
        grid_cover();
        lv_obj_invalidate(ui.cover);
    } else if (ui.cover_anim) {
        ui.cover_anim = false;
        if (!bm_media_cover(ui.m)) {
            pixel_cover(title);
            lv_obj_invalidate(ui.cover);
        }
    }
}

static void update_music(uint32_t now_ms)
{
    int mh = bm_media_host(ui.m);
    const bm_media_t *media = mh < 0 ? NULL : &ui.m->hosts[mh].media;
    const char *title = media ? media->title : "Nothing playing";
    lv_label_set_text(ui.song, title);
    lv_label_set_text(ui.artist, media ? media->artist : "");
    const bm_cover_t *art = bm_media_cover(ui.m);
    char key[sizeof(ui.cover_key)];
    snprintf(key, sizeof(key), "%c%s", art ? '#' : '~', art ? art->hash : title);
    if (ui.cover_px && strcmp(ui.cover_key, key) != 0) {
        memcpy(ui.cover_key, key, sizeof(key));
        if (art) art_scale(art);
        else pixel_cover(title);
        lv_obj_invalidate(ui.cover);
    }
    lv_label_set_text(ui.song_play, media && media->paused ? LV_SYMBOL_PLAY : LV_SYMBOL_PAUSE);
    lv_obj_set_style_opa(ui.song_ctl, media && ui.m->hosts[mh].connected ? LV_OPA_COVER : LV_OPA_40, 0);
    int32_t len = media ? media->length_s : 0;
    lv_label_set_text_fmt(ui.song_len, "%d:%02d", (int)(len / 60), (int)(len % 60));
    (void)now_ms;
}

static void update_pomodoro(void)
{
    const bm_pomo_t *p = &ui.m->pomo;
    bool stopped = p->state == BM_POMO_STOPPED;
    uint32_t color = p->on_break ? BM_C_DONE : BM_C_WORK;
    static const char *const phases[2][3] = {{"WORK", "WORK", "WORK \xC2\xB7 PAUSED"},
                                             {"BREAK", "BREAK", "BREAK \xC2\xB7 PAUSED"}};
    lv_label_set_text(ui.pomo_phase, phases[p->on_break][p->state]);
    lv_obj_set_style_text_color(ui.pomo_phase, ui_hex(stopped ? C_DIM : color), 0);
    lv_obj_set_style_bg_color(lv_obj_get_child(ui.pomo_bar, 0), ui_hex(color), 0);
    if (p->cycle) lv_label_set_text_fmt(ui.pomo_cycle, "%u done", p->cycle);
    else lv_label_set_text(ui.pomo_cycle, "");
    ui_show(ui.pomo_steps, stopped);
    lv_label_set_text_fmt(ui.pomo_work, "%u", p->work_min);
    lv_label_set_text_fmt(ui.pomo_break, "%u", p->break_min);
    lv_label_set_text(ui.pomo_play, p->state == BM_POMO_RUNNING ? LV_SYMBOL_PAUSE : LV_SYMBOL_PLAY);
    lv_obj_set_style_opa(lv_obj_get_parent(ui.pomo_play), ui.m->clock_known ? LV_OPA_COVER : LV_OPA_40, 0);
    bool ringing = bm_alarm_ringing(ui.m);
    ui_show(ui.alarm_catch, ringing);
    if (ringing != !lv_obj_has_flag(ui.pomo_ring, LV_OBJ_FLAG_HIDDEN)) {
        ui_show(ui.pomo_ring, ringing);
        lv_obj_set_style_border_color(ui.pomo_ring, ui_hex(color), 0);
        lv_obj_update_layout(ui.views[BM_VIEW_POMODORO]);
        lv_obj_align_to(ui.pomo_ring, ui.pomo_pet->img, LV_ALIGN_CENTER, 0, 0);
    }
}

void ui_views_update(void)
{
    uint32_t now_ms = lv_tick_get();
    update_strip();
    update_home();
    update_agents();
    update_usage(now_ms);
    update_hilo();
    update_music(now_ms);
    update_pomodoro();
    ui_views_tick(now_ms);
}

static void civil_date(int64_t wall_ms, int32_t tz_min, char *out, size_t n)
{
    static const char *const wd[] = {"Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"};
    static const char *const mo[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
    int64_t days = (wall_ms / 1000 + (int64_t)tz_min * 60) / 86400;
    int64_t z = days + 719468, era = (z >= 0 ? z : z - 146096) / 146097;
    int64_t doe = z - era * 146097, yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153;
    int day = (int)(doy - (153 * mp + 2) / 5 + 1), month = (int)(mp < 10 ? mp + 3 : mp - 9);
    snprintf(out, n, "%s, %s %d", wd[((days % 7) + 7) % 7], mo[month - 1], day);
}

void ui_views_tick(uint32_t now_ms)
{
    char buf[48];
    const bm_usage_t *u = main_usage();
    if (u) {
        int32_t s = bm_usage_reset_s(u, now_ms);
        bm_fmt_dur((int64_t)s * 1000, buf, sizeof(buf));
        lv_label_set_text(ui.stat_val[2], buf);
        lv_label_set_text_fmt(ui.reset, "Resets in #f3ede4 %d h %d min#", (int)(s / 3600), (int)(s / 60 % 60));
    } else {
        lv_label_set_text(ui.stat_val[2], "--");
        lv_label_set_text(ui.reset, "No usage data yet");
    }

    for (int i = 0; i < BM_AGENT_ROWS; i++) {
        if (ui.rows[i].session < 0) continue;
        const bm_session_t *s = &ui.m->sessions[ui.rows[i].session];
        bm_fmt_dur(bm_wall_ms(ui.m, now_ms) - s->since * 1000, buf, sizeof(buf));
        lv_label_set_text(ui.rows[i].el, buf);
    }

    const bm_hilo_t *h = current_hilo();
    if (h && h->has_current) {
        bm_fmt_hms(bm_wall_ms(ui.m, now_ms) - h->started_at * 1000, buf, sizeof(buf));
        lv_label_set_text(ui.hilo_time, buf);
    } else {
        lv_label_set_text(ui.hilo_time, "");
    }
    if (ui.m->clock_known) {
        civil_date(bm_wall_ms(ui.m, now_ms), ui.m->settings.tz_offset_min, buf, sizeof(buf));
        lv_label_set_text(ui.hilo_day, buf);
    }

    int32_t left = bm_pomo_left_s(ui.m, now_ms);
    lv_label_set_text_fmt(ui.pomo_time, "%02d:%02d", (int)(left / 60), (int)(left % 60));
    ui_track_set(ui.pomo_bar, (int)(bm_pomo_progress(ui.m, now_ms) * 100));

    int mh = bm_media_host(ui.m);
    if (mh >= 0) {
        const bm_media_t *media = &ui.m->hosts[mh].media;
        int32_t pos = bm_media_position_s(media, now_ms);
        lv_label_set_text_fmt(ui.song_cur, "%d:%02d", (int)(pos / 60), (int)(pos % 60));
        ui_track_set(ui.song_bar, media->length_s ? (int)(pos * 100 / media->length_s) : 0);
    } else {
        lv_label_set_text(ui.song_cur, "0:00");
        ui_track_set(ui.song_bar, 0);
    }
}

void ui_views_frame(void)
{
    if (ui.m->sleeping) return;
    switch (ui.m->view) {
    case BM_VIEW_HOME: ui_pet_draw(ui.home_pet, bm_main_pet(ui.m), BM_PET_MAIN_HUE, ui.m->acc, 0); break;
    case BM_VIEW_AGENTS:
        for (int i = 0; i < BM_AGENT_ROWS; i++) {
            if (ui.rows[i].session < 0) continue;
            const bm_session_t *s = &ui.m->sessions[ui.rows[i].session];
            ui_session_pet(ui.rows[i].pet, s);
            bool pulse = bm_waiting(ui.m, s);
            float k = (sinf(ui.t * 2 * 3.14159f / 1.1f) + 1) / 2;
            lv_obj_set_style_border_opa(ui.rows[i].row, pulse ? (lv_opa_t)(0x33 + k * (255 - 0x33)) : LV_OPA_TRANSP, 0);
        }
        break;
    case BM_VIEW_POMODORO: ui_pet_draw(ui.pomo_pet, bm_pomo_pet(ui.m), BM_PET_MAIN_HUE, ui.m->acc, 0);
        if (bm_alarm_ringing(ui.m)) {
            float k = (sinf(ui.t * 2 * 3.14159f / 1.1f) + 1) / 2;
            lv_obj_set_style_border_opa(ui.pomo_ring, (lv_opa_t)(0x40 + k * (255 - 0x40)), 0);
        }
        break;
    case BM_VIEW_MUSIC: cover_frame(lv_tick_get()); break;
    default: break;
    }
}
