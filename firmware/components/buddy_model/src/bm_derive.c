#include <math.h>
#include <stdio.h>
#include <string.h>

#include "bm_internal.h"

bool bm_live(const bm_model_t *m, const bm_session_t *s)
{
    return s->used && m->hosts[s->host].connected;
}

bool bm_waiting(const bm_model_t *m, const bm_session_t *s)
{
    return bm_live(m, s) && s->status == BM_WAITING;
}

const bm_session_t *bm_attn_session(const bm_model_t *m)
{
    if (m->attn < 0) return NULL;
    const bm_session_t *s = &m->sessions[m->attn];
    return s->used && s->has_request ? s : NULL;
}

bool bm_request_approvable(const bm_request_t *r)
{
    return !r->is_question && !r->high_risk && r->remote_allowed;
}

int bm_hosts_connected(const bm_model_t *m)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (m->hosts[i].used && m->hosts[i].connected) n++;
    return n;
}

int bm_live_waiting_count(const bm_model_t *m)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_SESSIONS; i++)
        if (m->sessions[i].has_request && bm_live(m, &m->sessions[i])) n++;
    return n;
}

int bm_session_count(const bm_model_t *m)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_SESSIONS; i++)
        if (m->sessions[i].used) n++;
    return n;
}

int bm_agent_order(const bm_model_t *m, int8_t *out, int max)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &m->sessions[i];
        if (!s->used) continue;
        int j = n++;
        while (j > 0) {
            const bm_session_t *prev = &m->sessions[out[j - 1]];
            if (prev->status < s->status || (prev->status == s->status && prev->order < s->order)) break;
            out[j] = out[j - 1];
            j--;
        }
        out[j] = (int8_t)i;
    }
    return n < max ? n : max;
}

int bm_usage_pct(const bm_usage_t *u)
{
    int pct = (int)lroundf(u->session_pct);
    return pct > 100 ? 100 : pct;
}

uint32_t bm_usage_color(int pct)
{
    return pct >= 100 ? BM_C_ERR : pct >= 80 ? BM_C_WAIT : BM_C_WORK;
}

int32_t bm_usage_reset_s(const bm_usage_t *u, uint32_t now_ms)
{
    int32_t left = u->reset_in_min * 60 - (int32_t)((now_ms - u->received_ms) / 1000);
    return left > 0 ? left : 0;
}

int bm_usage_host(const bm_model_t *m)
{
    int best = -1;
    for (int pass = 0; pass < 2 && best < 0; pass++) {
        for (int i = 0; i < BM_MAX_HOSTS; i++) {
            const bm_host_t *h = &m->hosts[i];
            if (!h->used || !h->usage.known || (pass == 0 && !h->connected)) continue;
            if (best < 0 || h->usage.session_pct > m->hosts[best].usage.session_pct) best = i;
        }
    }
    return best;
}

static int latest_host(const bm_model_t *m, bool (*has)(const bm_host_t *), uint32_t (*stamp)(const bm_host_t *))
{
    int best = -1;
    for (int pass = 0; pass < 2 && best < 0; pass++) {
        for (int i = 0; i < BM_MAX_HOSTS; i++) {
            const bm_host_t *h = &m->hosts[i];
            if (!h->used || !has(h) || (pass == 0 && !h->connected)) continue;
            if (best < 0 || (int32_t)(stamp(h) - stamp(&m->hosts[best])) > 0) best = i;
        }
    }
    return best;
}

static bool has_hilo(const bm_host_t *h) { return h->hilo.has_current || h->hilo.n_next; }
static uint32_t hilo_stamp(const bm_host_t *h) { return h->hilo.updated_ms; }
static bool has_media(const bm_host_t *h) { return h->media.playing; }
static uint32_t media_stamp(const bm_host_t *h) { return h->media.received_ms; }

int bm_hilo_host(const bm_model_t *m)
{
    return latest_host(m, has_hilo, hilo_stamp);
}

int bm_media_host(const bm_model_t *m)
{
    return latest_host(m, has_media, media_stamp);
}

int32_t bm_media_position_s(const bm_media_t *media, uint32_t now_ms)
{
    if (media->paused) return media->position_s;
    int32_t pos = media->position_s + (int32_t)((now_ms - media->received_ms) / 1000);
    return media->length_s && pos > media->length_s ? media->length_s : pos;
}

static int max_usage_pct(const bm_model_t *m)
{
    int h = bm_usage_host(m);
    return h < 0 ? 0 : bm_usage_pct(&m->hosts[h].usage);
}

static bool any_live_status(const bm_model_t *m, bm_status_t st)
{
    for (int i = 0; i < BM_MAX_SESSIONS; i++)
        if (bm_live(m, &m->sessions[i]) && m->sessions[i].status == st) return true;
    return false;
}

