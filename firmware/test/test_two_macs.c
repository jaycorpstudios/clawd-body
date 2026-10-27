#include <stdarg.h>

#include "bm_conn.h"
#include "bm_internal.h"
#include "support.h"

#define SIDE 16

static bm_conn_t A, B, C;
static uint32_t counter;

typedef struct {
    uint8_t px[SIDE * SIDE * 2];
    char hash[17];
    char b64[SIDE * SIDE * 4];
} face_t;

static bm_err_t over(bm_conn_t *c, const char *host, const char *type, const char *fmt, ...)
    __attribute__((format(printf, 4, 5)));

static bm_err_t over(bm_conn_t *c, const char *host, const char *type, const char *fmt, ...)
{
    char data[2048], json[2400];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(data, sizeof(data), fmt, ap);
    va_end(ap);
    snprintf(json, sizeof(json), "{\"v\":1,\"id\":\"01K8F7%020u\",\"ts\":%lld,\"host\":\"%s\",\"type\":\"%s\",\"data\":%s}",
             ++counter, BASE_TS + now / 1000, host, type, data);
    bm_err_t err = bm_conn_deliver(&M, c, json, strlen(json), now);
    outs_t o;
    drain(&o);
    return err;
}

static void make_face(face_t *f, uint8_t seed)
{
    static const char T[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (size_t i = 0; i < sizeof(f->px); i++) f->px[i] = (uint8_t)(i * 13 + seed);
    snprintf(f->hash, sizeof(f->hash), "%016llx", (unsigned long long)bm_fnv1a64(f->px, sizeof(f->px)));
    size_t o = 0, n = sizeof(f->px);
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)f->px[i] << 16 | (i + 1 < n ? (uint32_t)f->px[i + 1] << 8 : 0) |
                     (i + 2 < n ? f->px[i + 2] : 0);
        f->b64[o++] = T[v >> 18 & 63];
        f->b64[o++] = T[v >> 12 & 63];
        f->b64[o++] = i + 1 < n ? T[v >> 6 & 63] : '=';
        f->b64[o++] = i + 2 < n ? T[v & 63] : '=';
    }
    f->b64[o] = '\0';
}

static bm_err_t give_face(bm_conn_t *c, const char *host, const face_t *f)
{
    return over(c, host, "host.face",
                "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":%d,\"h\":%d,\"index\":0,\"count\":1,\"data\":\"%s\"}",
                f->hash, SIDE, SIDE, f->b64);
}

static bm_err_t snapshot_with_face(bm_conn_t *c, const char *host, const face_t *f)
{
    return over(c, host, "snapshot",
                "{\"sessions\":[{\"session\":\"s-%s\",\"project\":\"p-%s\",\"task\":\"t\",\"status\":\"working\","
                "\"since\":%lld}],\"usage\":{\"session_pct\":10,\"weekly_pct\":5,\"reset_in_min\":100},"
                "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]},\"face\":{\"hash\":\"%s\"}}",
                host, host, BASE_TS + now / 1000, f->hash);
}

static int slot_of(const char *host)
{
    return bm__host_slot(&M, host, false);
}

static void two_macs_with_faces(face_t *fw, face_t *fh)
{
    now = 1000;
    bm_config_t cfg = {0};
    bm_init(&M, &cfg, now);
    bm_conn_open(&A);
    bm_conn_open(&B);
    make_face(fw, 1);
    make_face(fh, 2);
    CHECK(snapshot_with_face(&A, "work", fw) == BM_OK);
    CHECK(snapshot_with_face(&B, "home", fh) == BM_OK);
    CHECK(give_face(&A, "work", fw) == BM_OK);
    CHECK(give_face(&B, "home", fh) == BM_OK);
}

TEST(two_macs_each_keep_their_own_face)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    int w = slot_of("work"), h = slot_of("home");
    CHECK(w >= 0 && h >= 0 && w != h);
    CHECK(A.slot == w && B.slot == h);
    CHECK(bm_faces_count(&M) == 2);
    CHECK_STR(M.hosts[w].face.hash, fw.hash);
    CHECK_STR(M.hosts[h].face.hash, fh.hash);
    CHECK(memcmp(M.hosts[w].face.px, fw.px, sizeof(fw.px)) == 0);
    CHECK(memcmp(M.hosts[h].face.px, fh.px, sizeof(fh.px)) == 0);
    CHECK(bm_session_count(&M) == 2);
}

TEST(face_from_one_mac_cannot_land_on_the_other)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    face_t other;
    make_face(&other, 9);
    CHECK(give_face(&A, "home", &other) == BM_E_HOST_BOUND);
    CHECK_STR(M.hosts[slot_of("home")].face.hash, fh.hash);
}

