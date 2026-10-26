#include "ext_rtc.h"

#include "esp_log.h"

#include "bm.h"
#include "i2c_reg.h"

#define PCF_ADDR 0x51
#define REG_SECONDS 0x04
#define SECONDS_OS 0x80
#define MIN_VALID_YEAR 2026

static const char *TAG = "rtc";
static i2c_master_dev_handle_t pcf;

static uint8_t from_bcd(uint8_t v) { return (uint8_t)((v >> 4) * 10 + (v & 0x0f)); }
static uint8_t to_bcd(int v) { return (uint8_t)(((v / 10) << 4) | (v % 10)); }

bool ext_rtc_init(void)
{
    pcf = i2c_reg_open(PCF_ADDR);
    if (!pcf) ESP_LOGW(TAG, "no PCF85063 at 0x%02x", PCF_ADDR);
    return pcf != NULL;
}

bool ext_rtc_read(int64_t *unix_s)
{
    uint8_t r[7];
    if (!pcf || !i2c_reg_read(pcf, REG_SECONDS, r, sizeof(r))) return false;
    if (r[0] & SECONDS_OS) return false;
    bm_utc_t t = {
        .sec = from_bcd(r[0] & 0x7f),
        .min = from_bcd(r[1] & 0x7f),
        .hour = from_bcd(r[2] & 0x3f),
        .day = from_bcd(r[3] & 0x3f),
        .month = from_bcd(r[5] & 0x1f),
        .year = 2000 + from_bcd(r[6]),
    };
    if (t.year < MIN_VALID_YEAR || t.month < 1 || t.month > 12 || t.day < 1 || t.day > 31) return false;
    *unix_s = bm_unix_from_utc(&t);
    return true;
}

bool ext_rtc_write(int64_t unix_s)
{
    if (!pcf) return false;
    bm_utc_t t;
    bm_utc_from_unix(unix_s, &t);
    if (t.year < 2000 || t.year > 2099) return false;
    uint8_t r[7] = {to_bcd(t.sec), to_bcd(t.min), to_bcd(t.hour), to_bcd(t.day), (uint8_t)t.wday, to_bcd(t.month),
                    to_bcd(t.year - 2000)};
    return i2c_reg_write(pcf, REG_SECONDS, r, sizeof(r));
}
