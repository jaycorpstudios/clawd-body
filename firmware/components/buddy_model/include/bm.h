#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "bm_eyes.h"

#define BM_MAX_HOSTS 2
#define BM_SESSIONS_PER_HOST 8
#define BM_MAX_SESSIONS (BM_MAX_HOSTS * BM_SESSIONS_PER_HOST)
#define BM_MAX_STEPS 5
#define BM_MAX_DIFF 12
#define BM_MAX_OPTIONS 4
#define BM_MAX_NEXT 3
#define BM_MAX_AGREEMENTS 3
#define BM_AGENT_ROWS 5
#define BM_VIEWS 7
#define BM_OUTBOX_LEN 8
#define BM_OUT_MAX 512
#define BM_SOUND_QUEUE 8
#define BM_SEEN_IDS 32

#define BM_IDLE_SLEEP_MS 60000
#define BM_FACE_RETURN_MS 20000
#define BM_REMIND_MS 25000
#define BM_HOLD_MS 900
#define BM_LONG_PRESS_MS 650
#define BM_NEXT_ATTN_MS 1500
#define BM_TOAST_MS 2400
#define BM_SLEEP_SHIFT_S 6
#define BM_LOW_BATTERY_PCT 15
#define BM_PAIRING_HOLD_MS 5000
#define BM_PAIRING_MS 60000
#define BM_PASSKEY_MS 30000
#define BM_SETTINGS_SETTLE_MS 400
#define BM_SLEEP_CARD_S 8
#define BM_FACE_MAX 160
#define BM_FACE_CHUNKS 16
#define BM_COVER_MAX 96
#define BM_COVER_CHUNKS 8
#define BM_COVER_WAIT_MS 8000
#define BM_LOOK_ECHO_MS 5000
#define BM_POMO_WORK_MIN 25
#define BM_POMO_BREAK_MIN 5
#define BM_ALARM_MS 30000
#define BM_ALARM_BURSTS 3
#define BM_ALARM_BURST_GAP_MS 1000
#define BM_ALARM_REPEAT_MS 5000
#define BM_ALARM_MIN_VOLUME 60
#define BM_TZ_MIN -720
#define BM_TZ_MAX 840
#define BM_TZ_STEP 15

#define BM_C_WORK 0xff9a52
#define BM_C_WAIT 0xffc53d
#define BM_C_DONE 0x5ee3a8
#define BM_C_ERR 0xff5d62
#define BM_C_IDLE 0x8b8f99
#define BM_C_INFO 0x7cc8ff
#define BM_C_BLE 0x5b8cff

typedef enum { BM_WAITING, BM_ERROR, BM_WORKING, BM_DONE, BM_IDLE } bm_status_t;

typedef enum {
    BM_PET_IDLE, BM_PET_WORKING, BM_PET_ALERT, BM_PET_HAPPY, BM_PET_ERROR, BM_PET_WORRIED, BM_PET_SLEEP
} bm_pet_state_t;

typedef enum {
    BM_ACC_NONE, BM_ACC_WIZARD, BM_ACC_SHADES, BM_ACC_HEADPHONES, BM_ACC_CROWN, BM_ACC_PARTY, BM_ACC_BAND, BM_ACC_HEART,
    BM_ACC_COUNT
} bm_acc_t;

typedef enum {
    BM_STEP_PLAN, BM_STEP_READ, BM_STEP_EDIT, BM_STEP_RUN, BM_STEP_ASK, BM_STEP_OK, BM_STEP_DENY, BM_STEP_ERR
} bm_step_kind_t;

typedef enum {
    BM_OV_NONE, BM_OV_DONE, BM_OV_ERROR, BM_OV_APPROVED, BM_OV_DENIED, BM_OV_WARN, BM_OV_LIMIT, BM_OV_CONN, BM_OV_BATT
} bm_overlay_t;

typedef enum { BM_SHEET_NONE, BM_SHEET_AGENT, BM_SHEET_PERM, BM_SHEET_USAGE, BM_SHEET_HILO } bm_sheet_t;

typedef enum {
    BM_VIEW_FACE, BM_VIEW_HOME, BM_VIEW_AGENTS, BM_VIEW_USAGE, BM_VIEW_HILO, BM_VIEW_MUSIC, BM_VIEW_POMODORO
} bm_view_t;

typedef enum {
    BM_SND_PERM, BM_SND_QUESTION, BM_SND_RISK, BM_SND_REMINDER,
    BM_SND_DONE, BM_SND_APPROVED, BM_SND_CONNECTED, BM_SND_CHARGE,
    BM_SND_ERROR, BM_SND_WARN, BM_SND_LIMIT, BM_SND_BATTERY, BM_SND_DISCONNECTED,
    BM_SND_START, BM_SND_DENIED, BM_SND_MEDIA, BM_SND_CLICK
} bm_sound_t;

