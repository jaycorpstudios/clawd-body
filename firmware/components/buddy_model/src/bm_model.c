#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "bm_internal.h"

static bool due(uint32_t now_ms, uint32_t at_ms)
{
    return (int32_t)(now_ms - at_ms) >= 0;
}

static uint32_t deadline(uint32_t now_ms, uint32_t delay_ms)
{
    uint32_t at = now_ms + delay_ms;
    return at ? at : 1;
}

static int index_of(const bm_model_t *m, const bm_session_t *s)
{
    return (int)(s - m->sessions);
}

static int64_t wall_s(const bm_model_t *m, uint32_t now_ms)
{
    return bm_wall_ms(m, now_ms) / 1000;
}

void bm__copy(char *dst, size_t n, const char *src)
{
    if (!n) return;
    size_t len = src ? strlen(src) : 0;
    if (len >= n) {
        len = n - 1;
        while (len && ((unsigned char)src[len] & 0xC0) == 0x80) len--;
    }
    if (len) memcpy(dst, src, len);
    dst[len] = '\0';
}

void bm__touch(bm_model_t *m)
{
    m->rev++;
}

void bm_init(bm_model_t *m, const bm_config_t *cfg, uint32_t now_ms)
{
    memset(m, 0, sizeof(*m));
    if (cfg) m->cfg = *cfg;
    m->attn = -1;
    m->sheet_session = -1;
    m->ov.session = -1;
    m->last_act_ms = now_ms;
    m->last_remind_ms = now_ms;
    m->acc = BM_ACC_WIZARD;
    bm__settings_defaults(&m->settings);
    m->settings.tz_offset_min = (int16_t)m->cfg.tz_offset_min;
    bm__pomo_defaults(&m->pomo);
    m->face_rx.host = -1;
    m->cover_rx.host = -1;
    m->sleep_card = BM_CARD_CLOCK;
}

int64_t bm_wall_ms(const bm_model_t *m, uint32_t now_ms)
{
    return m->clock_known ? (int64_t)now_ms + m->wall_offset_ms : 0;
}

static void stamp_unknown_link_times(bm_model_t *m, uint32_t now_ms)
{
    for (int i = 0; i < BM_MAX_HOSTS; i++) {
        bm_host_t *h = &m->hosts[i];
        if (h->used && h->connected && !h->connected_at) h->connected_at = wall_s(m, now_ms);
    }
}

void bm__observe_ts(bm_model_t *m, int64_t ts, bool exact, uint32_t now_ms)
{
    int64_t wall = ts * 1000;
    if (exact || !m->clock_known || wall - bm_wall_ms(m, now_ms) >= 1000) {
        bool first = !m->clock_known;
        m->wall_offset_ms = wall - (int64_t)now_ms;
        m->clock_known = true;
        m->clock_synced++;
        if (first) stamp_unknown_link_times(m, now_ms);
    }
}

void bm_clock_from_rtc(bm_model_t *m, int64_t unix_s, uint32_t now_ms)
{
    if (m->clock_known) return;
    m->wall_offset_ms = unix_s * 1000 - (int64_t)now_ms;
    m->clock_known = true;
    stamp_unknown_link_times(m, now_ms);
    bm__touch(m);
}

int bm__host_slot(bm_model_t *m, const char *name, bool create)
{
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (m->hosts[i].used && strcmp(m->hosts[i].name, name) == 0) return i;
    if (!create) return -1;
    int slot = -1;
    for (int i = 0; i < BM_MAX_HOSTS && slot < 0; i++)
        if (!m->hosts[i].used) slot = i;
    /* A renamed or replaced Mac would otherwise keep its slot until the buddy reboots. */
    for (int i = 0; i < BM_MAX_HOSTS && slot < 0; i++)
        if (!m->hosts[i].connected) slot = i;
    if (slot < 0) return -1;
    bm__clear_host(m, slot);
    if (m->face_rx.host == slot) m->face_rx.count = 0;
    if (m->cover_rx.host == slot) m->cover_rx.count = 0;
    memset(&m->hosts[slot], 0, sizeof(m->hosts[slot]));
    m->hosts[slot].used = true;
    bm__copy(m->hosts[slot].name, sizeof(m->hosts[slot].name), name);
    return slot;
}

bm_session_t *bm__find_session(bm_model_t *m, int host, const char *id)
{
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        bm_session_t *s = &m->sessions[i];
        if (s->used && s->host == host && strcmp(s->id, id) == 0) return s;
    }
    return NULL;
}

bm_session_t *bm__find_request(bm_model_t *m, int host, const char *request_id)
{
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        bm_session_t *s = &m->sessions[i];
        if (s->used && s->host == host && strcmp(s->req.request_id, request_id) == 0) return s;
    }
    return NULL;
}

void bm__remove_session(bm_model_t *m, bm_session_t *s)
{
    int idx = index_of(m, s);
    if (m->attn == idx) m->attn = -1;
    if (m->sheet_session == idx) {
        m->sheet = BM_SHEET_NONE;
        m->sheet_session = -1;
    }
    if (m->ov.session == idx) m->ov.session = -1;
    memset(s, 0, sizeof(*s));
}

