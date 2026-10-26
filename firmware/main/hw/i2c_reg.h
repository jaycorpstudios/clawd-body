#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "driver/i2c_master.h"

i2c_master_dev_handle_t i2c_reg_open(uint8_t addr);
bool i2c_reg_read(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t *out, size_t len);
bool i2c_reg_write(i2c_master_dev_handle_t dev, uint8_t reg, const uint8_t *data, size_t len);
