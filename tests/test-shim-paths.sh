#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# test-shim-paths.sh — exercise configurable target-module resolution.
# Usage: ./tests/test-shim-paths.sh
# Requires: pkcs11-tool, opensc-pkcs11.so and a compiler.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

SHIM_DIR="src/pkcs11-shim"
fail=0
total=0

ok()  { total=$((total + 1)); printf '  ✅ %s\n' "$1"; }
bad() { total=$((total + 1)); fail=$((fail + 1)); printf '  ❌ %s\n' "$1"; }

echo "== Build =="
if ! make -C "$SHIM_DIR" clean >/dev/null 2>&1; then :; fi
if ! make -C "$SHIM_DIR" >/dev/null 2>&1; then
  echo "  ❌ build failed"
  exit 1
fi
ok "build"

TOOL="${PKCS11_TOOL:-$(command -v pkcs11-tool || true)}"
if [ -z "$TOOL" ]; then
  echo "  ❌ pkcs11-tool not found (set PKCS11_TOOL)"
  exit 2
fi

MODULE=$(find /usr/lib /usr/lib64 -maxdepth 2 -name opensc-pkcs11.so -print -quit 2>/dev/null)
if [ -z "$MODULE" ]; then
  echo "  ❌ opensc-pkcs11.so not found"
  exit 2
fi

SHIM="$PWD/$SHIM_DIR/libpkcs11-dnie.so"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lib" "$TMP/empty"
ln -s "$MODULE" "$TMP/lib/opensc-pkcs11.so"

run() {
  env -u DNIE_COMPAT_MODULE -u DNIE_COMPAT_SEARCH_PATH -u DNIE_COMPAT_MULTIARCH \
      -u DNIE_COMPAT_CONF -u DNIE_COMPAT_DEBUG "$@" \
      "$TOOL" --module "$SHIM" -L 2>&1
}

expect_ok() {
  local name="$1"; shift
  local output
  output=$(run "$@")
  if printf '%s' "$output" | grep -q 'Failed to load pkcs11 module'; then
    bad "$name (did not load)"
  else
    ok "$name"
  fi
}

expect_fail() {
  local name="$1"; shift
  local output
  output=$(run "$@")
  if printf '%s' "$output" | grep -q 'Failed to load pkcs11 module'; then
    ok "$name"
  else
    bad "$name (should have failed but loaded)"
  fi
}

echo "== Cases =="
expect_ok "exact path (DNIE_COMPAT_MODULE)" \
  DNIE_COMPAT_MODULE="$TMP/lib/opensc-pkcs11.so"

expect_ok "directory (DNIE_COMPAT_SEARCH_PATH)" \
  DNIE_COMPAT_SEARCH_PATH="$TMP/lib"

expect_ok "several directories, valid one last" \
  DNIE_COMPAT_SEARCH_PATH="$TMP/empty:$TMP/lib"

expect_ok "relative path ignored, search used instead" \
  DNIE_COMPAT_MODULE="opensc-pkcs11.so" DNIE_COMPAT_SEARCH_PATH="$TMP/lib"

expect_fail "invalid exact path is authoritative" \
  DNIE_COMPAT_MODULE="$TMP/does-not-exist.so" DNIE_COMPAT_SEARCH_PATH="$TMP/lib"

printf 'module=%s\n' "$TMP/lib/opensc-pkcs11.so" > "$TMP/conf-module.conf"
expect_ok "config file: module=" \
  DNIE_COMPAT_CONF="$TMP/conf-module.conf"

printf 'search=%s\n' "$TMP/lib" > "$TMP/conf-search.conf"
expect_ok "config file: search=" \
  DNIE_COMPAT_CONF="$TMP/conf-search.conf"

printf 'module=/does/not/exist.so\n' > "$TMP/conf-bad.conf"
expect_fail "invalid config file" \
  DNIE_COMPAT_CONF="$TMP/conf-bad.conf"

debug_output=$(run DNIE_COMPAT_DEBUG=1 DNIE_COMPAT_SEARCH_PATH="$TMP/lib")
if printf '%s' "$debug_output" | grep -q 'dnie-compat: conf='; then
  ok "DNIE_COMPAT_DEBUG diagnostics"
else
  bad "DNIE_COMPAT_DEBUG diagnostics"
fi

runtime_multi=$(run DNIE_COMPAT_DEBUG=1 DNIE_COMPAT_MULTIARCH=tripleta-runtime)
if printf '%s' "$runtime_multi" | grep -q '/usr/lib/tripleta-runtime/opensc-pkcs11.so'; then
  ok "DNIE_COMPAT_MULTIARCH at runtime"
else
  bad "DNIE_COMPAT_MULTIARCH at runtime"
fi

echo "== Build with custom MULTIARCH =="
if make -C "$SHIM_DIR" clean >/dev/null 2>&1 && make -C "$SHIM_DIR" MULTIARCH=tripleta-build >/dev/null 2>&1; then
  build_multi=$(run DNIE_COMPAT_DEBUG=1)
  if printf '%s' "$build_multi" | grep -q '/usr/lib/tripleta-build/opensc-pkcs11.so'; then
    ok "make MULTIARCH=tripleta-build"
  else
    bad "make MULTIARCH=tripleta-build"
  fi