static bm_session_t *eviction_victim(bm_model_t *m, int host)
{
    bm_session_t *victim = NULL;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        bm_session_t *s = &m->sessions[i];
        if (!s->used || s->host != host || (s->status != BM_IDLE && s->status != BM_DONE)) continue;
        if (!victim || s->order < victim->order) victim = s;
    }
    if (victim) return victim;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        bm_session_t *s = &m->sessions[i];
        if (!s->used || s->host != host) continue;
        if (!victim || s->status > victim->status || (s->status == victim->status && s->order < victim->order))
            victim = s;
    }
    return victim;
}

bm_session_t *bm__new_session(bm_model_t *m, int host, const char *id)
{
    int count = 0;
    bm_session_t *free_slot = NULL;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        bm_session_t *s = &m->sessions[i];
        if (s->used && s->host == host) count++;
        else if (!s->used && !free_slot) free_slot = s;
    }
    if (count >= BM_SESSIONS_PER_HOST || !free_slot) {
        free_slot = eviction_victim(m, host);
        if (!free_slot) return NULL;
        bm__remove_session(m, free_slot);
    }
    free_slot->used = true;
    free_slot->host = (uint8_t)host;
    free_slot->order = m->next_order++;
    free_slot->tokens = -1;
    bm__copy(free_slot->id, sizeof(free_slot->id), id);
    return free_slot;
}

void bm__clear_host(bm_model_t *m, int host)
{
    for (int i = 0; i < BM_MAX_SESSIONS; i++)
        if (m->sessions[i].used && m->sessions[i].host == host) bm__remove_session(m, &m->sessions[i]);
}

void bm__push_step(bm_session_t *s, int64_t ts, bm_step_kind_t kind, const char *text)
{
    if (s->n_steps == BM_MAX_STEPS) {
        memmove(&s->steps[0], &s->steps[1], sizeof(s->steps[0]) * (BM_MAX_STEPS - 1));
        s->n_steps--;
    }
    bm_step_t *st = &s->steps[s->n_steps++];
    st->ts = ts;
    st->kind = kind;
    bm__copy(st->text, sizeof(st->text), text);
}

void bm__sound(bm_model_t *m, bm_sound_t snd)
{
    if (m->snd_len == BM_SOUND_QUEUE) {
        m->snd_head = (m->snd_head + 1) % BM_SOUND_QUEUE;
        m->snd_len--;
    }
    m->sounds[(m->snd_head + m->snd_len++) % BM_SOUND_QUEUE] = snd;
}

bool bm_sound_pop(bm_model_t *m, bm_sound_t *out)
{
    if (!m->snd_len) return false;
    *out = m->sounds[m->snd_head];
    m->snd_head = (m->snd_head + 1) % BM_SOUND_QUEUE;
    m->snd_len--;
    return true;
}

void bm__toast(bm_model_t *m, const char *text, uint32_t color, uint32_t now_ms)
{
    bm__copy(m->toast, sizeof(m->toast), text);
    m->toast_color = color;
    m->toast_until_ms = deadline(now_ms, BM_TOAST_MS);
    bm__touch(m);
}

void bm__wake(bm_model_t *m, bool silent, bm_by_t by, uint32_t now_ms)
{
    static const char *const by_names[] = {"touch", "button", "long_press", "idle"};
    if (m->sleeping) {
        m->sleeping = false;
        if (!silent) {
            char data[32];
            snprintf(data, sizeof(data), "{\"by\":\"%s\"}", by_names[by]);
            bm__out(m, BM_ALL_HOSTS, "device.wake", data, now_ms);
        }
        bm__touch(m);
    }
    m->last_act_ms = now_ms;
}

void bm__alarm_start(bm_model_t *m, uint32_t now_ms)
{
    bm__wake(m, true, BM_BY_TOUCH, now_ms);
    m->panel = false;
    m->sheet = BM_SHEET_NONE;
    m->sheet_session = -1;
    m->view = BM_VIEW_POMODORO;
    m->alarm_until_ms = deadline(now_ms, BM_ALARM_MS);
    m->alarm_next_ms = now_ms;
    m->alarm_burst = 0;
    bm__touch(m);
}

bool bm_alarm_ringing(const bm_model_t *m)
{
    return m->alarm_until_ms != 0;
}

/* The touch or press that silences the alarm does nothing else. */
bool bm__alarm_ack(bm_model_t *m, uint32_t now_ms)
{
    if (!m->alarm_until_ms) return false;
    m->alarm_until_ms = 0;
    m->last_act_ms = now_ms;
    bm__touch(m);
    return true;
}

void bm_alarm_stop(bm_model_t *m, uint32_t now_ms)
{
    bm__alarm_ack(m, now_ms);
}

static void alarm_tick(bm_model_t *m, uint32_t now_ms)
{
    if (!m->alarm_until_ms) return;
    if (due(now_ms, m->alarm_until_ms)) {
        m->alarm_until_ms = 0;
        bm__touch(m);
        return;
    }
    if (!due(now_ms, m->alarm_next_ms)) return;
    bm__sound(m, BM_SND_DONE);
    m->alarm_burst++;
    m->alarm_next_ms += m->alarm_burst % BM_ALARM_BURSTS
                            ? BM_ALARM_BURST_GAP_MS
                            : BM_ALARM_REPEAT_MS - (BM_ALARM_BURSTS - 1) * BM_ALARM_BURST_GAP_MS;
}

