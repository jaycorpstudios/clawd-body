#include <string.h>

#include "bm_frame.h"

bm_frame_err_t bm_frame_count(size_t len, size_t frame_size, int *count)
{
    if (frame_size <= BM_FRAME_HEADER) return BM_FRAME_TOO_SMALL;
    if (len == 0 || len > BM_FRAME_MAX_MESSAGE) return BM_FRAME_TOO_LARGE;
    size_t chunk = frame_size - BM_FRAME_HEADER;
    size_t n = (len + chunk - 1) / chunk;
    if (n > UINT8_MAX) return BM_FRAME_TOO_LARGE;
    *count = (int)n;
    return BM_FRAME_OK;
}

size_t bm_frame_build(const uint8_t *msg, size_t len, uint8_t seq, size_t frame_size, int index, uint8_t *out)
{
    int count;
    if (bm_frame_count(len, frame_size, &count) != BM_FRAME_OK || index < 0 || index >= count) return 0;
    size_t chunk = frame_size - BM_FRAME_HEADER;
    size_t start = (size_t)index * chunk;
    size_t body = len - start < chunk ? len - start : chunk;
    out[0] = seq;
    out[1] = (uint8_t)index;
    out[2] = (uint8_t)count;
    memcpy(out + BM_FRAME_HEADER, msg + start, body);
    return BM_FRAME_HEADER + body;
}

void bm_reasm_reset(bm_reasm_t *r)
{
    r->seq = -1;
    r->expected = 0;
    r->len = 0;
}

const char *bm_reasm_push(bm_reasm_t *r, const uint8_t *frame, size_t n, size_t *len)
{
    if (n <= BM_FRAME_HEADER) goto drop;
    int seq = frame[0], index = frame[1], count = frame[2];
    size_t body = n - BM_FRAME_HEADER;
    if (count == 0 || index >= count) goto drop;
    if (index == 0) {
        r->seq = seq;
        r->expected = 0;
        r->len = 0;
    }
    if (r->seq != seq || index != r->expected || r->len + body > BM_FRAME_MAX_MESSAGE) goto drop;
    memcpy(r->buf + r->len, frame + BM_FRAME_HEADER, body);
    r->len += body;
    r->expected++;
    if (r->expected < count) return NULL;
    r->buf[r->len] = '\0';
    *len = r->len;
    bm_reasm_reset(r);
    return (const char *)r->buf;

drop:
    bm_reasm_reset(r);
    return NULL;
}
