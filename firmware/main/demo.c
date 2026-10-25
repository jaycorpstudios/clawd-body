#include "demo.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static const char *const HOSTS[] = {"work", "home"};

static const struct {
    const char *project, *task, *host;
} POOL[] = {
    {"payments-api", "Payments webhook refactor", "work"},
    {"acme-dashboard", "PR #482 review", "work"},
    {"buddy-firmware", "Agents screen in LVGL", "home"},
    {"hilo-app", "SQLite v3 migration", "home"},
    {"ledger-svc", "Reconciliation flow tests", "work"},
    {"infra-terraform", "ECS rollout plan", "work"},
    {"research-notes", "Chapter 3: literature review", "home"},
    {"acme-landing", "Mobile layout fix", "work"},
};
#define POOL_LEN (int)(sizeof(POOL) / sizeof(POOL[0]))

static const struct {
    const char *tool, *detail, *why;
    bool high;
} PERMS[] = {
    {"Bash", "npm run db:migrate", "Apply migration 0042 to the local database before running the tests.", false},
    {"Edit", "src/webhooks/stripe.ts", "Verify the webhook signature before processing the event.", false},
    {"WebFetch", "docs.espressif.com/\xE2\x80\xA6/ledc.html", "Read the LEDC API to drive the eye LEDs.", false},
    {"Bash", "terraform apply", "Deploy the new task definition to ECS (production).", true},
    {"Bash", "git push --force origin main", "Rewrite history after the rebase.", true},
};

static const struct {
    const char *detail, *options;
} QUESTIONS[] = {
    {"Where should I store Hilo history?", "[\"Local SQLite\",\"Markdown files\",\"Decide later\"]"},
    {"What should I do with the failing tests?", "[\"Fix them now\",\"Mark them skip\",\"Stop\"]"},
};

static const struct {
    const char *title, *artist;
    int len;
} SONGS[] = {{"Low Tide", "North Coral", 221}, {"Fan Noise", "The Bits", 184}, {"Night Build", "Tabstop", 247},
             {"Rush Hour", "The Minibuses", 199}};

static const char *const SUMMARIES[] = {"Changes ready for review: 3 files, tests green.",
                                        "PR opened with description and checklist.",
                                        "Migration applied; 128 tests passed."};
static const char *const ERRORS[] = {"3 tests failed in payments.spec.ts", "Build failed: type not found in match.ts",
                                     "Tool timeout after 120 s"};
static const char *const STEPS[] = {"Read 5 files in the module", "Edited src/ledger/match.ts",
                                    "Ran the test suite (passed)", "Edited main/ui/agents.c"};
static const char *const STEP_KINDS[] = {"read", "edit", "run", "edit"};

static uint32_t rnd(demo_t *d, uint32_t n)
{
    return d->random32 ? d->random32(d->random_ctx) % n : 0;
}

static int64_t ts(const demo_t *d, uint32_t now_ms)
{
    return DEMO_EPOCH + (int64_t)((now_ms - d->start_ms) / 1000);
}

static void send(demo_t *d, uint32_t now_ms, const char *host, const char *type, const char *fmt, ...)
{
    char data[2048], json[2400];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(data, sizeof(data), fmt, ap);
    va_end(ap);
    snprintf(json, sizeof(json), "{\"v\":1,\"id\":\"01K8F7%020u\",\"ts\":%lld,\"host\":\"%s\",\"type\":\"%s\",\"data\":%s}",
             (unsigned)++d->counter, (long long)ts(d, now_ms), host, type, data);
    if (bm_ingest(d->m, json, strlen(json), now_ms) != BM_OK) d->rejected++;
}

static void request_id(demo_t *d, char out[27])
{
    snprintf(out, 27, "01K8F8%020u", (unsigned)++d->counter);
}