typedef enum { BM_BY_TOUCH, BM_BY_BUTTON, BM_BY_LONG_PRESS, BM_BY_IDLE } bm_by_t;

typedef enum {
    BM_OK = 0,
    BM_E_JSON,
    BM_E_ENVELOPE,
    BM_E_VERSION,
    BM_E_DUPLICATE,
    BM_E_TYPE,
    BM_E_DATA,
    BM_E_HOSTS_FULL,
    BM_E_HOST_BOUND,
} bm_err_t;

typedef struct {
    int64_t ts;
    bm_step_kind_t kind;
    char text[121];
} bm_step_t;

typedef struct {
    bool added;
    char line[121];
} bm_diff_line_t;

typedef struct {
    char request_id[27];
    bool is_question;
    char tool[33];
    char detail[301];
    char why[301];
    char cwd[121];
    bm_diff_line_t diff[BM_MAX_DIFF];
    uint8_t n_diff;
    bool high_risk;
    bool remote_allowed;
    int64_t expires_at;
    char options[BM_MAX_OPTIONS][41];
    uint8_t n_options;
    bool snoozed;
    bool acked;
} bm_request_t;

typedef struct {
    bool used;
    uint8_t host;
    uint32_t order;
    char id[65];
    char project[65];
    char task[121];
    bm_status_t status;
    int64_t since;
    int32_t tokens;
    char summary[301];
    char error[301];
    bm_step_t steps[BM_MAX_STEPS];
    uint8_t n_steps;
    bool has_request;
    bm_request_t req;
    bool has_look;
    uint16_t look_hue;
    bm_acc_t look_acc;
} bm_session_t;

typedef struct {
    bool known;
    float session_pct;
    float weekly_pct;
    int32_t reset_in_min;
    int64_t tokens_today;
    uint32_t received_ms;
    bool warned;
} bm_usage_t;

typedef struct {
    char title[121];
    char project[65];
    char jira[20];
} bm_hilo_item_t;

typedef struct {
    bool has_current;
    bm_hilo_item_t current;
    int64_t started_at;
    bm_hilo_item_t next[BM_MAX_NEXT];
    uint8_t n_next;
    char agreements[BM_MAX_AGREEMENTS][121];
    uint8_t n_agreements;
    uint32_t updated_ms;
} bm_hilo_t;

typedef struct {
    bool playing;
    bool paused;
    char title[81];
    char artist[81];
    int32_t length_s;
    int32_t position_s;
    uint32_t received_ms;
    char cover[17];
} bm_media_t;

typedef struct {
    char hash[17];
    uint16_t w, h;
    uint16_t px[BM_FACE_MAX * BM_FACE_MAX];
} bm_face_t;

typedef struct {
    char hash[17];
    uint16_t w, h;
    uint16_t px[BM_COVER_MAX * BM_COVER_MAX];
} bm_cover_t;

typedef struct {
    bool used;
    char name[17];
    bool connected;
    int64_t connected_at;
    int64_t disconnected_at;
    bm_usage_t usage;
    bm_hilo_t hilo;
    bm_media_t media;
    bool music_off;
    bool has_face;
    bm_face_t face;
} bm_host_t;

typedef struct {
    bool sound;
    uint8_t volume;
    uint8_t brightness;
    int16_t tz_offset_min;
} bm_settings_t;

typedef enum { BM_POMO_STOPPED, BM_POMO_RUNNING, BM_POMO_PAUSED } bm_pomo_run_t;

typedef struct {
    bm_pomo_run_t state;
    bool on_break;
    int64_t ends_at;
    int32_t left_s;
    uint8_t work_min;
    uint8_t break_min;
    uint16_t cycle;
    int64_t updated_at;
} bm_pomo_t;

typedef struct {
    int8_t host;
    char hash[17];
    uint16_t w, h;
    uint8_t count, next;
    uint32_t bytes;
} bm_rx_t;

typedef struct {
    uint8_t host;
    char session[65];
    bm_acc_t acc;
    uint32_t until_ms;
} bm_look_pick_t;

typedef struct {
    bm_overlay_t type;
    int8_t session;
    uint8_t host;
    bool on;
    bool question;
    char name[65];
    char text[301];
    uint32_t until_ms;
} bm_overlay_state_t;

typedef struct {
    uint8_t hosts;
    char json[BM_OUT_MAX];
} bm_out_t;

