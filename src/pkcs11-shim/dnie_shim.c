/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * dnie_shim.c — PKCS#11 compatibility module for the Spanish DNIe.
 *
 * Copyright (C) 2026 dni-e contributors
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details. You should have received a copy of the GNU General Public
 * License along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * It exposes the PKCS#11 ABI under the name and path expected by official
 * applications and guides (libpkcs11-dnie.so) and delegates the whole
 * implementation to OpenSC (opensc-pkcs11.so), which is free software and
 * multi-architecture.
 *
 * This is NOT the official DGP/FNMT module: it is an independent
 * implementation based on OpenSC. It does not modify or redistribute the
 * official binary.
 *
 * Target module resolution, highest priority first:
 *
 *   1. DNIE_COMPAT_MODULE=/exact/path/opensc-pkcs11.so
 *      When set, it is authoritative: if it fails, nothing else is tried.
 *
 *   2. DNIE_COMPAT_SEARCH_PATH=/dir1:/dir2
 *      Directories where opensc-pkcs11.so (and pkcs11/opensc-pkcs11.so) is
 *      searched for.
 *
 *   3. /etc/dnie-compat.conf  (path configurable via DNIE_COMPAT_CONF)
 *      Keys: module=, search=, multiarch=
 *
 *   4. DNIE_COMPAT_MULTIARCH=aarch64-linux-gnu
 *      Tripleta used for /usr/lib/<tripleta>/... It overrides the one chosen
 *      at build time (make MULTIARCH=...).
 *
 *   5. Built-in paths and glob search under /usr/lib/<something>/.
 *
 * Relative paths are ignored. DNIE_COMPAT_DEBUG=1 prints the resolved
 * configuration and every attempted path to stderr.
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <dlfcn.h>
#include <glob.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned long CK_RV;
typedef CK_RV (*CK_GET_FUNCTION_LIST)(void **);

#define CKR_OK                    0x00000000UL
#define CKR_ARGUMENTS_BAD          0x00000007UL
#define CKR_GENERAL_ERROR          0x00000005UL
#define CKR_FUNCTION_NOT_SUPPORTED 0x00000054UL

#define MAX_CANDIDATES 64

#ifndef DNIE_COMPAT_MULTIARCH
#define DNIE_COMPAT_MULTIARCH ""
#endif

#ifndef DNIE_COMPAT_CONFIG_FILE
#define DNIE_COMPAT_CONFIG_FILE "/etc/dnie-compat.conf"
#endif

typedef struct {
    char *module;
    char *search;
    char *multiarch;
} Config;

static void *g_module = NULL;
static CK_GET_FUNCTION_LIST g_get_function_list = NULL;
static CK_RV g_load_status = CKR_GENERAL_ERROR;

static char *g_candidates[MAX_CANDIDATES];
static size_t g_candidate_count = 0;

static int debug_enabled(void) {
    const char *v = getenv("DNIE_COMPAT_DEBUG");
    return v != NULL && v[0] != '\0' && v[0] != '0';
}

static char *trim(char *s) {
    char *end;

    while (*s != '\0' && isspace((unsigned char)*s)) {
        s++;
    }
    if (*s == '\0') {
        return s;
    }
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) {
        *end = '\0';
        end--;
    }
    return s;
}

static void set_str(char **dst, const char *value) {
    free(*dst);
    *dst = (value != NULL) ? strdup(value) : NULL;
}

static int is_absolute(const char *path) {
    return path != NULL && path[0] == '/';
}

static void add_candidate(const char *path) {
    size_t i;

    if (!is_absolute(path)) {
        return;
    }
    for (i = 0; i < g_candidate_count; i++) {
        if (strcmp(g_candidates[i], path) == 0) {
            return;
        }
    }
    if (g_candidate_count >= MAX_CANDIDATES) {
        return;
    }
    g_candidates[g_candidate_count] = strdup(path);
    if (g_candidates[g_candidate_count] != NULL) {
        g_candidate_count++;
    }
}

