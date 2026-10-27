#include <stdlib.h>

#include "bm_conn.h"
#include "bm_internal.h"
#include "support.h"

#define EMPTY_SNAPSHOT                                                                                                 \
    "\"sessions\":[],\"usage\":{\"session_pct\":10,\"weekly_pct\":5,\"reset_in_min\":100},"                          \
    "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]}"

static bm_err_t snapshot(const char *host, const char *extra)
{
    return send(host, "snapshot", "{" EMPTY_SNAPSHOT "%s%s}", extra[0] ? "," : "", extra);
}

static int64_t wall_now(void)
{
    return bm_wall_ms(&M, now) / 1000;
}

static void b64(const uint8_t *in, size_t n, char *out)
{
    static const char T[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16 | (i + 1 < n ? (uint32_t)in[i + 1] << 8 : 0) | (i + 2 < n ? in[i + 2] : 0);
        out[o++] = T[v >> 18 & 63];
        out[o++] = T[v >> 12 & 63];
        out[o++] = i + 1 < n ? T[v >> 6 & 63] : '=';
        out[o++] = i + 2 < n ? T[v & 63] : '=';
    }
    out[o] = '\0';
}

typedef struct {
    uint8_t px[24 * 24 * 2];
    char hash[17];
} face_t;

static void make_face(face_t *f, uint8_t seed)
{
    for (size_t i = 0; i < sizeof(f->px); i++) f->px[i] = (uint8_t)(i * 7 + seed);
    snprintf(f->hash, sizeof(f->hash), "%016llx", (unsigned long long)bm_fnv1a64(f->px, sizeof(f->px)));
}

static bm_err_t send_chunk(const char *host, const face_t *f, int index, int count)
{
    size_t part = sizeof(f->px) / (size_t)count;
    size_t start = part * (size_t)index, len = index == count - 1 ? sizeof(f->px) - start : part;
    char data[1600];
    b64(f->px + start, len, data);
    return send(host, "host.face",
                "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":24,\"h\":24,\"index\":%d,\"count\":%d,\"data\":\"%s\"}",
                f->hash, index, count, data);
}

static void send_face(const char *host, const face_t *f)
{
    for (int i = 0; i < 3; i++) CHECK(send_chunk(host, f, i, 3) == BM_OK);
}

TEST(settings_default_to_silent_and_follow_settings_set)
{
    fresh();
    CHECK(!M.settings.sound && M.settings.volume == 60 && M.settings.brightness == 100);
    outs_t o;
    CHECK(send("work", "settings.set", "{\"sound\":true,\"volume\":0}") == BM_OK);
    CHECK(M.settings.sound && M.settings.volume == 0 && M.settings.brightness == 100);
    drain(&o);
    const bm_out_t *ack = find_out(&o, "device.settings");
    CHECK(ack && ack->hosts == 0xff);
    CHECK(strstr(ack->json, "{\"sound\":true,\"volume\":0,\"brightness\":100}"));
}

TEST(settings_set_out_of_range_changes_nothing)
{
    fresh();
    uint32_t rev = M.settings_rev;
    CHECK(send("work", "settings.set", "{\"volume\":101}") == BM_E_DATA);
    CHECK(send("work", "settings.set", "{\"brightness\":5}") == BM_E_DATA);
    CHECK(send("work", "settings.set", "{}") == BM_E_DATA);
    CHECK(send("work", "settings.set", "{\"sound\":1}") == BM_E_DATA);
    CHECK(M.settings_rev == rev && M.settings.volume == 60);
}

TEST(panel_changes_reach_the_macs_once_the_finger_settles)
{
    fresh();
    outs_t o;
    bm_panel(&M, true, now);
    CHECK(M.panel);
    for (int v = 50; v >= 30; v -= 5) {
        bm_settings_t s = M.settings;
        s.brightness = (uint8_t)v;
        bm_settings_change(&M, &s, now);
        advance(100);
    }
    drain(&o);
    CHECK(count_out(&o, "device.settings") == 0);
    advance(BM_SETTINGS_SETTLE_MS);
    drain(&o);
    CHECK(count_out(&o, "device.settings") == 1);
    CHECK(strstr(find_out(&o, "device.settings")->json, "\"brightness\":30"));
}

