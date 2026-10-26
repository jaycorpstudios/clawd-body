#pragma once

#include <stdbool.h>
#include <stdint.h>

bool ext_rtc_init(void);
bool ext_rtc_read(int64_t *unix_s);
bool ext_rtc_write(int64_t unix_s);
