#include "support.h"

#define RID1 "01K8F3Z9QW4Y6R2M7N5P8T0V1X"
#define RID2 "01K8F3Z9QW4Y6R2M7N5P8T0V2X"

static void set_status(const char *host, const char *id, const char *type, const char *field)
{
    CHECK(send(host, type, "{\"session\":\"%s\",\"%s\":\"something\"}", id, field) == BM_OK);
}

TEST(agents_sort_needs_you_failed_working_done_idle_and_stay_stable)
{
    fresh();
    start_session("work", "a", "a-done");
    start_session("work", "b", "b-working");
    start_session("home", "c", "c-error");
    start_session("work", "d", "d-waiting");
    start_session("home", "e", "e-working");
    start_session("home", "f", "f-idle");
    set_status("work", "a", "agent.task_done", "summary");
    set_status("home", "c", "agent.error", "detail");
    ask_permission("work", "d", RID1, "low", true);
    M.sessions[session_index("home", "f")].status = BM_IDLE;

    int8_t order[BM_MAX_SESSIONS];
    int n = bm_agent_order(&M, order, BM_MAX_SESSIONS);
    CHECK(n == 6);
    const char *expected[] = {"d", "c", "b", "e", "a", "f"};
    for (int i = 0; i < n; i++) CHECK_STR(M.sessions[order[i]].id, expected[i]);
    CHECK(bm_agent_order(&M, order, BM_AGENT_ROWS) == BM_AGENT_ROWS);
    CHECK(bm_session_count(&M) == 6);
}

TEST(home_message_follows_prototype_priority)
{
    bm_home_t h;
    fresh();
    bm_home(&M, now, &h);
    CHECK_STR(h.msg, "All quiet");
    CHECK_STR(h.sub, "no active sessions");

    start_session("work", "a", "alpha");
    start_session("work", "b", "beta");
    bm_home(&M, now, &h);
    CHECK_STR(h.msg, "2 agents working");

    set_status("work", "a", "agent.error", "detail");
    bm_home(&M, now, &h);
    CHECK_STR(h.msg, "1 task failed");
    CHECK_STR(h.sub, "1 working");
    CHECK(h.colored && h.color == BM_C_ERR);

    ask_permission("work", "b", RID1, "low", true);
    bm_home(&M, now, &h);
    CHECK_STR(h.msg, "beta needs you");
    CHECK_STR(h.sub, "tap to review");
    CHECK(h.tap_session == session_index("work", "b"));
    CHECK(h.color == BM_C_WAIT);

    bm_link(&M, "work", false, now);
    bm_link(&M, "home", false, now);
    bm_home(&M, now, &h);
    CHECK_STR(h.msg, "No Macs connected");
}

TEST(permission_needs_a_full_900ms_hold)
{
    outs_t o;
    fresh();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    drain(&o);
    CHECK(bm_attn_session(&M) == &M.sessions[session_index("work", "s")]);
    const bm_out_t *ack = find_out(&o, "device.ack");
    CHECK(ack && ack->hosts == 1 && strstr(ack->json, RID1));
    CHECK(heard(BM_SND_PERM));

    CHECK(bm_hold_begin(&M, now));
    advance(800);
    CHECK(bm_hold_progress(&M, now) > 0.8f && bm_hold_progress(&M, now) < 1.0f);
    bm_hold_cancel(&M);
    advance(500);
    drain(&o);
    CHECK(find_out(&o, "permission.decision") == NULL);
    CHECK(bm_attn_session(&M) != NULL);

    CHECK(bm_hold_begin(&M, now));
    advance(BM_HOLD_MS);
    drain(&o);
    const bm_out_t *d = find_out(&o, "permission.decision");
    CHECK(d && strstr(d->json, "\"decision\":\"approve\"") && strstr(d->json, RID1));
    CHECK(bm_attn_session(&M) == NULL);
    CHECK(M.ov.type == BM_OV_APPROVED);
    CHECK(M.sessions[session_index("work", "s")].status == BM_WORKING);
    advance(1600);
    CHECK(M.ov.type == BM_OV_NONE);
}