TEST(panel_closes_with_the_button_and_blocks_swipes)
{
    fresh();
    bm_panel(&M, true, now);
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_HOME);
    bm_button(&M, true, now);
    bm_button(&M, false, now);
    CHECK(!M.panel);
    CHECK(M.view == BM_VIEW_HOME);
}

TEST(a_mac_hears_the_settings_when_its_link_binds)
{
    fresh();
    bm_link(&M, "work", false, now);
    outs_t o;
    drain(&o);
    bm_conn_t c;
    bm_conn_open(&c);
    char json[600];
    snprintf(json, sizeof(json),
             "{\"v\":1,\"id\":\"01K8F6000000000000000000A1\",\"ts\":%lld,\"host\":\"work\",\"type\":\"snapshot\","
             "\"data\":{" EMPTY_SNAPSHOT "}}",
             BASE_TS);
    CHECK(bm_conn_deliver(&M, &c, json, strlen(json), now) == BM_OK);
    drain(&o);
    const bm_out_t *s = find_out(&o, "device.settings");
    CHECK(s && bm_conn_wants(&c, s));
}

TEST(face_chunks_assemble_and_a_matching_snapshot_asks_for_nothing)
{
    fresh();
    face_t f;
    make_face(&f, 3);
    send_face("work", &f);
    int w = bm__host_slot(&M, "work", false);
    CHECK(M.hosts[w].has_face && M.hosts[w].face.w == 24 && M.hosts[w].face.h == 24);
    CHECK(memcmp(M.hosts[w].face.px, f.px, sizeof(f.px)) == 0);
    outs_t o;
    drain(&o);
    char extra[64];
    snprintf(extra, sizeof(extra), "\"face\":{\"hash\":\"%s\"}", f.hash);
    CHECK(snapshot("work", extra) == BM_OK);
    drain(&o);
    CHECK(count_out(&o, "device.face_request") == 0);
}

TEST(snapshot_with_an_unknown_face_requests_it_from_that_mac)
{
    fresh();
    face_t f;
    make_face(&f, 9);
    char extra[64];
    snprintf(extra, sizeof(extra), "\"face\":{\"hash\":\"%s\"}", f.hash);
    CHECK(snapshot("home", extra) == BM_OK);
    outs_t o;
    drain(&o);
    const bm_out_t *req = find_out(&o, "device.face_request");
    CHECK(req && req->hosts == 1u << bm__host_slot(&M, "home", false));
    CHECK(strstr(req->json, f.hash));
}

TEST(face_with_a_wrong_hash_or_a_gap_is_dropped)
{
    fresh();
    face_t f;
    make_face(&f, 1);
    CHECK(send_chunk("work", &f, 0, 3) == BM_OK);
    CHECK(send_chunk("work", &f, 2, 3) == BM_OK);
    int w = bm__host_slot(&M, "work", false);
    CHECK(!M.hosts[w].has_face);
    face_t g = f;
    g.px[0] ^= 1;
    for (int i = 0; i < 3; i++) send_chunk("work", &g, i, 3);
    g.px[0] ^= 1;
    CHECK(!M.hosts[w].has_face);
    CHECK(send("work", "host.face",
               "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":24,\"h\":24,\"index\":3,\"count\":3,\"data\":\"AAAA\"}",
               f.hash) == BM_E_DATA);
    CHECK(send("work", "host.face",
               "{\"hash\":\"%s\",\"format\":\"png\",\"w\":24,\"h\":24,\"index\":0,\"count\":1,\"data\":\"AAAA\"}",
               f.hash) == BM_E_DATA);
}

TEST(snapshot_without_a_face_and_a_new_mac_in_the_slot_drop_the_face)
{
    fresh();
    face_t f;
    make_face(&f, 5);
    send_face("home", &f);
    int h = bm__host_slot(&M, "home", false);
    CHECK(M.hosts[h].has_face);
    CHECK(snapshot("home", "") == BM_OK);
    CHECK(!M.hosts[h].has_face);

    send_face("home", &f);
    CHECK(M.hosts[h].has_face);
    bm_link(&M, "home", false, now);
    start_session("studio", "s", "p");
    CHECK(bm_faces_count(&M) == 0);
}

TEST(link_times_are_kept_per_mac)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    int64_t t0 = wall_now();
    int w = bm__host_slot(&M, "work", false);
    bm_link(&M, "work", false, now);
    CHECK(M.hosts[w].disconnected_at == t0);
    advance(5000);
    bm_link(&M, "work", true, now);
    CHECK(M.hosts[w].connected_at == t0 + 5);
}

