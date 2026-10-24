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

echo "== 1/5 Packages =="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  pcscd libccid pcsc-tools opensc opensc-pkcs11 p11-kit libnss3-tools

echo "== 2/5 polkit rule and group (headless / remote access) =="
if [ -d /etc/polkit-1/rules.d ]; then
  install -Dm644 "$root/packaging/polkit/50-pcscd.rules" \
    /etc/polkit-1/rules.d/50-pcscd.rules
  echo "installed: /etc/polkit-1/rules.d/50-pcscd.rules (group plugdev)"

  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    if ! id -nG "$SUDO_USER" 2>/dev/null | tr ' ' '\n' | grep -qx plugdev; then
      usermod -aG plugdev "$SUDO_USER"
      echo "added $SUDO_USER to the plugdev group"
    fi
  else
    echo "SUDO_USER not set; make sure your user belongs to plugdev"
  fi

  systemctl try-restart polkit 2>/dev/null || true
else
  echo "polkit rules.d not found; skipped"
fi

echo "== 3/5 PC/SC service =="
systemctl enable --now pcscd.socket
systemctl is-active pcscd.socket

echo "== 4/5 PKCS#11 shim =="
make -C "$root/src/pkcs11-shim"
make -C "$root/src/pkcs11-shim" install PREFIX=/usr

echo "== 5/5 Check =="
pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L || true

cat <<'EOF'

Installed. Next steps:
  1. Connect the USB reader (CCID).
  2. ./scripts/verify-stack.sh
  3. ./scripts/verify-card.sh   (with the DNIe inserted, chip facing the contacts)

Autofirma is not in the Debian repositories; install it separately
(see docs/04-autofirma.md).
EOF