TEST(high_risk_and_mac_only_requests_can_only_be_denied)
{
    outs_t o;
    const char *risks[] = {"high", "low"};
    for (int i = 0; i < 2; i++) {
        fresh();
        start_session("home", "s", "alpha");
        ask_permission("home", "s", RID1, risks[i], false);
        CHECK(heard(i == 0 ? BM_SND_RISK : BM_SND_PERM));
        CHECK(!bm_request_approvable(&bm_attn_session(&M)->req));
        CHECK(!bm_hold_begin(&M, now));
        bm_tap(&M, BM_TAP_ANSWER, 0, now);
        advance(2000);
        drain(&o);
        CHECK(find_out(&o, "permission.decision") == NULL);
        CHECK(find_out(&o, "question.answer") == NULL);

        bm_tap(&M, BM_TAP_DENY, 0, now);
        drain(&o);
        const bm_out_t *d = find_out(&o, "permission.decision");
        CHECK(d && d->hosts == 2 && strstr(d->json, "\"decision\":\"deny\""));
        CHECK(M.ov.type == BM_OV_DENIED);
    }
}

TEST(question_answer_carries_index_and_escaped_choice)
{
    outs_t o;
    fresh();
    start_session("work", "q", "alpha");
    ask_question("work", "q", RID1);
    CHECK(heard(BM_SND_QUESTION));
    CHECK(!bm_hold_begin(&M, now));
    bm_tap(&M, BM_TAP_ANSWER, 3, now);
    drain(&o);
    CHECK(find_out(&o, "question.answer") == NULL);
    bm_tap(&M, BM_TAP_ANSWER, 0, now);
    drain(&o);
    const bm_out_t *a = find_out(&o, "question.answer");
    CHECK(a && strstr(a->json, "\"choice_index\":0,\"choice\":\"Keep \\\"both\\\"\""));
    CHECK(M.ov.type == BM_OV_APPROVED && M.ov.question);
}

TEST(later_snoozes_and_reminders_repeat_every_25s)
{
    outs_t o;
    fresh();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    heard(BM_SND_PERM);
    bm_tap(&M, BM_TAP_LATER, 0, now);
    drain(&o);
    const bm_out_t *z = find_out(&o, "device.snooze");
    CHECK(z && strstr(z->json, RID1));
    CHECK(bm_attn_session(&M) == NULL);
    CHECK(M.sessions[session_index("work", "s")].has_request);

    advance(BM_REMIND_MS);
    CHECK(!heard(BM_SND_REMINDER));
    advance(200);
    CHECK(heard(BM_SND_REMINDER));
    advance(BM_REMIND_MS);
    CHECK(heard(BM_SND_REMINDER));

    advance(5 * BM_IDLE_SLEEP_MS);
    CHECK(!M.sleeping);
    CHECK(bm_attn_session(&M) == NULL);

    bm_tap(&M, BM_TAP_OPEN_PERM, session_index("work", "s"), now);
    CHECK(bm_attn_session(&M) != NULL);
}

TEST(side_button_click_is_later_while_a_request_is_open)
{
    outs_t o;
    fresh();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    drain(&o);
    bm_button(&M, true, now);
    advance(100);
    bm_button(&M, false, now);
    drain(&o);
    CHECK(find_out(&o, "device.snooze") != NULL);
    CHECK(M.view == BM_VIEW_HOME);
}

TEST(resolved_on_mac_closes_the_prompt_and_opens_the_next)
{
    outs_t o;
    fresh();
    start_session("work", "a", "alpha");
    start_session("home", "b", "beta");
    ask_permission("home", "b", RID2, "low", true);
    ask_permission("work", "a", RID1, "low", true);
    CHECK(bm_attn_session(&M) == &M.sessions[session_index("work", "a")]);

    CHECK(send("work", "agent.request_resolved",
               "{\"request_id\":\"" RID1 "\",\"session\":\"a\",\"kind\":\"permission\",\"outcome\":\"approved\","
               "\"via\":\"mac\"}") == BM_OK);
    CHECK(bm_attn_session(&M) == NULL);
    CHECK(strstr(M.toast, "Resolved on the Work Mac") != NULL);
    advance(BM_NEXT_ATTN_MS - 100);
    CHECK(bm_attn_session(&M) == NULL);
    advance(200);
    CHECK(bm_attn_session(&M) == &M.sessions[session_index("home", "b")]);
    drain(&o);
    CHECK(count_out(&o, "device.ack") == 2);
}

