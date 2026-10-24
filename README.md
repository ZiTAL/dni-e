# DNIe on aarch64 and riscv64

Native stack for the Spanish electronic ID (**DNIe**) on Linux ARM64 and
RISC-V 64, without depending on the official `libpkcs11-dnie.so`
(closed-source, x86-64 only).

## Status

| Phase | Status |
|---|---|
| F0 — Environment and x86-64 baseline | ✅ |
| F1 — Component matrix | ✅ |
| F2 — Base stack on aarch64 | ✅ installed and validated (no reader yet) |
| F3 — PKCS#11 shim | ✅ x86-64, aarch64 and riscv64 |
| F4 — Autofirma | ✅ XAdES/PAdES signing on both architectures |
| F5 — riscv64 | ✅ installed and validated (no reader yet) |
| F6 — DNIe 4.0 coverage | 🟡 OpenSC accepts the 4.0 ATR; PIN test pending |
| F7 — Packaging | 🟡 Arch package ready; Debian via script |
| F8 — Validation and docs | 🟡 report and docs ready; real T1–T9 pending |

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

## Quick verification

```bash
./scripts/verify-stack.sh      # installed stack and reader
./scripts/verify-card.sh       # card, ATR and certificates (no PIN)
./tests/test-shim-paths.sh     # 13 module-resolution cases
./tests/run-matrix.sh          # runs the checks and archives the result
```

None of these scripts asks for a PIN. Tests that need it are marked T7–T9 in
the matrix and are never automated: three wrong attempts block the card.

## Documentation

- [docs/00-environment.md](docs/00-environment.md) — host, versions and baseline
- [docs/01-matrix.md](docs/01-matrix.md) — availability per architecture
- [docs/02-aarch64.md](docs/02-aarch64.md) — ARM64 deployment
- [docs/03-shim.md](docs/03-shim.md) — PKCS#11 compatibility module
- [docs/04-autofirma.md](docs/04-autofirma.md) — Autofirma on ARM/RISC-V
- [docs/05-riscv64.md](docs/05-riscv64.md) — RISC-V deployment
- [docs/06-dnie4.md](docs/06-dnie4.md) — DNIe 4.0 coverage in OpenSC
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