TEST(sleep_rotates_through_both_macs_in_slot_order)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    advance(BM_IDLE_SLEEP_MS + 1000);
    CHECK(M.sleeping && M.sleep_card == BM_CARD_CLOCK);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == 0);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == 1);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == BM_CARD_CLOCK);
}

TEST(a_disconnected_mac_keeps_its_face_until_a_new_mac_needs_the_slot)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    int w = slot_of("work");
    bm_conn_close(&M, &A, now);
    CHECK(!M.hosts[w].connected && M.hosts[w].has_face && M.hosts[w].disconnected_at);
    CHECK(bm_faces_count(&M) == 2);

    bm_conn_open(&C);
    face_t fs;
    make_face(&fs, 3);
    CHECK(snapshot_with_face(&C, "studio", &fs) == BM_OK);
    CHECK(C.slot == w && slot_of("work") < 0);
    CHECK(!M.hosts[w].has_face);
    CHECK(session_index("work", "s-work") < 0 && bm_session_count(&M) == 2);
    CHECK(bm_faces_count(&M) == 1);
    CHECK_STR(M.hosts[slot_of("home")].face.hash, fh.hash);
}

TEST(the_new_mac_is_asked_for_its_face_and_only_it)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    int w = slot_of("work");
    bm_conn_close(&M, &A, now);
    bm_conn_open(&C);
    face_t fs;
    make_face(&fs, 3);
    char json[600];
    snprintf(json, sizeof(json),
             "{\"v\":1,\"id\":\"01K8F7%020u\",\"ts\":%lld,\"host\":\"studio\",\"type\":\"snapshot\",\"data\":{"
             "\"sessions\":[],\"usage\":{\"session_pct\":1,\"weekly_pct\":1,\"reset_in_min\":1},"
             "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]},\"face\":{\"hash\":\"%s\"}}}",
             ++counter, BASE_TS + now / 1000, fs.hash);
    CHECK(bm_conn_deliver(&M, &C, json, strlen(json), now) == BM_OK);
    outs_t o;
    drain(&o);
    const bm_out_t *ask = find_out(&o, "device.face_request");
    CHECK(ask && ask->hosts == 1u << w);
    CHECK(bm_conn_wants(&C, ask) && !bm_conn_wants(&B, ask));
    CHECK(strstr(ask->json, fs.hash));
    CHECK(give_face(&C, "studio", &fs) == BM_OK);
    CHECK(bm_faces_count(&M) == 2);
}

TEST(both_slots_connected_turn_a_third_mac_away)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    bm_conn_open(&C);
    face_t fs;
    make_face(&fs, 3);
    CHECK(snapshot_with_face(&C, "studio", &fs) == BM_E_HOSTS_FULL);
    CHECK(C.slot < 0 && bm_faces_count(&M) == 2);
}

TEST(a_half_received_face_does_not_leak_into_the_next_mac_in_that_slot)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    int w = slot_of("work");
    face_t big;
    make_face(&big, 7);
    size_t half = strlen(big.b64) / 2 / 4 * 4;
    char part[sizeof(big.b64)];
    memcpy(part, big.b64, half);
    part[half] = '\0';
    CHECK(over(&A, "work", "host.face",
               "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":%d,\"h\":%d,\"index\":0,\"count\":2,\"data\":\"%s\"}",
               big.hash, SIDE, SIDE, part) == BM_OK);
    bm_conn_close(&M, &A, now);
    bm_conn_open(&C);
    face_t fs;
    make_face(&fs, 3);
    CHECK(snapshot_with_face(&C, "studio", &fs) == BM_OK);
    CHECK(C.slot == w);
    CHECK(over(&C, "studio", "host.face",
               "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":%d,\"h\":%d,\"index\":1,\"count\":2,\"data\":\"%s\"}",
               big.hash, SIDE, SIDE, big.b64 + half) == BM_OK);
    CHECK(!M.hosts[w].has_face);
    CHECK(M.face_rx.count == 0);
}

TEST(a_face_removed_while_its_card_is_shown_falls_back_to_the_clock)
{
    face_t fw, fh;
    two_macs_with_faces(&fw, &fh);
    advance(BM_IDLE_SLEEP_MS + 1000 + BM_SLEEP_CARD_S * 1000);
    int w = slot_of("work");
    CHECK(M.sleep_card == w);
    CHECK(over(&A, "work", "snapshot",
               "{\"sessions\":[],\"usage\":{\"session_pct\":1,\"weekly_pct\":1,\"reset_in_min\":1},"
               "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]}}") == BM_OK);
    CHECK(M.sleeping && !M.hosts[w].has_face);
    advance(200);
    CHECK(M.sleep_card == BM_CARD_CLOCK);
    advance(BM_SLEEP_CARD_S * 1000);
    CHECK(M.sleep_card == slot_of("home"));
}
