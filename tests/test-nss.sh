#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# test-nss.sh — load the shim into a temporary NSS database and list the DNIe
# certificates, mimicking what Firefox does. Does not ask for a PIN.
# Usage: ./tests/test-nss.sh [module.so]
set -uo pipefail

SHIM="${1:-${SHIM:-/usr/lib/libpkcs11-dnie.so}}"

if [ ! -f "$SHIM" ]; then
  echo "shim not found: $SHIM" >&2
  exit 2
fi
for tool in certutil modutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool not found (install libnss3-tools)" >&2
    exit 2
  fi
done

db=$(mktemp -d)
trap 'rm -rf "$db"' EXIT

certutil -N -d "sql:$db" --empty-password >/dev/null 2>&1
if ! modutil -dbdir "sql:$db" -add "DNIe" -libfile "$SHIM" >/dev/null 2>&1; then
  echo "could not add the module to the NSS database" >&2
  exit 1
fi

output=$(certutil -L -d "sql:$db" -h all 2>&1)
count=$(printf '%s' "$output" | grep -c 'DNI electrónico:')

printf '%s\n' "$output" | grep 'DNI electrónico:' || true

if [ "$count" -ge 3 ]; then
  echo "RESULT: OK ($count certificates)"
  exit 0
fi
echo "RESULT: FAILURES ($count certificates)"
exit 1
