#include "demo.h"
#include "support.h"

static uint32_t demo_rng = 12345;

static uint32_t lcg(void *ctx)
{
    (void)ctx;
    demo_rng = demo_rng * 1103515245u + 12345u;
    return demo_rng >> 8;
}

TEST(demo_feed_is_always_accepted_and_answers_decisions)
{
    static demo_t d;
    fresh();
    demo_start(&d, &M, lcg, NULL, now);
    int decisions = 0, resolved_by_buddy = 0;
    for (int step = 0; step < 2 * 3600 * 10; step++) {
        now += 100;
        bm_tick(&M, now);
        demo_tick(&d, now);
        const bm_session_t *a = bm_attn_session(&M);
        if (a && step % 37 == 0) {
            if (a->req.is_question) bm_tap(&M, BM_TAP_ANSWER, step % a->req.n_options, now);
            else if (step % 3 == 0 && bm_request_approvable(&a->req)) bm_hold_begin(&M, now);
            else if (step % 3 == 1) bm_tap(&M, BM_TAP_DENY, 0, now);
            else bm_tap(&M, BM_TAP_LATER, 0, now);
        }
        if (step % 600 == 0) bm_swipe(&M, 1, now);
        bm_out_t out;
        while (bm_out_pop(&M, &out)) {
            test_emit(out.json);
            if (strstr(out.json, "permission.decision") || strstr(out.json, "question.answer")) decisions++;
            demo_on_outgoing(&d, &out, now);
        }
        if (d.reply.pending) resolved_by_buddy++;
        bm_sound_t s;
        while (bm_sound_pop(&M, &s)) {
        }
    }
    CHECK(d.rejected == 0);
    CHECK(decisions > 10);
    CHECK(resolved_by_buddy > 0);
    CHECK(bm_session_count(&M) > 0);
}
