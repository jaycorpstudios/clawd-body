#pragma once

#include "bm.h"

#define BM_ALL_HOSTS 0xff

void bm__touch(bm_model_t *m);
int bm__host_slot(bm_model_t *m, const char *name, bool create);
bm_session_t *bm__find_session(bm_model_t *m, int host, const char *id);
bm_session_t *bm__find_request(bm_model_t *m, int host, const char *request_id);
bm_session_t *bm__new_session(bm_model_t *m, int host, const char *id);
void bm__remove_session(bm_model_t *m, bm_session_t *s);
void bm__clear_host(bm_model_t *m, int host);
void bm__push_step(bm_session_t *s, int64_t ts, bm_step_kind_t kind, const char *text);
void bm__observe_ts(bm_model_t *m, int64_t ts, bool exact, uint32_t now_ms);

void bm__sound(bm_model_t *m, bm_sound_t s);
void bm__toast(bm_model_t *m, const char *text, uint32_t color, uint32_t now_ms);
void bm__show_overlay(bm_model_t *m, const bm_overlay_state_t *ov, uint32_t duration_ms, uint32_t now_ms);
void bm__close_overlay(bm_model_t *m);
void bm__open_attn(bm_model_t *m, int idx, uint32_t now_ms);
void bm__wake(bm_model_t *m, bool silent, bm_by_t by, uint32_t now_ms);
void bm__check_usage(bm_model_t *m, int host, uint32_t now_ms);

void bm__out(bm_model_t *m, uint8_t hosts, const char *type, const char *data_json, uint32_t now_ms);
void bm__json_escape(const char *in, char *out, size_t n);
void bm__copy(char *dst, size_t n, const char *src);

void bm__on_session_start(bm_model_t *m, int host, const char *id, const char *project, const char *task, int64_t ts,
                          uint32_t now_ms);
void bm__on_session_end(bm_model_t *m, int host, const char *id, uint32_t now_ms);
void bm__on_request(bm_model_t *m, int host, const char *session, const char *project, const bm_request_t *req,
                    int64_t ts, uint32_t now_ms);
void bm__on_resolved(bm_model_t *m, int host, const char *request_id, const char *outcome, const char *via,
                     uint32_t now_ms);
void bm__on_task_done(bm_model_t *m, int host, const char *session, const char *summary, int64_t ts, uint32_t now_ms);
void bm__on_error(bm_model_t *m, int host, const char *session, const char *detail, int64_t ts, uint32_t now_ms);
void bm__on_step(bm_model_t *m, int host, const char *session, bm_step_kind_t kind, const char *text, int64_t ts);
void bm__on_usage(bm_model_t *m, int host, const bm_usage_t *u, uint32_t now_ms);
void bm__on_window_reset(bm_model_t *m, int host, uint32_t now_ms);
void bm__on_hilo_task(bm_model_t *m, int host, const bm_hilo_item_t *item, int64_t started_at, uint32_t now_ms);
void bm__on_media(bm_model_t *m, int host, const bm_media_t *media, uint32_t now_ms);
void bm__after_snapshot(bm_model_t *m, int host, uint32_t now_ms);

void bm__settings_defaults(bm_settings_t *s);
void bm__on_settings(bm_model_t *m, const bm_settings_t *s, uint32_t now_ms);
void bm__send_settings(bm_model_t *m, uint8_t hosts, uint32_t now_ms);
bm_err_t bm__on_face_chunk(bm_model_t *m, int host, const char *hash, int w, int h, int index, int count,
                           const char *data, uint32_t now_ms);
void bm__on_face_ref(bm_model_t *m, int host, const char *hash, uint32_t now_ms);
bm_err_t bm__on_cover_chunk(bm_model_t *m, int host, const char *hash, int w, int h, int index, int count,
                            const char *data, uint32_t now_ms);
void bm__want_cover(bm_model_t *m, int host, uint32_t now_ms);
void bm__pomo_defaults(bm_pomo_t *p);
void bm__on_pomodoro(bm_model_t *m, int host, const bm_pomo_t *p, bool from_snapshot, bool present, uint32_t now_ms);
void bm__pomo_tap(bm_model_t *m, bm_tap_t target, int arg, uint32_t now_ms);
void bm__pomo_tick(bm_model_t *m, uint32_t now_ms);
void bm__alarm_start(bm_model_t *m, uint32_t now_ms);
bool bm__alarm_ack(bm_model_t *m, uint32_t now_ms);
void bm__settings_tick(bm_model_t *m, uint32_t now_ms);
void bm__sleep_card_tick(bm_model_t *m, uint32_t now_ms);
void bm__media_tap(bm_model_t *m, int action, uint32_t now_ms);
