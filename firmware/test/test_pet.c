#include "bm_pet.h"
#include "harness.h"

static uint32_t buf[BM_PET_GRID * BM_PET_GRID], other[BM_PET_GRID * BM_PET_GRID];

#define AT(b, x, y) ((b)[(y) * BM_PET_GRID + (x)])

TEST(pet_render_is_deterministic_and_transparent_around)
{
    bm_pet_render(buf, BM_PET_IDLE, 1.25f, 200, BM_ACC_NONE, 0);
    bm_pet_render(other, BM_PET_IDLE, 1.25f, 200, BM_ACC_NONE, 0);
    CHECK(memcmp(buf, other, sizeof(buf)) == 0);
    CHECK(AT(buf, 0, 0) == 0 && AT(buf, 31, 31) == 0 && AT(buf, 0, 20) == 0);
}

TEST(pet_body_uses_the_hue)
{
    bm_pet_render(buf, BM_PET_ERROR, 0, 22, BM_ACC_NONE, 0);
    CHECK(AT(buf, 16, 22) == 0xffef7c39);
    bm_pet_render(buf, BM_PET_ERROR, 0, 200, BM_ACC_NONE, 0);
    CHECK(AT(buf, 16, 22) == 0xff39b2ef);
}

TEST(alert_shows_the_exclamation_mark)
{
    bm_pet_render(buf, BM_PET_ALERT, 0.1f, 22, BM_ACC_NONE, 0);
    CHECK(AT(buf, 27, 4) == (0xff000000u | BM_C_WAIT));
}

TEST(shades_hide_the_eyes_and_hats_replace_the_antenna)
{
    bm_pet_render(buf, BM_PET_ERROR, 0, 22, BM_ACC_NONE, 0);
    CHECK(AT(buf, 15, 6) == (0xff000000u | BM_C_ERR));
    CHECK(AT(buf, 10, 17) == 0xff1b0f0a);
    bm_pet_render(other, BM_PET_ERROR, 0, 22, BM_ACC_SHADES, 0);
    CHECK(AT(other, 10, 17) == 0xff141210);
    bm_pet_render(other, BM_PET_ERROR, 0, 22, BM_ACC_CROWN, 0);
    CHECK(AT(other, 15, 6) != AT(buf, 15, 6));
}

TEST(every_state_and_accessory_renders_something)
{
    for (int s = BM_PET_IDLE; s <= BM_PET_SLEEP; s++)
        for (int a = 0; a < BM_ACC_COUNT; a++)
            for (int f = 0; f < 40; f++) {
                bm_pet_render(buf, (bm_pet_state_t)s, f * 0.07f, (uint16_t)(f * 9), (bm_acc_t)a, 1.7f);
                int opaque = 0;
                for (int i = 0; i < BM_PET_GRID * BM_PET_GRID; i++) opaque += (buf[i] >> 24) == 0xff;
                CHECK(opaque > 150);
            }
}

TEST(cover_is_opaque_and_depends_on_the_title)
{
    static uint32_t a[BM_COVER_GRID * BM_COVER_GRID], b[BM_COVER_GRID * BM_COVER_GRID];
    bm_cover_render(a, "Low Tide");
    bm_cover_render(b, "Fan Noise");
    CHECK(memcmp(a, b, sizeof(a)) != 0);
    for (int i = 0; i < BM_COVER_GRID * BM_COVER_GRID; i++) CHECK((a[i] >> 24) == 0xff);
}
