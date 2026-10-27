#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# build.sh — build the Debian package from this repository.
#
# Usage: ./packaging/debian/build.sh
# Output: dist/dnie-pkcs11-compat_*.deb
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
  echo "dpkg-buildpackage not found (install dpkg-dev and debhelper)" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
src="$work/src"
mkdir -p "$src"

export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-} noautodbgsym"

tar -C "$ROOT_DIR" \
  --exclude='./.git' \
  --exclude='./artifacts' \
  --exclude='./dist' \
  --exclude='./reference' \
  --exclude='./prebuilt' \
  --exclude='./packaging/arch/pkg' \
  --exclude='./packaging/arch/src' \
  --exclude='./src/pkcs11-shim/libpkcs11-dnie.so' \
  --exclude='*.pkg.tar.zst' \
  --exclude='*.tar.gz' \
  --exclude='./passwd' \
  --exclude='./firmado.pdf' \
  --exclude='./*.sig0' \
  --exclude='*.pin' \
  -cf - . | tar -C "$src" -xf -

cp -a "$ROOT_DIR/packaging/debian" "$src/debian"
rm -f "$src/debian/build.sh"
chmod +x "$src/debian/rules"

cd "$src"
dpkg-buildpackage -us -uc -b

mkdir -p "$ROOT_DIR/dist"
rm -f "$ROOT_DIR"/dist/dnie-pkcs11-compat_*.deb
cp "$work"/dnie-pkcs11-compat_*.deb "$ROOT_DIR/dist/"
sha256sum "$ROOT_DIR"/dist/*.deb
