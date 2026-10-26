#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# test-tls-auth.sh — TLS client authentication with the DNIe, without a browser.
#
# It derives the PKCS#11 URLs from the card (no hardcoded certificate IDs),
# exports the authentication certificate to a temporary PEM and uses the
# private key from the token. The PIN is read from the terminal and passed
# through the environment, never on the command line.
#
# Usage: ./scripts/test-tls-auth.sh [host] [port]
set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-8444}"
TOKEN='pkcs11:model=PKCS%2315%20emulated;manufacturer=DGP-FNMT;serial=0201bc6a0e1d49;token=DNI%20electr%C3%B3nico'
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

command -v gnutls-cli >/dev/null 2>&1 || { echo "gnutls-cli not found" >&2; exit 2; }
command -v p11tool >/dev/null 2>&1 || { echo "p11tool not found" >&2; exit 2; }
[ -t 0 ] || { echo "run this script interactively" >&2; exit 2; }

CERT_URL=$(p11tool --list-all-certs "$TOKEN" 2>/dev/null |
  awk '/URL:/{print $2}' |
  grep 'object=CertAutenticacion;type=cert' | head -1)
[ -n "$CERT_URL" ] || { echo "authentication certificate not found" >&2; exit 2; }

# The DNIe names the private key Kpriv<name> while the certificate is Cert<name>.
CERT_OBJ=$(printf '%s' "$CERT_URL" | sed -n 's/.*object=\([^;]*\);type=cert.*/\1/p')
KEY_OBJ=${CERT_OBJ/Cert/Kpriv}
KEY_URL=${CERT_URL/object=$CERT_OBJ/object=$KEY_OBJ}
KEY_URL=${KEY_URL/type=cert/type=private}

AUTH_ID=$(pkcs15-tool --list-certificates 2>/dev/null |
  awk '/CertAutenticacion/{f=1} f&&/ID *:/{print $3; exit}')
[ -n "$AUTH_ID" ] || { echo "authentication certificate ID not found" >&2; exit 2; }
pkcs15-tool --read-certificate "$AUTH_ID" > "$TMP/auth.pem" 2>/dev/null

# Send the intermediate as well, so the server can build the chain.
CA_ID=$(pkcs15-tool --list-certificates 2>/dev/null |
  awk '/CertCAIntermediaDGP/{f=1} f&&/ID *:/{print $3; exit}')
if [ -n "$CA_ID" ]; then
  pkcs15-tool --read-certificate "$CA_ID" >> "$TMP/auth.pem" 2>/dev/null
fi

printf 'DNIe PIN: '
IFS= read -rs PIN
printf '\n'
export GNUTLS_PIN="$PIN"
unset PIN

set +e
output=$(printf 'GET / HTTP/1.0\r\nHost: %s\r\n\r\n' "$HOST" | \
  timeout 30 gnutls-cli --insecure \
    --x509certfile "$TMP/auth.pem" \
    --x509keyfile "$KEY_URL" \
    -p "$PORT" "$HOST" 2>&1)
status=$?
set -e
unset GNUTLS_PIN
printf '%s\n' "$output"

if printf '%s' "$output" | grep -q 'Successfully sent' &&
   printf '%s' "$output" | grep -q 'Handshake was completed'; then
  echo "RESULT: TLS client authentication OK"
  exit 0
fi
echo "RESULT: TLS client authentication FAILED (status $status)" >&2
exit 1