else
  bad "make MULTIARCH=tripleta-build (build failed)"
fi

echo "== Build with empty MULTIARCH =="
if make -C "$SHIM_DIR" clean >/dev/null 2>&1 && make -C "$SHIM_DIR" MULTIARCH= >/dev/null 2>&1; then
  if env -u DNIE_COMPAT_MODULE -u DNIE_COMPAT_SEARCH_PATH -u DNIE_COMPAT_MULTIARCH \
       -u DNIE_COMPAT_CONF "$TOOL" --module "$SHIM" -L 2>&1 | grep -q 'Failed to load'; then
    bad "make MULTIARCH= (did not load through built-in paths)"
  else
    ok "make MULTIARCH= (built-in paths)"
  fi
else
  bad "make MULTIARCH= (build failed)"
fi
echo "== Security =="
mkfifo "$TMP/config.fifo"
fifo_output=$(timeout 10 env DNIE_COMPAT_CONF="$TMP/config.fifo" "$TOOL" --module "$SHIM" -L 2>&1)
fifo_rc=$?
if [ "$fifo_rc" -ne 124 ] && ! printf '%s' "$fifo_output" | grep -q 'Failed to load'; then
  ok "FIFO configuration ignored (no hang)"
else
  bad "FIFO configuration ignored (no hang)"
fi

directory_output=$(run DNIE_COMPAT_CONF="$TMP")
if printf '%s' "$directory_output" | grep -q 'Failed to load'; then
  bad "directory configuration ignored"
else
  ok "directory configuration ignored"
fi

long_path=$(printf '/a%.0s' $(seq 1 2500))
long_output=$(run DNIE_COMPAT_SEARCH_PATH="$long_path:$TMP/lib")
if printf '%s' "$long_output" | grep -q 'Failed to load'; then
  bad "oversized search entry ignored"
else
  ok "oversized search entry ignored"
fi

if readelf -d "$SHIM" 2>/dev/null | grep -q 'BIND_NOW'; then
  ok "BIND_NOW (full RELRO)"
else
  bad "BIND_NOW (full RELRO)"
fi
if readelf -l "$SHIM" 2>/dev/null | grep -q 'GNU_RELRO'; then
  ok "GNU_RELRO segment"
else
  bad "GNU_RELRO segment"
fi

exports=$(nm -D --defined-only "$SHIM" 2>/dev/null | awk '{print $3}' | grep -E '^C_' | sort | tr '\n' ' ')
export_count=$(printf '%s' "$exports" | wc -w)
if [ "$export_count" -eq 2 ] && printf '%s' "$exports" | grep -q 'C_GetFunctionList' && \
   printf '%s' "$exports" | grep -q 'C_GetInterface'; then
  ok "only C_GetFunctionList and C_GetInterface exported"
else
  bad "exported symbols ($exports)"
fi

cc -O2 -pthread -o "$TMP/threads" tests/test-shim-threads.c -ldl 2>/dev/null
if DNIE_COMPAT_MODULE="$MODULE" timeout 60 "$TMP/threads" "$SHIM" 2>/dev/null | grep -q '^OK$'; then
  ok "concurrent C_GetFunctionList (8 threads)"
else
  bad "concurrent C_GetFunctionList (8 threads)"
fi

echo "== Non-FHS install (Guix/Nix style) =="
prefix="$TMP/prefix"
if make -C "$SHIM_DIR" clean >/dev/null 2>&1 && \
   make -C "$SHIM_DIR" PREFIX="$prefix" MODULE_PATH="$MODULE" >/dev/null 2>&1 && \
   make -C "$SHIM_DIR" install PREFIX="$prefix" >/dev/null 2>&1; then
  installed="$prefix/lib/libpkcs11-dnie.so"
  module_file="$prefix/share/p11-kit/modules/dnie-compat.module"
  if [ -f "$installed" ] && grep -qx "module: $installed" "$module_file"; then
    nonfhs_output=$(env -u DNIE_COMPAT_MODULE -u DNIE_COMPAT_SEARCH_PATH \
                        -u DNIE_COMPAT_MULTIARCH -u DNIE_COMPAT_CONF \
                        "$TOOL" --module "$installed" -L 2>&1)
    if printf '%s' "$nonfhs_output" | grep -q 'Failed to load'; then
      bad "non-FHS install loads through embedded MODULE_PATH"
    else
      ok "non-FHS install loads through embedded MODULE_PATH"
    fi
  else
    bad "non-FHS install layout"
  fi
else
  bad "non-FHS install build"
fi

make -C "$SHIM_DIR" clean >/dev/null 2>&1 && make -C "$SHIM_DIR" >/dev/null 2>&1

echo
if [ "$fail" -eq 0 ]; then
  echo "RESULT: OK ($total tests)"
else
  echo "RESULT: $fail failure(s) out of $total"
fi
exit "$fail"
