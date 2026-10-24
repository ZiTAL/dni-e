# 02 — aarch64 (Orange Pi 5)

**Host:** ARM64 board · Orange Pi 5 · Debian 13 (trixie) · kernel 6.1.115
**Date:** 2026-10-24
**Status:** ✅ stack installed and validated without a card (physical reader missing)

---

## 1. Installed

| Package | Version |
|---|---|
| `pcscd` | 2.3.3-1 |
| `libccid` | 1.6.2-1 |
| `pcsc-tools` | 1.7.3-1 |
| `opensc` | 0.26.1-2 |
| `opensc-pkcs11` | 0.26.1-2 |
| `p11-kit` | 0.25.5-3 |
| `openjdk-21-jre` | 21.0.12.1 |
| `libnss3-tools`, `xvfb`, `xauth` | (for Autofirma and tests) |

Service: `pcscd.socket` and `pcscd.service` **active**.

OpenSC module on Debian: `/usr/lib/aarch64-linux-gnu/opensc-pkcs11.so`.

## 2. Deployed shim

```
/usr/lib/libpkcs11-dnie.so                    ELF aarch64, SONAME libpkcs11-dnie.so
/usr/share/p11-kit/modules/dnie-compat.module
```

Tests:

```text
$ pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L
No slots.                # no reader connected; the module loads fine

$ DNIE_COMPAT_DEBUG=1 pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L
dnie-compat: probando /usr/lib/opensc-pkcs11.so
dnie-compat: ... cannot open shared object file
dnie-compat: probando /usr/lib/aarch64-linux-gnu/opensc-pkcs11.so
```

Multiarch resolution works. `p11-kit list-modules` loads the module but shows it
merged with `opensc-pkcs11` because both report the same library identity; this
is cosmetic and does not affect loading.

## 3. Autofirma

The AUR package (contents `any`) was installed with the launcher adapted to
Java 21:

```
/usr/bin/autofirma                              (launcher, _java_version="21")
/usr/share/java/autofirma/autofirma.jar         46 MB
```

Tests:

| Test | Result |
|---|---|
| GUI start under Xvfb | ✅ stays alive (timeout 124) |
| XAdES signing with a test PKCS#12 | ✅ 5,108 bytes, `SignatureValue` present |
| PAdES signing of a PDF | ✅ 55,364 bytes, `ByteRange` present |
| PKCS#11 store signing (SoftHSM) | ✅ 5,114 bytes, `SignatureValue` present |

```text
La operacion ha terminado correctamente
```

The PKCS#11 test uses the same path as the DNIe: Autofirma → PKCS#11 module →
card. With a reader, the module will be `libpkcs11-dnie.so`.

## 4. Missing

1. **USB reader.** The machine has no reader connected (`lsusb` only shows a
   serial adapter). Without a reader, T1–T4 cannot run.
2. **Valid certificates** for T7–T9.

## 5. Reproduce

```bash
sudo ./scripts/setup-debian.sh
./scripts/verify-stack.sh
```
