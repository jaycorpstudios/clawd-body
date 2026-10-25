#include "bsp/esp-bsp.h"
#include "bsp/display.h"
#include "lvgl.h"

void app_main(void)
{
    bsp_display_start();
    bsp_display_lock(-1);

    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);

    lv_obj_t *title = lv_label_create(screen);
    lv_label_set_text(title, "Hilo Buddy");
    lv_obj_set_style_text_color(title, lv_color_hex(0xff9a52), 0);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_32, 0);
    lv_obj_center(title);

    bsp_display_unlock();
}