TEST(decision_for_unknown_request_is_ignored)
{
    fresh();
    start_session("work", "a", "alpha");
    uint32_t rev = M.rev;
    CHECK(send("work", "agent.request_resolved",
               "{\"request_id\":\"" RID2 "\",\"session\":\"a\",\"kind\":\"permission\",\"outcome\":\"denied\","
               "\"via\":\"buddy\"}") == BM_OK);
    CHECK(M.rev == rev);
}

TEST(request_expires_locally_once_the_clock_passes_expires_at)
{
    fresh();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    advance(599 * 1000);
    CHECK(M.sessions[session_index("work", "s")].has_request);
    advance(2000);
    CHECK(!M.sessions[session_index("work", "s")].has_request);
    CHECK(bm_attn_session(&M) == NULL);
    CHECK(M.sessions[session_index("work", "s")].status == BM_WAITING);
}

TEST(idle_for_60s_sleeps_and_touch_wakes)
{
    outs_t o;
    fresh();
    bm_touch_wake(&M, now);
    advance(BM_IDLE_SLEEP_MS);
    CHECK(!M.sleeping);
    advance(100);
    CHECK(M.sleeping);
    drain(&o);
    const bm_out_t *s = find_out(&o, "device.sleep");
    CHECK(s && strstr(s->json, "\"by\":\"idle\"") && s->hosts == 0xff);

    bm_tap(&M, BM_TAP_USAGE, 0, now);
    CHECK(!M.sleeping && M.sheet == BM_SHEET_NONE);
    drain(&o);
    CHECK(strstr(find_out(&o, "device.wake")->json, "\"by\":\"touch\""));
}

TEST(sleep_clock_shifts_every_6s_within_20px)
{
    fresh();
    bm_button(&M, true, now);
    advance(BM_LONG_PRESS_MS);
    CHECK(M.sleeping);
    int shifts = 0;
    int16_t dx = M.sleep_dx, dy = M.sleep_dy;
    for (int i = 0; i < 60; i++) {
        advance(1000);
        if (M.sleep_dx != dx || M.sleep_dy != dy) shifts++;
        dx = M.sleep_dx;
        dy = M.sleep_dy;
        CHECK(dx >= -20 && dx <= 20 && dy >= -20 && dy <= 20);
    }
    CHECK(shifts >= 8 && shifts <= 10);
    bm_button(&M, false, now);
}

TEST(side_button_long_press_sleeps_and_click_cycles_views)
{
    outs_t o;
    fresh();
    for (int i = 1; i <= BM_VIEWS; i++) {
        bm_button(&M, true, now);
        advance(100);
        bm_button(&M, false, now);
        CHECK(M.view == (bm_view_t)(i % BM_VIEWS));
    }
    CHECK(heard(BM_SND_CLICK));
    bm_button(&M, true, now);
    advance(BM_LONG_PRESS_MS - 100);
    CHECK(!M.sleeping);
    advance(100);
    CHECK(M.sleeping);
    bm_button(&M, false, now);
    CHECK(M.sleeping);
    drain(&o);
    CHECK(strstr(find_out(&o, "device.sleep")->json, "long_press"));
    bm_button(&M, true, now);
    bm_button(&M, false, now);
    CHECK(!M.sleeping);
    drain(&o);
    CHECK(strstr(find_out(&o, "device.wake")->json, "\"by\":\"button\""));
}