bm_pet_state_t bm_main_pet(const bm_model_t *m)
{
    if (m->sleeping) return BM_PET_SLEEP;
    if (bm_attn_session(m)) return BM_PET_ALERT;
    switch (m->ov.type) {
    case BM_OV_DONE:
    case BM_OV_APPROVED: return BM_PET_HAPPY;
    case BM_OV_ERROR: return BM_PET_ERROR;
    case BM_OV_WARN:
    case BM_OV_BATT: return BM_PET_WORRIED;
    case BM_OV_CONN: return m->ov.on ? BM_PET_HAPPY : BM_PET_WORRIED;
    case BM_OV_LIMIT: return BM_PET_SLEEP;
    default: break;
    }
    int pct = max_usage_pct(m);
    if (pct >= 100) return BM_PET_SLEEP;
    if (any_live_status(m, BM_WAITING)) return BM_PET_ALERT;
    if (pct >= 80) return BM_PET_WORRIED;
    if (any_live_status(m, BM_WORKING)) return BM_PET_WORKING;
    return BM_PET_IDLE;
}

bm_pet_state_t bm_agent_pet(const bm_model_t *m, const bm_session_t *s)
{
    if (!bm_live(m, s)) return BM_PET_SLEEP;
    static const bm_pet_state_t map[] = {BM_PET_ALERT, BM_PET_ERROR, BM_PET_WORKING, BM_PET_HAPPY, BM_PET_IDLE};
    return map[s->status];
}

bm_mood_t bm_face_mood(const bm_model_t *m)
{
    switch (bm_main_pet(m)) {
    case BM_PET_SLEEP: return BM_MOOD_SLEEP;
    case BM_PET_WORKING: return BM_MOOD_WORKING;
    case BM_PET_HAPPY: return BM_MOOD_DONE;
    case BM_PET_ALERT:
    case BM_PET_ERROR:
    case BM_PET_WORRIED: return BM_MOOD_WAITING;
    default: return BM_MOOD_IDLE;
    }
}

/* Handed back to the terminal prompt: still waiting, but nothing to answer here. */
bool bm_on_mac(const bm_model_t *m, const bm_session_t *s)
{
    return bm_waiting(m, s) && !s->has_request;
}

const char *bm_session_label(const bm_model_t *m, const bm_session_t *s)
{
    if (!bm_live(m, s)) return "offline";
    return bm_on_mac(m, s) ? "on the Mac" : bm_status_label(s->status);
}

void bm_project_look(const char *project, uint16_t *hue, bm_acc_t *acc)
{
    uint32_t h = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)project; *p; p++) h = (h ^ *p) * 16777619u;
    *hue = (uint16_t)(h % 360);
    *acc = (bm_acc_t)((h / 360) % BM_ACC_COUNT);
}

void bm_session_look(const bm_session_t *s, uint16_t *hue, bm_acc_t *acc)
{
    bm_project_look(s->project, hue, acc);
    if (!s->has_look) return;
    *hue = s->look_hue;
    *acc = s->look_acc;
}

const char *bm_acc_name(bm_acc_t acc)
{
    static const char *const names[] = {"none", "wizard", "shades", "headphones", "crown", "party", "band", "heart"};
    return acc < BM_ACC_COUNT ? names[acc] : "none";
}

static const char *plural(int n, const char *one, const char *many)
{
    return n == 1 ? one : many;
}

static void append(char *buf, size_t n, const char *part)
{
    size_t len = strlen(buf);
    snprintf(buf + len, n - len, "%s%s", len ? " \xC2\xB7 " : "", part);
}

void bm_home(const bm_model_t *m, uint32_t now_ms, bm_home_t *out)
{
    memset(out, 0, sizeof(*out));
    out->tap_session = -1;
    char part[48];

    int uh = bm_usage_host(m);
    if (!bm_hosts_connected(m)) {
        bm__copy(out->msg, sizeof(out->msg), "No Macs connected");
        bm__copy(out->sub, sizeof(out->sub), "waiting for pairing");
        return;
    }
    if (uh >= 0 && bm_usage_pct(&m->hosts[uh].usage) >= 100) {
        char dur[16];
        bm_fmt_dur((int64_t)bm_usage_reset_s(&m->hosts[uh].usage, now_ms) * 1000, dur, sizeof(dur));
        bm__copy(out->msg, sizeof(out->msg), "Limit reached");
        snprintf(out->sub, sizeof(out->sub), "back in %s", dur);
        out->color = BM_C_ERR;
        out->colored = true;
        return;
    }

    int count[5] = {0};
    const bm_session_t *first_waiting = NULL;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &m->sessions[i];
        if (!bm_live(m, s)) continue;
        count[s->status]++;
        if (s->status != BM_WAITING) continue;
        bool better = !first_waiting || (s->has_request && !first_waiting->has_request) ||
                      (s->has_request == first_waiting->has_request && s->order < first_waiting->order);
        if (better) first_waiting = s;
    }
    int w = count[BM_WAITING], er = count[BM_ERROR], wk = count[BM_WORKING], dn = count[BM_DONE],
        idl = count[BM_IDLE];

    if (w && !first_waiting->has_request) {
        bm__copy(out->msg, sizeof(out->msg), "Answer it on the Mac");
        snprintf(out->sub, sizeof(out->sub), "%s \xC2\xB7 handed back", first_waiting->project);
        out->tap_session = (int8_t)(first_waiting - m->sessions);
    } else if (w) {
        snprintf(out->msg, sizeof(out->msg), "%s needs you", first_waiting->project);
        out->tap_session = (int8_t)(first_waiting - m->sessions);
        append(out->sub, sizeof(out->sub), "tap to review");
    } else if (er) {
        snprintf(out->msg, sizeof(out->msg), "%d %s", er, plural(er, "task failed", "tasks failed"));
    } else if (wk) {
        snprintf(out->msg, sizeof(out->msg), "%d %s", wk, plural(wk, "agent working", "agents working"));
    } else if (dn) {
        bm__copy(out->msg, sizeof(out->msg), "All done");
    } else {
        bm__copy(out->msg, sizeof(out->msg), "All quiet");
    }
    if (!w) {
        if (wk && er) {
            snprintf(part, sizeof(part), "%d working", wk);
            append(out->sub, sizeof(out->sub), part);
        }
        if (dn) {
            snprintf(part, sizeof(part), "%d done", dn);
            append(out->sub, sizeof(out->sub), part);
        }
        if (idl) {
            snprintf(part, sizeof(part), "%d idle", idl);
            append(out->sub, sizeof(out->sub), part);
        }
    }
    if (!out->sub[0]) bm__copy(out->sub, sizeof(out->sub), "no active sessions");
    if (w || er) {
        out->color = w ? BM_C_WAIT : BM_C_ERR;
        out->colored = true;
    }
}

