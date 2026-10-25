#pragma once

#include "bm.h"

#define BM_PET_GRID 32
#define BM_PET_MAIN_HUE 22

void bm_pet_render(uint32_t argb[BM_PET_GRID * BM_PET_GRID], bm_pet_state_t state, float t, uint16_t hue,
                   bm_acc_t acc, float seed);

#define BM_COVER_GRID 16

void bm_cover_render(uint32_t argb[BM_COVER_GRID * BM_COVER_GRID], const char *title);