TEST(swipe_changes_view_but_not_over_a_prompt_or_sheet)
{
    fresh();
    bm_swipe(&M, -1, now);
    CHECK(M.view == BM_VIEW_MUSIC);
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_HOME);
    bm_tap(&M, BM_TAP_USAGE, 0, now);
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_HOME);
    bm_tap(&M, BM_TAP_BACK, 0, now);
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_HOME);
}

TEST(task_done_overlay_lasts_3s_and_becomes_a_toast_over_a_prompt)
{
    fresh();
    start_session("work", "a", "alpha");
    start_session("work", "b", "beta");
    set_status("work", "a", "agent.task_done", "summary");
    CHECK(M.ov.type == BM_OV_DONE && heard(BM_SND_DONE));
    CHECK(bm_main_pet(&M) == BM_PET_HAPPY);
    advance(2900);
    CHECK(M.ov.type == BM_OV_DONE);
    advance(200);
    CHECK(M.ov.type == BM_OV_NONE);

    ask_permission("work", "b", RID1, "low", true);
    start_session("work", "c", "gamma");
    set_status("work", "c", "agent.error", "detail");
    CHECK(M.ov.type == BM_OV_NONE);
    CHECK(strstr(M.toast, "gamma failed") != NULL);
    advance(BM_TOAST_MS + 100);
    CHECK(M.toast[0] == '\0');
}

TEST(tapping_done_overlay_opens_agent_sheet)
{
    fresh();
    start_session("work", "a", "alpha");
    set_status("work", "a", "agent.task_done", "summary");
    bm_tap_overlay(&M, now);
    CHECK(M.ov.type == BM_OV_NONE);
    CHECK(M.sheet == BM_SHEET_AGENT && M.sheet_session == session_index("work", "a"));
    bm_button(&M, true, now);
    bm_button(&M, false, now);
    CHECK(M.sheet == BM_SHEET_NONE);
}

static void usage(const char *host, int pct)
{
    CHECK(send(host, "usage.update", "{\"session_pct\":%d,\"weekly_pct\":30,\"reset_in_min\":120}", pct) == BM_OK);
}

TEST(usage_warns_once_at_80_and_limit_persists_until_reset)
{
    fresh();
    usage("work", 79);
    CHECK(M.ov.type == BM_OV_NONE);
    usage("work", 80);
    CHECK(M.ov.type == BM_OV_WARN && heard(BM_SND_WARN));
    advance(3000);
    usage("work", 85);
    CHECK(M.ov.type == BM_OV_NONE);
    usage("work", 100);
    CHECK(M.ov.type == BM_OV_LIMIT && heard(BM_SND_LIMIT));
    CHECK(bm_main_pet(&M) == BM_PET_SLEEP);
    advance(60000);
    bm_tap_overlay(&M, now);
    CHECK(M.ov.type == BM_OV_LIMIT);
    bm_home_t h;
    bm_home(&M, now, &h);
    CHECK_STR(h.msg, "Limit reached");
    CHECK_STR(h.sub, "back in 1h59");
    CHECK(send("work", "usage.window_reset", "{}") == BM_OK);
    CHECK(M.ov.type == BM_OV_NONE);
    usage("work", 81);
    CHECK(M.ov.type == BM_OV_WARN);
}

TEST(usage_is_kept_per_mac)
{
    fresh();
    usage("work", 40);
    usage("home", 70);
    CHECK(bm_usage_pct(&M.hosts[0].usage) == 40);
    CHECK(bm_usage_pct(&M.hosts[1].usage) == 70);
    CHECK(bm_usage_host(&M) == 1);
    bm_link(&M, "home", false, now);
    CHECK(bm_usage_host(&M) == 0);
    CHECK(bm_usage_color(80) == BM_C_WAIT && bm_usage_color(100) == BM_C_ERR && bm_usage_color(10) == BM_C_WORK);
}

