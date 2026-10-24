# 07 — Portability: FHS distributions and Guix/Nix

**Date:** 2026-10-24
**Status:** ✅ build and install are path-agnostic; validated on FHS and emulated non-FHS layouts

---

## 1. Design rule

Nothing is hardcoded to `/usr`:

| Variable | Default | Purpose |
|---|---|---|
| `PREFIX` | `/usr` | Installation prefix |
| `LIBDIR` | `$(PREFIX)/lib` | Where `libpkcs11-dnie.so` goes |
| `P11KIT_MODULEDIR` | `$(PREFIX)/share/p11-kit/modules` | p11-kit registration |
| `DOCDIR` | `$(PREFIX)/share/doc/dnie-pkcs11-compat` | Example configuration |
| `MODULE_PATH` | *(empty)* | OpenSC module path embedded at build time |
| `MULTIARCH` | `cc -print-multiarch` | Tripleta for `/usr/lib/<tripleta>/` |
| `CONFIG_FILE` | `/etc/dnie-compat.conf` | Default configuration file |
| `DESTDIR` | *(empty)* | Staging directory for packagers |

The p11-kit `.module` file is generated at install time from
`dnie-compat.module.in`, replacing `@LIBDIR@` with the real library directory.

## 2. FHS distributions (Debian, Ubuntu, Fedora, Arch…)

```bash
make -C src/pkcs11-shim
sudo make -C src/pkcs11-shim install
```

With a custom prefix:

```bash
make -C src/pkcs11-shim PREFIX=/usr/local
sudo make -C src/pkcs11-shim install PREFIX=/usr/local
```

Debian/Ubuntu also have `scripts/setup-debian.sh`, which installs the OpenSC
packages and then runs `make install`.

## 3. Guix

Guix does not use `/usr` or `/etc`: everything lives under `/gnu/store` and is
immutable. The shim supports this through `MODULE_PATH` and a fully overridable
prefix.

Build the OpenSC module path first:

```bash
guix build opensc
# /gnu/store/...-opensc-0.26.1
```

Then build and install into an output directory:

```bash
make -C src/pkcs11-shim \
  MULTIARCH= \
  PREFIX="$out" \
  MODULE_PATH="$(guix build opensc)/lib/opensc-pkcs11.so" \
  install
```

`MULTIARCH=` disables the FHS multiarch candidates. The embedded module path is
an absolute store path, so Guix keeps OpenSC alive through the reference.

A package definition template is provided in [`guix.scm`](../guix.scm). Adjust
the `opensc`/`p11-kit` imports to your Guix revision:

```scheme
(use-modules (gnu packages security-token)  ; opensc
             (gnu packages tls))            ; p11-kit
```

Configuration on Guix: `/etc/dnie-compat.conf` normally does not exist, so the
shim falls back to `$XDG_CONFIG_HOME/dnie-compat.conf` or
`$HOME/.config/dnie-compat.conf`. Environment variables also work:

```bash
export DNIE_COMPAT_MODULE=/gnu/store/.../lib/opensc-pkcs11.so
```

## 4. Nix / NixOS

`/run/current-system/sw/lib/opensc-pkcs11.so` is a built-in candidate. For
per-user or store paths, use `MODULE_PATH` at build time or
`DNIE_COMPAT_MODULE` at runtime.

## 5. Configuration search order

1. `DNIE_COMPAT_CONF` (explicit path)
2. `/etc/dnie-compat.conf`
3. `$XDG_CONFIG_HOME/dnie-compat.conf`
4. `$HOME/.config/dnie-compat.conf`

A file is only read if it is a **regular file**. When running as root it must
also be root-owned and not group/other writable.

## 6. Validated layouts

| Layout | Test |
|---|---|
| FHS `/usr` | ✅ system install on Debian 13 (aarch64 and riscv64) |
| Custom prefix | ✅ `PREFIX=/tmp/.../prefix` install + load |
| Non-FHS (Guix/Nix style) | ✅ embedded `MODULE_PATH`, no `/usr/lib` |
| `MULTIARCH=` empty | ✅ built-in paths still resolve OpenSC |

All of the above are exercised by `tests/test-shim-paths.sh` (21 cases).
