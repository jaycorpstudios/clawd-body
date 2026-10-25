#include "harness.h"

#include <stdlib.h>

#define MAX_TESTS 256

typedef struct {
    const char *name;
    test_fn fn;
} test_t;

static test_t tests[MAX_TESTS];
static int n_tests, failures;
static const char *current;
static FILE *emit_file;

void test_register(const char *name, test_fn fn)
{
    if (n_tests < MAX_TESTS) tests[n_tests++] = (test_t){name, fn};
}

void test_fail(const char *file, int line, const char *expr)
{
    failures++;
    fprintf(stderr, "FAIL %s (%s:%d): %s\n", current, file, line, expr);
}

void test_emit(const char *json)
{
    if (emit_file) fprintf(emit_file, "%s\n", json);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *filter = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--emit") == 0 && i + 1 < argc) emit_file = fopen(argv[++i], "w");
        else filter = argv[i];
    }
    int ran = 0;
    for (int i = 0; i < n_tests; i++) {
        if (filter && !strstr(tests[i].name, filter)) continue;
        current = tests[i].name;
        int before = failures;
        tests[i].fn();
        ran++;
        if (failures == before) printf("ok   %s\n", current);
    }
    if (emit_file) fclose(emit_file);
    printf("%d tests, %d failures\n", ran, failures);
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
