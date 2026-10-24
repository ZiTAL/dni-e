#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# install.sh — install the DNIe stack on Linux (any architecture).
#
# It installs OpenSC/pcsc-lite/ccid if needed, builds and installs the
# libpkcs11-dnie.so compatibility shim, registers it with p11-kit, configures
# polkit/plugdev for headless access and optionally wires browsers and
# Autofirma.
#
# Usage:
#   ./install.sh                 # /usr/local, no root if writable
#   sudo ./install.sh --system   # /usr, system packages and service
#   ./install.sh --prefix "$HOME/.local"
#   ./install.sh --dry-run
#   ./install.sh --uninstall --system
#
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SHIM_DIR="$ROOT_DIR/src/pkcs11-shim"

PREFIX="/usr/local"
DRY_RUN=0
DO_DEPS=1
DO_BROWSER=1
DO_AUTOFIRMA=0
AUTOFIRMA_JAR=""
UNINSTALL=0

TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)
[ -n "${TARGET_HOME:-}" ] || TARGET_HOME="$HOME"

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    [dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --system                 Install into /usr and manage system services
  --prefix DIR             Install prefix (default: /usr/local)
  --no-deps                Do not install distribution packages
  --no-browser             Do not add the module to Firefox/Chrome
  --no-autofirma           Do not install Autofirma (default)
  --autofirma-jar FILE     Install Autofirma from an existing jar
  --dry-run                Show actions without changing anything
  --uninstall              Remove files installed by this script
  -h, --help               Show this help

Examples:
  ./install.sh --prefix "$HOME/.local"
  sudo ./install.sh --system --autofirma-jar ~/autofirma.jar
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --system) PREFIX="/usr" ;;
    --prefix)
      [ $# -ge 2 ] || die "--prefix requires a directory"
      PREFIX="$2"
      shift
      ;;
    --no-deps) DO_DEPS=0 ;;
    --no-browser) DO_BROWSER=0 ;;
    --no-autofirma) DO_AUTOFIRMA=0 ;;
    --autofirma-jar)
      [ $# -ge 2 ] || die "--autofirma-jar requires a file"
      AUTOFIRMA_JAR="$2"
      DO_AUTOFIRMA=1
      shift
      ;;
    --dry-run) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

PREFIX="${PREFIX%/}"
[ -n "$PREFIX" ] || die "invalid prefix"


can_use_root_now() {
  [ "$(id -u)" -eq 0 ] && return 0
  command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    die "root privileges required: $*"
  fi
}

prefix_writable() {
  [ -w "$PREFIX" ] 2>/dev/null || [ -w "$(dirname "$PREFIX")" ] 2>/dev/null
}

run_prefix() {
  if prefix_writable; then
    run "$@"
  else
    as_root "$@"
  fi
}

detect_pm() {
  local pm
  for pm in apt-get dnf yum pacman zypper apk xbps-install emerge; do
    if command -v "$pm" >/dev/null 2>&1; then
      printf '%s\n' "$pm"
      return 0
    fi
  done
  printf 'none\n'
}

has_runtime() {
  { command -v pcscd >/dev/null 2>&1 || [ -x /usr/sbin/pcscd ]; } &&
    command -v opensc-tool >/dev/null 2>&1 &&
    command -v pkcs11-tool >/dev/null 2>&1
}

has_build() {
  command -v cc >/dev/null 2>&1 && command -v make >/dev/null 2>&1
}

install_deps() {
  local pm pkgs
  pm=$(detect_pm)
  case "$pm" in
    apt-get)
      pkgs="pcscd libccid pcsc-tools opensc opensc-pkcs11 p11-kit libnss3-tools build-essential"
      set -- install -y
      ;;
    dnf|yum)
      pkgs="pcsc-lite pcsc-lite-ccid pcsc-tools opensc p11-kit nss-tools gcc make"
      set -- install -y
      ;;
    pacman)
      pkgs="pcsclite ccid pcsc-tools opensc p11-kit nss base-devel"
      set -- -S --needed --noconfirm
      ;;
    zypper)
      pkgs="pcsc-lite pcsc-ccid pcsc-tools opensc p11-kit mozilla-nss-tools gcc make"
      set -- --non-interactive install
      ;;
    apk)
      pkgs="pcsc-lite pcsc-lite-dev ccid pcsc-tools opensc p11-kit nss-tools build-base"
      set -- add
      ;;
    xbps-install)
      pkgs="pcsc-lite ccid pcsc-tools opensc p11-kit nss gcc make"
      set -- -Sy
      ;;
    emerge)
      pkgs="sys-apps/pcsc-lite app-crypt/ccid sys-apps/pcsc-tools dev-libs/opensc app-crypt/p11-kit dev-libs/nss"
      set -- -n
      ;;
    *)
      warn "unknown package manager; install manually: pcsc-lite, ccid, opensc, p11-kit, a C compiler and make"
      return 0
      ;;
  esac

  say "installing dependencies with $pm"
  # shellcheck disable=SC2086
  if ! as_root "$pm" "$@" $pkgs; then
    warn "package installation failed; install manually: $pkgs"
  fi
}