static void snapshot(demo_t *d, uint32_t now_ms, int host)
{
    int64_t t = ts(d, now_ms);
    if (host == 0) {
        send(d, now_ms, "work", "snapshot",
             "{\"sessions\":[{\"session\":\"w1\",\"project\":\"payments-api\",\"task\":\"Payments webhook refactor\","
             "\"status\":\"working\",\"since\":%lld,\"tokens\":118000,\"steps\":[{\"ts\":%lld,\"kind\":\"plan\",\"text\":"
             "\"4-step plan: payments webhook refactor\"},{\"ts\":%lld,\"kind\":\"edit\",\"text\":\"Edited "
             "src/webhooks/stripe.ts\"}]},{\"session\":\"w2\",\"project\":\"acme-dashboard\",\"task\":\"PR #482 "
             "review\",\"status\":\"done\",\"since\":%lld,\"tokens\":64000,\"summary\":\"Changes ready for review: 3 "
             "files, tests green.\"}],\"usage\":{\"session_pct\":42,\"weekly_pct\":31,\"reset_in_min\":134,"
             "\"tokens_today\":1840000},\"hilo\":{\"current\":{\"title\":\"Integrate BLE events into the daemon\","
             "\"project\":\"hilo-buddy\",\"started_at\":%lld},\"next\":[{\"title\":\"Review CloudWatch alerts\","
             "\"project\":\"acme\",\"jira\":\"DEMO-1423\"},{\"title\":\"Read multi-agent orchestration paper\","
             "\"project\":\"research\"},{\"title\":\"Define rotating views PRD\",\"project\":\"hilo-buddy\"}],"
             "\"agreements_today\":[\"Compact JSON events\",\"No credentials on the buddy\"]},\"media\":{\"title\":"
             "\"Low Tide\",\"artist\":\"North Coral\",\"length_s\":221,\"position_s\":64}}",
             t - 720, t - 600, t - 300, t - 180, t - 2892);
    } else {
        send(d, now_ms, "home", "snapshot",
             "{\"sessions\":[{\"session\":\"h1\",\"project\":\"buddy-firmware\",\"task\":\"Agents screen in LVGL\","
             "\"status\":\"working\",\"since\":%lld,\"tokens\":152000},{\"session\":\"h2\",\"project\":\"hilo-app\","
             "\"task\":\"SQLite v3 migration\",\"status\":\"idle\",\"since\":%lld,\"tokens\":41000}],\"usage\":"
             "{\"session_pct\":38,\"weekly_pct\":29,\"reset_in_min\":131},\"hilo\":{\"current\":null,\"next\":[],"
             "\"agreements_today\":[]}}",
             t - 1620, t - 2460);
    }
}

void demo_start(demo_t *d, bm_model_t *m, uint32_t (*random32)(void *), void *ctx, uint32_t now_ms)
{
    memset(d, 0, sizeof(*d));
    d->m = m;
    d->random32 = random32;
    d->random_ctx = ctx;
    d->start_ms = now_ms;
    d->next_event_ms = now_ms + DEMO_EVENT_MS;
    d->next_pool = 4;
    for (int h = 0; h < 2; h++) {
        bm_link(m, HOSTS[h], true, now_ms);
        snapshot(d, now_ms, h);
    }
    bm_set_battery(m, 76, false, now_ms);
}

static const bm_session_t *pick(demo_t *d, bm_status_t a, bm_status_t b)
{
    const bm_session_t *found[BM_MAX_SESSIONS];
    int n = 0;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &d->m->sessions[i];
        if (s->used && bm_live(d->m, s) && (s->status == a || s->status == b)) found[n++] = s;
    }
    return n ? found[rnd(d, (uint32_t)n)] : NULL;
}

static const char *host_of(demo_t *d, const bm_session_t *s)
{
    return d->m->hosts[s->host].name;
}

static void ev_start(demo_t *d, uint32_t now_ms)
{
    int i = d->next_pool++ % POOL_LEN;
    char id[24];
    snprintf(id, sizeof(id), "s%u", (unsigned)++d->counter);
    send(d, now_ms, POOL[i].host, "session.start", "{\"session\":\"%s\",\"project\":\"%s\",\"task\":\"%s\"}", id,
         POOL[i].project, POOL[i].task);
}

