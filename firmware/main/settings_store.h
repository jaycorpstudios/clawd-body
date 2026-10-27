#pragma once

#include <stdbool.h>

#include "bm.h"

bool settings_store_load(bm_settings_t *out);
bool settings_store_save(const bm_settings_t *s);
