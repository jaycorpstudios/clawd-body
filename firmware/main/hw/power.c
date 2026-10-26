#include "power.h"

#include "esp_log.h"

#include "i2c_reg.h"

/* AXP2101 registers, read only: the BSP never touches the PMU and its power-on defaults run the board. */
#define AXP_ADDR 0x34
#define AXP_CHIP_ID 0x4a
#define REG_STATUS1 0x00
#define REG_STATUS2 0x01
#define REG_CHIP_ID 0x03
#define REG_GAUGE_CTRL 0x18
#define REG_ADC_ENABLE 0x30
#define REG_VBAT_H 0x34
#define REG_BAT_DETECT 0x68
#define REG_BAT_PCT 0xa4

#define STATUS1_VBUS_GOOD 0x20
#define STATUS1_BAT_PRESENT 0x08
#define STATUS2_DIR(v) (((v) >> 5) & 0x3)
#define DIR_CHARGING 1

static const char *TAG = "power";
static i2c_master_dev_handle_t axp;

static uint8_t reg(uint8_t r)
{
    uint8_t v = 0;
    i2c_reg_read(axp, r, &v, 1);
    return v;
}

bool power_init(void)
{
    axp = i2c_reg_open(AXP_ADDR);
    if (!axp) {
        ESP_LOGW(TAG, "no AXP2101 at 0x%02x", AXP_ADDR);
        return false;
    }
    uint8_t id = reg(REG_CHIP_ID);
    ESP_LOGI(TAG, "axp id 0x%02x status 0x%02x/0x%02x gauge 0x%02x adc 0x%02x batdet 0x%02x", id, reg(REG_STATUS1),
             reg(REG_STATUS2), reg(REG_GAUGE_CTRL), reg(REG_ADC_ENABLE), reg(REG_BAT_DETECT));
    if (id != AXP_CHIP_ID) {
        ESP_LOGW(TAG, "unexpected chip id, battery left unknown");
        axp = NULL;
        return false;
    }
    return true;
}

bool power_read(power_state_t *out)
{
    if (!axp) return false;
    uint8_t s[2], v[2], pct;
    if (!i2c_reg_read(axp, REG_STATUS1, s, 2) || !i2c_reg_read(axp, REG_VBAT_H, v, 2) ||
        !i2c_reg_read(axp, REG_BAT_PCT, &pct, 1))
        return false;
    out->battery = s[0] & STATUS1_BAT_PRESENT;
    out->usb = s[0] & STATUS1_VBUS_GOOD;
    out->charging = out->battery && STATUS2_DIR(s[1]) == DIR_CHARGING;
    out->pct = pct > 100 ? 100 : pct;
    out->mv = (uint16_t)(((v[0] & 0x3f) << 8) | v[1]);
    return true;
}
