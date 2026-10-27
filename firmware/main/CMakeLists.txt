file(GLOB font_srcs "fonts/*.c")
file(GLOB ui_srcs "ui/*.c")
file(GLOB hw_srcs "hw/*.c")
idf_component_register(
    SRCS "main.c" "demo.c" "settings_store.c" "lv_mem_psram.c" "ble/ble.c" ${ui_srcs} ${hw_srcs} ${font_srcs}
    INCLUDE_DIRS "."
    PRIV_REQUIRES buddy_model esp_driver_gpio esp_driver_i2c bt nvs_flash)
# main is linked before lvgl, so pull in the allocator lvgl expects from us.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u lv_mem_init")
