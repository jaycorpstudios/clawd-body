#include <stdlib.h>

#include "bm_synth.h"
#include "harness.h"

#define CAP (BM_SYNTH_RATE * 2)

static float mix[CAP];
static int16_t pcm[CAP];

static int peak(size_t from, size_t to)
{
    int p = 0;
    for (size_t i = from; i < to; i++) p = abs(pcm[i]) > p ? abs(pcm[i]) : p;
    return p;
}

TEST(every_sound_renders_audible_and_unclipped)
{
    for (int snd = BM_SND_PERM; snd <= BM_SND_CLICK; snd++) {
        size_t n = bm_synth_render((bm_sound_t)snd, BM_SYNTH_RATE, mix, pcm, CAP);
        CHECK(n > 0 && n == bm_synth_length((bm_sound_t)snd, BM_SYNTH_RATE));
        int p = peak(0, n);
        CHECK(p > 2000 && p < 32767);
        CHECK(pcm[0] == 0 && abs(pcm[n - 1]) < p / 25);
    }
}

TEST(lengths_follow_the_prototype_notes_and_bell_tails)
{
    CHECK(bm_synth_length(BM_SND_CLICK, 1000) == 25);
    CHECK(bm_synth_length(BM_SND_PERM, 1000) == 760);
    CHECK(bm_synth_length(BM_SND_DONE, 1000) == 812);
    CHECK(bm_synth_length(BM_SND_LIMIT, 1000) == 640);
}

TEST(rests_are_silent_and_reminder_is_half_as_loud)
{
    size_t n = bm_synth_render(BM_SND_PERM, BM_SYNTH_RATE, mix, pcm, CAP);
    CHECK(n > 0);
    CHECK(peak(BM_SYNTH_RATE * 315 / 1000, BM_SYNTH_RATE * 405 / 1000) == 0);
    int perm = peak(0, BM_SYNTH_RATE * 90 / 1000);
    bm_synth_render(BM_SND_REMINDER, BM_SYNTH_RATE, mix, pcm, CAP);
    int reminder = peak(0, BM_SYNTH_RATE * 90 / 1000);
    CHECK(abs(reminder * 2 - perm) < perm / 20);
}

TEST(render_refuses_a_buffer_too_small)
{
    CHECK(bm_synth_render(BM_SND_PERM, BM_SYNTH_RATE, mix, pcm, 100) == 0);
    CHECK(bm_synth_length((bm_sound_t)99, BM_SYNTH_RATE) == 0);
}