static void go_sleep(bm_model_t *m, bm_by_t by, uint32_t now_ms)
{
    static const char *const by_names[] = {"touch", "button", "long_press", "idle"};
    if (m->attn >= 0) return;
    m->panel = false;
    m->sheet = BM_SHEET_NONE;
    m->sheet_session = -1;
    m->hold_active = false;
    m->sleeping = true;
    char data[32];
    snprintf(data, sizeof(data), "{\"by\":\"%s\"}", by_names[by]);
    bm__out(m, BM_ALL_HOSTS, "device.sleep", data, now_ms);
    bm__touch(m);
}

static uint32_t toast_color_for(bm_overlay_t type)
{
    switch (type) {
    case BM_OV_DONE: return BM_C_DONE;
    case BM_OV_ERROR: return BM_C_ERR;
    case BM_OV_WARN: return BM_C_WAIT;
    case BM_OV_BATT:
    case BM_OV_LIMIT: return BM_C_ERR;
    default: return BM_C_INFO;
    }
}

void bm__show_overlay(bm_model_t *m, const bm_overlay_state_t *ov, uint32_t duration_ms, uint32_t now_ms)
{
    bm__wake(m, true, BM_BY_TOUCH, now_ms);
    if (m->attn >= 0) {
        char text[96];
        if (ov->type == BM_OV_DONE) snprintf(text, sizeof(text), "\xE2\x9C\x93 %s finished", ov->name);
        else if (ov->type == BM_OV_ERROR) snprintf(text, sizeof(text), "\xE2\x9C\x95 %s failed", ov->name);
        else bm__copy(text, sizeof(text), "New notice");
        bm__toast(m, text, toast_color_for(ov->type), now_ms);
        return;
    }
    m->ov = *ov;
    m->ov.until_ms = duration_ms ? deadline(now_ms, duration_ms) : 0;
    bm__touch(m);
}

void bm__close_overlay(bm_model_t *m)
{
    memset(&m->ov, 0, sizeof(m->ov));
    m->ov.session = -1;
    bm__touch(m);
}

static void overlay_init(bm_overlay_state_t *ov, bm_overlay_t type)
{
    memset(ov, 0, sizeof(*ov));
    ov->type = type;
    ov->session = -1;
}

void bm__open_attn(bm_model_t *m, int idx, uint32_t now_ms)
{
    bm_session_t *s = &m->sessions[idx];
    m->sheet = BM_SHEET_NONE;
    m->sheet_session = -1;
    memset(&m->ov, 0, sizeof(m->ov));
    m->ov.session = -1;
    m->attn = (int8_t)idx;
    m->hold_active = false;
    m->panel = false;
    if (!s->req.acked) {
        s->req.acked = true;
        char data[64];
        snprintf(data, sizeof(data), "{\"request_id\":\"%s\",\"seen\":true}", s->req.request_id);
        bm__out(m, (uint8_t)(1u << s->host), "device.ack", data, now_ms);
    }
    bm__touch(m);
}

static int first_open_request(const bm_model_t *m)
{
    int best = -1;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &m->sessions[i];
        if (!s->used || !s->has_request || s->req.snoozed || !bm_live(m, s)) continue;
        if (best < 0 || s->order < m->sessions[best].order) best = i;
    }
    return best;
}

static void schedule_next_attn(bm_model_t *m, uint32_t now_ms)
{
    if (first_open_request(m) >= 0) m->next_attn_ms = deadline(now_ms, BM_NEXT_ATTN_MS);
}

static void open_sheet(bm_model_t *m, bm_sheet_t kind, int session)
{
    m->sheet = kind;
    m->sheet_session = (int8_t)session;
    bm__touch(m);
}

static void close_sheet(bm_model_t *m)
{
    m->sheet = BM_SHEET_NONE;
    m->sheet_session = -1;
    bm__touch(m);
}

static void decide(bm_model_t *m, bool approve, int choice, uint32_t now_ms)
{
    if (m->attn < 0) return;
    bm_session_t *s = &m->sessions[m->attn];
    bm_request_t *r = &s->req;
    if (!s->has_request) return;
    if (r->is_question && (choice < 0 || choice >= r->n_options)) return;
    if (!r->is_question && approve && !bm_request_approvable(r)) return;

    char data[160];
    uint8_t target = (uint8_t)(1u << s->host);
    if (r->is_question) {
        char choice_esc[96];
        bm__json_escape(r->options[choice], choice_esc, sizeof(choice_esc));
        snprintf(data, sizeof(data), "{\"request_id\":\"%s\",\"choice_index\":%d,\"choice\":\"%s\"}", r->request_id,
                 choice, choice_esc);
        bm__out(m, target, "question.answer", data, now_ms);
    } else {
        snprintf(data, sizeof(data), "{\"request_id\":\"%s\",\"decision\":\"%s\"}", r->request_id,
                 approve ? "approve" : "deny");
        bm__out(m, target, "permission.decision", data, now_ms);
    }

    m->attn = -1;
    m->hold_active = false;
    s->has_request = false;
    s->status = BM_WORKING;
    s->since = wall_s(m, now_ms);

    char text[160];
    bm_overlay_state_t ov;
    if (r->is_question) {
        snprintf(text, sizeof(text), "You answered: %s", r->options[choice]);
        bm__push_step(s, s->since, BM_STEP_OK, text);
        overlay_init(&ov, BM_OV_APPROVED);
        ov.question = true;
        bm__copy(ov.text, sizeof(ov.text), r->options[choice]);
        bm__sound(m, BM_SND_APPROVED);
    } else if (approve) {
        snprintf(text, sizeof(text), "You approved from the buddy: %s", r->tool);
        bm__push_step(s, s->since, BM_STEP_OK, text);
        overlay_init(&ov, BM_OV_APPROVED);
        bm__sound(m, BM_SND_APPROVED);
    } else {
        snprintf(text, sizeof(text), "You denied: %s %s", r->tool, r->detail);
        bm__push_step(s, s->since, BM_STEP_DENY, text);
        overlay_init(&ov, BM_OV_DENIED);
        bm__sound(m, BM_SND_DENIED);
    }
    bm__copy(ov.name, sizeof(ov.name), s->project);
    bm__show_overlay(m, &ov, 1600, now_ms);
    schedule_next_attn(m, now_ms);
    bm__touch(m);
}