typedef struct {
    uint32_t (*random32)(void *ctx);
    void *random_ctx;
    int32_t tz_offset_min;
} bm_config_t;

typedef struct {
    bm_config_t cfg;
    uint32_t rev;

    bm_host_t hosts[BM_MAX_HOSTS];
    bm_session_t sessions[BM_MAX_SESSIONS];
    uint32_t next_order;

    char seen[BM_SEEN_IDS][27];
    uint8_t seen_next;

    bool clock_known;
    int64_t wall_offset_ms;
    uint32_t clock_synced;

    bm_view_t view;
    bm_overlay_state_t ov;
    bm_look_pick_t look_pick;
    char toast[121];
    uint32_t toast_color;
    uint32_t toast_until_ms;
    int8_t attn;
    bm_sheet_t sheet;
    int8_t sheet_session;
    bool sleeping;
    int16_t sleep_dx, sleep_dy;
    int64_t sleep_shift_s;
    uint32_t last_act_ms;
    uint32_t last_touch_ms;
    uint32_t last_remind_ms;
    uint32_t next_attn_ms;
    bool hold_active;
    uint32_t hold_start_ms;
    bool button_down;
    bool button_long_fired;
    bool button_pairing_armed;
    uint32_t button_down_ms;

    bm_acc_t acc;
    uint8_t battery_pct;
    bool charging;
    bool battery_known;
    bool battery_warned;

    bool pairing;
    uint32_t pairing_until_ms;
    uint32_t passkey;
    bool passkey_shown;

    bm_settings_t settings;
    uint32_t settings_rev;
    uint32_t settings_emit_ms;
    bool panel;
    bm_pomo_t pomo;
    uint32_t alarm_until_ms, alarm_next_ms;
    uint8_t alarm_burst;
    uint32_t faces_rev;
    bm_rx_t face_rx;
    uint8_t face_rx_px[BM_FACE_MAX * BM_FACE_MAX * 2];
    bool has_cover;
    bm_cover_t cover;
    uint32_t covers_rev;
    bm_rx_t cover_rx;
    uint8_t cover_rx_px[BM_COVER_MAX * BM_COVER_MAX * 2];
    char cover_wait[17];
    uint32_t cover_wait_ms;
    int8_t sleep_card;
    int64_t sleep_card_s;

    bm_eyes_t eyes;

    bm_session_t scratch;

    bm_out_t outbox[BM_OUTBOX_LEN];
    uint8_t out_head, out_len;
    bm_sound_t sounds[BM_SOUND_QUEUE];
    uint8_t snd_head, snd_len;
} bm_model_t;

typedef enum {
    BM_TAP_NONE,
    BM_TAP_AGENT,
    BM_TAP_OPEN_PERM,
    BM_TAP_DETAILS,
    BM_TAP_USAGE,
    BM_TAP_HILO,
    BM_TAP_BACK,
    BM_TAP_LATER,
    BM_TAP_DENY,
    BM_TAP_ANSWER,
    BM_TAP_SESSION_ACC,
    BM_TAP_MEDIA,
    BM_TAP_POMO_TOGGLE,
    BM_TAP_POMO_RESET,
    BM_TAP_POMO_WORK,
    BM_TAP_POMO_BREAK,
} bm_tap_t;

typedef enum { BM_MEDIA_PLAY_PAUSE, BM_MEDIA_NEXT, BM_MEDIA_PREVIOUS } bm_media_action_t;

void bm_init(bm_model_t *m, const bm_config_t *cfg, uint32_t now_ms);
bm_err_t bm_ingest(bm_model_t *m, const char *json, size_t len, uint32_t now_ms);
bm_err_t bm_ingest_bound(bm_model_t *m, const char *json, size_t len, int8_t *slot, uint32_t now_ms);
void bm_link(bm_model_t *m, const char *host, bool connected, uint32_t now_ms);
void bm_tick(bm_model_t *m, uint32_t now_ms);

void bm_tap(bm_model_t *m, bm_tap_t target, int arg, uint32_t now_ms);
void bm_tap_overlay(bm_model_t *m, uint32_t now_ms);
void bm_swipe(bm_model_t *m, int dir, uint32_t now_ms);
void bm_touch_wake(bm_model_t *m, uint32_t now_ms);
void bm_button(bm_model_t *m, bool pressed, uint32_t now_ms);
bool bm_hold_begin(bm_model_t *m, uint32_t now_ms);
void bm_hold_cancel(bm_model_t *m);
float bm_hold_progress(const bm_model_t *m, uint32_t now_ms);
void bm_set_battery(bm_model_t *m, uint8_t pct, bool charging, uint32_t now_ms);
void bm_set_accessory(bm_model_t *m, bm_acc_t acc);