enable_service() {
  if ! can_use_root_now; then
    warn "skipping service setup (run with sudo or --system)"
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1; then
    as_root systemctl enable --now pcscd.socket 2>/dev/null ||
      as_root systemctl enable --now pcscd 2>/dev/null ||
      warn "could not enable pcscd with systemctl"
  elif command -v rc-update >/dev/null 2>&1; then
    as_root rc-update add pcscd default 2>/dev/null || true
    as_root rc-service pcscd start 2>/dev/null || true
  elif command -v sv >/dev/null 2>&1; then
    warn "runit detected: enable pcscd in your service directory"
  else
    warn "no supported service manager: start pcscd manually"
  fi
}

setup_polkit() {
  [ -d /etc/polkit-1/rules.d ] || return 0
  if ! can_use_root_now; then
    warn "skipping polkit setup (run with sudo or --system); see packaging/polkit/50-pcscd.rules"
    return 0
  fi

  as_root install -Dm644 "$ROOT_DIR/packaging/polkit/50-pcscd.rules" \
    /etc/polkit-1/rules.d/50-pcscd.rules

  if [ "$TARGET_USER" != "root" ]; then
    if ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx plugdev; then
      as_root usermod -aG plugdev "$TARGET_USER" ||
        warn "could not add $TARGET_USER to plugdev"
    fi
  fi

  as_root systemctl try-restart polkit 2>/dev/null || true
}

build_and_install_shim() {
  say "building the PKCS#11 shim"
  run make -C "$SHIM_DIR" clean
  run make -C "$SHIM_DIR"

  say "installing into $PREFIX"
  run_prefix make -C "$SHIM_DIR" install PREFIX="$PREFIX"
}

setup_browser() {
  [ "$DO_BROWSER" -eq 1 ] || return 0
  local module="$PREFIX/lib/libpkcs11-dnie.so"
  [ -f "$module" ] || { warn "shim not found at $module; skipping browsers"; return 0; }

  say "configuring browsers"
  if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != "root" ]; then
    run sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" \
      "$ROOT_DIR/scripts/setup-browser.sh" "$module" ||
      warn "browser setup failed"
  else
    run env HOME="$TARGET_HOME" "$ROOT_DIR/scripts/setup-browser.sh" "$module" ||
      warn "browser setup failed"
  fi
}

install_autofirma() {
  [ "$DO_AUTOFIRMA" -eq 1 ] || return 0
  [ -f "$AUTOFIRMA_JAR" ] || die "Autofirma jar not found: $AUTOFIRMA_JAR"

  say "installing Autofirma"
  run_prefix install -Dm644 "$AUTOFIRMA_JAR" "$PREFIX/share/java/autofirma/autofirma.jar"
  run_prefix install -Dm755 "$ROOT_DIR/packaging/autofirma/autofirma-launcher" \
    "$PREFIX/bin/autofirma-dnie"
  run_prefix install -Dm644 "$ROOT_DIR/packaging/autofirma/autofirma-dnie.desktop" \
    "$PREFIX/share/applications/autofirma-dnie.desktop"

  if [ "$DRY_RUN" -eq 0 ] && [ -f "$PREFIX/share/applications/autofirma-dnie.desktop" ]; then
    sed -i "s|@PREFIX@|$PREFIX|g" "$PREFIX/share/applications/autofirma-dnie.desktop"
  fi
}

uninstall_all() {
  say "removing the shim from $PREFIX"
  run_prefix make -C "$SHIM_DIR" uninstall PREFIX="$PREFIX"

  say "removing Autofirma launcher (if installed)"
  run_prefix rm -f "$PREFIX/bin/autofirma-dnie"
  run_prefix rm -f "$PREFIX/share/applications/autofirma-dnie.desktop"
  run_prefix rm -f "$PREFIX/share/java/autofirma/autofirma.jar"

  if [ -f /etc/polkit-1/rules.d/50-pcscd.rules ] &&
     cmp -s "$ROOT_DIR/packaging/polkit/50-pcscd.rules" /etc/polkit-1/rules.d/50-pcscd.rules; then
    say "removing the polkit rule"
    as_root rm -f /etc/polkit-1/rules.d/50-pcscd.rules
    as_root systemctl try-restart polkit 2>/dev/null || true
  fi

  say "done (distribution packages were left installed)"
}

main() {
  if [ "$UNINSTALL" -eq 1 ]; then
    uninstall_all
    exit 0
  fi

  if [ "$DRY_RUN" -eq 0 ] && [ "$PREFIX" = "/usr" ] && [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "--system requires root or sudo"
  fi

  if [ "$DO_DEPS" -eq 1 ] && { ! has_runtime || ! has_build; }; then
    install_deps
  fi

  has_build || die "a C compiler (cc) and make are required"

  build_and_install_shim
  enable_service
  setup_polkit
  setup_browser
  install_autofirma

  echo
  say "installed"
  echo "  module:  $PREFIX/lib/libpkcs11-dnie.so"
  echo "  alias:   $PREFIX/lib/libpkcs11-fnmtdnie.so"
  echo "  p11-kit: $PREFIX/share/p11-kit/modules/dnie-compat.module"
  echo
  echo "Next steps:"
  echo "  1. Connect a CCID reader and an inserted DNIe."
  echo "  2. $ROOT_DIR/scripts/verify-stack.sh"
  echo "  3. $ROOT_DIR/scripts/verify-card.sh"
}

main "$@"
