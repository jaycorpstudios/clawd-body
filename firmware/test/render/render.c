#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bm_internal.h"
#include "lvgl.h"
#include "support.h"
#include "ui.h"

#define W 480
#define FRAME_MS 33

static uint16_t fb[W * W];
static const char *out_dir;
static const char *only;
static int failures;

void test_register(const char *name, test_fn fn)
{
    (void)name;
    (void)fn;
}

void test_fail(const char *file, int line, const char *expr)
{
    failures++;
    fprintf(stderr, "FAIL (%s:%d): %s\n", file, line, expr);
}

void test_emit(const char *json)
{
    (void)json;
}

static uint32_t tick_cb(void)
{
    return now;
}

static void flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px)
{
    const uint16_t *src = (const uint16_t *)px;
    for (int32_t y = area->y1; y <= area->y2; y++)
        for (int32_t x = area->x1; x <= area->x2; x++) fb[y * W + x] = *src++;
    lv_display_flush_ready(disp);
}

static uint32_t crc_table[256];

static void crc_init(void)
{
    for (uint32_t n = 0; n < 256; n++) {
        uint32_t c = n;
        for (int k = 0; k < 8; k++) c = c & 1 ? 0xedb88320u ^ (c >> 1) : c >> 1;
        crc_table[n] = c;
    }
}

static uint32_t crc(uint32_t c, const uint8_t *buf, size_t len)
{
    for (size_t i = 0; i < len; i++) c = crc_table[(c ^ buf[i]) & 0xff] ^ (c >> 8);
    return c;
}

static void put32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static void chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len)
{
    uint8_t hdr[8];
    put32(hdr, len);
    memcpy(hdr + 4, type, 4);
    fwrite(hdr, 1, 8, f);
    if (len) fwrite(data, 1, len, f);
    uint32_t c = crc(0xffffffffu, (const uint8_t *)type, 4);
    c = crc(c, data, len) ^ 0xffffffffu;
    uint8_t tail[4];
    put32(tail, c);
    fwrite(tail, 1, 4, f);
}

/* Uncompressed deflate (stored blocks): no zlib needed. */
static void write_png(const char *path)
{
    size_t row = 1 + W * 3, raw_len = row * W;
    uint8_t *raw = malloc(raw_len);
    for (int y = 0; y < W; y++) {
        uint8_t *r = raw + y * row;
        *r++ = 0;
        for (int x = 0; x < W; x++) {
            uint16_t c = fb[y * W + x];
            *r++ = (uint8_t)((c >> 11 & 0x1f) * 255 / 31);
            *r++ = (uint8_t)((c >> 5 & 0x3f) * 255 / 63);
            *r++ = (uint8_t)((c & 0x1f) * 255 / 31);
        }
    }
    size_t blocks = (raw_len + 65534) / 65535, z_len = 2 + raw_len + blocks * 5 + 4;
    uint8_t *z = malloc(z_len), *p = z;
    *p++ = 0x78;
    *p++ = 0x01;
    uint32_t a = 1, b = 0;
    for (size_t off = 0; off < raw_len; off += 65535) {
        uint16_t n = (uint16_t)(raw_len - off < 65535 ? raw_len - off : 65535);
        *p++ = off + n == raw_len;
        *p++ = (uint8_t)n;
        *p++ = (uint8_t)(n >> 8);
        *p++ = (uint8_t)~n;
        *p++ = (uint8_t)(~n >> 8);
        memcpy(p, raw + off, n);
        p += n;
    }
    for (size_t i = 0; i < raw_len; i++) {
        a = (a + raw[i]) % 65521;
        b = (b + a) % 65521;
    }
    put32(p, b << 16 | a);

    FILE *f = fopen(path, "wb");
    if (!f) {
        perror(path);
        exit(1);
    }
    fwrite("\x89PNG\r\n\x1a\n", 1, 8, f);
    uint8_t ihdr[13];
    put32(ihdr, W);
    put32(ihdr + 4, W);
    ihdr[8] = 8;
    ihdr[9] = 2;
    ihdr[10] = ihdr[11] = ihdr[12] = 0;
    chunk(f, "IHDR", ihdr, 13);
    chunk(f, "IDAT", z, (uint32_t)z_len);
    chunk(f, "IEND", NULL, 0);
    fclose(f);
    free(raw);
    free(z);
}

static void run(uint32_t ms)
{
    uint32_t end = now + ms;
    while ((int32_t)(end - now) > 0) {
        now += FRAME_MS;
        lv_timer_handler();
    }
}

static bool wanted(const char *name)
{
    return !only || strstr(name, only);
}

static void shot(const char *name)
{
    if (!wanted(name)) return;
    lv_obj_invalidate(lv_screen_active());
    lv_refr_now(NULL);
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.png", out_dir, name);
    write_png(path);
    printf("%s\n", path);
}

typedef bm_err_t (*chunk_fn)(bm_model_t *, int, const char *, int, int, int, int, const char *, uint32_t);