TEST(sleep_rotates_clock_and_faces_or_shows_the_computers)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    advance(BM_IDLE_SLEEP_MS + 1000);
    CHECK(M.sleeping && M.sleep_card == BM_CARD_CLOCK);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == BM_CARD_COMPUTERS);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == BM_CARD_CLOCK);

    face_t f;
    make_face(&f, 2);
    send_face("home", &f);
    int h = bm__host_slot(&M, "home", false);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == h);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == BM_CARD_CLOCK);
    bm_touch_wake(&M, now);
    advance(100);
    CHECK(M.sleep_card == BM_CARD_CLOCK);
}

static const char *const POMO_25 =
    "\"state\":\"running\",\"phase\":\"work\",\"ends_at\":%lld,\"work_min\":25,\"break_min\":5,\"cycle\":0,"
    "\"updated_at\":%lld";

TEST(pomodoro_from_a_mac_is_adopted_and_rebroadcast)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    char fmt[256];
    snprintf(fmt, sizeof(fmt), "{%s}", POMO_25);
    CHECK(send("work", "pomodoro.state", fmt, wall_now() + 1500, wall_now()) == BM_OK);
    CHECK(M.pomo.state == BM_POMO_RUNNING && M.pomo.work_min == 25);
    CHECK(bm_pomo_left_s(&M, now) == 1500);
    outs_t o;
    drain(&o);
    const bm_out_t *b = find_out(&o, "device.pomodoro");
    CHECK(b && b->hosts == 0xff);
}

TEST(pomodoro_counts_alone_and_flips_phases_with_a_cue)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    bm_link(&M, "work", false, now);
    bm_link(&M, "home", false, now);
    M.view = BM_VIEW_POMODORO;
    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    CHECK(M.pomo.state == BM_POMO_RUNNING);
    int64_t first_end = M.pomo.ends_at;
    advance(25 * 60 * 1000);
    CHECK(M.pomo.on_break && M.pomo.cycle == 1 && M.pomo.ends_at == first_end + 5 * 60);
    CHECK(heard(BM_SND_DONE));
    advance(5 * 60 * 1000);
    CHECK(!M.pomo.on_break && M.pomo.cycle == 1);
    CHECK(heard(BM_SND_START));
}

TEST(pomodoro_pause_resume_reset_and_durations)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    bm_tap(&M, BM_TAP_POMO_WORK, 1, now);
    bm_tap(&M, BM_TAP_POMO_BREAK, -1, now);
    CHECK(M.pomo.work_min == 30 && M.pomo.break_min == 4);
    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    advance(60000);
    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    CHECK(M.pomo.state == BM_POMO_PAUSED && M.pomo.left_s == 29 * 60);
    bm_tap(&M, BM_TAP_POMO_WORK, 1, now);
    CHECK(M.pomo.work_min == 30);
    advance(600000);
    CHECK(bm_pomo_left_s(&M, now) == 29 * 60);
    bm_touch_wake(&M, now);
    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    CHECK(M.pomo.ends_at == wall_now() + 29 * 60);
    bm_tap(&M, BM_TAP_POMO_RESET, 0, now);
    CHECK(M.pomo.state == BM_POMO_STOPPED && M.pomo.cycle == 0 && bm_pomo_left_s(&M, now) == 30 * 60);
    CHECK(M.pomo.updated_at == wall_now());
}

TEST(pomodoro_newer_on_the_buddy_wins_over_a_snapshot)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    int64_t mine = M.pomo.updated_at;
    outs_t o;
    drain(&o);
    char extra[300];
    snprintf(extra, sizeof(extra),
             "\"pomodoro\":{\"state\":\"stopped\",\"phase\":\"work\",\"work_min\":50,\"break_min\":10,\"cycle\":0,"
             "\"updated_at\":%lld}",
             mine - 100);
    CHECK(snapshot("home", extra) == BM_OK);
    CHECK(M.pomo.state == BM_POMO_RUNNING && M.pomo.work_min == 25);
    drain(&o);
    const bm_out_t *back = find_out(&o, "device.pomodoro");
    CHECK(back && back->hosts == 1u << bm__host_slot(&M, "home", false));

    snprintf(extra, sizeof(extra),
             "\"pomodoro\":{\"state\":\"stopped\",\"phase\":\"work\",\"work_min\":50,\"break_min\":10,\"cycle\":0,"
             "\"updated_at\":%lld}",
             mine + 100);
    CHECK(snapshot("home", extra) == BM_OK);
    CHECK(M.pomo.state == BM_POMO_STOPPED && M.pomo.work_min == 50);
}

