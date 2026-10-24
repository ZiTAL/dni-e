#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# verify-card.sh — check the DNIe card WITHOUT asking for a PIN.
# Usage: ./scripts/verify-card.sh
set -uo pipefail

fail=0
ok()  { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; fail=1; }

echo "== Card state =="
state=$(timeout 6 pcsc_scan 2>/dev/null | grep 'Card state' | head -1 | sed 's/^ *//')
atr=$(timeout 6 pcsc_scan 2>/dev/null | grep -o 'ATR: .*' | head -1)
if echo "$state" | grep -q 'Card inserted'; then ok "$state"; else bad "${state:-no card}"; fi
[ -n "$atr" ] && printf '     %s\n' "$atr"

if echo "$state" | grep -q 'Unresponsive'; then
  bad "card does not respond: turn the DNIe around (chip orientation) and clean the contacts"
fi

echo "== Identification =="
name=$(timeout 10 opensc-tool -n 2>/dev/null | tail -1)
if [ "$name" = "dnie" ]; then ok "OpenSC recognizes: dnie"; else bad "OpenSC does not recognize the card (${name:-no response})"; fi

echo "== Certificates (no PIN) =="
certs=$(timeout 15 pkcs15-tool --list-certificates 2>/dev/null | grep -c '^X.509' || true)
if [ "${certs:-0}" -ge 3 ]; then
  ok "$certs certificates visible"
else
  bad "only ${certs:-0} certificates visible"
fi
timeout 15 pkcs15-tool --list-certificates 2>/dev/null | grep '^X.509' | sed 's/^/     /'

echo
if [ "$fail" -eq 0 ]; then echo "RESULT: OK"; else echo "RESULT: FAILURES"; fi
exit "$fail"