static void ev_permission(demo_t *d, uint32_t now_ms, bool high)
{
    const bm_session_t *s = pick(d, BM_WORKING, BM_IDLE);
    if (!s) return;
    int base = high ? 3 : 0, n = high ? 2 : 3, i = base + (int)rnd(d, (uint32_t)n);
    char rid[27];
    request_id(d, rid);
    send(d, now_ms, host_of(d, s), "agent.needs_permission",
         "{\"request_id\":\"%s\",\"session\":\"%s\",\"project\":\"%s\",\"tool\":\"%s\",\"detail\":\"%s\",\"why\":\"%s\","
         "%s\"cwd\":\"~/code/%s\",\"risk\":\"%s\",\"remote_allowed\":%s,\"expires_at\":%lld}",
         rid, s->id, s->project, PERMS[i].tool, PERMS[i].detail, PERMS[i].why,
         i == 1 ? "\"diff\":[[\"r\",\"if (event.type === \\\"charge.succeeded\\\") {\"],[\"a\",\"verifySignature(req, "
                  "secret);\"],[\"a\",\"if (event.type === \\\"charge.succeeded\\\") {\"]],"
                : "",
         s->project, high ? "high" : "low", high ? "false" : "true", (long long)ts(d, now_ms) + 600);
}

static void ev_question(demo_t *d, uint32_t now_ms)
{
    const bm_session_t *s = pick(d, BM_WORKING, BM_IDLE);
    if (!s) return;
    int i = (int)rnd(d, 2);
    char rid[27];
    request_id(d, rid);
    send(d, now_ms, host_of(d, s), "agent.question",
         "{\"request_id\":\"%s\",\"session\":\"%s\",\"project\":\"%s\",\"detail\":\"%s\",\"options\":%s,"
         "\"expires_at\":%lld}",
         rid, s->id, s->project, QUESTIONS[i].detail, QUESTIONS[i].options, (long long)ts(d, now_ms) + 600);
}

static void ev_resolve_on_mac(demo_t *d, uint32_t now_ms)
{
    const bm_session_t *s = pick(d, BM_WAITING, BM_WAITING);
    if (!s || !s->has_request) return;
    bool q = s->req.is_question;
    send(d, now_ms, host_of(d, s), "agent.request_resolved",
         "{\"request_id\":\"%s\",\"session\":\"%s\",\"kind\":\"%s\",\"outcome\":\"%s\",\"via\":\"mac\"%s}",
         s->req.request_id, s->id, q ? "question" : "permission", q ? "answered" : "approved",
         q ? ",\"choice_index\":0" : "");
}

static void ev_done(demo_t *d, uint32_t now_ms)
{
    const bm_session_t *s = pick(d, BM_WORKING, BM_WORKING);
    if (s)
        send(d, now_ms, host_of(d, s), "agent.task_done", "{\"session\":\"%s\",\"summary\":\"%s\"}", s->id,
             SUMMARIES[rnd(d, 3)]);
}

static void ev_fail(demo_t *d, uint32_t now_ms)
{
    const bm_session_t *s = pick(d, BM_WORKING, BM_WORKING);
    if (s)
        send(d, now_ms, host_of(d, s), "agent.error", "{\"session\":\"%s\",\"detail\":\"%s\"}", s->id,
             ERRORS[rnd(d, 3)]);
}

static void ev_step(demo_t *d, uint32_t now_ms)
{
    const bm_session_t *s = pick(d, BM_WORKING, BM_WORKING);
    int i = (int)rnd(d, 4);
    if (s)
        send(d, now_ms, host_of(d, s), "agent.step", "{\"session\":\"%s\",\"kind\":\"%s\",\"text\":\"%s\"}", s->id,
             STEP_KINDS[i], STEPS[i]);
}

static void ev_usage(demo_t *d, uint32_t now_ms)
{
    int h = (int)rnd(d, 2);
    const bm_usage_t *u = &d->m->hosts[h].usage;
    int pct = (int)u->session_pct + 7;
    if (pct > 100) {
        send(d, now_ms, HOSTS[h], "usage.window_reset", "{}");
        return;
    }
    int64_t tokens = (u->tokens_today > 0 ? u->tokens_today : 1200000) + 40000 + rnd(d, 120000);
    send(d, now_ms, HOSTS[h], "usage.update",
         "{\"session_pct\":%d,\"weekly_pct\":%d,\"reset_in_min\":%d,\"tokens_today\":%lld}", pct,
         (int)u->weekly_pct + 1, u->reset_in_min > 5 ? (int)u->reset_in_min - 5 : 0, (long long)tokens);
}