static void put565(uint8_t *px, int i, int r, int g, int b)
{
    uint16_t c = (uint16_t)(r << 11 | g << 5 | b);
    px[i * 2] = (uint8_t)c;
    px[i * 2 + 1] = (uint8_t)(c >> 8);
}

static void hash_of(const uint8_t *px, size_t n, char hash[17])
{
    snprintf(hash, 17, "%016llx", (unsigned long long)bm_fnv1a64(px, n));
}

static void send_chunks(chunk_fn take, const char *host, const uint8_t *px, int side, int chunks)
{
    static const char T[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    static char data[8000];
    size_t total = (size_t)side * (size_t)side * 2, part = total / (size_t)chunks;
    char hash[17];
    hash_of(px, total, hash);
    int slot = bm__host_slot(&M, host, false);
    for (int i = 0; i < chunks; i++) {
        const uint8_t *in = px + part * (size_t)i;
        size_t o = 0;
        for (size_t k = 0; k < part; k += 3) {
            uint32_t v = (uint32_t)in[k] << 16 | (k + 1 < part ? (uint32_t)in[k + 1] << 8 : 0) |
                         (k + 2 < part ? in[k + 2] : 0);
            data[o++] = T[v >> 18 & 63];
            data[o++] = T[v >> 12 & 63];
            data[o++] = k + 1 < part ? T[v >> 6 & 63] : '=';
            data[o++] = k + 2 < part ? T[v & 63] : '=';
        }
        data[o] = '\0';
        CHECK(take(&M, slot, hash, side, side, i, chunks, data, now) == BM_OK);
    }
}

static void send_face(const char *host)
{
    enum { SIDE = 160 };
    static uint8_t px[SIDE * SIDE * 2];
    for (int y = 0; y < SIDE; y++)
        for (int x = 0; x < SIDE; x++) {
            int dx = x - SIDE / 2, dy = y - SIDE / 2;
            bool ring = dx * dx + dy * dy < 50 * 50;
            put565(px, y * SIDE + x, ring ? 31 : x * 31 / SIDE, ring ? 40 : y * 63 / SIDE, ring ? 8 : 20);
        }
    send_chunks(bm__on_face_chunk, host, px, SIDE, 16);
    CHECK(M.hosts[bm__host_slot(&M, host, false)].has_face);
}

/* A sunset: sky gradient, a sun, dark hills. */
static uint8_t cover_px[BM_COVER_MAX * BM_COVER_MAX * 2];

static void make_cover(char hash[17])
{
    enum { SIDE = BM_COVER_MAX };
    for (int y = 0; y < SIDE; y++)
        for (int x = 0; x < SIDE; x++) {
            int dx = x - 60, dy = y - 52;
            bool sun = dx * dx + dy * dy < 18 * 18;
            bool hill = y > 70 + (x - 30) * (x - 30) / 120;
            if (hill) put565(cover_px, y * SIDE + x, 4, 6, 8);
            else if (sun) put565(cover_px, y * SIDE + x, 31, 52, 10);
            else put565(cover_px, y * SIDE + x, 10 + y * 20 / SIDE, 8 + y * 30 / SIDE, 22 - y * 14 / SIDE);
        }
    hash_of(cover_px, sizeof(cover_px), hash);
}

static void wait_card(int card)
{
    for (int i = 0; i < 40 && M.sleep_card != card; i++) run(1000);
    CHECK(M.sleep_card == card);
    run(200);
}

static void fall_asleep(void)
{
    run(BM_IDLE_SLEEP_MS + 1000);
    CHECK(M.sleeping);
}

static void wake(void)
{
    bm_touch_wake(&M, now);
    run(600);
}

static void go_view(bm_view_t v)
{
    for (int i = 0; i < BM_VIEWS && M.view != v; i++) bm_swipe(&M, 1, now);
    run(600);
}

#define EMPTY_SNAPSHOT                                                                                                 \
    "{\"sessions\":[],\"usage\":{\"session_pct\":42,\"weekly_pct\":18,\"reset_in_min\":100},"                       \
    "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]}}"

static void linked(void)
{
    fresh();
    CHECK(send("work", "snapshot", EMPTY_SNAPSHOT) == BM_OK);
    run(3000);
}

static void scene_sleep(void)
{
    linked();
    bm_link(&M, "home", false, now);
    run(600);
    shot("home");

    fall_asleep();
    wait_card(BM_CARD_CLOCK);
    shot("sleep-clock");
    wait_card(BM_CARD_COMPUTERS);
    shot("sleep-computers-1-of-2");

    send_face("work");
    run(100);
    wait_card(bm__host_slot(&M, "work", false));
    run(65000 - 200);
    shot("sleep-face-connected");

    bm_link(&M, "work", false, now);
    run(100);
    wake();
    fall_asleep();
    wait_card(bm__host_slot(&M, "work", false));
    shot("sleep-face-seen-ago");

    bm__on_face_ref(&M, bm__host_slot(&M, "work", false), NULL, now);
    run(100);
    wait_card(BM_CARD_COMPUTERS);
    shot("sleep-computers-none");
}

static void pomo_snapshot(const char *state)
{
    CHECK(send("work", "pomodoro.state", "%s", state) == BM_OK);
    run(300);
}

static void scene_focus(void)
{
    fresh();
    go_view(BM_VIEW_POMODORO);
    shot("focus-no-clock");

    linked();
    go_view(BM_VIEW_POMODORO);
    shot("focus-stopped");

    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    run(41000);
    shot("focus-running-work");

    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    run(500);
    shot("focus-paused");

    bm_tap(&M, BM_TAP_POMO_TOGGLE, 0, now);
    int64_t t = bm_wall_ms(&M, now) / 1000;
    char state[300];
    snprintf(state, sizeof(state),
             "{\"state\":\"running\",\"phase\":\"break\",\"ends_at\":%lld,\"work_min\":25,\"break_min\":5,"
             "\"cycle\":3,\"updated_at\":%lld}",
             (long long)(t + 140), (long long)t);
    pomo_snapshot(state);
    shot("focus-break-cycle-3");

    bm_link(&M, "work", false, now);
    bm_link(&M, "home", false, now);
    run(3000);
    shot("focus-link-down");

    run(50 * 1000);
    bm_touch_wake(&M, now);
    run(50 * 1000);
    bm_touch_wake(&M, now);
    run(41 * 1000);
    CHECK(bm_alarm_ringing(&M));
    shot("focus-alarm-after-break-alone");
    run(550);
    shot("focus-alarm-pulse");
    bm_alarm_stop(&M, now);
    run(300);
    shot("focus-alarm-silenced");

    bm_tap(&M, BM_TAP_POMO_RESET, 0, now);
    bm_tap(&M, BM_TAP_POMO_WORK, 1, now);
    for (int i = 0; i < 20; i++) bm_tap(&M, BM_TAP_POMO_WORK, 1, now);
    bm_tap(&M, BM_TAP_POMO_BREAK, -1, now);
    run(500);
    shot("focus-stopped-90-4");
}

static void now_playing(bool playing, const char *cover)
{
    char ref[64] = "";
    if (cover) snprintf(ref, sizeof(ref), ",\"cover\":{\"hash\":\"%s\"}", cover);
    CHECK(send("work", "media.now_playing",
               "{\"title\":\"Night Build\",\"artist\":\"Tabstop\",\"length_s\":247,\"position_s\":72,\"playing\":%s%s}",
               playing ? "true" : "false", ref) == BM_OK);
    run(300);
}

static void scene_music(void)
{
    linked();
    go_view(BM_VIEW_MUSIC);
    shot("music-nothing-playing");

    now_playing(true, NULL);
    run(5000);
    shot("music-playing");

    now_playing(false, NULL);
    shot("music-paused");

    char hash[17];
    make_cover(hash);
    now_playing(true, hash);
    shot("music-cover-requested");
    CHECK(bm_cover_waiting(&M, now));
    run(700);
    shot("music-cover-regenerating");
    send_chunks(bm__on_cover_chunk, "work", cover_px, BM_COVER_MAX, 8);
    run(300);
    CHECK(bm_media_cover(&M) != NULL);
    shot("music-cover");

    now_playing(true, "0123456789abcdef");
    run(3000);
    shot("music-cover-still-waiting");
    run(5000);
    CHECK(!bm_cover_waiting(&M, now));
    shot("music-cover-gave-up");

    bm_link(&M, "work", false, now);
    run(600);
    bm_tap_overlay(&M, now);
    run(4000);
    shot("music-mac-disconnected");
}

static void scene_panel(void)
{
    linked();
    go_view(BM_VIEW_HOME);
    CHECK(send("work", "settings.set", "{\"tz_offset_min\":-360}") == BM_OK);
    bm_panel(&M, true, now);
    run(600);
    shot("panel-tz-utc-6");
    bm_settings_t s = M.settings;
    s.tz_offset_min = 345;
    bm_settings_change(&M, &s, now);
    run(300);
    shot("panel-tz-utc+5-45");
    bm_panel(&M, false, now);
    run(600);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <out-dir> [scene-filter]\n", argv[0]);
        return 2;
    }
    out_dir = argv[1];
    only = argc > 2 ? argv[2] : NULL;
    crc_init();

    fresh();
    lv_init();
    lv_tick_set_cb(tick_cb);
    lv_display_t *disp = lv_display_create(W, W);
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_RGB565);
    static uint16_t buf[W * W];
    lv_display_set_buffers(disp, buf, NULL, sizeof(buf), LV_DISPLAY_RENDER_MODE_FULL);
    lv_display_set_flush_cb(disp, flush_cb);
    ui_init(&M);
    run(200);

    scene_sleep();
    scene_focus();
    scene_music();
    scene_panel();

    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
