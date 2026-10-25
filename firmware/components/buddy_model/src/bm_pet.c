#include <math.h>
#include <string.h>

#include "bm_pet.h"

#define G BM_PET_GRID
#define OPAQUE(rgb) (0xff000000u | (rgb))

typedef struct {
    uint32_t *buf;
    int ox, oy;
} canvas_t;

static uint32_t hsl(float h, float s, float l)
{
    float c = (1 - fabsf(2 * l - 1)) * s, hp = fmodf(h, 360.0f) / 60.0f;
    float x = c * (1 - fabsf(fmodf(hp, 2.0f) - 1)), r = 0, g = 0, b = 0;
    if (hp < 1) r = c, g = x;
    else if (hp < 2) r = x, g = c;
    else if (hp < 3) g = c, b = x;
    else if (hp < 4) g = x, b = c;
    else if (hp < 5) r = x, b = c;
    else r = c, b = x;
    float mm = l - c / 2;
    uint32_t R = (uint32_t)lroundf((r + mm) * 255), Gc = (uint32_t)lroundf((g + mm) * 255),
             B = (uint32_t)lroundf((b + mm) * 255);
    return OPAQUE(R << 16 | Gc << 8 | B);
}

static uint32_t with_alpha(uint32_t rgb, float a)
{
    if (a < 0) a = 0;
    if (a > 1) a = 1;
    return (uint32_t)lroundf(a * 255) << 24 | (rgb & 0xffffff);
}

static void blend(uint32_t *dst, uint32_t src)
{
    uint32_t sa = src >> 24;
    if (sa == 255 || (*dst >> 24) == 0) {
        *dst = src;
        return;
    }
    if (sa == 0) return;
    uint32_t da = *dst >> 24, oa = sa + da * (255 - sa) / 255, out = oa << 24;
    for (int sh = 0; sh <= 16; sh += 8) {
        uint32_t sc = (src >> sh) & 255, dc = (*dst >> sh) & 255;
        uint32_t c = (sc * sa + dc * da * (255 - sa) / 255) / oa;
        out |= c << sh;
    }
    *dst = out;
}

static void rect(canvas_t *cv, float x, float y, float w, float h, uint32_t color, bool fixed)
{
    int x0 = (int)lroundf(x + (fixed ? 0 : cv->ox)), y0 = (int)lroundf(y + (fixed ? 0 : cv->oy));
    int x1 = x0 + (int)ceilf(w), y1 = y0 + (int)ceilf(h);
    for (int yy = y0 < 0 ? 0 : y0; yy < y1 && yy < G; yy++)
        for (int xx = x0 < 0 ? 0 : x0; xx < x1 && xx < G; xx++) blend(&cv->buf[yy * G + xx], color);
}

#define PX(x, y, w, h, c) rect(cv, (float)(x), (float)(y), (float)(w), (float)(h), (c), false)
#define PXF(x, y, w, h, c) rect(cv, (float)(x), (float)(y), (float)(w), (float)(h), (c), true)

static int sgn_pos(float v)
{
    return v > 0 ? 1 : 0;
}