/* The buddy shows its pick at once; the Mac stores it and echoes it in the next snapshot. */
static void session_acc(bm_model_t *m, int dir, uint32_t now_ms)
{
    if (m->sheet != BM_SHEET_AGENT || m->sheet_session < 0) return;
    bm_session_t *s = &m->sessions[m->sheet_session];
    if (!s->used) return;
    uint16_t hue;
    bm_acc_t acc;
    bm_session_look(s, &hue, &acc);
    s->has_look = true;
    s->look_hue = hue;
    s->look_acc = (bm_acc_t)(((int)acc + (dir < 0 ? -1 : 1) + BM_ACC_COUNT) % BM_ACC_COUNT);
    char id[400], data[460];
    bm__json_escape(s->id, id, sizeof(id));
    snprintf(data, sizeof(data), "{\"session\":\"%s\",\"acc\":\"%s\"}", id, bm_acc_name(s->look_acc));
    bm__out(m, (uint8_t)(1u << s->host), "device.session_look", data, now_ms);
    bm__touch(m);
}

static void later(bm_model_t *m, uint32_t now_ms)
{
    if (m->attn < 0) return;
    bm_session_t *s = &m->sessions[m->attn];
    s->req.snoozed = true;
    char data[64];
    snprintf(data, sizeof(data), "{\"request_id\":\"%s\"}", s->req.request_id);
    bm__out(m, (uint8_t)(1u << s->host), "device.snooze", data, now_ms);
    m->attn = -1;
    m->hold_active = false;
    bm__touch(m);
}

void bm_tap(bm_model_t *m, bm_tap_t target, int arg, uint32_t now_ms)
{
    if (bm__alarm_ack(m, now_ms)) return;
    if (m->sleeping) {
        bm__wake(m, false, BM_BY_TOUCH, now_ms);
        return;
    }
    m->last_act_ms = now_ms;
    bool valid_session = arg >= 0 && arg < BM_MAX_SESSIONS && m->sessions[arg].used;
    switch (target) {
    case BM_TAP_AGENT:
        if (valid_session) open_sheet(m, BM_SHEET_AGENT, arg);
        break;
    case BM_TAP_DETAILS:
        if (m->attn >= 0) open_sheet(m, BM_SHEET_PERM, m->attn);
        break;
    case BM_TAP_USAGE: open_sheet(m, BM_SHEET_USAGE, -1); break;
    case BM_TAP_HILO: open_sheet(m, BM_SHEET_HILO, -1); break;
    case BM_TAP_BACK: close_sheet(m); break;
    case BM_TAP_OPEN_PERM:
        if (!valid_session) break;
        if (m->sessions[arg].has_request && bm_live(m, &m->sessions[arg])) {
            m->sessions[arg].req.snoozed = false;
            bm__open_attn(m, arg, now_ms);
        } else {
            open_sheet(m, BM_SHEET_AGENT, arg);
        }
        break;
    case BM_TAP_LATER: later(m, now_ms); break;
    case BM_TAP_DENY: decide(m, false, -1, now_ms); break;
    case BM_TAP_ANSWER: decide(m, true, arg, now_ms); break;
    case BM_TAP_SESSION_ACC: session_acc(m, arg, now_ms); break;
    case BM_TAP_MEDIA: bm__media_tap(m, arg, now_ms); break;
    case BM_TAP_POMO_TOGGLE:
    case BM_TAP_POMO_RESET:
    case BM_TAP_POMO_WORK:
    case BM_TAP_POMO_BREAK: bm__pomo_tap(m, target, arg, now_ms); break;
    case BM_TAP_NONE: break;
    }
}

void bm_tap_overlay(bm_model_t *m, uint32_t now_ms)
{
    if (bm__alarm_ack(m, now_ms)) return;
    if (m->sleeping) {
        bm__wake(m, false, BM_BY_TOUCH, now_ms);
        return;
    }
    m->last_act_ms = now_ms;
    if (!m->ov.type || m->attn >= 0) return;
    if ((m->ov.type == BM_OV_DONE || m->ov.type == BM_OV_ERROR) && m->ov.session >= 0) {
        int idx = m->ov.session;
        bm__close_overlay(m);
        open_sheet(m, BM_SHEET_AGENT, idx);
    } else if (m->ov.type != BM_OV_LIMIT) {
        bm__close_overlay(m);
    }
}

void bm_touch_wake(bm_model_t *m, uint32_t now_ms)
{
    if (bm__alarm_ack(m, now_ms)) return;
    if (m->sleeping) bm__wake(m, false, BM_BY_TOUCH, now_ms);
    else m->last_act_ms = now_ms;
}

