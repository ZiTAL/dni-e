#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# build-prebuilt.sh — assemble a .deb around an already built shim.
#
# Used for architectures without a native CI runner (riscv64): the shim is
# cross-compiled by the tarball job and this script produces a package with the
# same layout as dpkg-buildpackage does for amd64/arm64.
#
# Usage:
#   VERSION=0.2.3 DEB_ARCH=riscv64 \
#     SHIM=src/pkcs11-shim/libpkcs11-dnie.so \
#     ./packaging/debian/build-prebuilt.sh
#
# Output: dist/dnie-pkcs11-compat_<version>_<arch>.deb
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
VERSION="${VERSION:?set VERSION}"
DEB_ARCH="${DEB_ARCH:-riscv64}"
SHIM="${SHIM:-$ROOT_DIR/src/pkcs11-shim/libpkcs11-dnie.so}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"

case "$DEB_ARCH" in
  amd64)   elf_machine="X86-64" ;;
  arm64)   elf_machine="AArch64" ;;
  riscv64) elf_machine="RISC-V" ;;
  armhf)   elf_machine="ARM" ;;
  *) echo "unsupported DEB_ARCH: $DEB_ARCH" >&2; exit 2 ;;
esac

[ -f "$SHIM" ] || { echo "shim not found: $SHIM" >&2; exit 2; }
if ! readelf -h "$SHIM" | grep -q "Machine:.*$elf_machine"; then
  echo "shim does not look like $DEB_ARCH:" >&2
  file "$SHIM" >&2
  exit 2
fi

command -v dpkg-deb >/dev/null 2>&1 || {
  echo "dpkg-deb not found (install dpkg-dev)" >&2
  exit 2
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pkg="$work/dnie-pkcs11-compat"
docdir="$pkg/usr/share/doc/dnie-pkcs11-compat"

install -Dm755 "$SHIM" "$pkg/usr/lib/libpkcs11-dnie.so"
ln -s libpkcs11-dnie.so "$pkg/usr/lib/libpkcs11-fnmtdnie.so"

install -d "$pkg/usr/share/p11-kit/modules"
sed 's|@LIBDIR@|/usr/lib|g' \
  "$ROOT_DIR/src/pkcs11-shim/dnie-compat.module.in" \
  > "$pkg/usr/share/p11-kit/modules/dnie-compat.module"
chmod 644 "$pkg/usr/share/p11-kit/modules/dnie-compat.module"

install -Dm644 "$ROOT_DIR/src/pkcs11-shim/dnie-compat.conf.example" \
  "$docdir/dnie-compat.conf.example"
install -Dm644 "$ROOT_DIR/packaging/debian/copyright" "$docdir/copyright"
gzip -9nc "$ROOT_DIR/packaging/debian/changelog" > "$docdir/changelog.gz"
chmod 644 "$docdir/changelog.gz" "$docdir/copyright" "$docdir/dnie-compat.conf.example"

installed_size=$(du -sk "$pkg" | cut -f1)
mkdir -p "$pkg/DEBIAN"
# Keep in sync with packaging/debian/control.
cat > "$pkg/DEBIAN/control" <<EOF
Package: dnie-pkcs11-compat
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: ZiTAL <2283548+ZiTAL@users.noreply.github.com>
Installed-Size: $installed_size
Depends: libc6 (>= 2.34), opensc, p11-kit, pcscd
Recommends: libccid
Conflicts: libpkcs11-dnie, libpkcs11-fnmtdnie
Replaces: libpkcs11-dnie, libpkcs11-fnmtdnie
Provides: libpkcs11-dnie, libpkcs11-fnmtdnie
Section: misc
Priority: optional
Homepage: https://github.com/ZiTAL/dni-e
Description: PKCS#11 compatibility module for the Spanish DNIe
 OpenSC-based module that exposes the libpkcs11-dnie.so name and ABI
 expected by Spanish DNIe applications and guides, on any architecture
 supported by OpenSC, including aarch64 and riscv64.
 .
 It is an independent implementation based on OpenSC, not the official
 DGP/FNMT module.
EOF

mkdir -p "$OUT_DIR"
deb="$OUT_DIR/dnie-pkcs11-compat_${VERSION}_${DEB_ARCH}.deb"
rm -f "$deb"
dpkg-deb --build --root-owner-group "$pkg" "$deb" >/dev/null
sha256sum "$deb"
echo "release asset: $deb"
