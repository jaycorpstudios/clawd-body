#include <math.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "ui_priv.h"

#define CELL BM_EYES_CELL
#define TILE_CELL 5
#define TILE_INNER (BM_EYES_TILE_GRID - 2)
#define MAX_CELLS (TILE_INNER * TILE_INNER)
#define SLEEP_GAZE 0.55
#define FACE_CX ((BM_EYES_FACE_X + BM_EYES_FACE_W / 2.0f) * CELL)
#define FACE_CY ((BM_EYES_FACE_Y + BM_EYES_FACE_H / 2.0f) * CELL)
#define SLEEP_CX ((BM_EYES_SLEEP_X + BM_EYES_SLEEP_W / 2.0f) * CELL)
#define SLEEP_CY ((BM_EYES_SLEEP_Y + BM_EYES_SLEEP_H / 2.0f) * CELL)

typedef struct {
    lv_obj_t *img;
    lv_image_dsc_t dsc;
    uint16_t *px;
    uint8_t cells[MAX_CELLS], shown[MAX_CELLS];
    int w, h, cell;
    uint16_t ink, bg;
    bool drawn;
} cells_t;

static cells_t *face[2], *sleep_eye[2], *tile;
static lv_obj_t *spark_v[BM_EYES_SPARKS], *spark_h[BM_EYES_SPARKS], *zs[BM_EYES_ZS];
static int32_t sleep_bg = -1;

static uint16_t rgb565(uint32_t rgb)
{
    return lv_color_to_u16(lv_color_hex(rgb));
}