static void add_search_dirs(const char *list) {
    char buffer[PATH_MAX];
    char *copy;
    char *save = NULL;
    char *token;

    if (list == NULL || list[0] == '\0') {
        return;
    }
    copy = strdup(list);
    if (copy == NULL) {
        return;
    }

    for (token = strtok_r(copy, ":", &save); token != NULL;
         token = strtok_r(NULL, ":", &save)) {
        token = trim(token);
        if (token[0] == '\0') {
            continue;
        }
        if (!is_absolute(token)) {
            if (debug_enabled()) {
                fprintf(stderr, "dnie-compat: ignored (not absolute): %s\n", token);
            }
            continue;
        }
        snprintf(buffer, sizeof(buffer), "%s/opensc-pkcs11.so", token);
        add_candidate(buffer);
        snprintf(buffer, sizeof(buffer), "%s/pkcs11/opensc-pkcs11.so", token);
        add_candidate(buffer);
    }
    free(copy);
}

static void parse_config(const char *path, Config *config) {
    char line[2 * PATH_MAX];
    FILE *file;

    file = fopen(path, "r");
    if (file == NULL) {
        return;
    }

    while (fgets(line, sizeof(line), file) != NULL) {
        char *key;
        char *value;
        char *equals;
        char *entry = trim(line);

        if (entry[0] == '\0' || entry[0] == '#') {
            continue;
        }
        equals = strchr(entry, '=');
        if (equals == NULL) {
            continue;
        }
        *equals = '\0';
        key = trim(entry);
        value = trim(equals + 1);

        if (strcmp(key, "module") == 0) {
            set_str(&config->module, value);
        } else if (strcmp(key, "search") == 0) {
            set_str(&config->search, value);
        } else if (strcmp(key, "multiarch") == 0) {
            set_str(&config->multiarch, value);
        }
    }
    fclose(file);
}

static void resolve_config(Config *config) {
    const char *conf_path = getenv("DNIE_COMPAT_CONF");
    const char *value;

    if (conf_path == NULL || conf_path[0] == '\0') {
        conf_path = DNIE_COMPAT_CONFIG_FILE;
    }
    parse_config(conf_path, config);

    value = getenv("DNIE_COMPAT_MODULE");
    if (value != NULL && value[0] != '\0') {
        set_str(&config->module, value);
    }
    value = getenv("DNIE_COMPAT_SEARCH_PATH");
    if (value != NULL && value[0] != '\0') {
        set_str(&config->search, value);
    }
    value = getenv("DNIE_COMPAT_MULTIARCH");
    if (value != NULL && value[0] != '\0') {
        set_str(&config->multiarch, value);
    }

    if (config->multiarch == NULL || config->multiarch[0] == '\0') {
        set_str(&config->multiarch, DNIE_COMPAT_MULTIARCH);
    }

    if (debug_enabled()) {
        fprintf(stderr,
                "dnie-compat: conf=%s module=%s search=%s multiarch=%s\n",
                conf_path,
                config->module != NULL ? config->module : "(none)",
                config->search != NULL ? config->search : "(none)",
                (config->multiarch != NULL && config->multiarch[0] != '\0')
                    ? config->multiarch
                    : "(none)");
    }
}

static CK_RV try_load(const char *path) {
    void *handle;
    CK_GET_FUNCTION_LIST function_list;

    if (debug_enabled()) {
        fprintf(stderr, "dnie-compat: trying %s\n", path);
    }

    handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        if (debug_enabled()) {
            fprintf(stderr, "dnie-compat: %s\n", dlerror());
        }
        return CKR_GENERAL_ERROR;
    }

    *(void **)(&function_list) = dlsym(handle, "C_GetFunctionList");
    if (function_list == NULL) {
        dlclose(handle);
        return CKR_GENERAL_ERROR;
    }

    g_module = handle;
    g_get_function_list = function_list;
    return CKR_OK;
}

static CK_RV try_glob(const char *pattern) {
    glob_t matches;
    CK_RV result = CKR_GENERAL_ERROR;
    size_t i;

    if (glob(pattern, 0, NULL, &matches) != 0) {
        return result;
    }
    for (i = 0; i < matches.gl_pathc; i++) {
        if (try_load(matches.gl_pathv[i]) == CKR_OK) {
            result = CKR_OK;
            break;
        }
    }
    globfree(&matches);
    return result;
}

