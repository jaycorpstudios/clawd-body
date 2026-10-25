#pragma once

#include "bm.h"

#define DEMO_EPOCH 1792900000LL
#define DEMO_EVENT_MS 4200

typedef struct {
    bm_model_t *m;
    uint32_t (*random32)(void *ctx);
    void *random_ctx;
    uint32_t start_ms, next_event_ms, counter;
    int next_pool;
    int rejected;
    struct {
        bool pending;
        uint32_t at_ms;
        char host[17];
        char request_id[27];
        char session[65];
        char kind[12];
        char outcome[12];
        int choice;
    } reply;
} demo_t;

void demo_start(demo_t *d, bm_model_t *m, uint32_t (*random32)(void *), void *ctx, uint32_t now_ms);
void demo_tick(demo_t *d, uint32_t now_ms);
void demo_on_outgoing(demo_t *d, const bm_out_t *out, uint32_t now_ms);
