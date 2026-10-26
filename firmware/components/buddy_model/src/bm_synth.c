#include "bm_synth.h"

#include <math.h>
#include <string.h>

#define PI_F 3.14159265f
#define ATTACK_S 0.008f
#define ENV_FLOOR 0.0008f
#define BELL_TAIL 2.6f
#define BELL_RATIO 2.76f
#define BELL_GAIN 0.22f
#define BELL_FLOOR 0.0005f
#define VIB_DEPTH 0.012f
/* Attention, the loudest family, peaks at 0.63 of full scale so overlapping bell tails never clip; the codec volume sets the level. */
#define OUTPUT_SCALE 7.0f

typedef enum { WAVE_SINE, WAVE_TRIANGLE, WAVE_SQUARE } wave_t;

typedef struct {
    wave_t wave;
    float gain;
    float vib_hz;
    bool bell;
    float lowpass_hz;
} family_t;

typedef struct {
    uint16_t hz;
    uint16_t ms;
} note_t;

typedef struct {
    const family_t *fam;
    float vol;
    uint8_t n;
    note_t notes[5];
} sound_t;

static const family_t ATTENTION = {WAVE_TRIANGLE, 0.09f, 7.0f, false, 0};
static const family_t SUCCESS = {WAVE_SINE, 0.08f, 0, true, 0};
static const family_t PROBLEM = {WAVE_SQUARE, 0.035f, 0, false, 1300.0f};
static const family_t INFO = {WAVE_SINE, 0.045f, 0, false, 0};

static const sound_t SOUNDS[] = {
    [BM_SND_PERM] = {&ATTENTION, 1, 5, {{880, 110}, {1320, 200}, {0, 100}, {880, 110}, {1320, 240}}},
    [BM_SND_QUESTION] = {&ATTENTION, 1, 3, {{880, 110}, {1109, 110}, {1320, 280}}},
    [BM_SND_RISK] = {&ATTENTION, 1, 5, {{880, 90}, {1320, 90}, {880, 90}, {1320, 90}, {1760, 260}}},
    [BM_SND_REMINDER] = {&ATTENTION, 0.5f, 2, {{880, 90}, {1320, 180}}},
    [BM_SND_DONE] = {&SUCCESS, 1, 4, {{1047, 80}, {1319, 80}, {1568, 80}, {2093, 220}}},
    [BM_SND_APPROVED] = {&SUCCESS, 1, 2, {{1568, 80}, {2093, 200}}},
    [BM_SND_CONNECTED] = {&SUCCESS, 1, 2, {{1047, 100}, {1568, 180}}},
    [BM_SND_CHARGE] = {&SUCCESS, 1, 2, {{1319, 80}, {1568, 160}}},
    [BM_SND_ERROR] = {&PROBLEM, 1, 2, {{330, 130}, {262, 300}}},
    [BM_SND_WARN] = {&PROBLEM, 1, 3, {{392, 120}, {0, 50}, {392, 160}}},
    [BM_SND_LIMIT] = {&PROBLEM, 1, 3, {{330, 130}, {262, 130}, {220, 380}}},
    [BM_SND_BATTERY] = {&PROBLEM, 1, 3, {{262, 90}, {0, 60}, {262, 180}}},
    [BM_SND_DISCONNECTED] = {&PROBLEM, 1, 2, {{392, 110}, {294, 240}}},
    [BM_SND_START] = {&INFO, 1, 2, {{1760, 40}, {2349, 60}}},
    [BM_SND_DENIED] = {&INFO, 1, 2, {{1568, 50}, {1175, 90}}},
    [BM_SND_MEDIA] = {&INFO, 1, 3, {{2093, 40}, {2637, 40}, {3136, 60}}},
    [BM_SND_CLICK] = {&INFO, 1, 1, {{2093, 25}}},
};

static const sound_t *lookup(bm_sound_t snd)
{
    return (unsigned)snd < sizeof(SOUNDS) / sizeof(SOUNDS[0]) && SOUNDS[snd].fam ? &SOUNDS[snd] : NULL;
}

static float tail_s(const family_t *f, float d) { return f->bell ? d * BELL_TAIL : d; }