TEST(snapshot_replaces_only_its_host_and_reopens_pending)
{
    outs_t o;
    fresh();
    start_session("work", "old", "stale");
    start_session("home", "keep", "other");
    CHECK(send("work", "snapshot",
               "{\"sessions\":[{\"session\":\"s1\",\"project\":\"payments-api\",\"task\":\"t\",\"status\":\"waiting\","
               "\"since\":%lld,\"pending_permission\":{\"request_id\":\"" RID1 "\",\"session\":\"s1\",\"project\":"
               "\"payments-api\",\"tool\":\"Bash\",\"detail\":\"ls\",\"cwd\":\"~\",\"risk\":\"low\","
               "\"remote_allowed\":true,\"expires_at\":%lld}},{\"session\":\"s2\",\"project\":\"hilo-app\",\"task\":"
               "\"t\",\"status\":\"done\",\"since\":1}],\"usage\":{\"session_pct\":42,\"weekly_pct\":31,"
               "\"reset_in_min\":134},\"hilo\":{\"current\":{\"title\":\"Now\",\"project\":\"hilo-buddy\","
               "\"started_at\":1},\"next\":[{\"title\":\"Next\",\"project\":\"acme\",\"jira\":\"DEMO-1\"}],"
               "\"agreements_today\":[\"Compact JSON\"]},\"media\":{\"title\":\"Low Tide\",\"artist\":\"North "
               "Coral\",\"length_s\":221,\"position_s\":64}}",
               BASE_TS, BASE_TS + 600) == BM_OK);
    CHECK(session_index("work", "old") < 0);
    CHECK(session_index("home", "keep") >= 0);
    CHECK(session_index("work", "s1") >= 0 && session_index("work", "s2") >= 0);
    CHECK(M.hosts[0].hilo.has_current && M.hosts[0].hilo.n_next == 1 && M.hosts[0].hilo.n_agreements == 1);
    CHECK(M.hosts[0].media.playing && bm_media_host(&M) == 0);
    advance(10000);
    CHECK(bm_media_position_s(&M.hosts[0].media, now) == 74);
    CHECK(bm_attn_session(&M) == &M.sessions[session_index("work", "s1")]);
    drain(&o);
    CHECK(find_out(&o, "device.ack") != NULL);
}

TEST(snapshot_sets_the_clock_and_later_messages_only_move_it_forward)
{
    fresh();
    CHECK(!M.clock_known);
    start_session("work", "a", "alpha");
    CHECK(M.clock_known);
    int64_t first = bm_wall_ms(&M, now);
    CHECK(first == (BASE_TS + now / 1000) * 1000);
    CHECK(send_raw("{\"v\":1,\"id\":\"01K8F600000000000000000001\",\"ts\":1000,\"host\":\"work\",\"type\":"
                   "\"agent.step\",\"data\":{\"session\":\"a\",\"kind\":\"read\",\"text\":\"Read x\"}}") == BM_OK);
    CHECK(bm_wall_ms(&M, now) == first);
    char clock[8];
    bm_fmt_clock(3600 * 1000 * 25 + 60 * 1000 * 7, 60, clock, sizeof(clock));
    CHECK_STR(clock, "02:07");
}

TEST(disconnect_dims_sessions_and_closes_its_prompt)
{
    fresh();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    bm_link(&M, "work", false, now);
    CHECK(bm_attn_session(&M) == NULL);
    CHECK(!bm_live(&M, &M.sessions[session_index("work", "s")]));
    CHECK(bm_agent_pet(&M, &M.sessions[session_index("work", "s")]) == BM_PET_SLEEP);
    CHECK(M.ov.type == BM_OV_CONN && !M.ov.on && heard(BM_SND_DISCONNECTED));
    CHECK(bm_main_pet(&M) == BM_PET_WORRIED);
    advance(BM_REMIND_MS * 2);
    CHECK(!heard(BM_SND_REMINDER));
}