static void draw_acc(canvas_t *cv, bm_acc_t acc, int ey, bm_pet_state_t state, float tt)
{
    const uint32_t PU = OPAQUE(0x7b4fc9), PU2 = OPAQUE(0x5e3aa3), YE = OPAQUE(0xffcc3d), BK = OPAQUE(0x141210),
                   WH = OPAQUE(0xf5f1ea);
    switch (acc) {
    case BM_ACC_SHADES:
        PX(7, ey - 1, 18, 1, BK);
        for (int x0 = 8; x0 <= 18; x0 += 10) {
            PX(x0, ey, 6, 2, BK);
            PX(x0 + 1, ey + 2, 5, 1, BK);
            PX(x0 + 2, ey + 3, 3, 1, BK);
            PX(x0 + 1, ey, 1, 1, WH);
            PX(x0 + 1, ey + 1, 2, 1, WH);
        }
        break;
    case BM_ACC_HEART:
        for (int x0 = 9; x0 <= 19; x0 += 10) {
            const uint32_t c = OPAQUE(0xff4d7a);
            PX(x0, ey, 1, 1, c);
            PX(x0 + 2, ey, 1, 1, c);
            PX(x0, ey + 1, 3, 1, c);
            PX(x0 + 1, ey + 2, 1, 1, c);
        }
        break;
    case BM_ACC_WIZARD: {
        PX(5, 10, 22, 1, PU2);
        PX(9, 9, 14, 1, YE);
        static const int rows[6][2] = {{10, 21}, {11, 20}, {12, 19}, {13, 18}, {14, 17}, {15, 16}};
        for (int i = 0; i < 6; i++) PX(rows[i][0], 8 - i, rows[i][1] - rows[i][0] + 1, 1, i % 2 ? PU : PU2);
        PX(16, 2, 1, 1, PU);
        int wy = state == BM_PET_WORKING ? (int)lroundf(sinf(tt * 7)) : 0;
        PX(27, 9 + wy, 1, 11, BK);
        PX(26, 7 + wy, 3, 2, YE);
        PX(27, 6 + wy, 1, 1, YE);
        PX(25, 7 + wy, 1, 1, YE);
        PX(29, 7 + wy, 1, 1, YE);
        break;
    }
    case BM_ACC_HEADPHONES: {
        const uint32_t band = OPAQUE(0x2b2f36), cup = OPAQUE(0x2bb3a6), inner = OPAQUE(0x1b7f76);
        PX(9, 9, 14, 1, band);
        PX(8, 10, 1, 3, band);
        PX(23, 10, 1, 3, band);
        PX(4, 14, 3, 5, cup);
        PX(25, 14, 3, 5, cup);
        PX(5, 15, 1, 3, inner);
        PX(26, 15, 1, 3, inner);
        break;
    }
    case BM_ACC_CROWN:
        PX(11, 8, 10, 3, YE);
        PX(11, 6, 1, 2, YE);
        PX(15, 5, 2, 3, YE);
        PX(20, 6, 1, 2, YE);
        PX(13, 9, 1, 1, OPAQUE(0xff5d62));
        PX(18, 9, 1, 1, OPAQUE(0x5ee3a8));
        break;
    case BM_ACC_PARTY:
        for (int i = 0; i < 7; i++) {
            int half = (i + 1) / 2;
            PX(16 - half, 4 + i, 1 + half * 2, 1, i % 2 ? OPAQUE(0xff7aa8) : OPAQUE(0x7cc8ff));
        }
        PX(15, 2, 2, 2, YE);
        break;
    case BM_ACC_BAND:
        PX(7, 12, 18, 2, OPAQUE(0x2bb3a6));
        PX(25, 12, 2, 1, OPAQUE(0x2bb3a6));
        PX(25, 14, 2, 2, OPAQUE(0x1b7f76));
        PX(27, 15, 1, 2, OPAQUE(0x1b7f76));
        break;
    default: break;
    }
}

static uint32_t tip_color(bm_pet_state_t state)
{
    switch (state) {
    case BM_PET_WORKING: return BM_C_WORK;
    case BM_PET_ALERT:
    case BM_PET_WORRIED: return BM_C_WAIT;
    case BM_PET_HAPPY: return BM_C_DONE;
    case BM_PET_ERROR: return BM_C_ERR;
    case BM_PET_SLEEP: return 0x4a4a5a;
    default: return BM_C_INFO;
    }
}

static void draw_z(canvas_t *cv, float x, float baseline, float alpha)
{
    uint32_t c = with_alpha(0x6d6a80, alpha);
    int x0 = (int)lroundf(x), y0 = (int)lroundf(baseline) - 3;
    PXF(x0, y0, 3, 1, c);
    PXF(x0 + 1, y0 + 1, 1, 1, c);
    PXF(x0, y0 + 2, 3, 1, c);
}

