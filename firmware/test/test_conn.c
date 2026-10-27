#include "bm_conn.h"
#include "bm_frame.h"
#include "support.h"

static bm_conn_t A, B;
static bm_reasm_t RA, RB;
static uint8_t seq;
static uint32_t conn_counter;

static bm_err_t deliver(bm_conn_t *c, const char *host, const char *session)
{
    char json[512];
    snprintf(json, sizeof(json),
             "{\"v\":1,\"id\":\"01K8F6%020u\",\"ts\":%lld,\"host\":\"%s\",\"type\":\"session.start\","
             "\"data\":{\"session\":\"%s\",\"project\":\"p\",\"task\":\"t\"}}",
             ++conn_counter, BASE_TS + now / 1000, host, session);
    size_t len = strlen(json);
    int count;
    CHECK(bm_frame_count(len, 40, &count) == BM_FRAME_OK && count > 1);
    bm_err_t err = BM_E_JSON;
    for (int i = 0; i < count; i++) {
        uint8_t frame[40];
        size_t n = bm_frame_build((const uint8_t *)json, len, seq, 40, i, frame);
        size_t out_len;
        const char *out = bm_reasm_push(c == &A ? &RA : &RB, frame, n, &out_len);
        CHECK((out != NULL) == (i == count - 1));
        if (out) err = bm_conn_deliver(&M, c, out, out_len, now);
    }
    seq++;
    return err;
}

static void unlinked(void)
{
    now = 1000;
    bm_config_t cfg = {0};
    bm_init(&M, &cfg, now);
    bm_conn_open(&A);
    bm_conn_open(&B);
    bm_reasm_reset(&RA);
    bm_reasm_reset(&RB);
}

static int slot_of(const char *host)
{
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (M.hosts[i].used && strcmp(M.hosts[i].name, host) == 0) return i;
    return -1;
}

TEST(connection_binds_to_the_host_of_its_first_message)
{
    unlinked();
    CHECK(deliver(&A, "work", "s1") == BM_OK);
    CHECK(A.slot == slot_of("work") && A.slot >= 0);
    CHECK(M.hosts[A.slot].connected);
    CHECK(M.ov.type == BM_OV_CONN && M.ov.on);
}

TEST(bound_connection_cannot_speak_for_another_host)
{
    unlinked();
    CHECK(deliver(&A, "work", "s1") == BM_OK);
    CHECK(deliver(&A, "home", "s2") == BM_E_HOST_BOUND);
    CHECK(slot_of("home") < 0);
    CHECK(session_index("home", "s2") < 0);
}

TEST(second_connection_cannot_claim_a_connected_host)
{
    unlinked();
    CHECK(deliver(&A, "work", "s1") == BM_OK);
    CHECK(deliver(&B, "work", "s2") == BM_E_HOST_BOUND);
    CHECK(B.slot < 0);
    CHECK(deliver(&B, "home", "s3") == BM_OK);
    CHECK(B.slot == slot_of("home") && B.slot != A.slot);
}

TEST(closing_unlinks_and_a_new_connection_can_rebind)
{
    unlinked();
    CHECK(deliver(&A, "work", "s1") == BM_OK);
    int slot = A.slot;
    bm_conn_close(&M, &A, now);
    CHECK(!M.hosts[slot].connected && !M.ov.on);
    bm_conn_open(&B);
    CHECK(deliver(&B, "work", "s2") == BM_OK);
    CHECK(B.slot == slot && M.hosts[slot].connected);
}

TEST(closed_connection_rejects_messages)
{
    unlinked();
    bm_conn_close(&M, &A, now);
    CHECK(deliver(&A, "work", "s1") == BM_E_HOST_BOUND);
    CHECK(slot_of("work") < 0);
}

TEST(outgoing_messages_go_only_to_their_hosts)
{
    unlinked();
    CHECK(deliver(&A, "work", "s1") == BM_OK);
    CHECK(deliver(&B, "home", "s2") == BM_OK);
    bm_out_t only_a = {.hosts = (uint8_t)(1u << A.slot)}, all = {.hosts = 0xff};
    CHECK(bm_conn_wants(&A, &only_a) && !bm_conn_wants(&B, &only_a));
    CHECK(bm_conn_wants(&A, &all) && bm_conn_wants(&B, &all));
    bm_conn_t fresh_conn;
    bm_conn_open(&fresh_conn);
    CHECK(!bm_conn_wants(&fresh_conn, &all));
}

static void hold_button(uint32_t ms)
{
    bm_button(&M, true, now);
    advance(ms);
    bm_button(&M, false, now);
}

TEST(holding_the_button_on_the_face_or_home_starts_pairing)
{
    fresh();
    hold_button(BM_PAIRING_HOLD_MS + 100);
    CHECK(M.pairing && !M.sleeping && !M.passkey_shown);
    CHECK(M.view == BM_VIEW_FACE);
    outs_t o;
    drain(&o);
    CHECK(find_out(&o, "device.sleep") && find_out(&o, "device.wake"));
}

TEST(pairing_needs_the_face_or_home)
{
    fresh();
    bm_swipe(&M, 1, now);
    bm_swipe(&M, 1, now);
    hold_button(BM_PAIRING_HOLD_MS + 100);
    CHECK(!M.pairing);
}

TEST(pairing_times_out_and_blocks_idle_sleep)
{
    fresh();
    bm_pairing_start(&M, now);
    advance(BM_PAIRING_MS - 100);
    CHECK(M.pairing && !M.sleeping);
    advance(200);
    CHECK(!M.pairing);
    CHECK_STR(M.toast, "Pairing timed out");
}

TEST(passkey_keeps_the_window_open_long_enough)
{
    fresh();
    bm_pairing_start(&M, now);
    advance(BM_PAIRING_MS - 1000);
    bm_pairing_passkey(&M, 1234567, now);
    CHECK(M.passkey_shown && M.passkey == 234567);
    advance(BM_PASSKEY_MS - 100);
    CHECK(M.pairing);
    bm_pairing_end(&M, BM_PAIR_OK, now);
    CHECK(!M.pairing && M.passkey == 0);
    CHECK_STR(M.toast, "Paired with a new Mac");
}

TEST(passkey_outside_pairing_is_ignored)
{
    fresh();
    bm_pairing_passkey(&M, 123456, now);
    CHECK(!M.passkey_shown);
}

TEST(side_press_cancels_pairing)
{
    fresh();
    bm_pairing_start(&M, now);
    hold_button(100);
    CHECK(!M.pairing && M.view == BM_VIEW_FACE);
    CHECK(M.toast[0] == '\0');
}
