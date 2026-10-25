#pragma once

#include <stdio.h>
#include <string.h>

typedef void (*test_fn)(void);
void test_register(const char *name, test_fn fn);
void test_fail(const char *file, int line, const char *expr);
void test_emit(const char *json);

#define TEST(name)                                                                                                     \
    static void name(void);                                                                                            \
    __attribute__((constructor)) static void register_##name(void) { test_register(#name, name); }                     \
    static void name(void)

#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        if (!(cond)) test_fail(__FILE__, __LINE__, #cond);                                                             \
    } while (0)

#define CHECK_STR(a, b)                                                                                                \
    do {                                                                                                               \
        if (strcmp((a), (b)) != 0) {                                                                                   \
            char msg_[512];                                                                                            \
            snprintf(msg_, sizeof(msg_), "\"%s\" != \"%s\"", (a), (b));                                                \
            test_fail(__FILE__, __LINE__, msg_);                                                                       \
        }                                                                                                              \
    } while (0)
