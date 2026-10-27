#include <math.h>
#include <string.h>

#include "bm_internal.h"
#include "cJSON.h"

typedef enum { ABSENT = 0, PRESENT = 1, BAD = -1 } field_t;

static bool is_ulid(const char *s)
{
    if (strlen(s) != 26) return false;
    for (; *s; s++)
        if (!strchr("0123456789ABCDEFGHJKMNPQRSTVWXYZ", *s)) return false;
    return true;
}

static bool is_host(const char *s)
{
    size_t n = strlen(s);
    if (n < 1 || n > 16) return false;
    for (; *s; s++)
        if (!((*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') || *s == '-')) return false;
    return true;
}

static bool is_jira(const char *s)
{
    const char *dash = strchr(s, '-');
    if (!dash) return false;
    size_t key = (size_t)(dash - s), num = strlen(dash + 1);
    if (key < 2 || key > 10 || num < 1 || num > 7 || !(s[0] >= 'A' && s[0] <= 'Z')) return false;
    for (const char *p = s + 1; p < dash; p++)
        if (!((*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9'))) return false;
    for (const char *p = dash + 1; *p; p++)
        if (*p < '0' || *p > '9') return false;
    return true;
}

static size_t utf8_len(const char *s)
{
    size_t n = 0;
    for (; *s; s++)
        if (((unsigned char)*s & 0xC0) != 0x80) n++;
    return n;
}

static field_t get_str(const cJSON *obj, const char *key, size_t min, size_t max, char *out, size_t n)
{
    const cJSON *it = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!it) return ABSENT;
    if (!cJSON_IsString(it)) return BAD;
    size_t len = utf8_len(it->valuestring);
    if (len < min || len > max) return BAD;
    if (strlen(it->valuestring) < n) {
        bm__copy(out, n, it->valuestring);
    } else {
        static const char ELLIPSIS[] = "\xE2\x80\xA6";
        bm__copy(out, n - (sizeof(ELLIPSIS) - 1), it->valuestring);
        strcat(out, ELLIPSIS);
    }
    return PRESENT;
}

static bool req_str(const cJSON *obj, const char *key, size_t min, size_t max, char *out, size_t n)
{
    return get_str(obj, key, min, max, out, n) == PRESENT;
}

static bool opt_str(const cJSON *obj, const char *key, size_t min, size_t max, char *out, size_t n)
{
    out[0] = '\0';
    return get_str(obj, key, min, max, out, n) != BAD;
}

static field_t get_int(const cJSON *obj, const char *key, int64_t min, int64_t max, int64_t *out)
{
    const cJSON *it = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!it) return ABSENT;
    if (!cJSON_IsNumber(it)) return BAD;
    double v = it->valuedouble;
    if (v != floor(v) || v < (double)min || v > (double)max) return BAD;
    *out = (int64_t)v;
    return PRESENT;
}

static bool req_int(const cJSON *obj, const char *key, int64_t min, int64_t max, int64_t *out)
{
    return get_int(obj, key, min, max, out) == PRESENT;
}

static bool req_pct(const cJSON *obj, const char *key, float *out)
{
    const cJSON *it = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!cJSON_IsNumber(it) || it->valuedouble < 0 || it->valuedouble > 100) return false;
    *out = (float)it->valuedouble;
    return true;
}

static int enum_index(const cJSON *obj, const char *key, const char *const *names, int count)
{
    const cJSON *it = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!cJSON_IsString(it)) return -1;
    for (int i = 0; i < count; i++)
        if (strcmp(it->valuestring, names[i]) == 0) return i;
    return -1;
}

static const cJSON *opt_array(const cJSON *obj, const char *key, int max, bool *ok)
{
    const cJSON *it = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!it) return NULL;
    if (!cJSON_IsArray(it) || cJSON_GetArraySize(it) > max) *ok = false;
    return *ok ? it : NULL;
}

#define ULID_OK(obj, key, out) (req_str(obj, key, 26, 26, out, 27) && is_ulid(out))

static const char *const STEP_KINDS[] = {"plan", "read", "edit", "run", "ask", "ok", "deny", "err"};
static const char *const STATUSES[] = {"waiting", "error", "working", "done", "idle"};

static bool parse_step(const cJSON *o, bm_step_t *st)
{
    int k = enum_index(o, "kind", STEP_KINDS, 8);
    if (!cJSON_IsObject(o) || k < 0) return false;
    st->kind = (bm_step_kind_t)k;
    return req_int(o, "ts", 0, INT64_MAX, &st->ts) && req_str(o, "text", 1, 120, st->text, sizeof(st->text));
}

static bool parse_permission(const cJSON *o, bm_request_t *r, char *session, char *project)
{
    static const char *const RISKS[] = {"low", "high"};
    memset(r, 0, sizeof(*r));
    if (!cJSON_IsObject(o)) return false;
    int risk = enum_index(o, "risk", RISKS, 2);
    const cJSON *remote = cJSON_GetObjectItemCaseSensitive(o, "remote_allowed");
    if (risk < 0 || !cJSON_IsBool(remote)) return false;
    r->high_risk = risk == 1;
    r->remote_allowed = cJSON_IsTrue(remote);
    if (r->high_risk && r->remote_allowed) return false;

    bool ok = ULID_OK(o, "request_id", r->request_id) && req_str(o, "session", 1, 64, session, 65) &&
              req_str(o, "project", 1, 64, project, 65) && req_str(o, "tool", 1, 32, r->tool, sizeof(r->tool)) &&
              req_str(o, "detail", 1, 300, r->detail, sizeof(r->detail)) &&
              opt_str(o, "why", 1, 300, r->why, sizeof(r->why)) && req_str(o, "cwd", 0, 120, r->cwd, sizeof(r->cwd)) &&
              req_int(o, "expires_at", 0, INT64_MAX, &r->expires_at);
    const cJSON *diff = opt_array(o, "diff", BM_MAX_DIFF, &ok);
    const cJSON *line;
    cJSON_ArrayForEach(line, diff)
    {
        const cJSON *kind = cJSON_GetArrayItem(line, 0), *text = cJSON_GetArrayItem(line, 1);
        if (!cJSON_IsArray(line) || cJSON_GetArraySize(line) != 2 || !cJSON_IsString(kind) || !cJSON_IsString(text) ||
            (strcmp(kind->valuestring, "a") != 0 && strcmp(kind->valuestring, "r") != 0) ||
            utf8_len(text->valuestring) > 120 || strlen(text->valuestring) > 120 * 4)
            return false;
        bm_diff_line_t *d = &r->diff[r->n_diff++];
        d->added = kind->valuestring[0] == 'a';
        bm__copy(d->line, sizeof(d->line), text->valuestring);
    }
    return ok;
}

static bool parse_question(const cJSON *o, bm_request_t *r, char *session, char *project)
{
    memset(r, 0, sizeof(*r));
    if (!cJSON_IsObject(o)) return false;
    r->is_question = true;
    bool ok = ULID_OK(o, "request_id", r->request_id) && req_str(o, "session", 1, 64, session, 65) &&
              req_str(o, "project", 1, 64, project, 65) && req_str(o, "detail", 1, 300, r->detail, sizeof(r->detail)) &&
              req_int(o, "expires_at", 0, INT64_MAX, &r->expires_at);
    const cJSON *opts = cJSON_GetObjectItemCaseSensitive(o, "options");
    int n = cJSON_GetArraySize(opts);
    if (!ok || !cJSON_IsArray(opts) || n < 2 || n > BM_MAX_OPTIONS) return false;
    const cJSON *opt;
    cJSON_ArrayForEach(opt, opts)
    {
        if (!cJSON_IsString(opt)) return false;
        size_t len = utf8_len(opt->valuestring);
        if (len < 1 || len > 40 || strlen(opt->valuestring) >= sizeof(r->options[0])) return false;
        bm__copy(r->options[r->n_options++], sizeof(r->options[0]), opt->valuestring);
    }
    bm__copy(r->tool, sizeof(r->tool), "Question");
    return true;
}

static bool parse_session_state(const cJSON *o, bm_session_t *s)
{
    uint8_t host = s->host;
    uint32_t order = s->order;
    bool used = s->used;
    memset(s, 0, sizeof(*s));
    s->used = used;
    s->host = host;
    s->order = order;
    s->tokens = -1;

    int status = enum_index(o, "status", STATUSES, 5);
    int64_t tokens = 0;
    field_t tok = get_int(o, "tokens", 0, INT32_MAX, &tokens);
    if (!cJSON_IsObject(o) || status < 0 || tok == BAD) return false;
    if (tok == PRESENT) s->tokens = (int32_t)tokens;
    s->status = (bm_status_t)status;

    bool ok = req_str(o, "session", 1, 64, s->id, sizeof(s->id)) &&
              req_str(o, "project", 1, 64, s->project, sizeof(s->project)) &&
              req_str(o, "task", 0, 120, s->task, sizeof(s->task)) && req_int(o, "since", 0, INT64_MAX, &s->since) &&
              opt_str(o, "summary", 1, 300, s->summary, sizeof(s->summary)) &&
              opt_str(o, "error", 1, 300, s->error, sizeof(s->error));
    const cJSON *steps = opt_array(o, "steps", BM_MAX_STEPS, &ok), *st;
    cJSON_ArrayForEach(st, steps)
    {
        if (!parse_step(st, &s->steps[s->n_steps++])) return false;
    }
    if (!ok) return false;

    const cJSON *perm = cJSON_GetObjectItemCaseSensitive(o, "pending_permission");
    const cJSON *question = cJSON_GetObjectItemCaseSensitive(o, "pending_question");
    if (perm && question) return false;
    char session[65], project[65];
    if (perm && !parse_permission(perm, &s->req, session, project)) return false;
    if (question && !parse_question(question, &s->req, session, project)) return false;
    s->has_request = perm || question;
    return true;
}

static bool parse_usage(const cJSON *o, bm_usage_t *u)
{
    memset(u, 0, sizeof(*u));
    int64_t reset = 0, tokens = 0;
    field_t tok = get_int(o, "tokens_today", 0, INT64_MAX, &tokens);
    if (!cJSON_IsObject(o) || !req_pct(o, "session_pct", &u->session_pct) ||
        !req_pct(o, "weekly_pct", &u->weekly_pct) || !req_int(o, "reset_in_min", 0, 300, &reset) || tok == BAD)
        return false;
    u->reset_in_min = (int32_t)reset;
    u->tokens_today = tok == PRESENT ? tokens : -1;
    return true;
}

static bool parse_hilo_item(const cJSON *o, bm_hilo_item_t *it)
{
    memset(it, 0, sizeof(*it));
    if (!cJSON_IsObject(o)) return false;
    field_t jira = get_str(o, "jira", 1, 18, it->jira, sizeof(it->jira));
    if (jira == BAD || (jira == PRESENT && !is_jira(it->jira))) return false;
    return req_str(o, "title", 0, 120, it->title, sizeof(it->title)) &&
           req_str(o, "project", 1, 64, it->project, sizeof(it->project));
}

static field_t get_bool(const cJSON *obj, const char *key, bool *out)
{
    const cJSON *it = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!it) return ABSENT;
    if (!cJSON_IsBool(it)) return BAD;
    *out = cJSON_IsTrue(it);
    return PRESENT;
}

