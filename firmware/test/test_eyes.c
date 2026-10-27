#include <math.h>

#include "bm_eyes.h"
#include "support.h"

static uint32_t seed;

static uint32_t rnd(void *ctx)
{
    (void)ctx;
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}

static bm_eyes_t E;
static uint32_t t;

static void eyes_fresh(bm_mood_t mood)
{
    seed = 2463534242u;
    memset(&E, 0, sizeof(E));
    t = 1000;
    bm_eyes_tick(&E, mood, t, rnd, NULL);
}

static void eyes_run(bm_mood_t mood, uint32_t ms)
{
    for (uint32_t end = t + ms; t < end;) {
        t += 10;
        bm_eyes_tick(&E, mood, t, rnd, NULL);
    }
}

static void mask(bm_eye_shape_t shape, float open, int side, char *out)
{
    uint8_t cells[BM_EYES_FACE_W * BM_EYES_FACE_H];
    bm_eye_cells(cells, BM_EYES_FACE_W, BM_EYES_FACE_H, open, shape, side);
    for (int y = 0; y < BM_EYES_FACE_H; y++) {
        for (int x = 0; x < BM_EYES_FACE_W; x++) *out++ = cells[y * BM_EYES_FACE_W + x] ? 'X' : '.';
        *out++ = '/';
    }
    *out = '\0';
}

static int ink(bm_eye_shape_t shape, float open, int w, int h)
{
    uint8_t cells[BM_EYES_FACE_W * BM_EYES_FACE_H];
    bm_eye_cells(cells, w, h, open, shape, -1);
    int n = 0;
    for (int i = 0; i < w * h; i++) n += cells[i];
    return n;
}

TEST(each_mood_has_the_prototype_pool)
{
    CHECK(bm_eyes_pool_size(BM_MOOD_IDLE) == 8);
    CHECK(bm_eyes_pool_size(BM_MOOD_WORKING) == 7);
    CHECK(bm_eyes_pool_size(BM_MOOD_WAITING) == 5);
    CHECK(bm_eyes_pool_size(BM_MOOD_DONE) == 4);
    CHECK(bm_eyes_pool_size(BM_MOOD_SLEEP) == 3);
    CHECK_STR(bm_eyes_beat_name(BM_MOOD_WORKING, 1), "deep focus");
}

TEST(beats_never_repeat_the_last_one_and_cover_the_pool)
{
    for (bm_mood_t mood = BM_MOOD_IDLE; mood < BM_MOODS; mood++) {
        eyes_fresh(mood);
        uint32_t started = E.beats_started;
        int last = -1, seen = 0, beats = 0;
        for (int i = 0; i < 60000 && beats < 100; i++) {
            eyes_run(mood, 10);
            if (E.beats_started == started) continue;
            started = E.beats_started;
            CHECK(E.beat != last);
            last = E.beat;
            seen |= 1 << E.beat;
            beats++;
        }
        CHECK(beats == 100);
        CHECK(seen == (1 << bm_eyes_pool_size(mood)) - 1);
    }
}

TEST(working_rests_lower_and_half_open)
{
    eyes_fresh(BM_MOOD_WORKING);
    CHECK(E.target.gy == 1 && E.target.open[0] == 60 && E.target.shape[0] == BM_EYE_OPEN);
    eyes_fresh(BM_MOOD_WAITING);
    CHECK(E.target.shape[0] == BM_EYE_WORRIED && E.target.open[1] == 90);
}

TEST(a_beat_starts_300_to_900_ms_after_a_mood_and_gaze_moves_in_whole_cells)
{
    eyes_fresh(BM_MOOD_IDLE);
    eyes_run(BM_MOOD_IDLE, 290);
    CHECK(E.beats_started == 0);
    eyes_run(BM_MOOD_IDLE, 620);
    CHECK(E.beats_started == 1);
    for (int i = 0; i < 2000; i++) {
        eyes_run(BM_MOOD_IDLE, 10);
        CHECK(E.out.gx >= -3 && E.out.gx <= 3 && E.out.gy >= -2 && E.out.gy <= 3);
    }
}

TEST(idle_blinks_every_2_to_6_s_and_sleep_never_blinks)
{
    eyes_fresh(BM_MOOD_IDLE);
    eyes_run(BM_MOOD_IDLE, 60000);
    CHECK(E.blinks_done >= 60 / 6 && E.blinks_done <= 60 / 2 + 2 * 12);
    eyes_fresh(BM_MOOD_SLEEP);
    eyes_run(BM_MOOD_SLEEP, 60000);
    CHECK(E.blinks_done == 0);
}

