#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# setup-browser.sh — add the DNIe PKCS#11 module to Firefox and Chrome/Chromium.
#
# Usage: ./scripts/setup-browser.sh <module.so> [--remove]
#
# It only touches NSS databases owned by the current $HOME. Backups are kept
# next to each database as <db>.dnie-backup.<timestamp>.
set -euo pipefail

MODULE="${1:-}"
MODE="add"

case "${2:-}" in
  --remove) MODE="remove" ;;
  "") ;;
  *) echo "unknown option: $2" >&2; exit 1 ;;
esac

[ -n "$MODULE" ] || { echo "usage: $0 <module.so> [--remove]" >&2; exit 1; }

if [ "$MODE" = "add" ] && [ ! -f "$MODULE" ]; then
  echo "module not found: $MODULE" >&2
  exit 1
fi

for tool in certutil modutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool not found (install nss tools: libnss3-tools / nss-tools)" >&2
    exit 2
  fi
done

if pgrep -x firefox >/dev/null 2>&1 || pgrep -x firefox-esr >/dev/null 2>&1; then
  echo "WARNING: Firefox is running; restart it after this script" >&2
fi
for chrome in chromium google-chrome chrome; do
  if pgrep -x "$chrome" >/dev/null 2>&1; then
    echo "WARNING: $chrome is running; restart it after this script" >&2
  fi
done

stamp=$(date +%Y%m%d-%H%M%S)
changed=0

firefox_profiles() {
  local ini base rel path key value
  for ini in "$HOME/.mozilla/firefox/profiles.ini" \
             "$HOME/.config/mozilla/firefox/profiles.ini"; do
    [ -f "$ini" ] || continue
    base=$(dirname "$ini")
    rel=1
    path=""
    while IFS='=' read -r key value; do
      case "$key" in
        "[Profile"*|"")
          if [ -n "$path" ]; then
            if [ "$rel" = "1" ]; then printf '%s\n' "$base/$path"; else printf '%s\n' "$path"; fi
            path=""
            rel=1
          fi
          ;;
        IsRelative) rel="$value" ;;
        Path) path="$value" ;;
      esac
    done < "$ini"
    if [ -n "$path" ]; then
      if [ "$rel" = "1" ]; then printf '%s\n' "$base/$path"; else printf '%s\n' "$path"; fi
    fi
  done
}

configure_db() {
  local db="$1" label="$2" create="${3:-0}"

  if [ ! -d "$db" ]; then
    if [ "$create" = "1" ] && [ "$MODE" = "add" ]; then
      mkdir -p "$db"
    else
      return 0
    fi
  fi
  if [ "$MODE" = "add" ] && [ ! -f "$db/cert9.db" ]; then
    certutil -N -d "sql:$db" --empty-password >/dev/null 2>&1 || return 0
  fi
  [ -f "$db/cert9.db" ] || return 0

  cp -a "$db" "$db.dnie-backup.$stamp" 2>/dev/null || true

  if [ "$MODE" = "remove" ]; then
    if modutil -dbdir "sql:$db" -list 2>/dev/null | grep -q 'DNIe'; then
      modutil -dbdir "sql:$db" -delete "DNIe" -force >/dev/null 2>&1 || true
      echo "  removed from $label: $db"
      changed=$((changed + 1))
    fi
    return 0
  fi

  if modutil -dbdir "sql:$db" -list 2>/dev/null | grep -q 'DNIe'; then
    modutil -dbdir "sql:$db" -delete "DNIe" -force >/dev/null 2>&1 || true
  fi
  if modutil -dbdir "sql:$db" -add "DNIe" -libfile "$MODULE" -force >/dev/null 2>&1; then
    echo "  added to $label: $db"
    changed=$((changed + 1))
  else
    echo "  ERROR: could not add the module to $db" >&2
  fi
}

if [ "$MODE" = "add" ]; then
  echo "Configuring NSS databases for $MODULE"
else
  echo "Removing the DNIe module from NSS databases"
fi

while IFS= read -r profile; do
  [ -n "$profile" ] || continue
  configure_db "$profile" "Firefox"
done < <(firefox_profiles)

configure_db "$HOME/.pki/nssdb" "Chrome/Chromium" 1

if [ "$changed" -eq 0 ]; then
  echo "No NSS database was modified."
else
  echo "Done ($changed database(s)). Restart the browsers."
fi
