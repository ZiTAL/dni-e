# 05 — riscv64 (VisionFive 2)

**Host:** RISC-V board · StarFive VisionFive 2 · Debian 13 (trixie) · kernel 6.6.20
**Date:** 2026-10-24
**Status:** ✅ stack installed and validated (physical reader missing)

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
No slots.
```

## 3. Autofirma

System Java: **OpenJDK 25.0.4.1 (riscv64)**.

Deployed in `~/autofirma` with the launcher adapted to Java 25.

| Test | Result |
|---|---|
| CLI start / help | ✅ |
| XAdES signing with PKCS#12 | ✅ 5,109 B |
| PAdES signing of a PDF | ✅ 55,364 B |
| PKCS#11 store signing (SoftHSM) | ✅ 5,115 B |
| GUI | ⏳ requires Xvfb/X11 (not installed) |

SoftHSM was extracted without root with `apt-get download` + `dpkg -x`, and the
token was initialised with `pkcs11-tool --init-token` (the packaged
`softhsm2-util` has the module path compiled in and could not find the copy in
`$HOME`).

## 4. Shim tests

`tests/test-shim-paths.sh`: **21/21**.

| Architecture | Result |
|---|---|
| x86-64 | ✅ 21/21 |
| aarch64 | ✅ 21/21 |
| riscv64 | ✅ 21/21 |

## 5. Missing

1. **USB reader on this board.** The polkit rule is already installed
   (`/etc/polkit-1/rules.d/50-pcscd.rules`), so the reader should be visible as
   soon as it is connected. The single available reader is currently validated
   on the ARM64 board.
2. **Valid certificates** for T7–T9.

## 6. polkit note

On headless or SSH sessions, pcscd denies `access_pcsc` unless the
`plugdev` group is authorized. The rule from
`packaging/polkit/50-pcscd.rules` is installed by `scripts/setup-debian.sh`.
See [02-aarch64.md](02-aarch64.md#3-polkit-required-on-headless--ssh-access).