static void ev_song(demo_t *d, uint32_t now_ms)
{
    int i = (int)rnd(d, 4);
    send(d, now_ms, "work", "media.now_playing",
         "{\"title\":\"%s\",\"artist\":\"%s\",\"length_s\":%d,\"position_s\":0}", SONGS[i].title, SONGS[i].artist,
         SONGS[i].len);
}

static void ev_end(demo_t *d, uint32_t now_ms)
{
    const bm_session_t *s = pick(d, BM_DONE, BM_IDLE);
    if (!s) s = pick(d, BM_ERROR, BM_ERROR);
    if (s) send(d, now_ms, host_of(d, s), "session.end", "{\"session\":\"%s\"}", s->id);
}

void demo_tick(demo_t *d, uint32_t now_ms)
{
    if (d->reply.pending && (int32_t)(now_ms - d->reply.at_ms) >= 0) {
        d->reply.pending = false;
        char choice[40] = "";
        if (d->reply.choice >= 0) snprintf(choice, sizeof(choice), ",\"choice_index\":%d", d->reply.choice);
        send(d, now_ms, d->reply.host, "agent.request_resolved",
             "{\"request_id\":\"%s\",\"session\":\"%s\",\"kind\":\"%s\",\"outcome\":\"%s\",\"via\":\"buddy\"%s}",
             d->reply.request_id, d->reply.session, d->reply.kind, d->reply.outcome, choice);
    }
    if ((int32_t)(now_ms - d->next_event_ms) < 0) return;
    d->next_event_ms = now_ms + DEMO_EVENT_MS;
    uint32_t r = rnd(d, 100);
    if (bm_attn_session(d->m) && r < 50) return;
    if (r < 18) ev_start(d, now_ms);
    else if (r < 30) ev_permission(d, now_ms, false);
    else if (r < 35) ev_permission(d, now_ms, true);
    else if (r < 41) ev_question(d, now_ms);
    else if (r < 48) ev_resolve_on_mac(d, now_ms);
    else if (r < 62) ev_done(d, now_ms);
    else if (r < 68) ev_fail(d, now_ms);
    else if (r < 78) ev_step(d, now_ms);
    else if (r < 86) ev_usage(d, now_ms);
    else if (r < 92) ev_song(d, now_ms);
    else ev_end(d, now_ms);
}

static bool json_str(const char *json, const char *key, char *out, size_t n)
{
    char needle[32];
    snprintf(needle, sizeof(needle), "\"%s\":\"", key);
    const char *p = strstr(json, needle);
    if (!p) return false;
    p += strlen(needle);
    const char *end = strchr(p, '"');
    if (!end || (size_t)(end - p) >= n) return false;
    memcpy(out, p, (size_t)(end - p));
    out[end - p] = '\0';
    return true;
}

void demo_on_outgoing(demo_t *d, const bm_out_t *out, uint32_t now_ms)
{
    bool decision = strstr(out->json, "\"type\":\"permission.decision\"") != NULL;
    bool answer = strstr(out->json, "\"type\":\"question.answer\"") != NULL;
    if (!decision && !answer) return;
    char rid[27];
    if (!json_str(out->json, "request_id", rid, sizeof(rid))) return;
    for (int i = 0; i < BM_MAX_SESSIONS; i++) {
        const bm_session_t *s = &d->m->sessions[i];
        if (!s->used || strcmp(s->req.request_id, rid) != 0) continue;
        d->reply.pending = true;
        d->reply.at_ms = now_ms + 300;
        snprintf(d->reply.host, sizeof(d->reply.host), "%s", d->m->hosts[s->host].name);
        snprintf(d->reply.request_id, sizeof(d->reply.request_id), "%s", rid);
        snprintf(d->reply.session, sizeof(d->reply.session), "%s", s->id);
        snprintf(d->reply.kind, sizeof(d->reply.kind), "%s", answer ? "question" : "permission");
        snprintf(d->reply.outcome, sizeof(d->reply.outcome), "%s",
                 answer ? "answered" : strstr(out->json, "\"approve\"") ? "approved" : "denied");
        d->reply.choice = -1;
        if (answer) {
            const char *p = strstr(out->json, "\"choice_index\":");
            d->reply.choice = p ? p[15] - '0' : 0;
        }
        return;
    }
}
