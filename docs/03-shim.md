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
- Only two symbols are exported; everything else is hidden.
- Build hardening: stack protector, full RELRO, `BIND_NOW`, `-z defs`.
- Initialization is serialized with `pthread_once`, safe for concurrent
  `C_GetFunctionList` / `C_GetInterface` calls.

## 3. Security hardening

Findings from the audit and the fix applied:

| # | Finding | Risk | Fix |
|---|---|---|---|
| S1 | `DNIE_COMPAT_*` variables were read with `getenv(3)`, so a setuid/setgid process could be redirected to an arbitrary `.so` | High | all variables read with `secure_getenv(3)`; ignored in secure-execution mode |
| S2 | The configuration file could be a FIFO or device, blocking the process or reading an unexpected source | Medium | `stat(2)` + `S_ISREG` required before `fopen` |
| S3 | When running as root, a group/other-writable or non-root-owned config file allowed privilege escalation | Medium | root requires `st_uid == 0` and no `S_IWGRP`/`S_IWOTH` |
| S4 | Relative paths in overrides could load a module from the current directory | Medium | non-absolute paths are ignored |
| S5 | A very long search directory could be truncated into a different path | Low | `snprintf` result checked; truncated candidates are skipped |
| S6 | Lazy initialization was not thread-safe; concurrent calls could load twice or see partial state | Medium | `pthread_once(3)` |
| S7 | All internal symbols were exported, widening the interposition surface | Low | `-fvisibility=hidden`; only `C_GetFunctionList` and `C_GetInterface` are exported (asserted by tests) |
| S8 | No hardening flags in the default build | Medium | `-fstack-protector-strong`, `-Wl,-z,relro,-z,now,-z,defs`; test checks `GNU_RELRO` and `BIND_NOW` |
| S9 | A user-controlled config file in `$HOME` could be read by a root process | Low | secure mode ignores it; root ownership/permission check applies |

Residual risks (out of scope, documented): `LD_PRELOAD`/`LD_LIBRARY_PATH`
attacks against the host process, a compromised root account, and OpenSC's own
security. The shim never sees PIN material: PIN handling stays inside OpenSC.

## 4. Module path configuration

The shim looks for `opensc-pkcs11.so` with this precedence:

| Order | Source | Example | Notes |
|---|---|---|---|
| 1 | `DNIE_COMPAT_MODULE` | `/opt/opensc/lib/opensc-pkcs11.so` | Exact path. **Authoritative**: if it fails, nothing else is tried |
| 2 | `DNIE_COMPAT_SEARCH_PATH` | `/opt/opensc/lib:/usr/local/lib` | Colon-separated directories |
| 3 | Config file | `$DNIE_COMPAT_CONF`, `/etc/dnie-compat.conf`, `$XDG_CONFIG_HOME/…`, `$HOME/.config/…` | First regular, safe file wins |
| 4 | `DNIE_COMPAT_MULTIARCH` | `aarch64-linux-gnu` | Runtime override of the compiled tripleta |
| 5 | `MODULE_PATH` (build) | `make MODULE_PATH=/gnu/store/…/opensc-pkcs11.so` | Embedded path; required on Guix/Nix |
| 6 | `make MULTIARCH=` | `make MULTIARCH=riscv64-linux-gnu` | `MULTIARCH=` disables `/usr/lib/<tripleta>/` |
| 7 | Built-in paths + glob | `/usr/lib/opensc-pkcs11.so`, `/usr/lib/*/…`, `/run/current-system/sw/lib/…` | Last resort |

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

## 5. Tests

`tests/test-shim-paths.sh` — 21 cases, all without a reader:

| Group | Cases |
|---|---|
| Resolution | exact path, directory, several directories, relative ignored, authoritative failure, config `module=`, config `search=`, invalid config, debug output, runtime multiarch, build-time multiarch, empty multiarch |
| Security | FIFO config ignored, directory config ignored, oversized search entry, `BIND_NOW`, `GNU_RELRO`, only two exported symbols, 8-thread concurrency |
| Portability | non-FHS install loads through embedded `MODULE_PATH` |

Executed on:

| Architecture | Result |
|---|---|
| x86-64 (Manjaro) | ✅ 21/21 |
| aarch64 (Debian 13) | ✅ 21/21 |
| riscv64 (Debian 13) | ✅ 21/21 |

## 6. Installation

```bash
cd src/pkcs11-shim
make
sudo make install
```

Installs:

- `/usr/lib/libpkcs11-dnie.so`
- `/usr/share/p11-kit/modules/dnie-compat.module` (generated from `.in`)
- `/usr/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example`

All paths are overridable (`PREFIX`, `LIBDIR`, `P11KIT_MODULEDIR`, `DOCDIR`,
`CONFIG_FILE`, `MODULE_PATH`). See [07-portability.md](07-portability.md).

On Debian, `scripts/setup-debian.sh` does all of this.

## 7. Arch package

```bash
./packaging/arch/build-local.sh
sudo pacman -U packaging/arch/dnie-pkcs11-compat-0.2.3-1-*.pkg.tar.zst
```

## 8. Known limitations

- If the official module is installed, the package conflicts with it
  (`conflicts=('libpkcs11-dnie')`).
- `C_GetInfo` returns OpenSC data, not the official vendor data.
- p11-kit may show a single entry because it shares library identity with
  OpenSC; this is cosmetic and the module still loads.
- It implements nothing by itself: if OpenSC does not support an operation, the
  shim does not either.
