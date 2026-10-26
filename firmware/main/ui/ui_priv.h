#pragma once

#include "bm.h"
#include "bm_pet.h"
#include "fonts/fonts.h"
#include "lvgl.h"

#define SCREEN 480
#define C_BG 0x000000
#define C_FG 0xf3ede4
#define C_DIM 0x8a837a
#define C_LINE 0x1f1c19
#define C_TRACK 0x1d1b18

#define F_TITLE (&font_pixel_28)
#define F_SMALL (&font_mono_16)

typedef struct {
    lv_obj_t *img;
    lv_image_dsc_t dsc;
    int32_t size;
    uint32_t *scaled;
    uint32_t px[BM_PET_GRID * BM_PET_GRID];
} ui_pet_t;

typedef struct {
    lv_obj_t *obj;
    float x, y, vx, vy;
} ui_confetti_t;

#define CONFETTI_MAX 46
#define SPARK_POINTS 12

typedef struct {
    bm_model_t *m;
    uint32_t rev;
    int64_t sec;
    float t;

    lv_obj_t *scr, *strip, *views[BM_VIEWS];
    lv_obj_t *clock, *pill[BM_MAX_HOSTS], *pill_dot[BM_MAX_HOSTS], *pill_lbl[BM_MAX_HOSTS], *batt_pct, *batt_charge,
        *batt_lvl;
    lv_obj_t *dots[BM_VIEWS];

    ui_pet_t *home_pet;
    lv_obj_t *home_msg, *home_sub, *stat_val[3];

    lv_obj_t *ag_count, *ag_empty;
    struct {
        lv_obj_t *row, *name, *task, *chip, *chip_lbl, *el;
        ui_pet_t *pet;
        int8_t session;
    } rows[BM_AGENT_ROWS];

    struct {
        lv_obj_t *box, *arc, *pct, *lbl;
    } rings[BM_MAX_HOSTS];
    lv_obj_t *reset, *week_val, *week_bar, *tok_val, *spark, *spark_dot;
    lv_point_precise_t spark_pts[SPARK_POINTS];
    int64_t spark_tokens[SPARK_POINTS];
    int64_t spark_last;

    lv_obj_t *hilo_day, *hilo_card, *hilo_now, *hilo_proj, *hilo_time, *hilo_next[BM_MAX_NEXT], *hilo_agree;

    lv_obj_t *cover, *song, *artist, *song_bar, *song_cur, *song_len;
    lv_image_dsc_t cover_dsc;
    uint32_t cover_px[BM_COVER_GRID * BM_COVER_GRID];
    char cover_title[81];

    lv_obj_t *ov, *ov_big, *ov_det, *ov_hint;
    ui_pet_t *ov_pet;
    bm_overlay_t ov_shown;
    ui_confetti_t confetti[CONFETTI_MAX];
    int n_confetti;

    lv_obj_t *attn, *ap_k, *ap_p, *ap_h, *ap_cmd, *ap_why, *ap_actions, *ap_deny, *ap_ok, *ap_ok_fill, *ap_locked,
        *ap_locked_lbl, *ap_opts, *ap_opt[BM_MAX_OPTIONS], *ap_opt_lbl[BM_MAX_OPTIONS];
    ui_pet_t *ap_pet;

    lv_obj_t *sheet, *sh_title, *sh_body;
    ui_pet_t *sh_pet;
    int8_t sh_pet_session;

    lv_obj_t *pair, *pair_hint, *pair_code, *pair_digits[2], *pair_left;
    ui_pet_t *pair_pet;

    lv_obj_t *toast, *toast_lbl;
    lv_obj_t *sleep, *sleep_inner, *sleep_clock;
    ui_pet_t *sleep_pet;
} ui_t;

extern ui_t ui;

lv_color_t ui_hex(uint32_t rgb);
lv_obj_t *ui_box(lv_obj_t *parent);
lv_obj_t *ui_label(lv_obj_t *parent, const lv_font_t *font, uint32_t color, const char *text);
lv_obj_t *ui_track(lv_obj_t *parent, int32_t w, uint32_t color);
void ui_track_set(lv_obj_t *track, int pct);
void ui_on_tap(lv_obj_t *obj, bm_tap_t target, int arg);
void ui_set_tap_arg(lv_obj_t *obj, int arg);
void ui_show(lv_obj_t *obj, bool show);
void ui_upper(char *dst, size_t n, const char *src);
void ui_symbolize(char *dst, size_t n, const char *src);

ui_pet_t *ui_pet_create(lv_obj_t *parent, int32_t size);
void ui_pet_draw(ui_pet_t *p, bm_pet_state_t state, uint16_t hue, bm_acc_t acc, float seed);
void ui_session_pet(ui_pet_t *p, const bm_session_t *s);

void ui_bar_create(lv_obj_t *scr);
void ui_bar_update(uint32_t now_ms);

void ui_views_create(lv_obj_t *scr);
void ui_views_update(void);
void ui_views_tick(uint32_t now_ms);
void ui_views_frame(void);

void ui_overlay_create(lv_obj_t *scr);
void ui_overlay_update(uint32_t now_ms);
void ui_overlay_frame(void);

void ui_attn_create(lv_obj_t *scr);
void ui_attn_update(uint32_t now_ms);
void ui_attn_frame(uint32_t now_ms);

void ui_sheet_create(lv_obj_t *scr);
void ui_sheet_update(uint32_t now_ms);
void ui_sheet_frame(void);

void ui_pair_create(lv_obj_t *scr);
void ui_pair_update(uint32_t now_ms);
void ui_pair_frame(void);

void ui_misc_create(lv_obj_t *scr);
void ui_misc_update(uint32_t now_ms);
void ui_misc_frame(uint32_t now_ms);
