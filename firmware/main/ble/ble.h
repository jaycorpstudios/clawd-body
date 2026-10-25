#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "bm.h"

#define BLE_LINKS BM_MAX_HOSTS

typedef enum {
    BLE_EV_OPEN,
    BLE_EV_CLOSE,
    BLE_EV_MESSAGE,
    BLE_EV_PASSKEY,
    BLE_EV_PAIRED,
    BLE_EV_PAIR_FAILED,
} ble_ev_kind_t;

typedef struct {
    uint8_t kind;
    uint8_t link;
    uint32_t value;
} ble_ev_t;

bool ble_start(void);
size_t ble_poll(ble_ev_t *ev, char *payload, size_t cap);
void ble_set_pairing(bool on);
void ble_tick(void);
bool ble_send(int link, const char *json, size_t len);