TEST(a_blink_closes_open_eyes_but_not_happy_ones)
{
    eyes_fresh(BM_MOOD_IDLE);
    float least = 1;
    for (int i = 0; i < 800; i++) {
        eyes_run(BM_MOOD_IDLE, 10);
        if (E.out.shape[0] == BM_EYE_OPEN && E.out.open[0] < least) least = E.out.open[0];
    }
    CHECK(least < 0.2f);
    eyes_fresh(BM_MOOD_DONE);
    for (int i = 0; i < 300; i++) {
        eyes_run(BM_MOOD_DONE, 10);
        if (E.out.shape[0] == BM_EYE_HAPPY) CHECK(E.out.open[0] > 0.99f);
    }
}

TEST(done_holds_4_s_then_follows_the_state_but_sleep_wins_at_once)
{
    eyes_fresh(BM_MOOD_IDLE);
    eyes_run(BM_MOOD_DONE, 100);
    CHECK(E.mood == BM_MOOD_DONE);
    eyes_run(BM_MOOD_IDLE, BM_EYES_DONE_MS - 200);
    CHECK(E.mood == BM_MOOD_DONE);
    eyes_run(BM_MOOD_IDLE, 200);
    CHECK(E.mood == BM_MOOD_IDLE);
    eyes_run(BM_MOOD_DONE, 100);
    eyes_run(BM_MOOD_SLEEP, 10);
    CHECK(E.mood == BM_MOOD_SLEEP);
}

TEST(done_bounces_and_sparkles_once_it_starts)
{
    eyes_fresh(BM_MOOD_IDLE);
    eyes_run(BM_MOOD_DONE, 10);
    int lifted = 0;
    for (int i = 0; i < 150; i++) {
        eyes_run(BM_MOOD_DONE, 10);
        lifted += E.out.gy < 0;
    }
    CHECK(lifted > 20);
    for (int i = 0; i < BM_EYES_SPARKS; i++) {
        CHECK(E.sparks[i].at_ms != 0);
        CHECK(E.sparks[i].x >= 4 && E.sparks[i].x <= BM_EYES_GRID - 5 && E.sparks[i].y >= 4 && E.sparks[i].y <= 33);
    }
}

TEST(sleeping_eyes_breathe_one_cell)
{
    eyes_fresh(BM_MOOD_SLEEP);
    int lo = 0, hi = 0;
    for (int i = 0; i < 1000; i++) {
        eyes_run(BM_MOOD_SLEEP, 10);
        if (E.beat < 0) {
            lo = E.out.gy < lo ? E.out.gy : lo;
            hi = E.out.gy > hi ? E.out.gy : hi;
        }
    }
    CHECK(lo == -1 && hi == 1);
}

TEST(a_reaction_waits_for_its_start_then_returns_to_the_mood)
{
    eyes_fresh(BM_MOOD_WORKING);
    bm_eyes_react(&E, BM_REACT_HAPPY, t + 500);
    eyes_run(BM_MOOD_WORKING, 490);
    CHECK(E.react == BM_REACT_NONE);
    eyes_run(BM_MOOD_WORKING, 20);
    CHECK(E.react == BM_REACT_HAPPY && E.out.shape[0] == BM_EYE_HAPPY && E.out.shape[1] == BM_EYE_HAPPY);
    eyes_run(BM_MOOD_WORKING, 1100);
    CHECK(E.react == BM_REACT_NONE && E.beat < 0 && E.out.shape[0] != BM_EYE_HAPPY);

    bm_eyes_react(&E, BM_REACT_GLANCE, t);
    eyes_run(BM_MOOD_WORKING, 10);
    CHECK(E.out.gx == -3 && E.out.shape[0] == BM_EYE_WORRIED);

    eyes_run(BM_MOOD_WORKING, 1000);
    uint32_t blinks = E.blinks_done;
    bm_eyes_react(&E, BM_REACT_BLINK, t);
    eyes_run(BM_MOOD_WORKING, 300);
    CHECK(E.blinks_done == blinks + 1);
}

