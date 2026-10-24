#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# verify-stack.sh — check the DNIe stack is complete (does not touch the card).
# Works on Arch and Debian (multiarch paths).
# Usage: ./scripts/verify-stack.sh
set -uo pipefail

fail=0
ok()   { printf '  ✅ %s\n' "$1"; }
bad()  { printf '  ❌ %s\n' "$1"; fail=1; }
warn() { printf '  ⚠️  %s\n' "$1"; }

echo "== Architecture =="
printf '  %s %s\n' "$(uname -s)" "$(uname -m)"

echo "== Binaries =="
for cmd in pcscd pcsc_scan opensc-tool pkcs11-tool pkcs15-tool; do
  if command -v "$cmd" >/dev/null 2>&1 || [ -x "/usr/sbin/$cmd" ]; then
    ok "$cmd"
  else
    bad "$cmd not found"
  fi
done

echo "== PKCS#11 module =="
module=$(ls /usr/lib/opensc-pkcs11.so /usr/lib/*/opensc-pkcs11.so /usr/lib64/opensc-pkcs11.so 2>/dev/null | head -1)
if [ -n "$module" ]; then ok "$module"; else bad "opensc-pkcs11.so not found"; fi
module_file=$(ls /usr/share/p11-kit/modules/opensc*.module 2>/dev/null | head -1)
if [ -n "$module_file" ]; then ok "p11-kit registration ($module_file)"; else warn "no p11-kit registration"; fi

echo "== Compatibility shim =="
if [ -f /usr/lib/libpkcs11-dnie.so ]; then ok "/usr/lib/libpkcs11-dnie.so"; else warn "shim not installed"; fi

echo "== PC/SC service =="
if systemctl is-active --quiet pcscd.socket 2>/dev/null; then ok "pcscd.socket active"
elif systemctl is-active --quiet pcscd 2>/dev/null; then ok "pcscd active"
else bad "pcscd inactive (systemctl enable --now pcscd.socket)"; fi

echo "== Reader =="
readers=$(pcsc_scan -r 2>/dev/null | grep -c '^[0-9]\+:' || true)
if [ "${readers:-0}" -gt 0 ]; then
  ok "$readers reader(s)"
  pcsc_scan -r 2>/dev/null | grep '^[0-9]\+:' | sed 's/^/     /'
else
  bad "no reader detected (connect a CCID reader over USB)"
  if command -v lsusb >/dev/null 2>&1 && lsusb 2>/dev/null | grep -qiE 'smartcard|smart card|058f:9540'; then
    warn "USB smartcard reader present but PC/SC cannot see it; check polkit access_pcsc (see docs/02-aarch64.md)"
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "RESULT: OK"; else echo "RESULT: FAILURES"; fi
exit "$fail"
