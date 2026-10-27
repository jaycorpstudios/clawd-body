#include <stdio.h>
#include <string.h>

#include "bm_internal.h"
#include "support.h"

#define SIDE 32
#define EMPTY_SNAPSHOT                                                                                                 \
    "\"sessions\":[],\"usage\":{\"session_pct\":10,\"weekly_pct\":5,\"reset_in_min\":100},"                          \
    "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]}"

typedef struct {
    uint8_t px[SIDE * SIDE * 2];
    char hash[17];
} cover_t;

static void make_cover(cover_t *c, uint8_t seed)
{
    for (size_t i = 0; i < sizeof(c->px); i++) c->px[i] = (uint8_t)(i * 5 + seed);
    snprintf(c->hash, sizeof(c->hash), "%016llx", (unsigned long long)bm_fnv1a64(c->px, sizeof(c->px)));
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

static bm_err_t cover_chunk(const char *host, const cover_t *c, int index, int count)
{
    size_t part = sizeof(c->px) / (size_t)count;
    size_t start = part * (size_t)index, len = index == count - 1 ? sizeof(c->px) - start : part;
    char data[1800];
    b64(c->px + start, len, data);
    return send(host, "media.cover",
                "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":%d,\"h\":%d,\"index\":%d,\"count\":%d,\"data\":\"%s\"}",
                c->hash, SIDE, SIDE, index, count, data);
}

static void send_cover(const char *host, const cover_t *c)
{
    for (int i = 0; i < 3; i++) CHECK(cover_chunk(host, c, i, 3) == BM_OK);
}

static bm_err_t playing(const char *host, const char *title, const char *hash)
{
    char cover[64] = "";
    if (hash) snprintf(cover, sizeof(cover), ",\"cover\":{\"hash\":\"%s\"}", hash);
    return send(host, "media.now_playing", "{\"title\":\"%s\",\"artist\":\"Tabstop\",\"length_s\":200,\"position_s\":3%s}",
                title, cover);
}

TEST(a_track_with_an_unknown_cover_asks_its_mac_once)
{
    fresh();
    cover_t c;
    make_cover(&c, 1);
    outs_t o;
    drain(&o);
    CHECK(playing("work", "Night Build", c.hash) == BM_OK);
    drain(&o);
    const bm_out_t *req = find_out(&o, "device.cover_request");
    CHECK(req && req->hosts == 1u << bm__host_slot(&M, "work", false));
    CHECK(strstr(req->json, c.hash));
    CHECK(bm_media_cover(&M) == NULL);

    CHECK(cover_chunk("work", &c, 0, 3) == BM_OK);
    CHECK(playing("work", "Night Build", c.hash) == BM_OK);
    drain(&o);
    CHECK(count_out(&o, "device.cover_request") == 0);
}

TEST(cover_chunks_assemble_and_show_for_the_track_that_names_them)
{
    fresh();
    cover_t c;
    make_cover(&c, 2);
    CHECK(playing("work", "Night Build", c.hash) == BM_OK);
    uint32_t rev = M.covers_rev;
    send_cover("work", &c);
    const bm_cover_t *got = bm_media_cover(&M);
    CHECK(got && got->w == SIDE && got->h == SIDE && strcmp(got->hash, c.hash) == 0);
    CHECK(got && memcmp(got->px, c.px, sizeof(c.px)) == 0);
    CHECK(M.covers_rev == rev + 1);

    outs_t o;
    drain(&o);
    CHECK(playing("work", "Night Build", c.hash) == BM_OK);
    drain(&o);
    CHECK(count_out(&o, "device.cover_request") == 0);

    CHECK(playing("work", "Fan Noise", NULL) == BM_OK);
    CHECK(bm_media_cover(&M) == NULL);
    cover_t d;
    make_cover(&d, 3);
    CHECK(playing("work", "Low Tide", d.hash) == BM_OK);
    CHECK(bm_media_cover(&M) == NULL);
    drain(&o);
    CHECK(count_out(&o, "device.cover_request") == 1);
}

TEST(a_cover_with_a_wrong_hash_a_gap_or_out_of_range_is_dropped)
{
    fresh();
    cover_t c;
    make_cover(&c, 4);
    CHECK(playing("work", "Night Build", c.hash) == BM_OK);
    cover_t bad = c;
    bad.px[0] ^= 1;
    send_cover("work", &bad);
    CHECK(!M.has_cover);
    CHECK(cover_chunk("work", &c, 0, 3) == BM_OK);
    CHECK(cover_chunk("work", &c, 2, 3) == BM_OK);
    CHECK(cover_chunk("work", &c, 1, 3) == BM_OK);
    CHECK(!M.has_cover);
    CHECK(send("work", "media.cover",
               "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":120,\"h\":120,\"index\":0,\"count\":1,\"data\":\"AAAA\"}",
               c.hash) == BM_E_DATA);
    CHECK(send("work", "media.cover",
               "{\"hash\":\"%s\",\"format\":\"rgb565\",\"w\":32,\"h\":32,\"index\":0,\"count\":9,\"data\":\"AAAA\"}",
               c.hash) == BM_E_DATA);
    CHECK(playing("work", "Night Build", "NOTHEX0000000000") == BM_E_DATA);
    send_cover("work", &c);
    CHECK(bm_media_cover(&M) != NULL);
}

TEST(a_snapshot_names_the_cover_and_a_new_mac_in_the_slot_drops_a_half_received_one)
{
    fresh();
    cover_t c;
    make_cover(&c, 5);
    char snap[400];
    snprintf(snap, sizeof(snap),
             "{" EMPTY_SNAPSHOT ",\"media\":{\"title\":\"Night Build\",\"artist\":\"Tabstop\",\"length_s\":200,"
             "\"position_s\":3,\"cover\":{\"hash\":\"%s\"}}}",
             c.hash);
    outs_t o;
    drain(&o);
    CHECK(send("home", "snapshot", "%s", snap) == BM_OK);
    drain(&o);
    CHECK(count_out(&o, "device.cover_request") == 1);

    int home = bm__host_slot(&M, "home", false);
    CHECK(cover_chunk("home", &c, 0, 3) == BM_OK);
    CHECK(M.cover_rx.count);
    bm_link(&M, "home", false, now);
    bm_link(&M, "work", true, now);
    bm_link(&M, "lab", true, now);
    CHECK(bm__host_slot(&M, "lab", false) == home);
    CHECK(!M.cover_rx.count);
    CHECK(cover_chunk("lab", &c, 1, 3) == BM_OK);
    CHECK(!M.has_cover);
}
