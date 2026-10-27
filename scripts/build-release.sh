#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# build-release.sh — build a release tarball for the current architecture.
#
# Usage: VERSION=0.2.2 ./scripts/build-release.sh
# Output: dist/dnie-pkcs11-compat-<version>-<arch>.tar.gz (+ .sha256)
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHIM_DIR="$ROOT_DIR/src/pkcs11-shim"
VERSION="${VERSION:-0.2.2}"
ARCH="${ARCH:-$(uname -m)}"
CC="${CC:-cc}"

case "$ARCH" in
  x86_64|i386|i686|aarch64|armv7l|riscv64|ppc64le|s390x) ;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

name="dnie-pkcs11-compat-${VERSION}-${ARCH}"
out="$ROOT_DIR/dist/${name}.tar.gz"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

echo "==> building the shim for $ARCH with $CC"
make -C "$SHIM_DIR" clean >/dev/null
make -C "$SHIM_DIR" CC="$CC"

echo "==> staging $name"
mkdir -p "$staging/$name/prebuilt"

tar -C "$ROOT_DIR" \
  --exclude='./.git' \
  --exclude='./artifacts' \
  --exclude='./reference' \
  --exclude='./dist' \
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
  -cf - . | tar -C "$staging/$name" -xf -

cp "$SHIM_DIR/libpkcs11-dnie.so" "$staging/$name/prebuilt/libpkcs11-dnie.so"
chmod 755 "$staging/$name/prebuilt/libpkcs11-dnie.so"

mkdir -p "$ROOT_DIR/dist"
tar -C "$staging" -czf "$out" "$name"

sha256sum "$out" | sed "s|$ROOT_DIR/||" | tee "$out.sha256"

echo
echo "release asset: $out"
file "$staging/$name/prebuilt/libpkcs11-dnie.so" | cut -c1-100
