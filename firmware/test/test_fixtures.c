#include <dirent.h>
#include <stdlib.h>

#include "cJSON.h"
#include "support.h"

#ifndef FIXTURES_DIR
#error "FIXTURES_DIR must point to shared/fixtures"
#endif

static const char *const BUDDY_TO_MAC[] = {"permission.decision", "question.answer", "device."};

static const char *const TOLERATED_INVALID[] = {
    "extra-envelope-field.json",
    "window-reset-with-data.json",
};

static bool starts_with_any(const char *s, const char *const *prefixes, size_t n)
{
    for (size_t i = 0; i < n; i++)
        if (strncmp(s, prefixes[i], strlen(prefixes[i])) == 0) return true;
    return false;
}

static bool listed(const char *name, const char *const *names, size_t n)
{
    for (size_t i = 0; i < n; i++)
        if (strcmp(name, names[i]) == 0) return true;
    return false;
}

typedef void (*fixture_fn)(const char *name, cJSON *root);

static int each_fixture(const char *sub, fixture_fn fn)
{
    char dir[512];
    snprintf(dir, sizeof(dir), "%s/%s", FIXTURES_DIR, sub);
    DIR *d = opendir(dir);
    CHECK(d != NULL);
    if (!d) return 0;
    int n = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strstr(e->d_name, ".json")) continue;
        char path[1024];
        size_t len;
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
        char *text = read_file(path, &len);
        cJSON *root = cJSON_ParseWithLength(text, len);
        CHECK(root != NULL);
        if (root) fn(e->d_name, root);
        cJSON_Delete(root);
        free(text);
        n++;
    }
    closedir(d);
    return n;
}

static void check_valid(const char *name, cJSON *root)
{
    fresh();
    const char *type = cJSON_GetObjectItem(root, "type")->valuestring;
    char *json = cJSON_PrintUnformatted(root);
    bm_err_t err = send_raw(json);
    bool outgoing = starts_with_any(type, BUDDY_TO_MAC, 3);
    if (outgoing ? err != BM_E_ENVELOPE && err != BM_E_TYPE : err != BM_OK) {
        char msg[160];
        snprintf(msg, sizeof(msg), "%s: unexpected result %d", name, err);
        test_fail(__FILE__, __LINE__, msg);
    }
    if (!outgoing) CHECK(send_raw(json) == BM_E_DUPLICATE);
    free(json);
}

TEST(every_valid_fixture_is_accepted_or_is_buddy_to_mac)
{
    CHECK(each_fixture("valid", check_valid) >= 20);
}

static void check_invalid(const char *name, cJSON *root)
{
    fresh();
    char *json = cJSON_PrintUnformatted(cJSON_GetObjectItem(root, "event"));
    bm_err_t err = send_raw(json);
    bool tolerated = listed(name, TOLERATED_INVALID, sizeof(TOLERATED_INVALID) / sizeof(TOLERATED_INVALID[0]));
    if (tolerated ? err != BM_OK : err == BM_OK) {
        char msg[200];
        snprintf(msg, sizeof(msg), "%s (%s): result %d", name, cJSON_GetObjectItem(root, "reason")->valuestring, err);
        test_fail(__FILE__, __LINE__, msg);
    }
    free(json);
}

TEST(every_invalid_fixture_is_rejected_except_unknown_fields)
{
    CHECK(each_fixture("invalid", check_invalid) >= 20);
}

TEST(rejected_message_leaves_state_untouched)
{
    fresh();
    start_session("work", "s1", "alpha");
    uint32_t rev = M.rev;
    CHECK(send("work", "snapshot", "{\"sessions\":[],\"usage\":{\"session_pct\":120,\"weekly_pct\":1,\"reset_in_min\":5},"
                                   "\"hilo\":{\"current\":null,\"next\":[],\"agreements_today\":[]}}") == BM_E_DATA);
    CHECK(session_index("work", "s1") >= 0);
    CHECK(M.rev == rev);
}

TEST(not_json_and_unknown_version_are_rejected)
{
    fresh();
    CHECK(send_raw("{not json") == BM_E_JSON);
    CHECK(send_raw("{\"v\":2,\"id\":\"01K8F400000000000000000008\",\"ts\":1,\"host\":\"work\",\"type\":\"session.end\","
                   "\"data\":{\"session\":\"x\"}}") == BM_E_VERSION);
}

TEST(third_host_is_rejected)
{
    fresh();
    CHECK(send("lab", "session.start", "{\"session\":\"s\",\"project\":\"p\",\"task\":\"t\"}") == BM_E_HOSTS_FULL);
}
