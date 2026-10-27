#pragma once

#include <stdbool.h>

#include "bm.h"

/* Fills only what was saved, so start from the current settings. */
bool settings_store_load(bm_settings_t *out);
bool settings_store_save(const bm_settings_t *s);
