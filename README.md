# DNIe on aarch64 and riscv64

[![ci](https://github.com/ZiTAL/dni-e/actions/workflows/ci.yml/badge.svg)](https://github.com/ZiTAL/dni-e/actions/workflows/ci.yml)

Prebuilt releases for **aarch64**, **riscv64** and x86_64 are published on the
[releases page](https://github.com/ZiTAL/dni-e/releases).

Native stack for the Spanish electronic ID (**DNIe**) on Linux ARM64 and
RISC-V 64, without depending on the official `libpkcs11-dnie.so`
(closed-source, x86-64 only).

## Status

| Phase | Status |
|---|---|
| F0 — Environment and x86-64 baseline | ✅ |
| F1 — Component matrix | ✅ |
| F2 — Base stack on aarch64 | ✅ T1–T6 validated with the real card |
| F3 — PKCS#11 shim | ✅ x86-64, aarch64 and riscv64 |
| F4 — Autofirma | ✅ XAdES/PAdES signing on both architectures |
| F5 — riscv64 | ✅ T1–T6 validated with the real card |
| F6 — DNIe 4.0 coverage | ✅ `C_Sign` and authentication validated with the 4.0 card |
| F7 — Packaging | 🟡 Arch package ready; Debian package built in CI |
| F8 — Validation and docs | 🟡 T1–T6/T10 on both boards; T7 via GnuTLS, Chromium and Firefox on TLS 1.2; T8 pending a VNC session |

**Known limitations:** TLS 1.3 client authentication requires RSA-PSS, which
the DNIe key does not provide; use TLS 1.2 (Chromium:
`--ssl-version-max=tls1.2`). Firefox sends an empty certificate when the site's
acceptable CA list does not include `AC DNIE 004`; with the DNIe issuer
advertised it works. Autofirma's signing key needs a context-specific PIN and a
graphical `pinentry`, so signing on a headless board requires VNC.

## Install (any Linux, any architecture)

From a release tarball (no compiler needed):

```bash
sha256sum -c SHA256SUMS --ignore-missing
tar xzf dnie-pkcs11-compat-0.2.2-aarch64.tar.gz
cd dnie-pkcs11-compat-0.2.2-aarch64
sudo ./install.sh --binary --system
```

Debian/Ubuntu also have a native package:

```bash
sudo dpkg -i dnie-pkcs11-compat_0.2.2_arm64.deb
```

From source:

```bash
git clone https://github.com/ZiTAL/dni-e.git
cd dni-e
sudo ./install.sh --system
```

The installer detects the package manager, installs OpenSC, pcsc-lite and ccid
when needed, builds the shim for the current architecture, registers it with
p11-kit, configures polkit/plugdev, and can wire browsers and Autofirma. User
prefix, dry-run and uninstall are supported:

```bash
./install.sh --prefix "$HOME/.local"
sudo ./install.sh --system --uninstall
```

Full matrix and options: [docs/08-universal-install.md](docs/08-universal-install.md).

## How it works

```
Firefox ──PKCS#11──▶ libpkcs11-dnie.so (shim) ──▶ opensc-pkcs11.so
Autofirma ──JCA/JCE + JMulticard──▶ pcscd ──▶ reader ──▶ DNIe
```

- **OpenSC** (LGPL) implements the card driver and the PKCS#11 module.
- The **shim** occupies the path expected by official guides and applications.
- **Autofirma/jmulticard** (GPL/EUPL) cover signing from Java, with no native
  binaries to port.

The module path is configurable:
`DNIE_COMPAT_MODULE` > `DNIE_COMPAT_SEARCH_PATH` > `/etc/dnie-compat.conf` >
`DNIE_COMPAT_MULTIARCH` > `make MULTIARCH=` > built-in paths and `glob`.
See [docs/03-shim.md](docs/03-shim.md).

## Browser authentication

Chromium with OpenSC is the working path for DNIe TLS client authentication:

```bash
./scripts/setup-browser.sh /usr/lib/libpkcs11-dnie.so   # adds the module to NSS
chromium --ssl-version-max=tls1.2 https://www1.agenciatributaria.gob.es
```

TLS 1.3 requires RSA-PSS for RSA client certificates, while the DNIe/OpenSC
key only provides `CKM_RSA_PKCS`, so the connection must use TLS 1.2. Firefox
also works when the site advertises the DNIe issuer (`AC DNIE 004`) in its
acceptable CA list; otherwise it filters the certificate out; see
[docs/10-headless-browser.md](docs/10-headless-browser.md) §5.2–5.3.

## Quick verification

```bash
./scripts/verify-stack.sh      # installed stack and reader
./scripts/verify-card.sh       # card, ATR and certificates (no PIN)
./tests/test-nss.sh            # NSS/Firefox sees the DNIe certificates
./tests/test-shim-paths.sh     # 21 resolution, security and portability cases
./tests/run-matrix.sh          # runs the checks and archives the result
```

None of these scripts asks for a PIN. Tests that need it are marked T7–T9 in
the matrix and are never automated: three wrong attempts block the card.

## Portability

Install paths are fully configurable (`PREFIX`, `LIBDIR`, `P11KIT_MODULEDIR`,
`DOCDIR`, `MODULE_PATH`, `MULTIARCH`). The shim works on FHS distributions and
on non-FHS systems such as **Guix** and **Nix**; see
[docs/07-portability.md](docs/07-portability.md) and [guix.scm](guix.scm).

## Security

The shim is small and audited: environment overrides are ignored in
secure-execution mode (`secure_getenv`), configuration files must be regular and
safely owned, relative paths are rejected, initialization is thread-safe, only
two symbols are exported, and the build uses stack protector and full RELRO.
Findings and fixes are listed in [PLAN.md](PLAN.md#8-security-hardening).

## Documentation

- [NEXT-STEPS.md](NEXT-STEPS.md) — handover checklist for after certificate renewal
- [INSTALL.md](INSTALL.md) — installation guide (releases and source)
- [docs/00-environment.md](docs/00-environment.md) — host, versions and baseline
- [docs/01-matrix.md](docs/01-matrix.md) — availability per architecture
- [docs/02-aarch64.md](docs/02-aarch64.md) — ARM64 deployment
- [docs/03-shim.md](docs/03-shim.md) — PKCS#11 compatibility module
- [docs/04-autofirma.md](docs/04-autofirma.md) — Autofirma on ARM/RISC-V
- [docs/05-riscv64.md](docs/05-riscv64.md) — RISC-V deployment
- [docs/06-dnie4.md](docs/06-dnie4.md) — DNIe 4.0 coverage in OpenSC
- [docs/07-portability.md](docs/07-portability.md) — FHS, Guix and Nix
- [docs/08-universal-install.md](docs/08-universal-install.md) — installer for any Linux and architecture
- [docs/09-multiarch-validation.md](docs/09-multiarch-validation.md) — cross-build, musl and QEMU validation
- [docs/10-headless-browser.md](docs/10-headless-browser.md) — headless browsers and the DNIe PIN
- [REPORT.md](REPORT.md) — autonomous session report

## License

Copyright (C) 2026 dni-e contributors.

This project is free software: you can redistribute it and/or modify it under
the terms of the **GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version**. See [LICENSE](LICENSE).

Third-party components keep their own licenses:

- OpenSC: LGPL-2.1-or-later
- Autofirma: GPL-2.0-or-later AND EUPL-1.1
- jmulticard: LGPL-2.1-or-later / EUPL-1.1-or-later

This project does not redistribute or modify the official DGP/FNMT module.