void bm_settings_load(bm_model_t *m, const bm_settings_t *s);
void bm_settings_change(bm_model_t *m, const bm_settings_t *s, uint32_t now_ms);
void bm_panel(bm_model_t *m, bool open, uint32_t now_ms);

int32_t bm_pomo_left_s(const bm_model_t *m, uint32_t now_ms);
float bm_pomo_progress(const bm_model_t *m, uint32_t now_ms);
bm_pet_state_t bm_pomo_pet(const bm_model_t *m);
bool bm_alarm_ringing(const bm_model_t *m);
void bm_alarm_stop(bm_model_t *m, uint32_t now_ms);

#define BM_CARD_CLOCK (-1)
#define BM_CARD_COMPUTERS (-2)
int bm_faces_count(const bm_model_t *m);
uint64_t bm_fnv1a64(const void *data, size_t len);
size_t bm_base64_decode(const char *in, uint8_t *out, size_t cap);

typedef enum { BM_PAIR_CANCELLED, BM_PAIR_TIMEOUT, BM_PAIR_OK, BM_PAIR_FAILED } bm_pair_result_t;
void bm_pairing_start(bm_model_t *m, uint32_t now_ms);
void bm_pairing_end(bm_model_t *m, bm_pair_result_t result, uint32_t now_ms);
void bm_pairing_passkey(bm_model_t *m, uint32_t passkey, uint32_t now_ms);

bool bm_out_pop(bm_model_t *m, bm_out_t *out);
bool bm_sound_pop(bm_model_t *m, bm_sound_t *out);

int64_t bm_wall_ms(const bm_model_t *m, uint32_t now_ms);
void bm_clock_from_rtc(bm_model_t *m, int64_t unix_s, uint32_t now_ms);

typedef struct {
    int year, month, day, hour, min, sec, wday;
} bm_utc_t;
void bm_utc_from_unix(int64_t unix_s, bm_utc_t *out);
int64_t bm_unix_from_utc(const bm_utc_t *t);
bool bm_live(const bm_model_t *m, const bm_session_t *s);
bool bm_waiting(const bm_model_t *m, const bm_session_t *s);
const bm_session_t *bm_attn_session(const bm_model_t *m);
bool bm_request_approvable(const bm_request_t *r);
int bm_hosts_connected(const bm_model_t *m);
int bm_live_waiting_count(const bm_model_t *m);

int bm_agent_order(const bm_model_t *m, int8_t *out, int max);
int bm_session_count(const bm_model_t *m);
bm_pet_state_t bm_main_pet(const bm_model_t *m);
bm_pet_state_t bm_agent_pet(const bm_model_t *m, const bm_session_t *s);
bm_mood_t bm_face_mood(const bm_model_t *m);
bool bm_on_mac(const bm_model_t *m, const bm_session_t *s);
const char *bm_session_label(const bm_model_t *m, const bm_session_t *s);
void bm_project_look(const char *project, uint16_t *hue, bm_acc_t *acc);
/* The Mac's pick when it sent one, else the project's own look. */
void bm_session_look(const bm_session_t *s, uint16_t *hue, bm_acc_t *acc);
const char *bm_acc_name(bm_acc_t acc);

typedef struct {
    char msg[96];
    char sub[96];
    uint32_t color;
    bool colored;
    int8_t tap_session;
} bm_home_t;
void bm_home(const bm_model_t *m, uint32_t now_ms, bm_home_t *out);

int bm_usage_host(const bm_model_t *m);
int bm_usage_pct(const bm_usage_t *u);
uint32_t bm_usage_color(int pct);
int32_t bm_usage_reset_s(const bm_usage_t *u, uint32_t now_ms);
int bm_hilo_host(const bm_model_t *m);
int bm_media_host(const bm_model_t *m);
bool bm_view_shown(const bm_model_t *m, bm_view_t view);
const bm_cover_t *bm_media_cover(const bm_model_t *m);
bool bm_cover_waiting(const bm_model_t *m, uint32_t now_ms);
int32_t bm_media_position_s(const bm_media_t *media, uint32_t now_ms);

const char *bm_status_label(bm_status_t s);
uint32_t bm_status_color(bm_status_t s);
uint32_t bm_step_color(bm_step_kind_t k);
void bm_host_label(const char *host, char *out, size_t n);

void bm_fmt_dur(int64_t ms, char *out, size_t n);
void bm_fmt_hms(int64_t ms, char *out, size_t n);
void bm_fmt_ago(int64_t ms, char *out, size_t n);
void bm_fmt_clock(int64_t wall_ms, int32_t tz_offset_min, char *out, size_t n);
