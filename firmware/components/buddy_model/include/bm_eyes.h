#pragma once

#include <stdbool.h>
#include <stdint.h>

#define BM_EYES_CELL 8
#define BM_EYES_GRID 60
#define BM_EYES_FACE_W 9
#define BM_EYES_FACE_H 16
#define BM_EYES_FACE_X 8
#define BM_EYES_FACE_Y 14
#define BM_EYES_SLEEP_W 4
#define BM_EYES_SLEEP_H 7
#define BM_EYES_SLEEP_X 18
#define BM_EYES_SLEEP_Y 9
#define BM_EYES_TILE_GRID 16
#define BM_EYES_TILE_W 3
#define BM_EYES_TILE_H 6
#define BM_EYES_DONE_MS 4000
#define BM_EYES_REACT_DELAY_MS 340
#define BM_EYES_SPARKS 6
#define BM_EYES_SPARK_MS 900
#define BM_EYES_ZS 3
#define BM_EYES_Z_MS 2400

typedef enum { BM_MOOD_IDLE, BM_MOOD_WORKING, BM_MOOD_WAITING, BM_MOOD_DONE, BM_MOOD_SLEEP, BM_MOODS } bm_mood_t;

typedef enum {
    BM_EYE_OPEN, BM_EYE_WORRIED, BM_EYE_SLEEP, BM_EYE_HAPPY, BM_EYE_SQUEEZE, BM_EYE_SQUARE, BM_EYE_DOT, BM_EYE_HEART,
    BM_EYE_DASH, BM_EYE_SHAPES
} bm_eye_shape_t;

typedef enum { BM_REACT_NONE, BM_REACT_HAPPY, BM_REACT_BLINK, BM_REACT_GLANCE } bm_react_t;

typedef struct {
    int8_t gx, gy;
    uint8_t open[2];
    bm_eye_shape_t shape[2];
} bm_eye_pose_t;

typedef struct {
    int8_t gx, gy;
    float open[2];
    float blink;
    bm_eye_shape_t shape[2];
} bm_eyes_out_t;

typedef struct {
    uint8_t x, y;
    uint32_t at_ms;
} bm_spark_t;

typedef struct {
    bm_mood_t mood;
    uint32_t mood_ms;
    int8_t beat, last_beat, step;
    bm_mood_t last_mood;
    uint32_t beats_started;
    uint32_t step_until_ms, next_beat_ms;
    bm_eye_pose_t target;
    float open[2];
    uint32_t blink_at_ms, blink_start_ms;
    uint8_t blinks;
    uint32_t blinks_done;
    bm_react_t react, react_pending;
    uint32_t react_at_ms, react_until_ms;
    bm_spark_t sparks[BM_EYES_SPARKS];
    uint8_t spark_next;
    uint32_t z_ms[BM_EYES_ZS];
    uint8_t z_next;
    uint32_t last_ms;
    bool started;
    bm_eyes_out_t out;
} bm_eyes_t;

typedef uint32_t (*bm_rand_fn)(void *ctx);

void bm_eyes_tick(bm_eyes_t *e, bm_mood_t want, uint32_t now_ms, bm_rand_fn rnd, void *ctx);
void bm_eyes_react(bm_eyes_t *e, bm_react_t kind, uint32_t at_ms);
int bm_eyes_pool_size(bm_mood_t mood);
const char *bm_eyes_beat_name(bm_mood_t mood, int beat);

/* Fills a w×h cell mask (1 = ink); `side` is -1 for the left eye. */
void bm_eye_cells(uint8_t *cells, int w, int h, float open, bm_eye_shape_t shape, int side);
int bm_eyes_round(double v);
