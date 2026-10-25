file(GLOB font_srcs "fonts/*.c")
idf_component_register(SRCS "main.c" ${font_srcs} INCLUDE_DIRS "." PRIV_REQUIRES buddy_model)
