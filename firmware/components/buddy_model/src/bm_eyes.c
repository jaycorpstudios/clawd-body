#include <math.h>
#include <string.h>

#include "bm_eyes.h"

typedef struct {
    bool has_gx, has_gy, has_open, has_shape;
    int8_t gx, gy;
    uint8_t open[2];
    uint8_t shape[2];
    uint8_t blink, spark, z;
    uint16_t ms;
} step_t;

typedef struct {
    const char *name;
    const step_t *steps;
    uint8_t n;
} beat_t;

#define GX(v) .has_gx = true, .gx = (v)
#define GY(v) .has_gy = true, .gy = (v)
#define OPEN(a, b) .has_open = true, .open = {a, b}
#define SHAPE(a, b) .has_shape = true, .shape = {BM_EYE_##a, BM_EYE_##b}
#define MS(v) .ms = (v)
#define BEAT(nm, ...) {nm, (const step_t[]){__VA_ARGS__}, sizeof((const step_t[]){__VA_ARGS__}) / sizeof(step_t)}
#define TYPE {GY(1), MS(150)}, {GY(2), MS(150)}
#define HOP {GY(-1), MS(150)}, {GY(0), MS(150)}

static const beat_t IDLE[] = {
    BEAT("looks left", {GX(-3), MS(1500)}),
    BEAT("looks right", {GX(3), MS(1500)}),
    BEAT("looks up", {GX(1), GY(-2), MS(1300)}),
    BEAT("sweeps the room", {GX(-3), MS(650)}, {GX(0), MS(350)}, {GX(3), MS(750)}, {GX(0), MS(300)}),
    BEAT("double blink", {.blink = 2, MS(900)}),
    BEAT("curious", {GX(2), OPEN(100, 60), MS(1500)}),
    BEAT("calm dots", {SHAPE(DOT, DOT), MS(2200)}, {SHAPE(DOT, DOT), GX(2), MS(1200)}),
    BEAT("rests", {MS(1800)}),
};

static const beat_t WORKING[] = {
    BEAT("heads down, reading", {GX(-2), GY(2), MS(420)}, {GX(0), GY(2), MS(420)}, {GX(2), GY(2), MS(420)},
         {GX(-2), GY(3), MS(420)}, {GX(0), GY(3), MS(420)}, {GX(2), GY(3), MS(600)}),
    BEAT("deep focus", {SHAPE(SQUARE, SQUARE), GY(0), MS(2400)}, {SHAPE(SQUARE, SQUARE), GX(1), GY(0), MS(1400)}),
    BEAT("pushes through", {SHAPE(SQUEEZE, SQUEEZE), GY(0), MS(1100)}, {OPEN(60, 60), MS(300)},
         {SHAPE(SQUEEZE, SQUEEZE), GY(0), MS(700)}),
    BEAT("thinks it over", {GX(2), GY(-2), OPEN(100, 75), MS(1700)}),
    BEAT("types", TYPE, TYPE, TYPE, TYPE, TYPE),
    BEAT("tracks the output", {SHAPE(DOT, DOT), GX(-3), GY(1), MS(500)}, {SHAPE(DOT, DOT), GX(0), GY(1), MS(400)},
         {SHAPE(DOT, DOT), GX(3), GY(1), MS(500)}, {SHAPE(DOT, DOT), GX(-3), GY(2), MS(500)},
         {SHAPE(DOT, DOT), GX(3), GY(2), MS(600)}),
    BEAT("slow blink", {OPEN(30, 30), MS(260)}, {OPEN(60, 60), MS(900)}),
};

static const beat_t WAITING[] = {
    BEAT("glances left", {GX(-3), MS(650)}, {GX(0), MS(700)}),
    BEAT("glances right", {GX(3), MS(650)}, {GX(0), MS(700)}),
    BEAT("looks at you", {GY(0), OPEN(100, 100), MS(1600)}),
    BEAT("nervous blinks", {.blink = 2, MS(800)}),
    BEAT("sighs", {OPEN(50, 50), GY(2), MS(1000)}),
};

