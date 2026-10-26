#pragma once

#include <stdbool.h>

#include "bm.h"

bool audio_init(int volume);
void audio_play(bm_sound_t snd);
