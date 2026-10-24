#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the Arch package from this repository's source.
# Usage: ./packaging/arch/build-local.sh [-f]
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

pkgname=$(grep -m1 '^pkgname=' "$here/PKGBUILD" | cut -d= -f2)
pkgver=$(grep -m1 '^pkgver=' "$here/PKGBUILD" | cut -d= -f2)
tarball="$here/$pkgname-$pkgver.tar.gz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/$pkgname-$pkgver"
cp "$root/src/pkcs11-shim/dnie_shim.c" \
   "$root/src/pkcs11-shim/Makefile" \
   "$root/src/pkcs11-shim/dnie-compat.module.in" \
   "$root/src/pkcs11-shim/dnie-compat.conf.example" \
   "$root/src/pkcs11-shim/README.md" \
   "$root/LICENSE" \
   "$work/$pkgname-$pkgver/"

tar -C "$work" -czf "$tarball" "$pkgname-$pkgver"

cd "$here"
makepkg -f "$@"
