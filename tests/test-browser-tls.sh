#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# test-browser-tls.sh — headless client-certificate test with a local TLS server.
#
# It validates the browser's client-certificate flow with a SOFTWARE
# certificate. It cannot type the DNIe PIN: hardware-token PIN prompts are not
# scriptable in Firefox/Chromium. See docs/10-headless-browser.md.
#
# Usage: ./tests/test-browser-tls.sh
# Requires: openssl, curl, python3. Optional: node + playwright + Chromium.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
fail=0
ok()  { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; fail=1; }
skip() { printf '  ⚠️  %s\n' "$1"; }

for tool in openssl curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 2; }
done

work=$(mktemp -d)
server_pid=""
cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

echo "== Certificates =="
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=Test CA" \
  -keyout "$work/ca.key" -out "$work/ca.pem" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj "/CN=localhost" \
  -keyout "$work/server.key" -out "$work/server.csr" >/dev/null 2>&1
openssl x509 -req -in "$work/server.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" \
  -CAcreateserial -days 2 -out "$work/server.pem" \
  -extfile <(printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\n') >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj "/CN=Test Client" \
  -keyout "$work/client.key" -out "$work/client.csr" >/dev/null 2>&1
openssl x509 -req -in "$work/client.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" \
  -CAcreateserial -days 2 -out "$work/client.pem" >/dev/null 2>&1
ok "CA, server and client certificates generated"

port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
url="https://127.0.0.1:$port/"

openssl s_server -accept "127.0.0.1:$port" \
  -cert "$work/server.pem" -key "$work/server.key" \
  -CAfile "$work/ca.pem" -Verify 1 -www -quiet >"$work/server.log" 2>&1 &
server_pid=$!

for _ in $(seq 1 50); do
  if python3 - "$port" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
sys.exit(0)
PY
  then
    break
  fi
  sleep 0.1
done

echo "== curl baseline =="
if curl -sS --cacert "$work/ca.pem" --cert "$work/client.pem" --key "$work/client.key" \
     "$url" >/dev/null 2>&1; then
  ok "curl with client certificate"
else
  bad "curl with client certificate"
fi

if curl -sS --cacert "$work/ca.pem" "$url" >/dev/null 2>&1; then
  bad "curl without client certificate should fail"
else
  ok "curl without client certificate is rejected"
fi

echo "== headless browser (Playwright + Chromium) =="
CHROMIUM_PATH=$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)
if ! command -v node >/dev/null 2>&1 || [ -z "$CHROMIUM_PATH" ]; then
  skip "node or Chromium not found; browser test skipped"
else
  pkg_dir="${PLAYWRIGHT_DIR:-/tmp/dnie-playwright}"
  if [ ! -d "$pkg_dir/node_modules/playwright" ]; then
    mkdir -p "$pkg_dir"
    if (cd "$pkg_dir" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install playwright >/dev/null 2>&1); then
      ok "playwright installed in $pkg_dir"
    else
      skip "could not install playwright (offline?)"
    fi
  fi

  if [ -d "$pkg_dir/node_modules/playwright" ]; then
    if URL="$url" ORIGIN="https://127.0.0.1:$port" \
       CLIENT_CERT="$work/client.pem" CLIENT_KEY="$work/client.key" \
       CHROMIUM_PATH="$CHROMIUM_PATH" NODE_PATH="$pkg_dir/node_modules" \
       timeout 60 node tests/playwright-client-cert.mjs; then
      ok "headless Chromium with client certificate"
    else
      bad "headless Chromium with client certificate"
    fi
  fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "RESULT: OK"; else echo "RESULT: FAILURES"; fi
exit "$fail"
