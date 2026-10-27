#include <stdio.h>
#include <string.h>

#include "bm_internal.h"

static int64_t wall_s(const bm_model_t *m, uint32_t now_ms)
{
    return bm_wall_ms(m, now_ms) / 1000;
}

uint64_t bm_fnv1a64(const void *data, size_t len)
{
    uint64_t h = 0xcbf29ce484222325ULL;
    for (const uint8_t *p = data; len--; p++) h = (h ^ *p) * 0x100000001b3ULL;
    return h;
}

static int b64_value(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

/* Returns the decoded length, or 0 for malformed input or not enough room. */
size_t bm_base64_decode(const char *in, uint8_t *out, size_t cap)
{
    size_t len = strlen(in), n = 0;
    if (!len || len % 4) return 0;
    for (size_t i = 0; i < len; i += 4) {
        int v[4], pad = 0;
        for (int k = 0; k < 4; k++) {
            if (in[i + k] == '=' && i + 4 == len && k >= 2) {
                v[k] = 0;
                pad++;
            } else if (pad || (v[k] = b64_value(in[i + k])) < 0) {
                return 0;
            }
        }
        uint32_t triple = (uint32_t)v[0] << 18 | (uint32_t)v[1] << 12 | (uint32_t)v[2] << 6 | (uint32_t)v[3];
        int bytes = 3 - pad;
        if (n + (size_t)bytes > cap) return 0;
        for (int k = 0; k < bytes; k++) out[n++] = (uint8_t)(triple >> (16 - 8 * k));
    }
    return n;
}

void bm__settings_defaults(bm_settings_t *s)
{
    s->sound = false;
    s->volume = 60;
    s->brightness = 100;
}

static bool settings_valid(const bm_settings_t *s)
{
    return s->volume <= 100 && s->brightness >= 10 && s->brightness <= 100;
}

void bm_settings_load(bm_model_t *m, const bm_settings_t *s)
{
    if (!settings_valid(s)) return;
    m->settings = *s;
    m->settings_rev++;
    bm__touch(m);
}

void bm__send_settings(bm_model_t *m, uint8_t hosts, uint32_t now_ms)
{
    char data[64];
    snprintf(data, sizeof(data), "{\"sound\":%s,\"volume\":%u,\"brightness\":%u}", m->settings.sound ? "true" : "false",
             m->settings.volume, m->settings.brightness);
    bm__out(m, hosts, "device.settings", data, now_ms);
}

static void apply_settings(bm_model_t *m, const bm_settings_t *s)
{
    m->settings = *s;
    m->settings_rev++;
    bm__touch(m);
}

/* Panel drags change the value on every frame; the Macs hear about it once the finger settles. */
void bm_settings_change(bm_model_t *m, const bm_settings_t *s, uint32_t now_ms)
{
    if (!settings_valid(s) || memcmp(s, &m->settings, sizeof(*s)) == 0) return;
    bool sound_on = s->sound && !m->settings.sound;
    apply_settings(m, s);
    m->last_act_ms = now_ms;
    m->settings_emit_ms = now_ms + BM_SETTINGS_SETTLE_MS;
    if (!m->settings_emit_ms) m->settings_emit_ms = 1;
    if (sound_on) bm__sound(m, BM_SND_CLICK);
}

void bm__on_settings(bm_model_t *m, const bm_settings_t *s, uint32_t now_ms)
{
    apply_settings(m, s);
    m->settings_emit_ms = 0;
    bm__send_settings(m, BM_ALL_HOSTS, now_ms);
}

void bm__settings_tick(bm_model_t *m, uint32_t now_ms)
{
    if (!m->settings_emit_ms || (int32_t)(now_ms - m->settings_emit_ms) < 0) return;
    m->settings_emit_ms = 0;
    bm__send_settings(m, BM_ALL_HOSTS, now_ms);
}

void bm_panel(bm_model_t *m, bool open, uint32_t now_ms)
{
    if (m->sleeping) {
        bm__wake(m, false, BM_BY_TOUCH, now_ms);
        return;
    }
    m->last_act_ms = now_ms;
    if (open && (m->attn >= 0 || m->pairing)) return;
    if (m->panel == open) return;
    m->panel = open;
    if (open) {
        m->sheet = BM_SHEET_NONE;
        m->sheet_session = -1;
    }
    bm__touch(m);
}

static void hash_hex(uint64_t h, char out[17])
{
    snprintf(out, 17, "%016llx", (unsigned long long)h);
}

static void request_face(bm_model_t *m, int host, const char *hash, uint32_t now_ms)
{
    char data[48];
    snprintf(data, sizeof(data), "{\"hash\":\"%s\"}", hash);
    bm__out(m, (uint8_t)(1u << host), "device.face_request", data, now_ms);
}

void bm__on_face_ref(bm_model_t *m, int host, const char *hash, uint32_t now_ms)
{
    bm_host_t *h = &m->hosts[host];
    if (!hash) {
        if (h->has_face) {
            h->has_face = false;
            m->faces_rev++;
            bm__touch(m);
        }
        return;
    }
    bool receiving = m->face_rx.host == host && strcmp(m->face_rx.hash, hash) == 0 && m->face_rx.count;
    if ((!h->has_face || strcmp(h->face.hash, hash) != 0) && !receiving) request_face(m, host, hash, now_ms);
}

bm_err_t bm__on_face_chunk(bm_model_t *m, int host, const char *hash, int w, int h, int index, int count,
                           const char *data, uint32_t now_ms)
{
    (void)now_ms;
    bm_face_rx_t *rx = &m->face_rx;
    size_t total = (size_t)w * (size_t)h * 2;
    if (w < 16 || h < 16 || w > BM_FACE_MAX || h > BM_FACE_MAX || count < 1 || count > BM_FACE_CHUNKS || index < 0 ||
        index >= count)
        return BM_E_DATA;
    bool same = rx->count && rx->host == host && strcmp(rx->hash, hash) == 0 && rx->w == w && rx->h == h &&
                rx->count == count;
    if (index == 0 || !same) {
        if (index != 0) {
            rx->count = 0;
            return BM_OK;
        }
        rx->host = (int8_t)host;
        bm__copy(rx->hash, sizeof(rx->hash), hash);
        rx->w = (uint16_t)w;
        rx->h = (uint16_t)h;
        rx->count = (uint8_t)count;
        rx->next = 0;
        rx->bytes = 0;
    }
    if (index != rx->next) {
        rx->count = 0;
        return BM_OK;
    }
    size_t n = bm_base64_decode(data, rx->px + rx->bytes, total - rx->bytes);
    if (!n) {
        rx->count = 0;
        return BM_E_DATA;
    }
    rx->bytes += (uint32_t)n;
    rx->next++;
    if (rx->next < rx->count) return BM_OK;

    char got[17];
    hash_hex(bm_fnv1a64(rx->px, rx->bytes), got);
    rx->count = 0;
    if (rx->bytes != total || strcmp(got, hash) != 0) return BM_OK;
    bm_host_t *dst = &m->hosts[host];
    memcpy(dst->face.px, rx->px, total);
    dst->face.w = (uint16_t)w;
    dst->face.h = (uint16_t)h;
    bm__copy(dst->face.hash, sizeof(dst->face.hash), hash);
    dst->has_face = true;
    m->faces_rev++;
    bm__touch(m);
    return BM_OK;
}

int bm_faces_count(const bm_model_t *m)
{
    int n = 0;
    for (int i = 0; i < BM_MAX_HOSTS; i++)
        if (m->hosts[i].used && m->hosts[i].has_face) n++;
    return n;
}

static int next_card(const bm_model_t *m, int card)
{
    if (!bm_faces_count(m)) return card == BM_CARD_CLOCK ? BM_CARD_COMPUTERS : BM_CARD_CLOCK;
    for (int i = card < 0 ? 0 : card + 1; i < BM_MAX_HOSTS; i++)
        if (m->hosts[i].used && m->hosts[i].has_face) return i;
    return BM_CARD_CLOCK;
}

void bm__sleep_card_tick(bm_model_t *m, uint32_t now_ms)
{
    if (!m->sleeping) {
        if (m->sleep_card != BM_CARD_CLOCK) {
            m->sleep_card = BM_CARD_CLOCK;
            bm__touch(m);
        }
        m->sleep_card_s = 0;
        return;
    }
    int64_t secs = m->clock_known ? wall_s(m, now_ms) : now_ms / 1000;
    if (!m->sleep_card_s) m->sleep_card_s = secs;
    bool gone = m->sleep_card >= 0 && !(m->hosts[m->sleep_card].used && m->hosts[m->sleep_card].has_face);
    bool stale = m->sleep_card == BM_CARD_COMPUTERS && bm_faces_count(m);
    if (secs - m->sleep_card_s < BM_SLEEP_CARD_S && !gone && !stale) return;
    m->sleep_card_s = secs;
    m->sleep_card = (int8_t)(gone || stale ? BM_CARD_CLOCK : next_card(m, m->sleep_card));
    bm__touch(m);
}

void bm__pomo_defaults(bm_pomo_t *p)
{
    memset(p, 0, sizeof(*p));
    p->state = BM_POMO_STOPPED;
    p->work_min = BM_POMO_WORK_MIN;
    p->break_min = BM_POMO_BREAK_MIN;
}

static int64_t phase_s(const bm_pomo_t *p)
{
    return (int64_t)(p->on_break ? p->break_min : p->work_min) * 60;
}

/* Returns how many phases ended; both sides run the same rule, so no message is needed. */
static int pomo_advance(bm_pomo_t *p, int64_t now_s)
{
    int flips = 0;
    while (p->state == BM_POMO_RUNNING && now_s >= p->ends_at && flips < 1000) {
        if (!p->on_break && p->cycle < 999) p->cycle++;
        p->on_break = !p->on_break;
        p->ends_at += phase_s(p);
        flips++;
    }
    return flips;
}

static void send_pomodoro(bm_model_t *m, uint8_t hosts, uint32_t now_ms)
{
    static const char *const states[] = {"stopped", "running", "paused"};
    const bm_pomo_t *p = &m->pomo;
    char extra[40] = "";
    if (p->state == BM_POMO_RUNNING) snprintf(extra, sizeof(extra), "\"ends_at\":%lld,", (long long)p->ends_at);
    else if (p->state == BM_POMO_PAUSED) snprintf(extra, sizeof(extra), "\"left_s\":%ld,", (long)p->left_s);
    char data[200];
    snprintf(data, sizeof(data),
             "{\"state\":\"%s\",\"phase\":\"%s\",%s\"work_min\":%u,\"break_min\":%u,\"cycle\":%u,\"updated_at\":%lld}",
             states[p->state], p->on_break ? "break" : "work", extra, p->work_min, p->break_min, p->cycle,
             (long long)p->updated_at);
    bm__out(m, hosts, "device.pomodoro", data, now_ms);
}

void bm__on_pomodoro(bm_model_t *m, int host, const bm_pomo_t *p, bool from_snapshot, bool present, uint32_t now_ms)
{
    bool mine_set = m->pomo.updated_at > 0;
    if (!present) {
        if (mine_set) send_pomodoro(m, (uint8_t)(1u << host), now_ms);
        return;
    }
    if (p->updated_at > m->pomo.updated_at || (!from_snapshot && p->updated_at == m->pomo.updated_at)) {
        m->pomo = *p;
        if (m->clock_known) pomo_advance(&m->pomo, wall_s(m, now_ms));
        send_pomodoro(m, BM_ALL_HOSTS, now_ms);
        bm__touch(m);
    } else if (p->updated_at < m->pomo.updated_at) {
        send_pomodoro(m, (uint8_t)(1u << host), now_ms);
    }
}

int32_t bm_pomo_left_s(const bm_model_t *m, uint32_t now_ms)
{
    const bm_pomo_t *p = &m->pomo;
    if (p->state == BM_POMO_PAUSED) return p->left_s;
    if (p->state == BM_POMO_STOPPED) return (int32_t)phase_s(p);
    int64_t left = p->ends_at - wall_s(m, now_ms);
    return left < 0 ? 0 : (int32_t)left;
}

float bm_pomo_progress(const bm_model_t *m, uint32_t now_ms)
{
    float total = (float)phase_s(&m->pomo);
    float done = 1.0f - (float)bm_pomo_left_s(m, now_ms) / total;
    return done < 0 ? 0 : done > 1 ? 1 : done;
}

static void pomo_changed(bm_model_t *m, uint32_t now_ms)
{
    m->pomo.updated_at = m->clock_known ? wall_s(m, now_ms) : 0;
    send_pomodoro(m, BM_ALL_HOSTS, now_ms);
    bm__touch(m);
}

void bm__pomo_tap(bm_model_t *m, bm_tap_t target, int arg, uint32_t now_ms)
{
    bm_pomo_t *p = &m->pomo;
    int64_t now_s = wall_s(m, now_ms);
    switch (target) {
    case BM_TAP_POMO_TOGGLE:
        if (!m->clock_known) return;
        if (p->state == BM_POMO_RUNNING) {
            int64_t left = p->ends_at - now_s;
            p->left_s = (int32_t)(left < 0 ? 0 : left);
            p->state = BM_POMO_PAUSED;
        } else {
            p->ends_at = now_s + (p->state == BM_POMO_PAUSED ? p->left_s : phase_s(p));
            p->left_s = 0;
            p->state = BM_POMO_RUNNING;
            bm__sound(m, BM_SND_CLICK);
        }
        break;
    case BM_TAP_POMO_RESET:
        if (p->state == BM_POMO_STOPPED && !p->on_break && !p->cycle) return;
        p->state = BM_POMO_STOPPED;
        p->on_break = false;
        p->cycle = 0;
        p->ends_at = 0;
        p->left_s = 0;
        break;
    case BM_TAP_POMO_WORK:
    case BM_TAP_POMO_BREAK: {
        if (p->state != BM_POMO_STOPPED) return;
        bool work = target == BM_TAP_POMO_WORK;
        int max = work ? 90 : 60, step = work ? 5 : 1;
        int v = (work ? p->work_min : p->break_min) + (arg < 0 ? -step : step);
        if (v < 1) v = 1;
        if (v > max) v = max;
        if (work) p->work_min = (uint8_t)v;
        else p->break_min = (uint8_t)v;
        break;
    }
    default: return;
    }
    pomo_changed(m, now_ms);
}

void bm__pomo_tick(bm_model_t *m, uint32_t now_ms)
{
    if (m->pomo.state != BM_POMO_RUNNING || !m->clock_known) return;
    int64_t now_s = wall_s(m, now_ms);
    if (now_s < m->pomo.ends_at) return;
    pomo_advance(&m->pomo, now_s);
    bool on_break = m->pomo.on_break;
    bm__toast(m, on_break ? "Break time" : "Back to work", on_break ? BM_C_DONE : BM_C_WORK, now_ms);
    bm__sound(m, on_break ? BM_SND_DONE : BM_SND_START);
    bm__touch(m);
}

void bm__media_tap(bm_model_t *m, int action, uint32_t now_ms)
{
    static const char *const actions[] = {"play_pause", "next", "previous"};
    int host = bm_media_host(m);
    if (host < 0 || action < 0 || action > 2 || !m->hosts[host].connected) return;
    char data[40];
    snprintf(data, sizeof(data), "{\"action\":\"%s\"}", actions[action]);
    bm__out(m, (uint8_t)(1u << host), "media.control", data, now_ms);
    bm__sound(m, BM_SND_CLICK);
}
