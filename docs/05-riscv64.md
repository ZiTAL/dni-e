# 05 — riscv64 (VisionFive 2)

**Host:** RISC-V board · StarFive VisionFive 2 · Debian 13 (trixie) · kernel 6.6.20
**Date:** 2026-10-24
**Status:** ✅ stack and reader validated (T1–T6); signing pending certificate renewal

---

## 1. Installed

With `sudo ./scripts/setup-debian.sh`:

| Package | Version |
|---|---|
| `pcscd` | 2.3.3-1 |
| `libccid` | 1.6.2-1 |
| `pcsc-tools` | 1.7.3-1 |
| `opensc` / `opensc-pkcs11` | 0.26.1-2 |
| `p11-kit` | 0.25.5-3 |
| `libnss3-tools` | — |

Service `pcscd.socket`: **active**.

OpenSC module: `/usr/lib/riscv64-linux-gnu/opensc-pkcs11.so`.

## 2. Shim

```
/usr/lib/libpkcs11-dnie.so          ELF riscv64, SONAME libpkcs11-dnie.so
/usr/share/p11-kit/modules/dnie-compat.module
```

Real resolution:

```text
dnie-compat: conf=/etc/dnie-compat.conf module=(none) search=(none) multiarch=riscv64-linux-gnu
dnie-compat: probando /usr/lib/riscv64-linux-gnu/opensc-pkcs11.so
```

## 3. polkit and group membership

pcscd authorizes clients through polkit. The rule
`/etc/polkit-1/rules.d/50-pcscd.rules` allows the `plugdev` group, and the user
must belong to it. On this board `zital` was not in `plugdev`; adding it fixed
the "reader invisible" problem:

```bash
sudo usermod -aG plugdev zital
sudo systemctl restart polkit
```

`scripts/setup-debian.sh` now installs the rule **and** adds `$SUDO_USER` to
`plugdev`.

## 4. Reader and card validated

```
Reader 0: Alcor Micro AU9540 00 00
Card state: Card inserted
ATR: 3B 7F 96 00 00 00 6A 44 4E 49 65 10 01 01 55 04 21 03 90 00
OpenSC: dnie
Certificates: CertAutenticacion, CertFirmaDigital, CertCAIntermediaDGP
```

| Test | Result |
|---|---|
| T1 — `pcsc_scan` detects the reader | ✅ `Alcor Micro AU9540` |
| T2 — DNIe ATR | ✅ `3B 7F 96 …` |
| T3 — `opensc-tool -n` | ✅ `dnie` |
| T4 — `pkcs15-tool --list-certificates` | ✅ 3 certificates |
| T5 — `pkcs11-tool -L/-O` through the shim | ✅ token `DNI electrónico` |
| T6 — NSS (Firefox layer) lists the certificates | ✅ 3 certs (`tests/test-nss.sh`) |

## 5. Autofirma

System Java: **OpenJDK 25.0.4.1 (riscv64)**.

Deployed in `~/autofirma` with the launcher adapted to Java 25.

| Test | Result |
|---|---|
| CLI start / help | ✅ |
| XAdES signing with PKCS#12 | ✅ 5,109 B |
| PAdES signing of a PDF | ✅ 55,364 B |
| PKCS#11 store signing (SoftHSM) | ✅ 5,115 B |
| GUI | ⏳ requires Xvfb/X11 (not installed) |

## 6. Shim tests

`tests/test-shim-paths.sh`: **21/21**.

| Architecture | Result |
|---|---|
| x86-64 | ✅ 21/21 |
| aarch64 | ✅ 21/21 |
| riscv64 | ✅ 21/21 |

## 7. Missing

None for T1–T6. The certificates were renewed on 2026-10-26; T7–T9 are pending
the PIN tests.
