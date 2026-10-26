#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool battery;
    bool usb;
    bool charging;
    uint8_t pct;
    uint16_t mv;
} power_state_t;

bool power_init(void);
bool power_read(power_state_t *out);
