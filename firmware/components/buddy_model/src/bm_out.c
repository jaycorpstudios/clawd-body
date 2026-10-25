#include <stdio.h>
#include <string.h>

#include "bm_internal.h"

static const char CROCKFORD[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

static void make_ulid(bm_model_t *m, uint64_t time_ms, char out[27])
{
    for (int i = 9; i >= 0; i--) {
        out[i] = CROCKFORD[time_ms & 31];
        time_ms >>= 5;
    }
    for (int i = 10; i < 26; i++) {
        uint32_t r = m->cfg.random32 ? m->cfg.random32(m->cfg.random_ctx) : 0;
        out[i] = CROCKFORD[r & 31];
    }
    out[26] = '\0';
}

void bm__json_escape(const char *in, char *out, size_t n)
{
    size_t o = 0;
    for (const unsigned char *p = (const unsigned char *)in; *p && o + 7 < n; p++) {
        if (*p == '"' || *p == '\\') {
            out[o++] = '\\';
            out[o++] = (char)*p;
        } else if (*p < 0x20) {
            o += (size_t)snprintf(out + o, n - o, "\\u%04x", *p);
        } else {
            out[o++] = (char)*p;
        }
    }
    out[o] = '\0';
}

void bm__out(bm_model_t *m, uint8_t hosts, const char *type, const char *data_json, uint32_t now_ms)
{
    if (m->out_len == BM_OUTBOX_LEN) {
        m->out_head = (m->out_head + 1) % BM_OUTBOX_LEN;
        m->out_len--;
    }
    bm_out_t *o = &m->outbox[(m->out_head + m->out_len++) % BM_OUTBOX_LEN];
    int64_t wall = bm_wall_ms(m, now_ms);
    char id[27];
    make_ulid(m, (uint64_t)(m->clock_known ? wall : now_ms), id);
    o->hosts = hosts;
    snprintf(o->json, sizeof(o->json), "{\"v\":1,\"id\":\"%s\",\"ts\":%lld,\"type\":\"%s\",\"data\":%s}", id,
             (long long)(wall / 1000), type, data_json);
}

bool bm_out_pop(bm_model_t *m, bm_out_t *out)
{
    if (!m->out_len) return false;
    *out = m->outbox[m->out_head];
    m->out_head = (m->out_head + 1) % BM_OUTBOX_LEN;
    m->out_len--;
    return true;
}