static const beat_t DONE[] = {
    BEAT("bounces", HOP, HOP, HOP),
    BEAT("winks", {SHAPE(OPEN, DASH), MS(800)}),
    BEAT("heart eyes", {SHAPE(HEART, HEART), MS(1300)}),
    BEAT("sparkles", {.spark = BM_EYES_SPARKS, MS(1200)}),
};

static const beat_t SLEEP[] = {
    BEAT("peeks", {OPEN(0, 40), SHAPE(SLEEP, OPEN), GX(1), MS(1100)}),
    BEAT("snores", {.z = BM_EYES_ZS, MS(2200)}),
    BEAT("dreams", {MS(2600)}),
};

#define COUNT(a) (int)(sizeof(a) / sizeof((a)[0]))

static const struct {
    const beat_t *beats;
    int n;
    uint16_t gap[2], blink[2];
} POOLS[BM_MOODS] = {
    [BM_MOOD_IDLE] = {IDLE, COUNT(IDLE), {600, 2200}, {2000, 6000}},
    [BM_MOOD_WORKING] = {WORKING, COUNT(WORKING), {150, 900}, {4000, 8000}},
    [BM_MOOD_WAITING] = {WAITING, COUNT(WAITING), {500, 1600}, {1500, 3500}},
    [BM_MOOD_DONE] = {DONE, COUNT(DONE), {200, 700}, {3000, 5000}},
    [BM_MOOD_SLEEP] = {SLEEP, COUNT(SLEEP), {1500, 4000}, {0, 0}},
};

static const uint16_t REACT_MS[] = {[BM_REACT_HAPPY] = 1100, [BM_REACT_BLINK] = 700, [BM_REACT_GLANCE] = 900};

int bm_eyes_pool_size(bm_mood_t mood)
{
    return mood < BM_MOODS ? POOLS[mood].n : 0;
}

const char *bm_eyes_beat_name(bm_mood_t mood, int beat)
{
    return mood < BM_MOODS && beat >= 0 && beat < POOLS[mood].n ? POOLS[mood].beats[beat].name : "";
}

/* JavaScript's Math.round, so the cells match the prototype exactly. */
int bm_eyes_round(double v)
{
    return (int)floor(v + 0.5);
}

static bool due(uint32_t now_ms, uint32_t at_ms)
{
    return (int32_t)(now_ms - at_ms) >= 0;
}

static uint32_t between(bm_rand_fn rnd, void *ctx, uint32_t lo, uint32_t hi)
{
    uint32_t r = rnd ? rnd(ctx) : 0;
    return lo + r % (hi - lo + 1);
}

static void base_pose(bm_mood_t mood, bm_eye_pose_t *p)
{
    static const bm_eye_pose_t base[BM_MOODS] = {
        [BM_MOOD_IDLE] = {0, 0, {100, 100}, {BM_EYE_OPEN, BM_EYE_OPEN}},
        [BM_MOOD_WORKING] = {0, 1, {60, 60}, {BM_EYE_OPEN, BM_EYE_OPEN}},
        [BM_MOOD_WAITING] = {0, 1, {90, 90}, {BM_EYE_WORRIED, BM_EYE_WORRIED}},
        [BM_MOOD_DONE] = {0, 0, {100, 100}, {BM_EYE_HAPPY, BM_EYE_HAPPY}},
        [BM_MOOD_SLEEP] = {0, 0, {0, 0}, {BM_EYE_SLEEP, BM_EYE_SLEEP}},
    };
    *p = base[mood];
}

static void react_pose(bm_react_t kind, bm_eye_pose_t *p)
{
    if (kind == BM_REACT_GLANCE) {
        base_pose(BM_MOOD_WAITING, p);
        p->gx = -3;
        return;
    }
    base_pose(BM_MOOD_IDLE, p);
    if (kind == BM_REACT_HAPPY) p->shape[0] = p->shape[1] = BM_EYE_HAPPY;
}

