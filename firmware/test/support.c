#include "support.h"

#include <stdarg.h>
#include <stdlib.h>

bm_model_t M;
uint32_t now;
static uint32_t rng_state, msg_counter;

static uint32_t xorshift(void *ctx)
{
    (void)ctx;
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

void fresh(void)
{
    rng_state = 2463534242u;
    now = 1000;
    bm_config_t cfg = {.random32 = xorshift};
    bm_init(&M, &cfg, now);
    bm_link(&M, "work", true, now);
    bm_link(&M, "home", true, now);
    advance(2300);
    outs_t o;
    drain(&o);
    bm_sound_t s;
    while (bm_sound_pop(&M, &s)) {
    }
}

void advance(uint32_t ms)
{
    uint32_t end = now + ms;
    while (now < end) {
        uint32_t step = end - now < 100 ? end - now : 100;
        now += step;
        bm_tick(&M, now);
    }
}

bm_err_t send_raw(const char *json)
{
    return bm_ingest(&M, json, strlen(json), now);
}

bm_err_t send(const char *host, const char *type, const char *data_fmt, ...)
{
    char data[4096], json[5000];
    va_list ap;
    va_start(ap, data_fmt);
    vsnprintf(data, sizeof(data), data_fmt, ap);
    va_end(ap);
    snprintf(json, sizeof(json), "{\"v\":1,\"id\":\"01K8F5%020u\",\"ts\":%lld,\"host\":\"%s\",\"type\":\"%s\",\"data\":%s}",
             ++msg_counter, BASE_TS + now / 1000, host, type, data);
    return send_raw(json);
}

void drain(outs_t *o)
{
    o->n = 0;
    bm_out_t out;
    while (bm_out_pop(&M, &out)) {
        test_emit(out.json);
        if (o->n < MAX_OUTS) o->items[o->n++] = out;
    }
}

const bm_out_t *find_out(const outs_t *o, const char *type)
{
    char needle[64];
    snprintf(needle, sizeof(needle), "\"type\":\"%s\"", type);
    for (int i = 0; i < o->n; i++)
        if (strstr(o->items[i].json, needle)) return &o->items[i];
    return NULL;
}

int count_out(const outs_t *o, const char *type)
{
    char needle[64];
    int n = 0;
    snprintf(needle, sizeof(needle), "\"type\":\"%s\"", type);
    for (int i = 0; i < o->n; i++)
        if (strstr(o->items[i].json, needle)) n++;
    return n;
}

bool heard(bm_sound_t snd)
{
    bool found = false;
    bm_sound_t s;
    while (bm_sound_pop(&M, &s))
        if (s == snd) found = true;
    return found;
}

int session_index(const char *host, const char *id)
{
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &M.sessions[i];
        if (s->used && strcmp(M.hosts[s->host].name, host) == 0 && strcmp(s->id, id) == 0) return i;
    }
    return -1;
}

void start_session(const char *host, const char *id, const char *project)
{
    CHECK(send(host, "session.start", "{\"session\":\"%s\",\"project\":\"%s\",\"task\":\"Some Task\"}", id, project) ==
          BM_OK);
}

void ask_permission(const char *host, const char *session, const char *request_id, const char *risk, bool remote)
{
    CHECK(send(host, "agent.needs_permission",
               "{\"request_id\":\"%s\",\"session\":\"%s\",\"project\":\"p-%s\",\"tool\":\"Bash\",\"detail\":\"npm "
               "test\",\"cwd\":\"~/code/p\",\"risk\":\"%s\",\"remote_allowed\":%s,\"expires_at\":%lld}",
               request_id, session, session, risk, remote ? "true" : "false", BASE_TS + now / 1000 + 600) == BM_OK);
}

void ask_question(const char *host, const char *session, const char *request_id)
{
    CHECK(send(host, "agent.question",
               "{\"request_id\":\"%s\",\"session\":\"%s\",\"project\":\"p-%s\",\"detail\":\"Which "
               "one?\",\"options\":[\"Keep \\\"both\\\"\",\"Drop\"],\"expires_at\":%lld}",
               request_id, session, session, BASE_TS + now / 1000 + 600) == BM_OK);
}

char *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)size + 1);
    *len = fread(buf, 1, (size_t)size, f);
    buf[*len] = '\0';
    fclose(f);
    return buf;
}
