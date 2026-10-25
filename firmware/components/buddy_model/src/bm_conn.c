#include "bm_conn.h"

void bm_conn_open(bm_conn_t *c)
{
    c->open = true;
    c->slot = -1;
}

bm_err_t bm_conn_deliver(bm_model_t *m, bm_conn_t *c, const char *json, size_t len, uint32_t now_ms)
{
    if (!c->open) return BM_E_HOST_BOUND;
    return bm_ingest_bound(m, json, len, &c->slot, now_ms);
}

void bm_conn_close(bm_model_t *m, bm_conn_t *c, uint32_t now_ms)
{
    if (c->open && c->slot >= 0) bm_link(m, m->hosts[c->slot].name, false, now_ms);
    c->open = false;
    c->slot = -1;
}

bool bm_conn_wants(const bm_conn_t *c, const bm_out_t *out)
{
    return c->open && c->slot >= 0 && (out->hosts & (1u << c->slot));
}