static void start_blinks(bm_eyes_t *e, uint8_t n, uint32_t now_ms)
{
    e->blinks = n;
    e->blink_start_ms = now_ms;
}

static void add_sparks(bm_eyes_t *e, int n, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    for (int i = 0; i < n; i++) {
        bm_spark_t *s = &e->sparks[e->spark_next];
        e->spark_next = (uint8_t)((e->spark_next + 1) % BM_EYES_SPARKS);
        s->x = (uint8_t)between(rnd, ctx, 4, BM_EYES_GRID - 5);
        s->y = (uint8_t)between(rnd, ctx, 4, 33);
        s->at_ms = now_ms + (uint32_t)i * 120;
    }
}

static void schedule_blink(bm_eyes_t *e, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    const uint16_t *b = POOLS[e->mood].blink;
    e->blink_at_ms = b[1] ? now_ms + between(rnd, ctx, b[0], b[1]) : 0;
}

static void set_mood(bm_eyes_t *e, bm_mood_t mood, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    e->mood = mood;
    e->mood_ms = now_ms;
    e->beat = -1;
    base_pose(mood, &e->target);
    e->next_beat_ms = now_ms + between(rnd, ctx, 300, 900);
    schedule_blink(e, now_ms, rnd, ctx);
    if (mood == BM_MOOD_DONE) {
        memset(e->sparks, 0, sizeof(e->sparks));
        add_sparks(e, BM_EYES_SPARKS, now_ms, rnd, ctx);
    }
}

static int pick_beat(const bm_eyes_t *e, bm_rand_fn rnd, void *ctx)
{
    int n = POOLS[e->mood].n;
    bool avoid = e->last_mood == e->mood && e->last_beat >= 0 && n > 1;
    int i = (int)between(rnd, ctx, 0, (uint32_t)(n - 1 - avoid));
    return avoid && i >= e->last_beat ? i + 1 : i;
}

static void apply_step(bm_eyes_t *e, const step_t *st, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    base_pose(e->mood, &e->target);
    if (st->has_gx) e->target.gx = st->gx;
    if (st->has_gy) e->target.gy = st->gy;
    if (st->has_open) memcpy(e->target.open, st->open, sizeof(e->target.open));
    if (st->has_shape) {
        e->target.shape[0] = (bm_eye_shape_t)st->shape[0];
        e->target.shape[1] = (bm_eye_shape_t)st->shape[1];
    }
    if (st->blink) start_blinks(e, st->blink, now_ms);
    if (st->spark) add_sparks(e, st->spark, now_ms, rnd, ctx);
    for (int i = 0; i < st->z; i++) {
        e->z_ms[e->z_next] = now_ms + (uint32_t)i * 600;
        e->z_next = (uint8_t)((e->z_next + 1) % BM_EYES_ZS);
    }
    e->step_until_ms = now_ms + st->ms;
}

static void step_beat(bm_eyes_t *e, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    if (e->beat < 0 && due(now_ms, e->next_beat_ms)) {
        e->beat = (int8_t)pick_beat(e, rnd, ctx);
        e->last_beat = e->beat;
        e->last_mood = e->mood;
        e->beats_started++;
        e->step = -1;
        e->step_until_ms = now_ms;
    }
    if (e->beat < 0 || !due(now_ms, e->step_until_ms)) return;
    const beat_t *b = &POOLS[e->mood].beats[e->beat];
    if (++e->step >= b->n) {
        e->beat = -1;
        base_pose(e->mood, &e->target);
        const uint16_t *gap = POOLS[e->mood].gap;
        e->next_beat_ms = now_ms + between(rnd, ctx, gap[0], gap[1]);
        return;
    }
    apply_step(e, &b->steps[e->step], now_ms, rnd, ctx);
}

