#pragma once

#include "bm.h"
#include "harness.h"

#define BASE_TS 1792900000LL
#define MAX_OUTS 32

extern bm_model_t M;
extern uint32_t now;

typedef struct {
    bm_out_t items[MAX_OUTS];
    int n;
} outs_t;

void fresh(void);
void advance(uint32_t ms);
bm_err_t send(const char *host, const char *type, const char *data_fmt, ...) __attribute__((format(printf, 3, 4)));
bm_err_t send_raw(const char *json);
void drain(outs_t *o);
const bm_out_t *find_out(const outs_t *o, const char *type);
int count_out(const outs_t *o, const char *type);
bool heard(bm_sound_t snd);
int session_index(const char *host, const char *id);

void start_session(const char *host, const char *id, const char *project);
void ask_permission(const char *host, const char *session, const char *request_id, const char *risk, bool remote);
void ask_question(const char *host, const char *session, const char *request_id);
char *read_file(const char *path, size_t *len);