TEST(pomodoro_running_through_a_long_gap_catches_up)
{
    fresh();
    CHECK(snapshot("work", "") == BM_OK);
    char fmt[256];
    snprintf(fmt, sizeof(fmt), "{%s}", POMO_25);
    int64_t t = wall_now();
    CHECK(send("work", "pomodoro.state", fmt, t - 3500, t) == BM_OK);
    CHECK(M.pomo.cycle == 2 && !M.pomo.on_break);
    CHECK(M.pomo.ends_at == t + 100);
}

TEST(pomodoro_invalid_shapes_are_rejected)
{
    fresh();
    CHECK(send("work", "pomodoro.state",
               "{\"state\":\"running\",\"phase\":\"work\",\"work_min\":25,\"break_min\":5,\"cycle\":0,"
               "\"updated_at\":1}") == BM_E_DATA);
    CHECK(send("work", "pomodoro.state",
               "{\"state\":\"stopped\",\"phase\":\"work\",\"left_s\":3,\"work_min\":25,\"break_min\":5,\"cycle\":0,"
               "\"updated_at\":1}") == BM_E_DATA);
    CHECK(send("work", "pomodoro.state",
               "{\"state\":\"stopped\",\"phase\":\"nap\",\"work_min\":25,\"break_min\":5,\"cycle\":0,"
               "\"updated_at\":1}") == BM_E_DATA);
    CHECK(send("work", "pomodoro.state",
               "{\"state\":\"stopped\",\"phase\":\"work\",\"work_min\":91,\"break_min\":5,\"cycle\":0,"
               "\"updated_at\":1}") == BM_E_DATA);
}

TEST(paused_music_stays_put_and_controls_go_to_the_playing_mac)
{
    fresh();
    outs_t o;
    CHECK(send("home", "media.now_playing",
               "{\"title\":\"Song\",\"artist\":\"A\",\"length_s\":200,\"position_s\":20,\"playing\":false}") == BM_OK);
    int h = bm__host_slot(&M, "home", false);
    advance(10000);
    CHECK(bm_media_position_s(&M.hosts[h].media, now) == 20);
    CHECK(!heard(BM_SND_MEDIA));
    CHECK(send("home", "media.now_playing",
               "{\"title\":\"Song\",\"artist\":\"A\",\"length_s\":200,\"position_s\":20,\"playing\":true}") == BM_OK);
    CHECK(heard(BM_SND_MEDIA));
    CHECK(send("home", "media.now_playing",
               "{\"title\":\"Song\",\"artist\":\"A\",\"length_s\":200,\"position_s\":25,\"playing\":true}") == BM_OK);
    CHECK(!heard(BM_SND_MEDIA));
    drain(&o);
    bm_tap(&M, BM_TAP_MEDIA, BM_MEDIA_NEXT, now);
    drain(&o);
    const bm_out_t *c = find_out(&o, "media.control");
    CHECK(c && c->hosts == 1u << h && strstr(c->json, "\"action\":\"next\""));
    bm_link(&M, "home", false, now);
    drain(&o);
    bm_tap(&M, BM_TAP_MEDIA, BM_MEDIA_PLAY_PAUSE, now);
    drain(&o);
    CHECK(count_out(&o, "media.control") == 0);
}

TEST(base64_decoder_rejects_bad_input)
{
    uint8_t out[8];
    CHECK(bm_base64_decode("TWFu", out, sizeof(out)) == 3 && memcmp(out, "Man", 3) == 0);
    CHECK(bm_base64_decode("TWE=", out, sizeof(out)) == 2);
    CHECK(bm_base64_decode("TQ==", out, sizeof(out)) == 1);
    CHECK(bm_base64_decode("TQ=A", out, sizeof(out)) == 0);
    CHECK(bm_base64_decode("T*==", out, sizeof(out)) == 0);
    CHECK(bm_base64_decode("TWFuTWFuTWFu", out, sizeof(out)) == 0);
    CHECK(bm_base64_decode("TWF", out, sizeof(out)) == 0);
}
