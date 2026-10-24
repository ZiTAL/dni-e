/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Concurrent C_GetFunctionList smoke test.
 * Usage: test-shim-threads <shim.so>
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

typedef unsigned long (*get_function_list_t)(void **);

static get_function_list_t g_get_function_list;
static long g_failures;

static void *worker(void *arg) {
    long i;
    (void)arg;
    for (i = 0; i < 2000; i++) {
        void *list = NULL;
        unsigned long rv = g_get_function_list(&list);
        if (rv != 0 || list == NULL) {
            __sync_fetch_and_add(&g_failures, 1);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    pthread_t threads[8];
    void *handle;
    int i;

    if (argc < 2) {
        fprintf(stderr, "usage: %s <shim.so>\n", argv[0]);
        return 2;
    }

    handle = dlopen(argv[1], RTLD_NOW);
    if (handle == NULL) {
        fprintf(stderr, "%s\n", dlerror());
        return 2;
    }
    *(void **)(&g_get_function_list) = dlsym(handle, "C_GetFunctionList");
    if (g_get_function_list == NULL) {
        fprintf(stderr, "C_GetFunctionList not found\n");
        return 2;
    }

    for (i = 0; i < 8; i++) {
        if (pthread_create(&threads[i], NULL, worker, NULL) != 0) {
            fprintf(stderr, "pthread_create failed\n");
            return 2;
        }
    }
    for (i = 0; i < 8; i++) {
        pthread_join(threads[i], NULL);
    }

    if (g_failures != 0) {
        fprintf(stderr, "%ld concurrent failures\n", g_failures);
        return 1;
    }
    printf("OK\n");
    return 0;
}