const char *bm_status_label(bm_status_t s)
{
    static const char *const labels[] = {"needs you", "failed", "working", "done", "idle"};
    return labels[s];
}

uint32_t bm_status_color(bm_status_t s)
{
    static const uint32_t colors[] = {BM_C_WAIT, BM_C_ERR, BM_C_WORK, BM_C_DONE, BM_C_IDLE};
    return colors[s];
}

uint32_t bm_step_color(bm_step_kind_t k)
{
    static const uint32_t colors[] = {BM_C_INFO, BM_C_IDLE, BM_C_WORK, BM_C_DONE,
                                      BM_C_WAIT, BM_C_DONE, BM_C_IDLE, BM_C_ERR};
    return colors[k];
}

void bm_host_label(const char *host, char *out, size_t n)
{
    bm__copy(out, n, host);
    if (out[0] >= 'a' && out[0] <= 'z') out[0] = (char)(out[0] - 'a' + 'A');
}

void bm_fmt_dur(int64_t ms, char *out, size_t n)
{
    int64_t s = ms > 0 ? ms / 1000 : 0, m = s / 60;
    if (m >= 60) snprintf(out, n, "%lldh%02lld", (long long)(m / 60), (long long)(m % 60));
    else snprintf(out, n, "%lld:%02lld", (long long)m, (long long)(s % 60));
}

void bm_fmt_hms(int64_t ms, char *out, size_t n)
{
    int64_t s = ms > 0 ? ms / 1000 : 0;
    snprintf(out, n, "%lld:%02lld:%02lld", (long long)(s / 3600), (long long)(s / 60 % 60), (long long)(s % 60));
}

void bm_fmt_ago(int64_t ms, char *out, size_t n)
{
    int64_t m = ms > 0 ? ms / 60000 : 0;
    if (m < 1) snprintf(out, n, "now");
    else if (m < 60) snprintf(out, n, "%lld min ago", (long long)m);
    else snprintf(out, n, "%lld h ago", (long long)(m / 60));
}

void bm_fmt_clock(int64_t wall_ms, int32_t tz_offset_min, char *out, size_t n)
{
    int64_t day_s = (wall_ms / 1000 + (int64_t)tz_offset_min * 60) % 86400;
    if (day_s < 0) day_s += 86400;
    snprintf(out, n, "%02lld:%02lld", (long long)(day_s / 3600), (long long)(day_s / 60 % 60));
}

static int64_t floor_div(int64_t a, int64_t b) { return a / b - (a % b < 0); }

/* Howard Hinnant's days_from_civil / civil_from_days. */
void bm_utc_from_unix(int64_t unix_s, bm_utc_t *out)
{
    int64_t days = floor_div(unix_s, 86400), secs = unix_s - days * 86400;
    out->hour = (int)(secs / 3600);
    out->min = (int)(secs / 60 % 60);
    out->sec = (int)(secs % 60);
    out->wday = (int)((days % 7 + 11) % 7);
    int64_t z = days + 719468, era = floor_div(z, 146097), doe = z - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153;
    out->day = (int)(doy - (153 * mp + 2) / 5 + 1);
    out->month = (int)(mp < 10 ? mp + 3 : mp - 9);
    out->year = (int)(yoe + era * 400 + (out->month <= 2));
}

int64_t bm_unix_from_utc(const bm_utc_t *t)
{
    int64_t y = t->year - (t->month <= 2), era = floor_div(y, 400), yoe = y - era * 400;
    int64_t mp = t->month > 2 ? t->month - 3 : t->month + 9;
    int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + (153 * mp + 2) / 5 + t->day - 1;
    int64_t days = era * 146097 + doe - 719468;
    return days * 86400 + t->hour * 3600 + t->min * 60 + t->sec;
}
