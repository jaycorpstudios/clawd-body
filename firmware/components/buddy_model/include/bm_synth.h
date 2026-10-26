#pragma once

#include <stddef.h>
#include <stdint.h>

#include "bm.h"

#define BM_SYNTH_RATE 22050

size_t bm_synth_length(bm_sound_t snd, uint32_t rate);
size_t bm_synth_render(bm_sound_t snd, uint32_t rate, float *mix, int16_t *out, size_t cap);