static void next_view(bm_model_t *m, int dir)
{
    do m->view = (bm_view_t)(((int)m->view + dir + BM_VIEWS) % BM_VIEWS);
    while (!bm_view_shown(m, m->view));
    bm__touch(m);
}

void bm_swipe(bm_model_t *m, int dir, uint32_t now_ms)
{
    if (bm__alarm_ack(m, now_ms)) return;
    if (m->sleeping) {
        bm__wake(m, false, BM_BY_TOUCH, now_ms);
        return;
    }
    m->last_act_ms = now_ms;
    if (m->attn >= 0 || m->sheet != BM_SHEET_NONE || m->panel) return;
    if (m->ov.type && m->ov.type != BM_OV_LIMIT) bm__close_overlay(m);
    next_view(m, dir < 0 ? -1 : 1);
}

static void side_press(bm_model_t *m, uint32_t now_ms)
{
    if (m->sleeping) {
        bm__wake(m, false, BM_BY_BUTTON, now_ms);
        return;
    }
    m->last_act_ms = now_ms;
    bm__sound(m, BM_SND_CLICK);
    if (m->pairing) {
        bm_pairing_end(m, BM_PAIR_CANCELLED, now_ms);
        return;
    }
    if (m->panel) bm_panel(m, false, now_ms);
    else if (m->sheet != BM_SHEET_NONE) close_sheet(m);
    else if (m->attn >= 0) later(m, now_ms);
    else if (m->ov.type && m->ov.type != BM_OV_LIMIT) bm__close_overlay(m);
    else next_view(m, 1);
}

void bm_button(bm_model_t *m, bool pressed, uint32_t now_ms)
{
    if (pressed) {
        if (bm__alarm_ack(m, now_ms)) {
            m->button_down = false;
            return;
        }
        m->button_down = true;
        m->button_long_fired = false;
        m->button_pairing_armed =
            !m->sleeping && !m->pairing && m->view == BM_VIEW_HOME && m->attn < 0 && m->sheet == BM_SHEET_NONE;
        m->button_down_ms = now_ms;
        return;
    }
    if (m->button_down && !m->button_long_fired) side_press(m, now_ms);
    m->button_down = false;
}

bool bm_hold_begin(bm_model_t *m, uint32_t now_ms)
{
    const bm_session_t *s = bm_attn_session(m);
    if (m->sleeping || !s || !s->has_request || s->req.is_question || !bm_request_approvable(&s->req)) return false;
    m->hold_active = true;
    m->hold_start_ms = now_ms;
    m->last_act_ms = now_ms;
    bm__touch(m);
    return true;
}

void bm_hold_cancel(bm_model_t *m)
{
    if (!m->hold_active) return;
    m->hold_active = false;
    bm__touch(m);
}

float bm_hold_progress(const bm_model_t *m, uint32_t now_ms)
{
    if (!m->hold_active) return 0.0f;
    float p = (float)(now_ms - m->hold_start_ms) / BM_HOLD_MS;
    return p > 1.0f ? 1.0f : p;
}

void bm_set_battery(bm_model_t *m, uint8_t pct, bool charging, uint32_t now_ms)
{
    if (pct > 100) pct = 100;
    bool changed = !m->battery_known || pct != m->battery_pct || charging != m->charging;
    bool started_charging = m->battery_known && charging && !m->charging;
    m->battery_known = true;
    m->battery_pct = pct;
    m->charging = charging;
    if (!changed) return;

    char data[48];
    snprintf(data, sizeof(data), "{\"pct\":%u,\"charging\":%s}", pct, charging ? "true" : "false");
    bm__out(m, BM_ALL_HOSTS, "device.battery", data, now_ms);

    if (started_charging) {
        bm__toast(m, "\xE2\x9A\xA1 Charging", BM_C_DONE, now_ms);
        bm__sound(m, BM_SND_CHARGE);
    }
    if (charging || pct > BM_LOW_BATTERY_PCT) {
        m->battery_warned = false;
    } else if (!m->battery_warned) {
        m->battery_warned = true;
        bm_overlay_state_t ov;
        overlay_init(&ov, BM_OV_BATT);
        bm__show_overlay(m, &ov, 2800, now_ms);
        bm__sound(m, BM_SND_BATTERY);
    }
    bm__touch(m);
}

void bm_set_accessory(bm_model_t *m, bm_acc_t acc)
{
    if (acc >= BM_ACC_COUNT || acc == m->acc) return;
    m->acc = acc;
    char data[32];
    snprintf(data, sizeof(data), "{\"acc\":\"%s\"}", bm_acc_name(acc));
    bm__out(m, BM_ALL_HOSTS, "device.pet_accessory", data, m->last_act_ms);
    bm__touch(m);
}

void bm_link(bm_model_t *m, const char *host, bool connected, uint32_t now_ms)
{
    int slot = bm__host_slot(m, host, true);
    if (slot < 0 || m->hosts[slot].connected == connected) return;
    m->hosts[slot].connected = connected;
    *(connected ? &m->hosts[slot].connected_at : &m->hosts[slot].disconnected_at) = wall_s(m, now_ms);
    if (connected) bm__send_settings(m, (uint8_t)(1u << slot), now_ms);
    const bm_session_t *a = bm_attn_session(m);
    if (!connected && a && a->host == slot) {
        m->attn = -1;
        m->hold_active = false;
    }
    bm_overlay_state_t ov;
    overlay_init(&ov, BM_OV_CONN);
    ov.host = (uint8_t)slot;
    ov.on = connected;
    bm__show_overlay(m, &ov, 2200, now_ms);
    bm__sound(m, connected ? BM_SND_CONNECTED : BM_SND_DISCONNECTED);
    bm__touch(m);
}