static cells_t *cells_create(lv_obj_t *parent, int w, int h, int cell, uint32_t ink, uint32_t bg)
{
    cells_t *c = heap_caps_calloc_prefer(1, sizeof(*c), 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    int pw = w * cell, ph = h * cell;
    c->w = w;
    c->h = h;
    c->cell = cell;
    c->ink = rgb565(ink);
    c->bg = rgb565(bg);
    c->px = heap_caps_calloc_prefer((size_t)pw * ph, 2, 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
    c->dsc.header.magic = LV_IMAGE_HEADER_MAGIC;
    c->dsc.header.cf = LV_COLOR_FORMAT_RGB565;
    c->dsc.header.w = pw;
    c->dsc.header.h = ph;
    c->dsc.header.stride = pw * 2;
    c->dsc.data_size = (uint32_t)pw * ph * 2;
    c->dsc.data = (const uint8_t *)c->px;
    c->img = lv_image_create(parent);
    lv_image_set_src(c->img, &c->dsc);
    lv_obj_set_size(c->img, pw, ph);
    return c;
}

static void cells_resize(cells_t *c, int w, int h)
{
    if (w == c->w && h == c->h) return;
    int pw = w * c->cell, ph = h * c->cell;
    c->w = w;
    c->h = h;
    c->drawn = false;
    c->dsc.header.w = pw;
    c->dsc.header.h = ph;
    c->dsc.header.stride = pw * 2;
    c->dsc.data_size = (uint32_t)pw * ph * 2;
    lv_image_set_src(c->img, &c->dsc);
    lv_obj_set_size(c->img, pw, ph);
}

static void cells_colors(cells_t *c, uint32_t ink, uint32_t bg)
{
    uint16_t i = rgb565(ink), b = rgb565(bg);
    if (i == c->ink && b == c->bg) return;
    c->ink = i;
    c->bg = b;
    c->drawn = false;
}

static void cells_commit(cells_t *c)
{
    size_t n = (size_t)c->w * c->h;
    if (c->drawn && memcmp(c->cells, c->shown, n) == 0) return;
    memcpy(c->shown, c->cells, n);
    c->drawn = true;
    int pw = c->w * c->cell;
    for (int y = 0; y < c->h * c->cell; y++) {
        const uint8_t *row = &c->cells[y / c->cell * c->w];
        uint16_t *dst = &c->px[y * pw];
        for (int x = 0; x < pw; x++) dst[x] = row[x / c->cell] ? c->ink : c->bg;
    }
    lv_obj_invalidate(c->img);
}

static void move(lv_obj_t *obj, int32_t x, int32_t y)
{
    if (lv_obj_get_x(obj) != x || lv_obj_get_y(obj) != y) lv_obj_set_pos(obj, x, y);
}

static lv_obj_t *ink_box(lv_obj_t *parent, uint32_t color)
{
    lv_obj_t *b = ui_box(parent);
    lv_obj_set_style_bg_color(b, ui_hex(color), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    ui_show(b, false);
    return b;
}

void ui_eyes_face_create(lv_obj_t *v)
{
    lv_obj_set_layout(v, LV_LAYOUT_NONE);
    lv_obj_set_style_pad_all(v, 0, 0);
    lv_obj_set_style_bg_color(v, ui_hex(UI_ORANGE), 0);
    lv_obj_set_style_bg_opa(v, LV_OPA_COVER, 0);
    for (int i = 0; i < 2; i++)
        face[i] = cells_create(v, BM_EYES_FACE_W, BM_EYES_FACE_H, CELL, UI_INK, UI_ORANGE);
    for (int i = 0; i < BM_EYES_SPARKS; i++) {
        spark_v[i] = ink_box(v, UI_INK);
        spark_h[i] = ink_box(v, UI_INK);
    }
}

lv_obj_t *ui_eyes_tile_create(lv_obj_t *parent)
{
    lv_obj_t *t = ui_box(parent);
    lv_obj_set_size(t, BM_EYES_TILE_GRID * TILE_CELL, BM_EYES_TILE_GRID * TILE_CELL);
    lv_obj_set_style_radius(t, 15, 0);
    lv_obj_set_style_bg_color(t, ui_hex(UI_ORANGE), 0);
    lv_obj_set_style_bg_opa(t, LV_OPA_COVER, 0);
    tile = cells_create(t, TILE_INNER, TILE_INNER, TILE_CELL, UI_INK, UI_ORANGE);
    lv_obj_set_pos(tile->img, TILE_CELL, TILE_CELL);
    return t;
}

void ui_eyes_sleep_create(lv_obj_t *sleep)
{
    for (int i = 0; i < 2; i++) {
        sleep_eye[i] = cells_create(sleep, BM_EYES_FACE_W, BM_EYES_FACE_H, CELL, UI_ORANGE, UI_EMBER);
        cells_resize(sleep_eye[i], BM_EYES_SLEEP_W, BM_EYES_SLEEP_H);
    }
    for (int i = 0; i < BM_EYES_ZS; i++) {
        zs[i] = ui_label(sleep, &font_pixel_26, UI_ORANGE, "z");
        ui_show(zs[i], false);
    }
}

static void draw_pair(cells_t *eye[2], int x0, int y0, int gx, int gy, const bm_eyes_out_t *o)
{
    int w = eye[0]->w, xs[2] = {x0, BM_EYES_GRID - x0 - w};
    for (int i = 0; i < 2; i++) {
        bm_eye_cells(eye[i]->cells, w, eye[i]->h, o->open[i], o->shape[i], i ? 1 : -1);
        cells_commit(eye[i]);
        move(eye[i]->img, (xs[i] + gx) * CELL, (y0 + gy) * CELL);
    }
}

static void draw_sparks(uint32_t now_ms, bool on)
{
    const bm_eyes_t *e = &ui.m->eyes;
    for (int i = 0; i < BM_EYES_SPARKS; i++) {
        int32_t age = (int32_t)(now_ms - e->sparks[i].at_ms);
        bool lit = on && e->sparks[i].at_ms && age >= 0 && age <= BM_EYES_SPARK_MS;
        bool big = age * 2 < BM_EYES_SPARK_MS;
        ui_show(spark_v[i], lit);
        ui_show(spark_h[i], lit && big);
        if (!lit) continue;
        int32_t x = e->sparks[i].x * CELL, y = e->sparks[i].y * CELL;
        lv_obj_set_size(spark_v[i], CELL, big ? 3 * CELL : CELL);
        move(spark_v[i], x, big ? y - CELL : y);
        lv_obj_set_size(spark_h[i], 3 * CELL, CELL);
        move(spark_h[i], x - CELL, y);
    }
}

static void draw_tile(uint32_t now_ms)
{
    const bm_eyes_out_t *o = &ui.m->eyes.out;
    uint32_t look = now_ms / 1700 % 3;
    uint8_t eye[BM_EYES_TILE_W * BM_EYES_TILE_H];
    memset(tile->cells, 0, sizeof(tile->cells));
    for (int i = 0; i < 2; i++) {
        bm_eye_cells(eye, BM_EYES_TILE_W, BM_EYES_TILE_H, 1 - o->blink, BM_EYE_WORRIED, i ? 1 : -1);
        int x0 = (i ? 11 : 5) - 2 - (look == 1) - 1, y0 = 5 + (look == 2) - 1;
        for (int y = 0; y < BM_EYES_TILE_H; y++)
            for (int x = 0; x < BM_EYES_TILE_W; x++)
                tile->cells[(y0 + y) * TILE_INNER + x0 + x] = eye[y * BM_EYES_TILE_W + x];
    }
    cells_commit(tile);
}

static float lerp(float a, float b, float t)
{
    return a + (b - a) * t;
}

static uint32_t mix(uint32_t a, uint32_t b, float t)
{
    uint32_t out = 0;
    for (int s = 0; s < 24; s += 8)
        out |= (uint32_t)bm_eyes_round(lerp((float)(a >> s & 0xff), (float)(b >> s & 0xff), t)) << s;
    return out;
}

static void draw_sleep(uint32_t now_ms)
{
    const bm_eyes_t *e = &ui.m->eyes;
    float r = ui.m->rest, ember = bm_ease(r);
    uint32_t bg = mix(UI_ORANGE, UI_EMBER, ember), ink = mix(UI_INK, UI_ORANGE, ember);
    // A full-screen redraw costs ~30 ms on the board; RGB565 has only ~25 steps from orange to ember.
    if (rgb565(bg) != sleep_bg) {
        lv_obj_set_style_bg_color(ui.sleep, ui_hex(bg), 0);
        sleep_bg = rgb565(bg);
    }
    lv_opa_t cards = (lv_opa_t)(ember * 255);
    if (lv_obj_get_style_opa(ui.sleep_inner, 0) != cards) lv_obj_set_style_opa(ui.sleep_inner, cards, 0);

    int w = bm_eyes_round(lerp(BM_EYES_FACE_W, BM_EYES_SLEEP_W, r));
    int h = bm_eyes_round(lerp(BM_EYES_FACE_H, BM_EYES_SLEEP_H, r));
    int x0 = (int)floorf(lerp(FACE_CX, SLEEP_CX, r) / CELL - w / 2.0f);
    int y0 = (int)floorf(lerp(FACE_CY, SLEEP_CY, r) / CELL - h / 2.0f);
    for (int i = 0; i < 2; i++) {
        cells_resize(sleep_eye[i], w, h);
        cells_colors(sleep_eye[i], ink, bg);
    }
    float gaze = lerp(1, SLEEP_GAZE, r);
    int32_t ddx = (int32_t)(ui.m->sleep_dx * r), ddy = (int32_t)(ui.m->sleep_dy * r);
    int gx = bm_eyes_round(e->out.gx * gaze) + bm_eyes_round(ddx / (double)CELL);
    int gy = bm_eyes_round(e->out.gy * gaze) + bm_eyes_round(ddy / (double)CELL);
    draw_pair(sleep_eye, x0, y0, gx, gy, &e->out);
    int right = BM_EYES_GRID - x0;
    for (int i = 0; i < BM_EYES_ZS; i++) {
        int32_t age = (int32_t)(now_ms - e->z_ms[i]);
        bool on = e->z_ms[i] && age >= 0 && age <= BM_EYES_Z_MS;
        ui_show(zs[i], on);
        if (!on) continue;
        float a = (float)age / BM_EYES_Z_MS;
        move(zs[i], (right + 2) * CELL + (int32_t)(a * 40) + ddx, y0 * CELL - (int32_t)(a * 60) - 28 + ddy);
        lv_obj_set_style_opa(zs[i], (lv_opa_t)((1 - a) * ember * 255), 0);
    }
}

void ui_eyes_frame(uint32_t now_ms)
{
    const bm_eyes_t *e = &ui.m->eyes;
    if (ui.m->sleeping || ui.m->rest > 0) {
        draw_sleep(now_ms);
        return;
    }
    if (bm_attn_shown(ui.m)) {
        draw_tile(now_ms);
        return;
    }
    bool shown = ui.m->view == BM_VIEW_FACE && !ui.m->sheet;
    draw_sparks(now_ms, shown);
    if (shown) draw_pair(face, BM_EYES_FACE_X, BM_EYES_FACE_Y, e->out.gx, e->out.gy, &e->out);
}
