# 05 — riscv64 (VisionFive 2)

**Host:** RISC-V board · StarFive VisionFive 2 · Debian 13 (trixie) · kernel 6.6.20
**Date:** 2026-10-24, updated 2026-10-28
**Status:** ✅ T1–T10 validated on the board, including TLS client auth
(GnuTLS), `C_Sign` with the signing key and PAdES with Autofirma

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
| shim `libpkcs11-dnie.so` | 0.2.3 (published riscv64 `.deb`, 2026-10-28) |

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

**Update 2026-10-28:** the board had `dnie-pkcs11-compat` 0.2.0 from the first
install. It was upgraded to the published `v0.2.3` riscv64 `.deb`, the first
release that ships one:

```text
package dnie-pkcs11-compat 0.2.3 (dpkg -V clean)
sha256  642fb0ab42b860eacf10ed70de39013744407ab1cc22780800a63b0842aecd6c
backup  /usr/lib/libpkcs11-dnie.so.0.1.0.bak
```

The shim code is unchanged across the 0.2.x releases. This is the binary that
was validated with T9 (signature verified) and T8 (`openssl cms` verification
successful).

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

## 7. T7–T9 on the board (2026-10-28)

The reader and card were moved here and the card tests repeated with OpenSC
0.26.1 and the installed shim.

| Test | Result |
|---|---|
| T9 — `C_Sign`, signing key | ✅ `SHA256-RSA-PKCS` with `KprivFirmaDigital`, 256-byte signature, `Verified OK` against the FIRMA certificate |
| T8 — Autofirma PAdES | ✅ `-store pkcs11:… -alias CertFirmaDigital`; `openssl cms` verifies the signature (see below) |
| T7 — TLS with GnuTLS 3.8.9 | ✅ local TLS 1.2 server that advertises `AC DNIE 004`: the server received the 0e1c-byte client certificate (`depth=0 … AUTENTICACIÓN`) and returned 200; also completes against AEAT (the site returns its own 403) |
| T10 — clean package install | ✅ removed and reinstalled `dnie-pkcs11-compat` 0.2.3 from the published `.deb`; `dpkg -V` clean, module loads |

The stale OpenSC cache affected this board too: after the 2026-10-26 renewal
`pkcs15-tool` still listed the old 2022 IDs until `pkcs15-tool --clear-cache`.
Run it after any renewal.

Signing with the signing key needs the DNIe user-consent prompt disabled for
unattended use (it returns `Not allowed` headless); the PIN is still required.
The procedure and the `user_consent_enabled = false` config are in
`docs/02-aarch64.md` §6.1.

### 7.1 pdfsig 26.08 reports a false negative

The signed PDFs from both boards verify with `openssl cms` (with and without
the AC DNIE 004 chain). `pdfsig` 25.03 on the ARM64 board reported *Signature
is Valid*; `pdfsig` 26.08 reports *Signature is Invalid* for the same files.
Do not use recent pdfsig versions as the only check.

TLS 1.3 client authentication is not possible because the key only offers
`CKM_RSA_PKCS`.
