file(GLOB font_srcs "fonts/*.c")
file(GLOB ui_srcs "ui/*.c")
idf_component_register(
    SRCS "main.c" "demo.c" "ble/ble.c" ${ui_srcs} ${font_srcs}
    INCLUDE_DIRS "."
    PRIV_REQUIRES buddy_model esp_driver_gpio bt nvs_flash)