size_t bm_synth_length(bm_sound_t snd, uint32_t rate)
{
    const sound_t *s = lookup(snd);
    if (!s) return 0;
    float t = 0, end = 0;
    for (int i = 0; i < s->n; i++) {
        float d = s->notes[i].ms / 1000.0f;
        if (s->notes[i].hz) end = fmaxf(end, t + tail_s(s->fam, d));
        t += d;
    }
    return (size_t)ceilf(fmaxf(end, t) * rate);
}

static float wave(wave_t w, float phase)
{
    switch (w) {
    case WAVE_TRIANGLE: return phase < 0.5f ? 4 * phase - 1 : 3 - 4 * phase;
    case WAVE_SQUARE: return phase < 0.5f ? 1.0f : -1.0f;
    default: return sinf(2 * PI_F * phase);
    }
}

/* Linear attack, then the exponential ramp WebAudio's exponentialRampToValueAtTime draws. */
static float envelope(float t, float peak, float attack, float tail, float floor)
{
    if (t < 0 || t >= tail) return 0;
    if (t < attack) return peak * t / attack;
    return peak * powf(floor / peak, (t - attack) / (tail - attack));
}

typedef struct {
    float b0, b1, b2, a1, a2, x1, x2, y1, y2;
} biquad_t;

/* WebAudio lowpass with its default Q of 1 dB. */
static void lowpass_init(biquad_t *f, float hz, uint32_t rate)
{
    float w = 2 * PI_F * hz / rate, q = powf(10, 1.0f / 20), alpha = sinf(w) / (2 * q), c = cosf(w);
    float a0 = 1 + alpha;
    *f = (biquad_t){(1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0, 0, 0, 0, 0};
}

static float lowpass(biquad_t *f, float x)
{
    float y = f->b0 * x + f->b1 * f->x1 + f->b2 * f->x2 - f->a1 * f->y1 - f->a2 * f->y2;
    f->x2 = f->x1, f->x1 = x, f->y2 = f->y1, f->y1 = y;
    return y;
}

static void add_note(const sound_t *s, const note_t *n, size_t start, uint32_t rate, float *mix, size_t len)
{
    const family_t *f = s->fam;
    float d = n->ms / 1000.0f, tail = tail_s(f, d), peak = s->vol * f->gain, phase = 0, bell_phase = 0;
    biquad_t lp = {0};
    if (f->lowpass_hz) lowpass_init(&lp, f->lowpass_hz, rate);
    size_t count = (size_t)(tail * rate);
    for (size_t i = 0; i < count && start + i < len; i++) {
        float t = (float)i / rate;
        float hz = n->hz * (1 + (f->vib_hz ? VIB_DEPTH * sinf(2 * PI_F * f->vib_hz * t) : 0));
        float v = wave(f->wave, phase);
        if (f->lowpass_hz) v = lowpass(&lp, v);
        float out = v * envelope(t, peak, ATTACK_S, tail, ENV_FLOOR);
        if (f->bell) {
            out += sinf(2 * PI_F * bell_phase) * envelope(t, peak * BELL_GAIN, 0, d * 1.2f, BELL_FLOOR);
            bell_phase += n->hz * BELL_RATIO / rate;
            bell_phase -= floorf(bell_phase);
        }
        mix[start + i] += out;
        phase += hz / rate;
        phase -= floorf(phase);
    }
}

size_t bm_synth_render(bm_sound_t snd, uint32_t rate, float *mix, int16_t *out, size_t cap)
{
    const sound_t *s = lookup(snd);
    size_t len = bm_synth_length(snd, rate);
    if (!s || len > cap) return 0;
    memset(mix, 0, len * sizeof(float));
    float t = 0;
    for (int i = 0; i < s->n; i++) {
        if (s->notes[i].hz) add_note(s, &s->notes[i], (size_t)(t * rate), rate, mix, len);
        t += s->notes[i].ms / 1000.0f;
    }
    for (size_t i = 0; i < len; i++) {
        float v = mix[i] * OUTPUT_SCALE * 32767.0f;
        out[i] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
    }
    return len;
}