static bool parse_media(const cJSON *o, bm_media_t *media)
{
    memset(media, 0, sizeof(*media));
    int64_t len = 0, pos = 0;
    bool playing = true;
    bool ok = cJSON_IsObject(o) && req_str(o, "title", 1, 80, media->title, sizeof(media->title)) &&
              req_str(o, "artist", 0, 80, media->artist, sizeof(media->artist)) &&
              req_int(o, "length_s", 0, INT32_MAX, &len) && req_int(o, "position_s", 0, INT32_MAX, &pos) &&
              get_bool(o, "playing", &playing) != BAD;
    media->length_s = (int32_t)len;
    media->position_s = (int32_t)pos;
    media->paused = !playing;
    return ok;
}

static bool is_face_hash(const char *s)
{
    if (strlen(s) != 16) return false;
    for (; *s; s++)
        if (!((*s >= '0' && *s <= '9') || (*s >= 'a' && *s <= 'f'))) return false;
    return true;
}

static bool parse_face_ref(const cJSON *o, char hash[17])
{
    return cJSON_IsObject(o) && req_str(o, "hash", 16, 16, hash, 17) && is_face_hash(hash);
}

static bool parse_pomodoro(const cJSON *o, bm_pomo_t *p)
{
    static const char *const STATES[] = {"stopped", "running", "paused"};
    static const char *const PHASES[] = {"work", "break"};
    memset(p, 0, sizeof(*p));
    int state = enum_index(o, "state", STATES, 3), phase = enum_index(o, "phase", PHASES, 2);
    int64_t work = 0, brk = 0, cycle = 0, updated = 0, ends = 0, left = 0;
    if (!cJSON_IsObject(o) || state < 0 || phase < 0 || !req_int(o, "work_min", 1, 90, &work) ||
        !req_int(o, "break_min", 1, 60, &brk) || !req_int(o, "cycle", 0, 999, &cycle) ||
        !req_int(o, "updated_at", 0, INT64_MAX, &updated))
        return false;
    field_t has_ends = get_int(o, "ends_at", 0, INT64_MAX, &ends), has_left = get_int(o, "left_s", 0, 5400, &left);
    if (has_ends == BAD || has_left == BAD) return false;
    if ((has_ends == PRESENT) != (state == BM_POMO_RUNNING) || (has_left == PRESENT) != (state == BM_POMO_PAUSED))
        return false;
    p->state = (bm_pomo_run_t)state;
    p->on_break = phase == 1;
    p->ends_at = ends;
    p->left_s = (int32_t)left;
    p->work_min = (uint8_t)work;
    p->break_min = (uint8_t)brk;
    p->cycle = (uint16_t)cycle;
    p->updated_at = updated;
    return true;
}