static void lowercase_into(char *dst, size_t n, const char *src)
{
    bm__copy(dst, n, src);
    for (char *p = dst; *p; p++) *p = (char)tolower((unsigned char)*p);
}

void bm__on_session_start(bm_model_t *m, int host, const char *id, const char *project, const char *task, int64_t ts,
                          uint32_t now_ms)
{
    bm_session_t *s = bm__find_session(m, host, id);
    if (s) bm__remove_session(m, s);
    s = bm__new_session(m, host, id);
    if (!s) return;
    bm__copy(s->project, sizeof(s->project), project);
    bm__copy(s->task, sizeof(s->task), task);
    s->status = BM_WORKING;
    s->since = ts;

    char lower[121], text[160];
    lowercase_into(lower, sizeof(lower), task);
    snprintf(text, sizeof(text), "Session started: %s", lower);
    bm__push_step(s, ts, BM_STEP_PLAN, text);

    bm__wake(m, true, BM_BY_TOUCH, now_ms);
    snprintf(text, sizeof(text), "\xE2\x96\xB6 %s started", project);
    bm__toast(m, text, BM_C_WORK, now_ms);
    bm__sound(m, BM_SND_START);
}

void bm__on_session_end(bm_model_t *m, int host, const char *id, uint32_t now_ms)
{
    bm_session_t *s = bm__find_session(m, host, id);
    if (!s) return;
    char text[96];
    snprintf(text, sizeof(text), "\xE2\x96\xA0 %s ended", s->project);
    bm__remove_session(m, s);
    bm__toast(m, text, BM_C_IDLE, now_ms);
}

void bm__on_request(bm_model_t *m, int host, const char *session, const char *project, const bm_request_t *req,
                    int64_t ts, uint32_t now_ms)
{
    bm_session_t *s = bm__find_session(m, host, session);
    if (!s) {
        s = bm__new_session(m, host, session);
        if (!s) return;
        bm__copy(s->project, sizeof(s->project), project);
    }
    s->status = BM_WAITING;
    s->since = ts;
    s->req = *req;
    s->req.snoozed = false;
    s->req.acked = false;
    s->has_request = true;

    char text[400];
    if (req->is_question) snprintf(text, sizeof(text), "Asked: %s", req->detail);
    else snprintf(text, sizeof(text), "Asked permission: %s %s", req->tool, req->detail);
    bm__push_step(s, ts, BM_STEP_ASK, text);

    bm__wake(m, true, BM_BY_TOUCH, now_ms);
    if (bm_live(m, s)) bm__open_attn(m, index_of(m, s), now_ms);
    bm__sound(m, req->is_question ? BM_SND_QUESTION : req->high_risk ? BM_SND_RISK : BM_SND_PERM);
    m->last_remind_ms = now_ms;
    bm__touch(m);
}

void bm__on_resolved(bm_model_t *m, int host, const char *request_id, const char *outcome, const char *via,
                     uint32_t now_ms)
{
    bm_session_t *s = bm__find_request(m, host, request_id);
    if (!s) return;
    bool was_open = s->has_request;
    int idx = index_of(m, s);
    bool was_attn = m->attn == idx;
    s->has_request = false;
    if (was_attn) {
        m->attn = -1;
        m->hold_active = false;
    }
    if (m->sheet == BM_SHEET_PERM && m->sheet_session == idx) close_sheet(m);

    if (strcmp(outcome, "expired") == 0) {
        bm__push_step(s, wall_s(m, now_ms), BM_STEP_ASK, "Handed back to the Mac prompt");
        if (was_open || was_attn) bm__toast(m, "Answer it on the Mac", BM_C_IDLE, now_ms);
    } else if (was_open) {
        s->status = BM_WORKING;
        s->since = wall_s(m, now_ms);
        bm__push_step(s, s->since, BM_STEP_OK, strcmp(via, "mac") == 0 ? "Resolved on the Mac" : "Resolved");
        char text[64], label[17];
        bm_host_label(m->hosts[host].name, label, sizeof(label));
        snprintf(text, sizeof(text), "\xE2\x9C\x93 Resolved on the %s Mac", label);
        bm__toast(m, text, BM_C_INFO, now_ms);
        bm__sound(m, BM_SND_APPROVED);
    }
    schedule_next_attn(m, now_ms);
    bm__touch(m);
}

static void finish(bm_model_t *m, bm_session_t *s)
{
    int idx = index_of(m, s);
    s->has_request = false;
    if (m->attn == idx) {
        m->attn = -1;
        m->hold_active = false;
    }
}

void bm__on_task_done(bm_model_t *m, int host, const char *session, const char *summary, int64_t ts, uint32_t now_ms)
{
    bm_session_t *s = bm__find_session(m, host, session);
    if (!s) return;
    finish(m, s);
    s->status = BM_DONE;
    s->since = ts;
    bm__copy(s->summary, sizeof(s->summary), summary);
    bm__push_step(s, ts, BM_STEP_OK, "Finished the task");

    bm_overlay_state_t ov;
    overlay_init(&ov, BM_OV_DONE);
    ov.session = (int8_t)index_of(m, s);
    bm__copy(ov.name, sizeof(ov.name), s->project);
    bm__copy(ov.text, sizeof(ov.text), s->task);
    bm__show_overlay(m, &ov, 3000, now_ms);
    bm__sound(m, BM_SND_DONE);
    bm__touch(m);
}