TEST(a_full_host_evicts_idle_or_done_sessions_first)
{
    fresh();
    char id[8];
    for (int i = 0; i < BM_SESSIONS_PER_HOST; i++) {
        snprintf(id, sizeof(id), "s%d", i);
        start_session("work", id, "p");
    }
    set_status("work", "s3", "agent.task_done", "summary");
    start_session("work", "s8", "p");
    CHECK(session_index("work", "s3") < 0);
    CHECK(session_index("work", "s0") >= 0 && session_index("work", "s8") >= 0);
    start_session("work", "s9", "p");
    CHECK(session_index("work", "s0") < 0);
    CHECK(bm_session_count(&M) == BM_SESSIONS_PER_HOST);
}

TEST(steps_keep_the_last_five)
{
    fresh();
    start_session("work", "a", "alpha");
    for (int i = 0; i < 7; i++)
        CHECK(send("work", "agent.step", "{\"session\":\"a\",\"kind\":\"edit\",\"text\":\"step %d\"}", i) == BM_OK);
    const bm_session_t *s = &M.sessions[session_index("work", "a")];
    CHECK(s->n_steps == BM_MAX_STEPS);
    CHECK_STR(s->steps[0].text, "step 2");
    CHECK_STR(s->steps[4].text, "step 6");
}

TEST(low_battery_alerts_once_until_charged)
{
    outs_t o;
    fresh();
    bm_set_battery(&M, 40, false, now);
    bm_set_battery(&M, 15, false, now);
    CHECK(M.ov.type == BM_OV_BATT && heard(BM_SND_BATTERY));
    advance(3000);
    bm_set_battery(&M, 14, false, now);
    CHECK(M.ov.type == BM_OV_NONE);
    bm_set_battery(&M, 14, true, now);
    CHECK(heard(BM_SND_CHARGE));
    drain(&o);
    CHECK(count_out(&o, "device.battery") == 4);
    CHECK(strstr(o.items[3].json, "{\"pct\":14,\"charging\":true}"));
}

TEST(accessory_change_is_reported)
{
    outs_t o;
    fresh();
    bm_set_accessory(&M, BM_ACC_WIZARD);
    bm_set_accessory(&M, BM_ACC_CROWN);
    drain(&o);
    CHECK(count_out(&o, "device.pet_accessory") == 1);
    CHECK(strstr(o.items[0].json, "\"acc\":\"crown\""));
}

TEST(outgoing_envelope_has_no_host_and_a_ulid)
{
    outs_t o;
    fresh();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID1, "low", true);
    drain(&o);
    CHECK(o.n == 1);
    CHECK(strncmp(o.items[0].json, "{\"v\":1,\"id\":\"", 13) == 0);
    CHECK(strstr(o.items[0].json, "\"host\"") == NULL);
    CHECK(o.items[0].json[13 + 26] == '"');
}

TEST(formatting_matches_prototype)
{
    char b[32];
    bm_fmt_dur(65 * 1000, b, sizeof(b));
    CHECK_STR(b, "1:05");
    bm_fmt_dur(134 * 60 * 1000, b, sizeof(b));
    CHECK_STR(b, "2h14");
    bm_fmt_dur(-5, b, sizeof(b));
    CHECK_STR(b, "0:00");
    bm_fmt_hms(48 * 60 * 1000 + 12000, b, sizeof(b));
    CHECK_STR(b, "0:48:12");
    bm_fmt_ago(30 * 1000, b, sizeof(b));
    CHECK_STR(b, "now");
    bm_fmt_ago(12 * 60 * 1000, b, sizeof(b));
    CHECK_STR(b, "12 min ago");
    bm_fmt_ago(130 * 60 * 1000, b, sizeof(b));
    CHECK_STR(b, "2 h ago");
    bm_host_label("work", b, sizeof(b));
    CHECK_STR(b, "Work");
    CHECK_STR(bm_status_label(BM_WAITING), "needs you");
    CHECK_STR(bm_status_label(BM_ERROR), "failed");
}

TEST(project_look_is_stable)
{
    uint16_t h1, h2;
    bm_acc_t a1, a2;
    bm_project_look("payments-api", &h1, &a1);
    bm_project_look("payments-api", &h2, &a2);
    CHECK(h1 == h2 && a1 == a2 && h1 < 360 && a1 < BM_ACC_COUNT);
}