static bool parse_settings_set(const cJSON *o, const bm_settings_t *base, bm_settings_t *out)
{
    *out = *base;
    int64_t volume = 0, brightness = 0;
    field_t sound = get_bool(o, "sound", &out->sound), vol = get_int(o, "volume", 0, 100, &volume),
            bri = get_int(o, "brightness", 10, 100, &brightness);
    if (!cJSON_IsObject(o) || sound == BAD || vol == BAD || bri == BAD) return false;
    if (sound == ABSENT && vol == ABSENT && bri == ABSENT) return false;
    if (vol == PRESENT) out->volume = (uint8_t)volume;
    if (bri == PRESENT) out->brightness = (uint8_t)brightness;
    return true;
}

static bool is_base64(const char *s)
{
    for (; *s; s++)
        if (!((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') || *s == '+' ||
              *s == '/' || *s == '='))
            return false;
    return true;
}

static bm_err_t apply_face(bm_model_t *m, int host, const cJSON *d, uint32_t now_ms)
{
    char hash[17], format[8];
    int64_t w = 0, h = 0, index = 0, count = 0;
    const cJSON *data = cJSON_GetObjectItemCaseSensitive(d, "data");
    if (!parse_face_ref(d, hash) || !req_str(d, "format", 1, 6, format, sizeof(format)) ||
        strcmp(format, "rgb565") != 0 || !req_int(d, "w", 16, 160, &w) || !req_int(d, "h", 16, 160, &h) ||
        !req_int(d, "index", 0, 15, &index) || !req_int(d, "count", 1, 16, &count) || !cJSON_IsString(data) ||
        strlen(data->valuestring) < 4 || strlen(data->valuestring) > 6000 || !is_base64(data->valuestring))
        return BM_E_DATA;
    return bm__on_face_chunk(m, host, hash, (int)w, (int)h, (int)index, (int)count, data->valuestring, now_ms);
}

static bool parse_hilo(const cJSON *o, bm_hilo_t *h)
{
    memset(h, 0, sizeof(*h));
    if (!cJSON_IsObject(o)) return false;
    const cJSON *cur = cJSON_GetObjectItemCaseSensitive(o, "current");
    if (!cur) return false;
    if (!cJSON_IsNull(cur)) {
        if (!parse_hilo_item(cur, &h->current) || !req_int(cur, "started_at", 0, INT64_MAX, &h->started_at))
            return false;
        h->has_current = true;
    }
    const cJSON *next = cJSON_GetObjectItemCaseSensitive(o, "next");
    const cJSON *agree = cJSON_GetObjectItemCaseSensitive(o, "agreements_today");
    if (!cJSON_IsArray(next) || cJSON_GetArraySize(next) > BM_MAX_NEXT || !cJSON_IsArray(agree) ||
        cJSON_GetArraySize(agree) > BM_MAX_AGREEMENTS)
        return false;
    const cJSON *it;
    cJSON_ArrayForEach(it, next)
    {
        if (!parse_hilo_item(it, &h->next[h->n_next++])) return false;
    }
    cJSON_ArrayForEach(it, agree)
    {
        if (!cJSON_IsString(it) || utf8_len(it->valuestring) < 1 || utf8_len(it->valuestring) > 120 ||
            strlen(it->valuestring) >= sizeof(h->agreements[0]))
            return false;
        bm__copy(h->agreements[h->n_agreements++], sizeof(h->agreements[0]), it->valuestring);
    }
    return true;
}

static bm_err_t apply_snapshot(bm_model_t *m, int host, const cJSON *d, uint32_t now_ms)
{
    const cJSON *sessions = cJSON_GetObjectItemCaseSensitive(d, "sessions");
    const cJSON *media = cJSON_GetObjectItemCaseSensitive(d, "media");
    const cJSON *face = cJSON_GetObjectItemCaseSensitive(d, "face");
    const cJSON *pomo = cJSON_GetObjectItemCaseSensitive(d, "pomodoro");
    bm_usage_t usage;
    bm_hilo_t hilo;
    bm_media_t med = {0};
    bm_pomo_t pomodoro = {0};
    char face_hash[17];
    if (!cJSON_IsArray(sessions) || cJSON_GetArraySize(sessions) > BM_SESSIONS_PER_HOST ||
        !parse_usage(cJSON_GetObjectItemCaseSensitive(d, "usage"), &usage) ||
        !parse_hilo(cJSON_GetObjectItemCaseSensitive(d, "hilo"), &hilo) || (media && !parse_media(media, &med)) ||
        (face && !parse_face_ref(face, face_hash)) || (pomo && !parse_pomodoro(pomo, &pomodoro)))
        return BM_E_DATA;
    const cJSON *it;
    cJSON_ArrayForEach(it, sessions)
    {
        if (!parse_session_state(it, &m->scratch)) return BM_E_DATA;
    }

    bm__clear_host(m, host);
    cJSON_ArrayForEach(it, sessions)
    {
        bm_session_t *s = bm__new_session(m, host, "");
        parse_session_state(it, s);
    }
    bm_host_t *h = &m->hosts[host];
    bool warned = h->usage.warned;
    h->usage = usage;
    h->usage.known = true;
    h->usage.warned = warned;
    h->usage.received_ms = now_ms;
    h->hilo = hilo;
    h->hilo.updated_ms = now_ms;
    h->media = med;
    h->media.playing = media != NULL;
    h->media.received_ms = now_ms;
    bm__on_face_ref(m, host, face ? face_hash : NULL, now_ms);
    bm__on_pomodoro(m, host, &pomodoro, true, pomo != NULL, now_ms);
    bm__after_snapshot(m, host, now_ms);
    return BM_OK;
}

static bm_err_t apply(bm_model_t *m, int host, const char *type, const cJSON *d, int64_t ts, uint32_t now_ms)
{
    char session[65], project[65], text[301];
    if (strcmp(type, "snapshot") == 0) return apply_snapshot(m, host, d, now_ms);

    if (strcmp(type, "session.start") == 0) {
        char task[121];
        if (!req_str(d, "session", 1, 64, session, 65) || !req_str(d, "project", 1, 64, project, 65) ||
            !req_str(d, "task", 0, 120, task, sizeof(task)))
            return BM_E_DATA;
        bm__on_session_start(m, host, session, project, task, ts, now_ms);
    } else if (strcmp(type, "session.end") == 0) {
        if (!req_str(d, "session", 1, 64, session, 65)) return BM_E_DATA;
        bm__on_session_end(m, host, session, now_ms);
    } else if (strcmp(type, "agent.needs_permission") == 0 || strcmp(type, "agent.question") == 0) {
        bool question = type[6] == 'q';
        bool ok = question ? parse_question(d, &m->scratch.req, session, project)
                           : parse_permission(d, &m->scratch.req, session, project);
        if (!ok) return BM_E_DATA;
        bm__on_request(m, host, session, project, &m->scratch.req, ts, now_ms);
    } else if (strcmp(type, "agent.request_resolved") == 0) {
        static const char *const KINDS[] = {"permission", "question"};
        static const char *const OUTCOMES[] = {"approved", "denied", "answered", "expired"};
        static const char *const VIAS[] = {"mac", "buddy", "timeout"};
        char request_id[27];
        int64_t choice = 0;
        int kind = enum_index(d, "kind", KINDS, 2), outcome = enum_index(d, "outcome", OUTCOMES, 4);
        int via = enum_index(d, "via", VIAS, 3);
        field_t ch = get_int(d, "choice_index", 0, 3, &choice);
        if (!ULID_OK(d, "request_id", request_id) || !req_str(d, "session", 1, 64, session, 65) || kind < 0 ||
            outcome < 0 || via < 0 || ch == BAD)
            return BM_E_DATA;
        bool answered = outcome == 2, expired = outcome == 3, is_question = kind == 1;
        if ((answered && (!is_question || ch != PRESENT)) || (!answered && !expired && is_question) ||
            expired != (via == 2))
            return BM_E_DATA;
        bm__on_resolved(m, host, request_id, OUTCOMES[outcome], VIAS[via], now_ms);
    } else if (strcmp(type, "agent.task_done") == 0 || strcmp(type, "agent.error") == 0) {
        bool done = type[6] == 't';
        if (!req_str(d, "session", 1, 64, session, 65) || !req_str(d, done ? "summary" : "detail", 1, 300, text, 301))
            return BM_E_DATA;
        if (done) bm__on_task_done(m, host, session, text, ts, now_ms);
        else bm__on_error(m, host, session, text, ts, now_ms);
    } else if (strcmp(type, "agent.step") == 0) {
        int kind = enum_index(d, "kind", STEP_KINDS, 8);
        if (kind < 0 || !req_str(d, "session", 1, 64, session, 65) || !req_str(d, "text", 1, 120, text, 121))
            return BM_E_DATA;
        bm__on_step(m, host, session, (bm_step_kind_t)kind, text, ts);
    } else if (strcmp(type, "usage.update") == 0) {
        bm_usage_t u;
        if (!parse_usage(d, &u)) return BM_E_DATA;
        bm__on_usage(m, host, &u, now_ms);
    } else if (strcmp(type, "usage.window_reset") == 0) {
        if (!cJSON_IsObject(d)) return BM_E_DATA;
        bm__on_window_reset(m, host, now_ms);
    } else if (strcmp(type, "hilo.task_changed") == 0) {
        bm_hilo_item_t item;
        int64_t started = 0;
        if (!parse_hilo_item(d, &item) || !req_int(d, "started_at", 0, INT64_MAX, &started)) return BM_E_DATA;
        bm__on_hilo_task(m, host, &item, started, now_ms);
    } else if (strcmp(type, "media.now_playing") == 0) {
        bm_media_t media;
        if (!parse_media(d, &media)) return BM_E_DATA;
        bm__on_media(m, host, &media, now_ms);
    } else if (strcmp(type, "settings.set") == 0) {
        bm_settings_t s;
        if (!parse_settings_set(d, &m->settings, &s)) return BM_E_DATA;
        bm__on_settings(m, &s, now_ms);
    } else if (strcmp(type, "host.face") == 0) {
        return apply_face(m, host, d, now_ms);
    } else if (strcmp(type, "pomodoro.state") == 0) {
        bm_pomo_t p;
        if (!parse_pomodoro(d, &p)) return BM_E_DATA;
        bm__on_pomodoro(m, host, &p, false, true, now_ms);
    } else {
        return BM_E_TYPE;
    }
    return BM_OK;
}

static bool seen(const bm_model_t *m, const char *id)
{
    for (int i = 0; i < BM_SEEN_IDS; i++)
        if (strcmp(m->seen[i], id) == 0) return true;
    return false;
}

static void remember(bm_model_t *m, const char *id)
{
    bm__copy(m->seen[m->seen_next], sizeof(m->seen[0]), id);
    m->seen_next = (m->seen_next + 1) % BM_SEEN_IDS;
}

bm_err_t bm_ingest(bm_model_t *m, const char *json, size_t len, uint32_t now_ms)
{
    return bm_ingest_bound(m, json, len, NULL, now_ms);
}

static bool bound_elsewhere(const bm_model_t *m, const int8_t *slot, const char *host)
{
    if (!slot) return false;
    if (*slot >= 0) return strcmp(m->hosts[*slot].name, host) != 0;
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (m->hosts[i].used && m->hosts[i].connected && strcmp(m->hosts[i].name, host) == 0) return true;
    return false;
}

bm_err_t bm_ingest_bound(bm_model_t *m, const char *json, size_t len, int8_t *slot, uint32_t now_ms)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return BM_E_JSON;

    bm_err_t err = BM_E_ENVELOPE;
    char id[27], host[17], type[32];
    int64_t v = 0, ts = 0;
    const cJSON *data = cJSON_GetObjectItemCaseSensitive(root, "data");
    if (!cJSON_IsObject(root) || !req_int(root, "v", 0, INT32_MAX, &v)) goto done;
    if (v != 1) {
        err = BM_E_VERSION;
        goto done;
    }
    if (!ULID_OK(root, "id", id) || !req_int(root, "ts", 0, INT64_MAX, &ts) ||
        !req_str(root, "host", 1, 16, host, sizeof(host)) || !is_host(host) ||
        !req_str(root, "type", 1, 31, type, sizeof(type)) || !cJSON_IsObject(data))
        goto done;
    if (bound_elsewhere(m, slot, host)) {
        err = BM_E_HOST_BOUND;
        goto done;
    }
    if (seen(m, id)) {
        err = BM_E_DUPLICATE;
        goto done;
    }
    int host_slot = bm__host_slot(m, host, true);
    if (host_slot < 0) {
        err = BM_E_HOSTS_FULL;
        goto done;
    }
    bool snapshot = strcmp(type, "snapshot") == 0;
    err = apply(m, host_slot, type, data, ts, now_ms);
    if (err == BM_OK) {
        remember(m, id);
        bm__observe_ts(m, ts, snapshot, now_ms);
        if (slot && *slot < 0) {
            *slot = (int8_t)host_slot;
            bm_link(m, host, true, now_ms);
        }
    }

done:
    cJSON_Delete(root);
    return err;
}
