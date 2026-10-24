#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# make-firefox-profile.sh — create a headless Firefox profile with the DNIe
# PKCS#11 module loaded.
#
# Usage: ./scripts/make-firefox-profile.sh [profile-dir] [module.so]
# Default: ~/.mozilla/dnie-headless and /usr/lib/libpkcs11-dnie.so
#
# This does not need a graphical session and does not ask for a PIN.
set -euo pipefail

PROFILE="${1:-$HOME/.mozilla/dnie-headless}"
MODULE="${2:-/usr/lib/libpkcs11-dnie.so}"

[ -f "$MODULE" ] || { echo "module not found: $MODULE" >&2; exit 2; }
for tool in certutil modutil; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool not found (install nss tools)" >&2
    exit 2
  }
done

mkdir -p "$PROFILE"

if [ ! -f "$PROFILE/cert9.db" ]; then
  certutil -N -d "sql:$PROFILE" --empty-password
fi

if modutil -dbdir "sql:$PROFILE" -list 2>/dev/null | grep -q 'DNIe'; then
  modutil -dbdir "sql:$PROFILE" -delete "DNIe" -force >/dev/null 2>&1 || true
fi
modutil -dbdir "sql:$PROFILE" -add "DNIe" -libfile "$MODULE" -force >/dev/null

cat > "$PROFILE/user.js" <<'EOF'
user_pref("security.default_personal_cert", "Select Automatically");
user_pref("security.osclientcerts.autoload", false);
user_pref("browser.shell.checkDefaultBrowser", false);
EOF

echo "profile: $PROFILE"
echo "module:  $MODULE"
echo
echo "DNIe certificates visible in this profile:"
certutil -L -d "sql:$PROFILE" -h all 2>/dev/null | grep 'DNI electrónico' || {
  echo "  (none: is the card inserted?)"
}
echo
echo "Headless launch example:"
echo "  firefox-esr --headless --profile \"$PROFILE\" https://example.com"
