idf_component_register(
    SRCS "src/bm_model.c" "src/bm_ingest.c" "src/bm_derive.c" "src/bm_out.c" "src/bm_pet.c" "src/bm_frame.c" "src/bm_conn.c" "src/bm_synth.c" "src/bm_desk.c"
    INCLUDE_DIRS "include"
    PRIV_INCLUDE_DIRS "src"
    PRIV_REQUIRES json)