void bm__on_error(bm_model_t *m, int host, const char *session, const char *detail, int64_t ts, uint32_t now_ms)
{
    bm_session_t *s = bm__find_session(m, host, session);
    if (!s) return;
    finish(m, s);
    s->status = BM_ERROR;
    s->since = ts;
    bm__copy(s->error, sizeof(s->error), detail);
    bm__push_step(s, ts, BM_STEP_ERR, detail);

    bm_overlay_state_t ov;
    overlay_init(&ov, BM_OV_ERROR);
    ov.session = (int8_t)index_of(m, s);
    bm__copy(ov.name, sizeof(ov.name), s->project);
    bm__copy(ov.text, sizeof(ov.text), detail);
    bm__show_overlay(m, &ov, 3200, now_ms);
    bm__sound(m, BM_SND_ERROR);
    bm__touch(m);
}

void bm__on_step(bm_model_t *m, int host, const char *session, bm_step_kind_t kind, const char *text, int64_t ts)
{
    bm_session_t *s = bm__find_session(m, host, session);
    if (!s) return;
    bm__push_step(s, ts, kind, text);
    bm__touch(m);
}

static bool any_host_at_limit(const bm_model_t *m)
{
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (m->hosts[i].used && m->hosts[i].usage.known && bm_usage_pct(&m->hosts[i].usage) >= 100) return true;
    return false;
}

void bm__check_usage(bm_model_t *m, int host, uint32_t now_ms)
{
    bm_usage_t *u = &m->hosts[host].usage;
    int pct = bm_usage_pct(u);
    if (pct >= 100) {
        if (m->ov.type != BM_OV_LIMIT) {
            bm_overlay_state_t ov;
            overlay_init(&ov, BM_OV_LIMIT);
            ov.host = (uint8_t)host;
            bm__show_overlay(m, &ov, 0, now_ms);
            bm__sound(m, BM_SND_LIMIT);
        }
        return;
    }
    if (m->ov.type == BM_OV_LIMIT && !any_host_at_limit(m)) bm__close_overlay(m);
    if (pct >= 80 && !u->warned) {
        u->warned = true;
        bm_overlay_state_t ov;
        overlay_init(&ov, BM_OV_WARN);
        ov.host = (uint8_t)host;
        bm__show_overlay(m, &ov, 2800, now_ms);
        bm__sound(m, BM_SND_WARN);
    }
    if (pct < 80) u->warned = false;
}

void bm__on_usage(bm_model_t *m, int host, const bm_usage_t *in, uint32_t now_ms)
{
    bm_usage_t *u = &m->hosts[host].usage;
    bool warned = u->warned;
    *u = *in;
    u->warned = warned;
    u->known = true;
    u->received_ms = now_ms;
    bm__check_usage(m, host, now_ms);
    bm__touch(m);
}

void bm__on_window_reset(bm_model_t *m, int host, uint32_t now_ms)
{
    bm_usage_t *u = &m->hosts[host].usage;
    u->known = true;
    u->session_pct = 0;
    u->reset_in_min = 300;
    u->received_ms = now_ms;
    u->warned = false;
    if (m->ov.type == BM_OV_LIMIT && !any_host_at_limit(m)) bm__close_overlay(m);
    bm__toast(m, "5 h window reset", BM_C_INFO, now_ms);
    bm__sound(m, BM_SND_CHARGE);
}

void bm__on_hilo_task(bm_model_t *m, int host, const bm_hilo_item_t *item, int64_t started_at, uint32_t now_ms)
{
    bm_hilo_t *h = &m->hosts[host].hilo;
    h->has_current = true;
    h->current = *item;
    h->started_at = started_at;
    h->updated_ms = now_ms;
    bm__wake(m, true, BM_BY_TOUCH, now_ms);
    char text[140];
    snprintf(text, sizeof(text), "Hilo \xC2\xB7 %s", item->title);
    bm__toast(m, text, BM_C_WORK, now_ms);
    bm__sound(m, BM_SND_START);
}

void bm__on_media(bm_model_t *m, int host, const bm_media_t *media, uint32_t now_ms)
{
    bm_media_t *dst = &m->hosts[host].media;
    bool news = !media->paused && (!dst->playing || dst->paused || strcmp(dst->title, media->title) != 0 ||
                                   strcmp(dst->artist, media->artist) != 0);
    *dst = *media;
    dst->playing = true;
    dst->received_ms = now_ms;
    bm__touch(m);
    bm__want_cover(m, host, now_ms);
    if (!news) return;
    bm__wake(m, true, BM_BY_TOUCH, now_ms);
    char text[180];
    snprintf(text, sizeof(text), "\xE2\x99\xAA %s \xC2\xB7 %s", media->title, media->artist);
    bm__toast(m, text, BM_C_DONE, now_ms);
    bm__sound(m, BM_SND_MEDIA);
}

void bm__after_snapshot(bm_model_t *m, int host, uint32_t now_ms)
{
    if (m->hosts[host].usage.known) bm__check_usage(m, host, now_ms);
    if (m->attn < 0) schedule_next_attn(m, now_ms);
    bm__touch(m);
}

