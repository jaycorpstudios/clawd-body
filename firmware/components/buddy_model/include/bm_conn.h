#pragma once

#include "bm.h"

typedef struct {
    bool open;
    int8_t slot;
} bm_conn_t;

void bm_conn_open(bm_conn_t *c);
bm_err_t bm_conn_deliver(bm_model_t *m, bm_conn_t *c, const char *json, size_t len, uint32_t now_ms);
void bm_conn_close(bm_model_t *m, bm_conn_t *c, uint32_t now_ms);
bool bm_conn_wants(const bm_conn_t *c, const bm_out_t *out);