static float blink_amount(bm_eyes_t *e, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    if (e->blink_at_ms && due(now_ms, e->blink_at_ms) && (!e->blinks || (int32_t)(now_ms - e->blink_start_ms) > 400)) {
        start_blinks(e, 1, now_ms);
        schedule_blink(e, now_ms, rnd, ctx);
    }
    if (!e->blinks || !due(now_ms, e->blink_start_ms)) return 0;
    float p = (float)(now_ms - e->blink_start_ms) / 220.0f;
    if (p >= 1) {
        e->blinks_done++;
        if (--e->blinks) e->blink_start_ms = now_ms + 60;
        return 0;
    }
    return p < 0.45f ? p / 0.45f : p < 0.6f ? 1 : 1 - (p - 0.6f) / 0.4f;
}

static void react_tick(bm_eyes_t *e, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    if (e->react_pending && due(now_ms, e->react_at_ms)) {
        e->react = e->react_pending;
        e->react_pending = BM_REACT_NONE;
        e->react_until_ms = now_ms + REACT_MS[e->react];
        e->beat = -1;
        if (e->react == BM_REACT_BLINK) start_blinks(e, 1, now_ms);
    }
    if (e->react && due(now_ms, e->react_until_ms)) {
        e->react = BM_REACT_NONE;
        base_pose(e->mood, &e->target);
        e->next_beat_ms = now_ms + 400;
    }
    if (e->react) react_pose(e->react, &e->target);
    else step_beat(e, now_ms, rnd, ctx);
}

void bm_eyes_react(bm_eyes_t *e, bm_react_t kind, uint32_t at_ms)
{
    e->react_pending = kind;
    e->react_at_ms = at_ms;
}

static bool blinkable(bm_eye_shape_t s)
{
    return s == BM_EYE_OPEN || s == BM_EYE_WORRIED;
}

void bm_eyes_tick(bm_eyes_t *e, bm_mood_t want, uint32_t now_ms, bm_rand_fn rnd, void *ctx)
{
    if (!e->started) {
        e->started = true;
        e->last_beat = -1;
        e->last_ms = now_ms;
        set_mood(e, want, now_ms, rnd, ctx);
        e->open[0] = e->open[1] = e->target.open[0] / 100.0f;
    }
    float dt = (float)(now_ms - e->last_ms) / 1000.0f;
    if (dt > 0.1f) dt = 0.1f;
    e->last_ms = now_ms;

    bool done_holds = e->mood == BM_MOOD_DONE && want != BM_MOOD_SLEEP && now_ms - e->mood_ms < BM_EYES_DONE_MS;
    if (want != e->mood && !done_holds) set_mood(e, want, now_ms, rnd, ctx);
    react_tick(e, now_ms, rnd, ctx);

    float k = dt * 14 < 1 ? dt * 14 : 1;
    for (int i = 0; i < 2; i++) e->open[i] += (e->target.open[i] / 100.0f - e->open[i]) * k;

    bm_eyes_out_t *o = &e->out;
    o->blink = blink_amount(e, now_ms, rnd, ctx);
    o->gx = e->target.gx;
    int gy = e->target.gy;
    if (e->mood == BM_MOOD_SLEEP) gy += bm_eyes_round(sin((double)now_ms / 1500.0) * 0.6);
    uint32_t in_mood = now_ms - e->mood_ms;
    if (e->mood == BM_MOOD_DONE && in_mood < 1500) gy -= bm_eyes_round(fabs(sin((double)in_mood / 150.0)));
    o->gy = (int8_t)gy;
    for (int i = 0; i < 2; i++) {
        o->shape[i] = e->target.shape[i];
        o->open[i] = blinkable(o->shape[i]) ? e->open[i] * (1 - o->blink) : e->open[i];
    }
}

static void rect(uint8_t *cells, int w, int h, int x, int y, int rw, int rh, uint8_t v)
{
    for (int yy = y < 0 ? 0 : y; yy < y + rh && yy < h; yy++)
        for (int xx = x < 0 ? 0 : x; xx < x + rw && xx < w; xx++) cells[yy * w + xx] = v;
}