void bm_pet_render(uint32_t argb[G * G], bm_pet_state_t state, float t, uint16_t hue, bm_acc_t acc, float seed)
{
    memset(argb, 0, sizeof(uint32_t) * G * G);
    canvas_t c = {argb, 0, 0}, *cv = &c;
    const float tt = t + seed;
    const uint32_t body = hsl(hue, .85f, .58f), light = hsl(hue, .95f, .72f), dark = hsl(hue, .70f, .36f),
                   eye = OPAQUE(0x1b0f0a);
    const float cx = 16, cy = 19, rx = 10;
    float ry = 8;
    switch (state) {
    case BM_PET_IDLE: c.oy = (int)lroundf(sinf(tt * 2) * .7f); break;
    case BM_PET_WORKING: c.oy = -(int)lroundf(fabsf(sinf(tt * 7))); break;
    case BM_PET_ALERT: c.oy = -(int)lroundf(fabsf(sinf(tt * 6)) * 4); break;
    case BM_PET_HAPPY: c.oy = -(int)lroundf(fabsf(sinf(tt * 5)) * 3); break;
    case BM_PET_SLEEP: ry = sinf(tt * 1.3f) > 0 ? 8 : 7.6f; break;
    case BM_PET_ERROR: c.ox = (int)lroundf(sinf(tt * 28) * (float)sgn_pos(sinf(tt * 2))); break;
    case BM_PET_WORRIED: c.ox = (int)lroundf(sinf(tt * 3) * .7f); break;
    }
#define IN_BODY(x, y) (((x) + .5f - cx) / rx * (((x) + .5f - cx) / rx) + ((y) + .5f - cy) / ry * (((y) + .5f - cy) / ry) <= 1)

    PXF(9, 29, 14, 1, with_alpha(0xffffff, .08f));
    const bool working = state == BM_PET_WORKING;
    int step = working ? sgn_pos(sinf(tt * 7)) : 0;
    PX(cx - 7, cy + ry - 1 - step, 4, 2, dark);
    PX(cx + 3, cy + ry - 1 - (working ? 1 - step : 0), 4, 2, dark);
    if (state == BM_PET_ALERT || state == BM_PET_HAPPY) {
        int w = sgn_pos(sinf(tt * 10));
        PX(cx - rx - 2, cy - 4 - w, 2, 3, dark);
        PX(cx + rx, cy - 4 - (1 - w), 2, 3, dark);
    } else {
        int tap = working ? sgn_pos(sinf(tt * 14)) : 0;
        PX(cx - rx - 1, cy + 1 + tap, 2, 2, dark);
        PX(cx + rx - 1, cy + 1 + (working ? 1 - tap : 0), 2, 2, dark);
    }
    for (int y = 0; y < G; y++)
        for (int x = 0; x < G; x++) {
            if (!IN_BODY(x, y)) continue;
            uint32_t col = body;
            if (!IN_BODY(x, y - 1) || !IN_BODY(x - 1, y)) col = light;
            else if (!IN_BODY(x, y + 1) || !IN_BODY(x + 1, y)) col = dark;
            PX(x, y, 1, 1, col);
        }
    PX(cx - 7, cy - 5, 2, 1, light);
    PX(cx - 8, cy - 4, 1, 2, light);

    const int top = (int)floorf(cy - ry);
    const bool hat = acc == BM_ACC_WIZARD || acc == BM_ACC_CROWN || acc == BM_ACC_PARTY || acc == BM_ACC_HEADPHONES;
    const uint32_t tip = tip_color(state);
    if (!hat) {
        PX(15, top - 3, 2, 3, dark);
        PX(13, top - 7, 6, 5, with_alpha(tip, .22f + sinf(tt * 4) * .08f));
        PX(14, top - 6, 4, 3, OPAQUE(tip));
    }

    const int ey = (int)cy - 2;
    const bool blink = fmodf(tt, 3.7f) < .13f;
    int look = working ? (sinf(tt * 1.1f) > 0 ? 1 : -1) : state == BM_PET_IDLE ? (sinf(tt * .4f) > .85f ? 1 : 0) : 0;
    const int L = 10 + look, R = 20 + look;
    const bool hide_eyes = acc == BM_ACC_SHADES ||
                           (acc == BM_ACC_HEART && state != BM_PET_SLEEP && state != BM_PET_ERROR && !blink);
    if (hide_eyes) {
    } else if (state == BM_PET_HAPPY) {
        const int xs[2] = {L, R - 1};
        for (int i = 0; i < 2; i++) {
            PX(xs[i], ey + 1, 1, 1, eye);
            PX(xs[i] + 1, ey, 1, 1, eye);
            PX(xs[i] + 2, ey + 1, 1, 1, eye);
        }
    } else if (state == BM_PET_ERROR) {
        for (int ex = 10; ex <= 19; ex += 9) {
            PX(ex, ey, 1, 1, eye);
            PX(ex + 2, ey, 1, 1, eye);
            PX(ex + 1, ey + 1, 1, 1, eye);
            PX(ex, ey + 2, 1, 1, eye);
            PX(ex + 2, ey + 2, 1, 1, eye);
        }
    } else if (state == BM_PET_SLEEP || blink) {
        PX(L, ey + 2, 2, 1, eye);
        PX(R, ey + 2, 2, 1, eye);
    } else if (state == BM_PET_ALERT) {
        PX(9, ey - 1, 3, 4, eye);
        PX(20, ey - 1, 3, 4, eye);
        PX(9, ey - 1, 1, 1, OPAQUE(0xffffff));
        PX(20, ey - 1, 1, 1, OPAQUE(0xffffff));
    } else {
        PX(L, ey, 2, 3, eye);
        PX(R, ey, 2, 3, eye);
        PX(L, ey, 1, 1, 0x88ffffff);
        PX(R, ey, 1, 1, 0x88ffffff);
    }

    const int my = (int)cy + 2;
    switch (state) {
    case BM_PET_HAPPY:
        PX(14, my, 1, 1, eye);
        PX(15, my + 1, 2, 1, eye);
        PX(17, my, 1, 1, eye);
        break;
    case BM_PET_ALERT: PX(15, my, 2, 2, eye); break;
    case BM_PET_ERROR:
        for (int i = 0; i < 5; i++) PX(13 + i, my + (i % 2 ? 0 : 1), 1, 1, eye);
        break;
    case BM_PET_WORRIED:
        PX(15, my + 1, 2, 1, eye);
        PX(14, my + 2, 1, 1, eye);
        PX(17, my + 2, 1, 1, eye);
        break;
    case BM_PET_SLEEP: PX(15, my, 2, 1, dark); break;
    default: PX(15, my, 2, 1, eye); break;
    }

    draw_acc(cv, acc, ey, state, tt);

    if (state == BM_PET_HAPPY || state == BM_PET_IDLE) {
        PX(7, cy + 1, 2, 1, OPAQUE(0xff7aa8));
        PX(23, cy + 1, 2, 1, OPAQUE(0xff7aa8));
    }
    if (state == BM_PET_WORRIED) {
        int d = (int)lroundf(fmodf(tt * 2, 3));
        PX(24, ey - 1 + d, 1, 1, OPAQUE(BM_C_INFO));
        PX(23, ey + d, 3, 2, OPAQUE(BM_C_INFO));
    }
    if (state == BM_PET_ALERT) {
        int b = sinf(tt * 8) > 0 ? 0 : 1;
        PXF(26, 2 + b, 3, 6, OPAQUE(BM_C_WAIT));
        PXF(26, 9 + b, 3, 2, OPAQUE(BM_C_WAIT));
    }
    if (working) {
        for (int i = 0; i < 3; i++) {
            float ph = fmodf(tt * .9f + i / 3.0f, 1.0f);
            PXF(5 + i * 10 + (i == 1 ? 2 : 0), lroundf(10 - ph * 8), 1, 1, with_alpha(BM_C_WORK, 1 - ph));
        }
    }
    if (state == BM_PET_SLEEP) {
        for (int i = 0; i < 2; i++) {
            float ph = fmodf(tt * .35f + i * .5f, 1.0f);
            draw_z(cv, 23 + ph * 4, 11 - ph * 8, 1 - ph);
        }
    }
#undef IN_BODY
}

void bm_cover_render(uint32_t argb[BM_COVER_GRID * BM_COVER_GRID], const char *title)
{
    uint32_t h = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)title; *p; p++) h = (h ^ *p) * 16777619u;
    float hue = (float)(h % 360);
    uint32_t seed = h % 2147483646u + 1;
    for (int y = 0; y < BM_COVER_GRID; y++)
        for (int x = 0; x < BM_COVER_GRID; x++) {
            seed = (uint32_t)((uint64_t)seed * 16807 % 2147483647);
            float r1 = (float)seed / 2147483647.0f;
            seed = (uint32_t)((uint64_t)seed * 16807 % 2147483647);
            float r2 = (float)seed / 2147483647.0f;
            float v = sinf(x * .5f + r1) + cosf(y * .45f) + r2 * .6f;
            argb[y * BM_COVER_GRID + x] = hsl(fmodf(hue + v * 18 + 360, 360), (60 + v * 12) / 100, (22 + (v + 2) * 11) / 100);
        }
}