static void expire_requests(bm_model_t *m, uint32_t now_ms)
{
    if (!m->clock_known) return;
    int64_t now_s = wall_s(m, now_ms);
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        bm_session_t *s = &m->sessions[i];
        if (s->used && s->has_request && s->req.expires_at <= now_s)
            bm__on_resolved(m, s->host, s->req.request_id, "expired", "timeout", now_ms);
    }
}

static bool any_live_request(const bm_model_t *m)
{
    for (int i = 0; i < BM_MAX_SESSIONS; i++)
        if (m->sessions[i].used && m->sessions[i].has_request && bm_live(m, &m->sessions[i])) return true;
    return false;
}

static uint32_t next_random(bm_model_t *m)
{
    return m->cfg.random32 ? m->cfg.random32(m->cfg.random_ctx) : 0;
}

void bm_tick(bm_model_t *m, uint32_t now_ms)
{
    expire_requests(m, now_ms);
    bm__settings_tick(m, now_ms);
    bm__pomo_tick(m, now_ms);
    alarm_tick(m, now_ms);

    if (m->hold_active && now_ms - m->hold_start_ms >= BM_HOLD_MS) decide(m, true, -1, now_ms);

    if (m->button_down && !m->button_long_fired && now_ms - m->button_down_ms >= BM_LONG_PRESS_MS) {
        m->button_long_fired = true;
        if (m->sleeping) bm__wake(m, false, BM_BY_LONG_PRESS, now_ms);
        else if (!m->pairing) go_sleep(m, BM_BY_LONG_PRESS, now_ms);
    }

    if (m->button_down && m->button_pairing_armed && now_ms - m->button_down_ms >= BM_PAIRING_HOLD_MS) {
        m->button_pairing_armed = false;
        bm__wake(m, false, BM_BY_LONG_PRESS, now_ms);
        bm_pairing_start(m, now_ms);
    }
    if (m->pairing && due(now_ms, m->pairing_until_ms)) bm_pairing_end(m, BM_PAIR_TIMEOUT, now_ms);

    if (m->ov.type && m->ov.until_ms && due(now_ms, m->ov.until_ms)) bm__close_overlay(m);

    if (m->toast_until_ms && due(now_ms, m->toast_until_ms)) {
        m->toast[0] = '\0';
        m->toast_until_ms = 0;
        bm__touch(m);
    }

    if (m->next_attn_ms && due(now_ms, m->next_attn_ms)) {
        m->next_attn_ms = 0;
        int idx = first_open_request(m);
        if (m->attn < 0 && idx >= 0 && !m->sleeping) bm__open_attn(m, idx, now_ms);
    }

    if (any_live_request(m) && now_ms - m->last_remind_ms > BM_REMIND_MS) {
        m->last_remind_ms = now_ms;
        bm__sound(m, BM_SND_REMINDER);
        bm__wake(m, true, BM_BY_TOUCH, now_ms);
    }

    if (m->sleeping) {
        int64_t secs = m->clock_known ? wall_s(m, now_ms) : now_ms / 1000;
        if (secs % BM_SLEEP_SHIFT_S == 0 && secs != m->sleep_shift_s) {
            m->sleep_shift_s = secs;
            m->sleep_dx = (int16_t)((int)(next_random(m) % 41) - 20);
            m->sleep_dy = (int16_t)((int)(next_random(m) % 41) - 20);
            bm__touch(m);
        }
    } else if (now_ms - m->last_act_ms > BM_IDLE_SLEEP_MS && m->attn < 0 && !m->pairing && !any_live_request(m)) {
        go_sleep(m, BM_BY_IDLE, now_ms);
    }
    bm__sleep_card_tick(m, now_ms);
}

void bm_pairing_start(bm_model_t *m, uint32_t now_ms)
{
    m->pairing = true;
    m->pairing_until_ms = now_ms + BM_PAIRING_MS;
    m->passkey = 0;
    m->passkey_shown = false;
    m->sheet = BM_SHEET_NONE;
    m->sheet_session = -1;
    m->last_act_ms = now_ms;
    bm__sound(m, BM_SND_CLICK);
    bm__touch(m);
}

void bm_pairing_passkey(bm_model_t *m, uint32_t passkey, uint32_t now_ms)
{
    if (!m->pairing) return;
    m->passkey = passkey % 1000000;
    m->passkey_shown = true;
    if ((int32_t)(m->pairing_until_ms - (now_ms + BM_PASSKEY_MS)) < 0) m->pairing_until_ms = now_ms + BM_PASSKEY_MS;
    m->last_act_ms = now_ms;
    bm__sound(m, BM_SND_PERM);
    bm__touch(m);
}

void bm_pairing_end(bm_model_t *m, bm_pair_result_t result, uint32_t now_ms)
{
    if (!m->pairing) return;
    m->pairing = false;
    m->passkey = 0;
    m->passkey_shown = false;
    m->last_act_ms = now_ms;
    switch (result) {
    case BM_PAIR_OK: bm__toast(m, "Paired with a new Mac", BM_C_DONE, now_ms); break;
    case BM_PAIR_FAILED: bm__toast(m, "Pairing failed", BM_C_ERR, now_ms); break;
    case BM_PAIR_TIMEOUT: bm__toast(m, "Pairing timed out", BM_C_IDLE, now_ms); break;
    case BM_PAIR_CANCELLED: break;
    }
    bm__touch(m);
}
