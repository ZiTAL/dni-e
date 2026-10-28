# 00 — Environment and baseline

**Date:** 2026-10-24
**Phase:** F0 (setup)
**Result:** ✅ reproducible x86-64 baseline

---

## 1. Development machine

| Item | Value |
|---|---|
| Distribution | Manjaro Linux (rolling) |
| Kernel | 7.1.13-2-MANJARO |
| Architecture | x86_64 |
| Compiler | GCC 16.2.1 · Clang 22.1.8 |
| Build | GNU Make 4.4.1 · CMake 4.4.3 · Ninja 1.13.2 |
| pkg-config | 3.0.7 |
| OpenSSL | 3.6.4 |
| Java | OpenJDK 26.0.2.1 (system) · OpenJDK 17.0.20.1 (`jdk17-openjdk`, required by Autofirma) |
| Maven | 3.9.16 |
| Node | 24.14.0 (not used by this project) |

## 2. Installed DNIe stack

| Package | Version | Role |
|---|---|---|
| `pcsclite` | 2.5.1 | PC/SC daemon and API |
| `ccid` | 1.8.3 | USB CCID reader driver |
| `pcsc-tools` | 1.7.5 | `pcsc_scan` (diagnostics) |
| `opensc` | 0.27.1 | DNIe driver + PKCS#11 module |
| `p11-kit` | 0.26.5 | PKCS#11 module registry |
| `jdk17-openjdk` | 17.0.20.1 | Autofirma runtime |
| `autofirma` | 1.9.2 (AUR) | Electronic signing |

Relevant paths:

- OpenSC PKCS#11 module: `/usr/lib/opensc-pkcs11.so`
- p11-kit registration: `/usr/share/p11-kit/modules/opensc.module`
- PC/SC headers: `/usr/include/PCSC/` (`pkg-config libpcsclite` → 2.5.1)
- Autofirma: `/usr/share/java/autofirma/autofirma.jar` + `/usr/bin/autofirma`

## 3. Reader and card

| Item | Value |
|---|---|
| Reader | Alcor Micro AU9540 (`058f:9540`), CCID |
| State | `Card inserted`, `Shared Mode` |
| ATR | `3B 7F 96 00 00 00 6A 44 4E 49 65 10 01 01 55 04 21 03 90 00` |
| OpenSC identification | `dnie` |
| Generation | **DNIe 4.0** (version byte `0x04` in the ATR) |
| Certificates | `CertAutenticacion`, `CertFirmaDigital`, `CertCAIntermediaDGP` |

**Card orientation:** the reader requires the chip in one specific orientation;
the opposite one yields `Card state: Card inserted, Unresponsive card` and
`pcscd` logs `CmdPowerOn Card absent or mute`. It is the number one cause of
false negatives.

### Certificate status

| Certificate | Valid from | Valid until | Status |
|---|---|---|---|
| `CertAutenticacion` | 2026-10-26 | 2028-10-26 | ✅ valid (renewed) |
| `CertFirmaDigital` | 2026-10-26 | 2028-10-26 | ✅ valid (renewed) |
| `CertCAIntermediaDGP` | 2014-06-13 | 2029-06-13 | ✅ valid |

**Consequence:** T1–T6 are validated. With the renewed certificates T7 was
closed with GnuTLS, Chromium and Firefox on TLS 1.2, and T8/T9 on x86-64,
aarch64 and riscv64.

## 4. Services and configuration

```text
pcscd.socket   enabled + active
```

- The default Firefox profile has the `OpenSC` module loaded in
  `pkcs11.txt`.
- `p11-kit list-modules` exposes `opensc` correctly.
- Autofirma detects the card through JMulticard; it hides expired certificates or reports none if the card is unresponsive.

## 5. F0 acceptance criteria

| Criterion | Result |
|---|---|
| Repository created with the planned structure | ✅ |
| Complete toolchain | ✅ |
| Versions pinned | ✅ |
| Reader detected | ✅ |
| Card identified as DNIe | ✅ |
| Certificates listed without PIN | ✅ |
| x86-64 state snapshot | ✅ (this document) |

## 6. Follow-up items

- Define the aarch64 and riscv64 boards (done: Orange Pi 5 and VisionFive 2).
- Renew certificates to close T7–T9 (done 2026-10-26; all closed on x86-64,
  aarch64 and riscv64).
- Obtain (optional) a DNIe 3.0 for cross-testing with DNIe 4.0.
