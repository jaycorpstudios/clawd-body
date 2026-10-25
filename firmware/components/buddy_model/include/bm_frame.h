#pragma once

#include <stddef.h>
#include <stdint.h>

#define BM_FRAME_HEADER 3
#define BM_FRAME_MAX_MESSAGE 8192
#define BM_FRAME_MIN_SIZE 36

typedef enum {
    BM_FRAME_OK = 0,
    BM_FRAME_TOO_LARGE,
    BM_FRAME_TOO_SMALL,
} bm_frame_err_t;

bm_frame_err_t bm_frame_count(size_t len, size_t frame_size, int *count);
size_t bm_frame_build(const uint8_t *msg, size_t len, uint8_t seq, size_t frame_size, int index, uint8_t *out);

typedef struct {
    int seq;
    int expected;
    size_t len;
    uint8_t buf[BM_FRAME_MAX_MESSAGE + 1];
} bm_reasm_t;

void bm_reasm_reset(bm_reasm_t *r);
const char *bm_reasm_push(bm_reasm_t *r, const uint8_t *frame, size_t n, size_t *len);