static void add_multiarch_candidates(const char *multiarch) {
    char buffer[PATH_MAX];

    if (multiarch == NULL || multiarch[0] == '\0') {
        return;
    }
    snprintf(buffer, sizeof(buffer), "/usr/lib/%s/opensc-pkcs11.so", multiarch);
    add_candidate(buffer);
    snprintf(buffer, sizeof(buffer), "/usr/lib/%s/pkcs11/opensc-pkcs11.so", multiarch);
    add_candidate(buffer);
    snprintf(buffer, sizeof(buffer), "/usr/lib64/%s/opensc-pkcs11.so", multiarch);
    add_candidate(buffer);
}

static void add_default_candidates(void) {
    add_candidate("/usr/lib/opensc-pkcs11.so");
    add_candidate("/usr/lib64/opensc-pkcs11.so");
    add_candidate("/usr/lib/pkcs11/opensc-pkcs11.so");
    add_candidate("/usr/local/lib/opensc-pkcs11.so");
}

static CK_RV load_target(void) {
    static const char *const patterns[] = {
        "/usr/lib/*/opensc-pkcs11.so",
        "/usr/lib/*/pkcs11/opensc-pkcs11.so",
        "/usr/lib/*-linux-gnu*/opensc-pkcs11.so",
        NULL
    };
    Config config = {NULL, NULL, NULL};
    size_t i;

    if (g_get_function_list != NULL) {
        return CKR_OK;
    }

    resolve_config(&config);

    /* 1. Exact path: authoritative. */
    if (is_absolute(config.module)) {
        g_load_status = try_load(config.module);
        goto finished;
    }
    if (config.module != NULL && config.module[0] != '\0' && debug_enabled()) {
        fprintf(stderr, "dnie-compat: ignored (not absolute): %s\n", config.module);
    }

    /* 2 and 3. Configured directories and multiarch tripleta. */
    add_search_dirs(config.search);
    add_multiarch_candidates(config.multiarch);

    /* 4. Built-in paths. */
    add_default_candidates();

    for (i = 0; i < g_candidate_count; i++) {
        if (try_load(g_candidates[i]) == CKR_OK) {
            g_load_status = CKR_OK;
            goto finished;
        }
    }

    /* 5. Glob multiarch as a last resort. */
    for (i = 0; patterns[i] != NULL; i++) {
        if (try_glob(patterns[i]) == CKR_OK) {
            g_load_status = CKR_OK;
            goto finished;
        }
    }

    if (debug_enabled()) {
        fprintf(stderr, "dnie-compat: opensc-pkcs11.so not found\n");
    }
    g_load_status = CKR_GENERAL_ERROR;

finished:
    free(config.module);
    free(config.search);
    free(config.multiarch);
    return g_load_status;
}

CK_RV C_GetFunctionList(void **ppFunctionList) {
    CK_RV rv;

    if (ppFunctionList == NULL) {
        return CKR_ARGUMENTS_BAD;
    }

    rv = load_target();
    if (rv != CKR_OK) {
        return rv;
    }

    return g_get_function_list(ppFunctionList);
}

/*
 * PKCS#11 3.0: some modern consumers call C_GetInterface. If the target module
 * implements it, it is forwarded; otherwise the consumer is told it is not
 * supported and can fall back to C_GetFunctionList.
 */
CK_RV C_GetInterface(const char *pInterfaceName,
                     void *pVersion,
                     void **ppInterface,
                     unsigned long flags) {
    typedef CK_RV (*CK_GET_INTERFACE)(const char *, void *, void **, unsigned long);
    CK_GET_INTERFACE target;

    if (ppInterface == NULL) {
        return CKR_ARGUMENTS_BAD;
    }
    if (load_target() != CKR_OK) {
        return CKR_GENERAL_ERROR;
    }

    *(void **)(&target) = dlsym(g_module, "C_GetInterface");
    if (target == NULL) {
        return CKR_FUNCTION_NOT_SUPPORTED;
    }
    return target(pInterfaceName, pVersion, ppInterface, flags);
}
