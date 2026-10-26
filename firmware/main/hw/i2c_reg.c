#include "i2c_reg.h"

#include <string.h>

#include "bsp/esp-bsp.h"

#define I2C_TIMEOUT_MS 50

i2c_master_dev_handle_t i2c_reg_open(uint8_t addr)
{
    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (!bus || i2c_master_probe(bus, addr, I2C_TIMEOUT_MS) != ESP_OK) return NULL;
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = addr,
        .scl_speed_hz = CONFIG_BSP_I2C_CLK_SPEED_HZ,
    };
    i2c_master_dev_handle_t dev = NULL;
    return i2c_master_bus_add_device(bus, &cfg, &dev) == ESP_OK ? dev : NULL;
}

bool i2c_reg_read(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t *out, size_t len)
{
    return i2c_master_transmit_receive(dev, &reg, 1, out, len, I2C_TIMEOUT_MS) == ESP_OK;
}

bool i2c_reg_write(i2c_master_dev_handle_t dev, uint8_t reg, const uint8_t *data, size_t len)
{
    uint8_t buf[16];
    if (len + 1 > sizeof(buf)) return false;
    buf[0] = reg;
    memcpy(buf + 1, data, len);
    return i2c_master_transmit(dev, buf, len + 1, I2C_TIMEOUT_MS) == ESP_OK;
}