TEST(shapes_match_the_prototype_cells)
{
    char m[16 * 10 + 1];
#define E9 "........./"
    mask(BM_EYE_HAPPY, 1, -1, m);
    CHECK_STR(m, E9 E9 E9 E9 E9 "...XX..../..XXXX.../.XXXXXX../XXX..XXX./XX....XX./" E9 E9 E9 E9 E9 E9);
    mask(BM_EYE_SQUEEZE, 1, -1, m);
    CHECK_STR(m, E9 E9 E9 ".XX....../.XXX...../..XXX..../...XXX.../....XXX../"
                 "....XXX../...XXX.../..XXX..../.XXX...../.XX....../" E9 E9 E9);
    mask(BM_EYE_OPEN, 1, -1, m);
    CHECK(strncmp(m, ".XXXXXXX./XXXXXXXXX/", 20) == 0 && strcmp(m + 150, ".XXXXXXX./") == 0);
    mask(BM_EYE_WORRIED, 1, -1, m);
    CHECK(strncmp(m, ".....XXX./.....XXXX/XXXXXXXXX/", 30) == 0);
    mask(BM_EYE_WORRIED, 1, 1, m);
    CHECK(strncmp(m, ".XXX...../XXXX...../XXXXXXXXX/", 30) == 0);
    mask(BM_EYE_SLEEP, 0, -1, m);
    CHECK_STR(m, E9 E9 E9 E9 E9 E9 E9 E9 E9 "XX.....XX/XXXXXXXXX/..XXXXX../" E9 E9 E9 E9);
#undef E9
}

TEST(strokes_are_two_cells_and_every_shape_fits_its_box)
{
    CHECK(ink(BM_EYE_DOT, 1, 9, 16) == 16);
    CHECK(ink(BM_EYE_DASH, 1, 9, 16) == 14);
    CHECK(ink(BM_EYE_SQUARE, 1, 9, 16) == 9 * 9 - 5 * 5);
    CHECK(ink(BM_EYE_HEART, 1, 9, 16) == 46);
    CHECK(ink(BM_EYE_HEART, 1, 4, 7) == ink(BM_EYE_DOT, 1, 4, 7));
    CHECK(ink(BM_EYE_OPEN, 0.6f, 9, 16) == 9 * 10 - 4);
    CHECK(ink(BM_EYE_OPEN, 0.05f, 9, 16) == ink(BM_EYE_OPEN, 0, 9, 16));
    CHECK(ink(BM_EYE_SLEEP, 0, 4, 7) == 4);
    CHECK(ink(BM_EYE_WORRIED, 1, 3, 6) == 3 * 6 - 2);
}

TEST(the_buddy_starts_on_the_face_and_returns_to_it_after_20_s_without_a_touch)
{
    fresh();
    CHECK(M.view == BM_VIEW_FACE);
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_HOME);
    advance(BM_FACE_RETURN_MS - 200);
    CHECK(M.view == BM_VIEW_HOME);
    start_session("work", "s", "alpha");
    advance(200);
    CHECK(M.view == BM_VIEW_FACE);
    bm_swipe(&M, -1, now);
    CHECK(M.view == BM_VIEW_POMODORO);
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_FACE);
}

TEST(a_sheet_or_the_panel_keeps_the_view)
{
    fresh();
    bm_swipe(&M, 1, now);
    bm_tap(&M, BM_TAP_USAGE, 0, now);
    advance(BM_FACE_RETURN_MS + 1000);
    CHECK(M.view == BM_VIEW_HOME && M.sheet == BM_SHEET_USAGE);
    bm_tap(&M, BM_TAP_BACK, 0, now);
    bm_panel(&M, true, now);
    advance(BM_FACE_RETURN_MS + 1000);
    CHECK(M.view == BM_VIEW_HOME && M.panel);
    bm_panel(&M, false, now);
    advance(BM_FACE_RETURN_MS);
    CHECK(M.view == BM_VIEW_FACE);
}

static void settled(void)
{
    fresh();
    advance(BM_EYES_DONE_MS);
}

TEST(the_face_follows_the_agents)
{
    settled();
    CHECK(M.eyes.mood == BM_MOOD_IDLE);
    start_session("work", "s", "alpha");
    advance(100);
    CHECK(M.eyes.mood == BM_MOOD_WORKING);
    CHECK(send("work", "agent.task_done", "{\"session\":\"s\",\"summary\":\"ok\"}") == BM_OK);
    advance(100);
    CHECK(M.eyes.mood == BM_MOOD_DONE);
    advance(BM_EYES_DONE_MS);
    CHECK(M.eyes.mood == BM_MOOD_IDLE);
    advance(BM_IDLE_SLEEP_MS);
    CHECK(M.sleeping && M.eyes.mood == BM_MOOD_SLEEP);
}

#define RID "01K8F5REQ0000000000000000A"


