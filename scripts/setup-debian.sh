#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# setup-debian.sh — install the DNIe stack on Debian 13 (trixie) aarch64/riscv64.
# Usage: sudo ./scripts/setup-debian.sh [path/to/repo]
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo." >&2
  exit 1
fi

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "== 1/4 Packages =="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  pcscd libccid pcsc-tools opensc opensc-pkcs11 p11-kit libnss3-tools

echo "== 2/4 PC/SC service =="
systemctl enable --now pcscd.socket
systemctl is-active pcscd.socket

echo "== 3/4 PKCS#11 shim =="
make -C "$root/src/pkcs11-shim"
install -Dm755 "$root/src/pkcs11-shim/libpkcs11-dnie.so" /usr/lib/libpkcs11-dnie.so
install -Dm644 "$root/src/pkcs11-shim/dnie-compat.module" \
  /usr/share/p11-kit/modules/dnie-compat.module
install -Dm644 "$root/src/pkcs11-shim/dnie-compat.conf.example" \
  /usr/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example

echo "== 4/4 Check =="
pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L || true

cat <<'EOF'

Installed. Next steps:
  1. Connect the USB reader (CCID).
  2. ./scripts/verify-stack.sh
  3. ./scripts/verify-card.sh   (with the DNIe inserted, chip facing the contacts)

Autofirma is not in the Debian repositories; install it separately
(see docs/04-autofirma.md).
EOF
