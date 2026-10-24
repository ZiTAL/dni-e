#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# sign-release.sh — detached-sign SHA256SUMS and export the public key.
#
# Usage: GPG_KEY_ID=<fingerprint> ./scripts/sign-release.sh [file]
# Default file: dist/SHA256SUMS
set -euo pipefail

FILE="${1:-dist/SHA256SUMS}"
KEY="${GPG_KEY_ID:-}"

[ -f "$FILE" ] || { echo "file not found: $FILE" >&2; exit 2; }
[ -n "$KEY" ] || { echo "GPG_KEY_ID is not set" >&2; exit 2; }

gpg --batch --yes --armor --detach-sign --local-user "$KEY" "$FILE"
gpg --armor --export "$KEY" > "$(dirname "$FILE")/dnie-release-key.asc"

echo "signature: $FILE.asc"
echo "public key: $(dirname "$FILE")/dnie-release-key.asc"
