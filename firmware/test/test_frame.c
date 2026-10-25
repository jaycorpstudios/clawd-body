#include <stdbool.h>

#include "bm_frame.h"
#include "harness.h"

#define MAX_FRAMES 255

static uint8_t msg[BM_FRAME_MAX_MESSAGE + 1];
static uint8_t frames[MAX_FRAMES][512];
static size_t sizes[MAX_FRAMES];
static bm_reasm_t r;

static void fill(size_t n)
{
    for (size_t i = 0; i < n; i++) msg[i] = (uint8_t)i;
}

static int split(size_t n, uint8_t seq, size_t frame_size)
{
    fill(n);
    int count = 0;
    if (bm_frame_count(n, frame_size, &count) != BM_FRAME_OK) return -1;
    for (int i = 0; i < count; i++) sizes[i] = bm_frame_build(msg, n, seq, frame_size, i, frames[i]);
    return count;
}

static const char *push(int i, size_t *len)
{
    return bm_reasm_push(&r, frames[i], sizes[i], len);
}

static bool is_message(const char *out, size_t len, size_t n)
{
    fill(n);
    return out && len == n && memcmp(out, msg, n) == 0;
}

static void round_trip(size_t n, size_t frame_size)
{
    int count = split(n, 7, frame_size);
    CHECK(count > 0);
    bm_reasm_reset(&r);
    const char *out = NULL;
    size_t len = 0;
    for (int i = 0; i < count; i++) {
        CHECK(sizes[i] > BM_FRAME_HEADER && sizes[i] <= frame_size);
        out = push(i, &len);
        CHECK((out != NULL) == (i == count - 1));
    }
    CHECK(is_message(out, len, n));
}

TEST(frames_round_trip)
{
    static const size_t cases[][2] = {{1, 20}, {17, 20}, {18, 20}, {100, 20}, {8 * 1024, 185}, {8 * 1024, 512}};
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) round_trip(cases[i][0], cases[i][1]);
}

TEST(frames_reject_oversized_and_degenerate_input)
{
    int count;
    CHECK(bm_frame_count(8 * 1024 + 1, 244, &count) == BM_FRAME_TOO_LARGE);
    CHECK(bm_frame_count(0, 244, &count) == BM_FRAME_TOO_LARGE);
    CHECK(bm_frame_count(300, 4, &count) == BM_FRAME_TOO_LARGE);
    CHECK(bm_frame_count(8 * 1024, 20, &count) == BM_FRAME_TOO_LARGE);
    CHECK(bm_frame_count(10, 3, &count) == BM_FRAME_TOO_SMALL);
    CHECK(bm_frame_count(8 * 1024, BM_FRAME_MIN_SIZE, &count) == BM_FRAME_OK && count == 249);
}

TEST(missing_frame_drops_message)
{
    split(50, 1, 20);
    bm_reasm_reset(&r);
    size_t len;
    CHECK(push(0, &len) == NULL);
    CHECK(push(2, &len) == NULL);
    CHECK(push(1, &len) == NULL);
}

TEST(new_message_replaces_partial_one)
{
    split(50, 1, 20);
    uint8_t first1[512];
    memcpy(first1, frames[1], sizes[1]);
    size_t first1_size = sizes[1];
    bm_reasm_reset(&r);
    size_t len;
    CHECK(push(0, &len) == NULL);
    split(10, 2, 20);
    CHECK(is_message(push(0, &len), len, 10));
    CHECK(bm_reasm_push(&r, first1, first1_size, &len) == NULL);
}

TEST(mixed_sequence_is_rejected)
{
    split(50, 1, 20);
    uint8_t a[2][512];
    size_t a_size[2] = {sizes[0], sizes[1]};
    memcpy(a[0], frames[0], sizes[0]);
    memcpy(a[1], frames[1], sizes[1]);
    split(50, 2, 20);
    bm_reasm_reset(&r);
    size_t len;
    CHECK(bm_reasm_push(&r, a[0], a_size[0], &len) == NULL);
    CHECK(push(1, &len) == NULL);
    CHECK(bm_reasm_push(&r, a[1], a_size[1], &len) == NULL);
}

TEST(malformed_header_is_rejected)
{
    bm_reasm_reset(&r);
    size_t len;
    CHECK(bm_reasm_push(&r, (const uint8_t[]){0, 0}, 2, &len) == NULL);
    CHECK(bm_reasm_push(&r, (const uint8_t[]){0, 2, 2, 65}, 4, &len) == NULL);
    CHECK(bm_reasm_push(&r, (const uint8_t[]){0, 0, 0, 65}, 4, &len) == NULL);
}

TEST(reassembled_message_is_nul_terminated)
{
    static const char json[] = "{\"v\":1}";
    uint8_t f[64];
    size_t n = bm_frame_build((const uint8_t *)json, strlen(json), 0, sizeof(f), 0, f);
    bm_reasm_reset(&r);
    size_t len;
    const char *out = bm_reasm_push(&r, f, n, &len);
    CHECK(out && len == strlen(json));
    CHECK_STR(out, json);
}
