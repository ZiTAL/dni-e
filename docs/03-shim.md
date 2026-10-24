# 03 — PKCS#11 compatibility shim

**Date:** 2026-10-24
**Phase:** F3
**Status:** ✅ working and verified on x86-64, aarch64 and riscv64

---

## 1. What it solves

DNIe applications and guides load the module from `/usr/lib/libpkcs11-dnie.so`.
That file only exists as a closed-source x86-64 binary. The shim occupies that
path and delegates the implementation to OpenSC.

```
Firefox ──PKCS#11──▶ libpkcs11-dnie.so (shim) ──dlopen──▶ opensc-pkcs11.so
```

## 2. Implementation

- `C_GetFunctionList`: loads OpenSC with `dlopen` and returns its function
  table. The ABI is standard PKCS#11, so there is no translation.
- `C_GetInterface`: forwards if OpenSC implements it (PKCS#11 3.0); otherwise
  returns `CKR_FUNCTION_NOT_SUPPORTED`.
- SONAME: `libpkcs11-dnie.so`, identical to the official module.
- Only absolute paths are accepted.

## 3. Module path configuration

The shim looks for `opensc-pkcs11.so` with this precedence:

| Order | Source | Example | Notes |
|---|---|---|---|
| 1 | `DNIE_COMPAT_MODULE` | `/opt/opensc/lib/opensc-pkcs11.so` | Exact path. **Authoritative**: if it fails, nothing else is tried |
| 2 | `DNIE_COMPAT_SEARCH_PATH` | `/opt/opensc/lib:/usr/local/lib` | Colon-separated directories; looks for `<dir>/opensc-pkcs11.so` and `<dir>/pkcs11/opensc-pkcs11.so` |
| 3 | `/etc/dnie-compat.conf` | `module=`, `search=`, `multiarch=` | Persistent for desktop launches. Alternate path: `DNIE_COMPAT_CONF` |
| 4 | `DNIE_COMPAT_MULTIARCH` | `aarch64-linux-gnu` | Runtime override of the compiled tripleta |
| 5 | Build time | `make MULTIARCH=riscv64-linux-gnu` | `make MULTIARCH=` disables `/usr/lib/<tripleta>/` paths |
| 6 | Built-in paths + glob | `/usr/lib/opensc-pkcs11.so`, `/usr/lib/*/…` | Last resort |

Environment variables take precedence over the configuration file.

### Examples

```bash
# Module in a non-standard path
DNIE_COMPAT_MODULE=/opt/opensc/lib/opensc-pkcs11.so firefox

# Search several directories
DNIE_COMPAT_SEARCH_PATH=/opt/opensc/lib:/usr/local/lib firefox

# Change the tripleta without rebuilding
DNIE_COMPAT_MULTIARCH=riscv64-linux-gnu pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L

# Diagnostics
DNIE_COMPAT_DEBUG=1 pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L
```

Persistent file:

```ini
# /etc/dnie-compat.conf
module=/usr/lib/aarch64-linux-gnu/opensc-pkcs11.so
# search=/opt/opensc/lib
# multiarch=aarch64-linux-gnu
```

Template installed at
`/usr/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example`.

## 4. Tests

`tests/test-shim-paths.sh` — 13 cases, all without a reader:

| Case | Result |
|---|---|
| Exact path (`DNIE_COMPAT_MODULE`) | ✅ |
| Directory (`DNIE_COMPAT_SEARCH_PATH`) | ✅ |
| Several directories, valid one last | ✅ |
| Relative path ignored | ✅ |
| Invalid exact path is authoritative (fails) | ✅ |
| Config file: `module=` | ✅ |
| Config file: `search=` | ✅ |
| Invalid config file (fails) | ✅ |
| `DNIE_COMPAT_DEBUG` diagnostics | ✅ |
| `DNIE_COMPAT_MULTIARCH` at runtime | ✅ |
| `make MULTIARCH=tripleta-build` | ✅ |
| `make MULTIARCH=` (built-in paths) | ✅ |
| Load through built-in paths | ✅ |

Executed on:

| Architecture | Result |
|---|---|
| x86-64 (Manjaro) | ✅ 13/13 |
| aarch64 (Debian 13) | ✅ 13/13 |
| riscv64 (Debian 13) | ✅ 13/13 |

Real resolution on the boards:

```text
# ARM64 host
dnie-compat: conf=/etc/dnie-compat.conf module=(none) search=(none) multiarch=aarch64-linux-gnu
dnie-compat: probando /usr/lib/aarch64-linux-gnu/opensc-pkcs11.so

# RISC-V host
dnie-compat: conf=/etc/dnie-compat.conf module=(none) search=(none) multiarch=riscv64-linux-gnu
dnie-compat: probando /usr/lib/riscv64-linux-gnu/opensc-pkcs11.so
```

## 5. Installation

```bash
cd src/pkcs11-shim
make
sudo make install
```

Installs:

- `/usr/lib/libpkcs11-dnie.so`
- `/usr/share/p11-kit/modules/dnie-compat.module`
- `/usr/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example`

On Debian, `scripts/setup-debian.sh` does all of this.

## 6. Arch package

```bash
./packaging/arch/build-local.sh
sudo pacman -U packaging/arch/dnie-pkcs11-compat-0.1.0-1-*.pkg.tar.zst
```

## 7. Known limitations

- If the official module is installed, the package conflicts with it
  (`conflicts=('libpkcs11-dnie')`).
- `C_GetInfo` returns OpenSC data, not the official vendor data.
- p11-kit may show a single entry because it shares library identity with
  OpenSC; this is cosmetic and the module still loads.
- It implements nothing by itself: if OpenSC does not support an operation, the
  shim does not either.