TEST(the_face_sees_the_request_before_the_alert_shows)
{
    settled();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    CHECK(bm_attn_session(&M) && !bm_attn_shown(&M));
    advance(BM_EYES_SEES_MS - 80);
    CHECK(!bm_attn_shown(&M) && M.eyes.react == BM_REACT_SEES);
    CHECK(M.eyes.out.shape[0] == BM_EYE_OPEN && M.eyes.out.shape[1] == BM_EYE_OPEN && M.eyes.out.gy == 3);
    advance(100);
    CHECK(bm_attn_shown(&M) != NULL);

    settled();
    bm_swipe(&M, 1, now);
    CHECK(M.view == BM_VIEW_HOME);
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    CHECK(bm_attn_shown(&M) != NULL && M.eyes.react_pending != BM_REACT_SEES);
}

TEST(an_alert_takes_the_face_and_the_eyes_react_when_it_closes)
{
    settled();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    advance(100);
    CHECK(M.view == BM_VIEW_FACE && bm_attn_session(&M) && M.eyes.mood == BM_MOOD_WAITING);
    advance(BM_FACE_RETURN_MS + 1000);
    CHECK(bm_attn_session(&M) != NULL);

    CHECK(bm_hold_begin(&M, now));
    advance(BM_HOLD_MS + 100);
    CHECK(!bm_attn_session(&M) && M.ov.type == BM_OV_APPROVED);
    CHECK(M.eyes.react_pending == BM_REACT_HAPPY && M.eyes.react_at_ms == M.ov.until_ms);

    settled();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    bm_tap(&M, BM_TAP_LATER, 0, now);
    CHECK(M.eyes.react_pending == BM_REACT_GLANCE && M.eyes.react_at_ms == now + BM_EYES_REACT_DELAY_MS);
    advance(BM_EYES_REACT_DELAY_MS + 100);
    CHECK(M.eyes.react == BM_REACT_GLANCE);

    settled();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    bm_tap(&M, BM_TAP_DENY, 0, now);
    CHECK(M.eyes.react_pending == BM_REACT_BLINK);
}

TEST(the_alert_card_slides_up_after_the_face_sees_it_and_down_when_it_closes)
{
    settled();
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    CHECK(bm_attn_slide(&M, now) == 1 && !bm_attn_leaving(&M, now));
    advance(400);
    CHECK(bm_attn_shown(&M) && bm_attn_slide(&M, now) == 1);
    CHECK(fabsf(bm_attn_slide(&M, now + BM_ATTN_SLIDE_MS / 2) - 0.5f) < 0.01f);
    advance(BM_ATTN_SLIDE_MS);
    CHECK(bm_attn_slide(&M, now) == 0);

    CHECK(bm_hold_begin(&M, now));
    advance(BM_HOLD_MS);
    CHECK(!bm_attn_shown(&M) && bm_attn_leaving(&M, now) && bm_attn_slide(&M, now) == 0);
    CHECK(fabsf(bm_attn_slide(&M, now + BM_ATTN_SLIDE_MS / 2) - 0.5f) < 0.01f);
    advance(BM_ATTN_SLIDE_MS);
    CHECK(!bm_attn_leaving(&M, now) && bm_attn_slide(&M, now) == 1);

    settled();
    bm_swipe(&M, 1, now);
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    CHECK(bm_attn_shown(&M) && bm_attn_slide(&M, now) == 1);
    advance(200);
    CHECK(bm_attn_slide(&M, now) > 0 && bm_attn_slide(&M, now) < 1);
}

static void sleep_now(void)
{
    while (!M.sleeping) advance(100);
}

TEST(falling_asleep_on_the_face_cross_fades_to_the_sleep_screen_and_back)
{
    settled();
    sleep_now();
    CHECK(M.rest == 0);
    advance(BM_REST_DELAY_MS - 100);
    CHECK(M.rest == 0);
    advance(100);
    CHECK(M.rest > 0 && M.rest < 1);
    advance(2000);
    CHECK(M.rest == 1);

    bm_touch_wake(&M, now);
    CHECK(!M.sleeping && M.view == BM_VIEW_FACE);
    advance(100);
    CHECK(M.rest > 0 && M.rest < 1);
    advance(2000);
    CHECK(M.rest == 0);

    sleep_now();
    advance(BM_REST_DELAY_MS + 200);
    start_session("work", "s", "alpha");
    ask_permission("work", "s", RID, "low", true);
    advance(BM_REMIND_MS);
    CHECK(!M.sleeping && bm_attn_session(&M) && M.rest == 0);
}

TEST(sleep_from_another_view_or_an_overlay_switches_at_once)
{
    settled();
    bm_swipe(&M, 1, now);
    bm_button(&M, true, now);
    advance(BM_LONG_PRESS_MS + 100);
    bm_button(&M, false, now);
    CHECK(M.sleeping && M.view == BM_VIEW_HOME && M.rest == 1);
    bm_touch_wake(&M, now);
    advance(100);
    CHECK(M.rest == 0);
}
