#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# check-pin.sh — verify the DNIe PIN and list the private objects.
#
# The PIN is read from the terminal, never from the command line. A correct PIN
# resets the retry counter; a wrong PIN consumes one of the three attempts.
# Only run it if you are sure of the PIN.
set -euo pipefail

MODULE="${1:-/usr/lib/opensc-pkcs11.so}"

[ -f "$MODULE" ] || { echo "module not found: $MODULE" >&2; exit 2; }
[ -t 0 ] || { echo "run this script interactively" >&2; exit 2; }

printf 'DNIe PIN: '
IFS= read -rs PIN
printf '\n'

if pkcs11-tool --module "$MODULE" --login --pin "$PIN" --list-objects; then
  echo "PIN OK"
else
  echo "PIN rejected or card blocked" >&2
fi
unset PIN