static void dot(uint8_t *cells, int w, int h, int s)
{
    rect(cells, w, h, (w - 2 * s) / 2, (h - 2 * s) / 2, 2 * s, 2 * s, 1);
}

static const char *const HEART[] = {".XX...XX.", "XXXX.XXXX", "XXXXXXXXX", "XXXXXXXXX",
                                    ".XXXXXXX.", "..XXXXX..", "...XXX...", "....X...."};

static void heart(uint8_t *cells, int w, int h)
{
    int hx = (w - 9) / 2, hy = (h - 8) / 2;
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 9; x++)
            if (HEART[y][x] == 'X') rect(cells, w, h, hx + x, hy + y, 1, 1, 1);
}

/* Every stroke is `s` cells thick and every diagonal steps one cell, so lines never thin out. */
void bm_eye_cells(uint8_t *cells, int w, int h, float open, bm_eye_shape_t shape, int side)
{
    memset(cells, 0, (size_t)w * (size_t)h);
    int s = bm_eyes_round(w / 4.5) > 1 ? bm_eyes_round(w / 4.5) : 1, mid = (w - s) / 2;
    switch (shape) {
    case BM_EYE_HAPPY: {
        int top = bm_eyes_round(h * 0.32), n = (w - s) / 2;
        for (int i = 0; i <= n; i++) {
            rect(cells, w, h, mid - i, top + i, s, s, 1);
            rect(cells, w, h, mid + i, top + i, s, s, 1);
        }
        return;
    }
    case BM_EYE_SQUEEZE: {
        int n = (int)(h * 0.3) < w - s - 1 ? (int)(h * 0.3) : w - s - 1;
        int left = (w - n - s) / 2, cy = (h - s) / 2;
        for (int i = 0; i <= n; i++) {
            int x = side < 0 ? left + n - i : left + i;
            rect(cells, w, h, x, cy - i, s, s, 1);
            rect(cells, w, h, x, cy + i, s, s, 1);
        }
        return;
    }
    case BM_EYE_SQUARE: {
        int q = w, y = bm_eyes_round((h - q) / 2.0);
        rect(cells, w, h, 0, y, q, s, 1);
        rect(cells, w, h, 0, y + q - s, q, s, 1);
        rect(cells, w, h, 0, y, s, q, 1);
        rect(cells, w, h, q - s, y, s, q, 1);
        return;
    }
    case BM_EYE_HEART:
        if (w < 9) dot(cells, w, h, s);
        else heart(cells, w, h);
        return;
    case BM_EYE_DOT: dot(cells, w, h, s); return;
    case BM_EYE_DASH: rect(cells, w, h, 1, bm_eyes_round(h * 0.58), w - 2, s, 1); return;
    default: break;
    }
    int rows = bm_eyes_round((open < 1 ? open : 1) * h);
    if (shape == BM_EYE_SLEEP || rows <= s + 1) {
        int y = bm_eyes_round(h * 0.6), up = shape == BM_EYE_SLEEP ? (s + 1) / 2 : 0;
        rect(cells, w, h, s, y, w - 2 * s, s, 1);
        rect(cells, w, h, 0, y - up, s, s, 1);
        rect(cells, w, h, w - s, y - up, s, s, 1);
        return;
    }
    int top = h - rows, half = (w + 1) / 2;
    rect(cells, w, h, 0, top, w, rows, 1);
    if (shape == BM_EYE_WORRIED && rows > 2 * s) rect(cells, w, h, side < 0 ? 0 : w - half, top, half, s, 0);
    if (w >= 5 && rows >= 4) {
        rect(cells, w, h, 0, top, 1, 1, 0);
        rect(cells, w, h, w - 1, top, 1, 1, 0);
        rect(cells, w, h, 0, h - 1, 1, 1, 0);
        rect(cells, w, h, w - 1, h - 1, 1, 1, 0);
    }
}
