# Autonomous session report

**Date:** 2026-10-24, updated 2026-10-28
**Scope:** deploy and validate the DNIe stack on an ARM64 host (Orange Pi 5) and a RISC-V host (VisionFive 2).
**Outcome:** both machines have the full stack installed and validated. The
certificates were renewed on 2026-10-26 (valid until 2028-10-26). T7 is closed
with GnuTLS, Chromium (TLS 1.2) and Firefox, T8 and T9 are closed on x86-64,
and T9 is also green on the ARM64 board for the authentication key. The only
open item is the signing PIN prompt on the boards, which needs a graphical
`pinentry` (VNC); see [NEXT-STEPS.md](NEXT-STEPS.md).

---

## 1. Executive summary

| | ARM64 host (Orange Pi 5) | RISC-V host (VisionFive 2) |
|---|---|---|
| OS | Debian 13 trixie | Debian 13 trixie |
| `pcscd` + `ccid` | ✅ installed and active | ✅ installed and active |
| OpenSC | ✅ 0.26.1 | ✅ 0.26.1 |
| Shim `libpkcs11-dnie.so` | ✅ in `/usr/lib` | ✅ in `/usr/lib` |
| p11-kit | ✅ | ✅ |
| Autofirma | ✅ Java 21 | ✅ Java 25 |
| XAdES / PAdES signing | ✅ | ✅ |
| PKCS#11 signing | ✅ | ✅ |
| USB reader | ✅ validated (T1–T6) | ✅ validated (T1–T6) |

**No PIN attempt was spent in the initial session.** Everything was tested
without a card or with laboratory stores (PKCS#12 and SoftHSM). The later tests
with the real card (2026-10-26/27) used a PIN verified independently with
`pkcs15-tool --verify-pin`.

---

## 2. Executed validations

| Test | ARM64 | RISC-V |
|---|---|---|
| Shim compilation | ✅ aarch64 | ✅ riscv64 |
| SONAME `libpkcs11-dnie.so` | ✅ | ✅ |
| Module load (no reader) | ✅ `No slots.` | ✅ `No slots.` |
| Autofirma starts | ✅ under Xvfb | ✅ CLI mode |
| XAdES signing with PKCS#12 | ✅ 5,108 B | ✅ 5,109 B |
| PAdES signing of a PDF | ✅ 55,364 B | ✅ 55,364 B |
| PKCS#11 store signing | ✅ 5,114 B | ✅ 5,115 B |
| `SignatureValue` present | ✅ | ✅ |
| 21 resolution/security/portability tests | ✅ | ✅ |
| Reader + ATR + certificates (T1–T4, real DNIe 4.0) | ✅ | ✅ |
| Shim PKCS#11 objects (T5) | ✅ | ✅ |
| NSS/Firefox certificate listing (T6) | ✅ | ✅ |

The real DNIe signing test (T8) was performed on the x86-64 workstation with
the renewed card: Autofirma produced a PAdES signature and `openssl cms`
verified it, with the chain to the DNIe CA (`-partial_chain`). `pdfsig` reports
a false negative because the DNIe signing certificate uses
`keyUsage = Non Repudiation` instead of `digitalSignature`.

T7 was validated at the TLS layer on the x86-64 workstation: `scripts/test-tls-auth.sh`
used GnuTLS with the DNIe authentication certificate and private key (PKCS#11),
the client sent both certificates and the handshake completed
(`RESULT: TLS client authentication OK`).

On 2026-10-27 a Firefox session showed the DNIe certificate in the chooser and
then sent an **empty** certificate list after the PIN. On 2026-10-28 the same
machine, card and PIN were tested again and Firefox completed the handshake
with OpenSC and with the shim, using automatic selection and the chooser, with
a fresh profile and with a copy of the real profile, and against AEAT at TLS
1.2. The empty list is reproducible when the server's acceptable CA list does
not contain the DNIe issuer: NSS then filters the certificate out and does not
ask for the PIN. The exact 2026-10-27 sequence could not be reproduced; the CA
file used by that test server is the main suspect. See
`docs/10-headless-browser.md` §5.2.

On the ARM64 board the same day, T9 was validated directly on the
authentication key: `pkcs11-tool --test` signed with `KprivAutenticacion`
using RSA-PKCS and its SHA1/SHA256/RIPEMD160/MD5 variants. The signing key
requires a context-specific PIN (`CKA_ALWAYS_AUTHENTICATE`) and OpenSC's
`pinentry` cannot prompt on the headless board. T7 with the GnuTLS 3.8.9 and
OpenSSL 3.5 + pkcs11-provider 1.2.0 clients also fails at the TLS layer
(empty Certificate message / invalid key handle), while the card, the PIN and
`C_Sign` work. See `docs/02-aarch64.md` §6.

Chromium 155 with the same OpenSC module **completes** client authentication
with the DNIe when the test server is forced to TLS 1.2 and requests
`RSA+SHA256` (PKCS#1 v1.5). The server verified the client certificate to
`AC DNIE 004` and the page loaded. On the default TLS 1.3 server Chromium
fails with `ERR_SSL_CLIENT_AUTH_NO_COMMON_ALGORITHMS`, because TLS 1.3
requires RSA-PSS and the DNIe key only provides `CKM_RSA_PKCS`. Firefox does
the same on TLS 1.2 once the server advertises the DNIe issuer; both browsers
are working paths on x86-64 (`docs/10-headless-browser.md` §5.2–5.3).

The PKCS#11 test is the important one: it is exactly the path the DNIe will use
(Autofirma → PKCS#11 module → card). It was done with SoftHSM because there is
no reader yet; replacing SoftHSM with `libpkcs11-dnie.so` keeps the same flow.

---

## 3. Security and portability

The shim was audited and hardened (see `PLAN.md` §8): `secure_getenv` for all
environment overrides, regular-file and ownership checks for the configuration,
rejection of relative paths, truncation checks, `pthread_once`, hidden symbols,
stack protector and full RELRO. The suite now covers 21 cases, including
FIFO/directory configuration, oversized paths, exported-symbol count and
8-thread concurrency.

Install paths are path-agnostic (`PREFIX`, `LIBDIR`, `P11KIT_MODULEDIR`,
`DOCDIR`, `MODULE_PATH`, `MULTIARCH`), and the p11-kit module file is generated
at install time. This makes the shim usable on FHS distributions and on
non-FHS systems such as Guix and Nix; see `docs/07-portability.md` and
`guix.scm`.

### 3.1 Configurable module paths

`/usr/lib/<tripleta>/` is no longer hardcoded. Precedence:

1. `DNIE_COMPAT_MODULE=/exact/path/opensc-pkcs11.so` (authoritative)
2. `DNIE_COMPAT_SEARCH_PATH=/dir1:/dir2`
3. `/etc/dnie-compat.conf` (`module=`, `search=`, `multiarch=`)
4. `DNIE_COMPAT_MULTIARCH=aarch64-linux-gnu` (runtime)
5. `make MULTIARCH=riscv64-linux-gnu` (build time)
6. Built-in paths and `glob`

Verified with `tests/test-shim-paths.sh`: **13/13 on x86-64, aarch64 and riscv64**.

---

## 4. What is already done

### ARM64 host

```
pcscd 2.3.3 · libccid 1.6.2 · pcsc-tools 1.7.3
opensc 0.26.1 · opensc-pkcs11 0.26.1 · p11-kit 0.25.5
openjdk-21-jre 21.0.12 · libnss3-tools · xvfb · xauth · softhsm2
```

- `pcscd.socket` and `pcscd.service` active.
- aarch64 shim installed at `/usr/lib/libpkcs11-dnie.so`.
- p11-kit registration at `/usr/share/p11-kit/modules/dnie-compat.module`.
- Autofirma installed (`/usr/bin/autofirma`, launcher adapted to Java 21).

### RISC-V host

- Full stack installed with `scripts/setup-debian.sh`.
- `pcscd.socket` active.
- riscv64 shim installed and resolving `/usr/lib/riscv64-linux-gnu/opensc-pkcs11.so`.
- Autofirma in `~/autofirma` with Java 25 (validated XAdES, PAdES and PKCS#11).

---

## 5. Reader, certificates and open items

### 5.1 USB reader

Validated with the real DNIe 4.0 card on **both** hosts: reader, ATR, `dnie`,
three certificates, PKCS#11 objects and the NSS/Firefox certificate listing.

On headless or SSH access, pcscd needs the polkit rule shipped in
`packaging/polkit/50-pcscd.rules` **and** the user must belong to `plugdev`;
otherwise the reader is invisible even though `lsusb` shows it. The Debian
setup script handles both.

### 5.2 Certificates

They were **renewed on 2026-10-26** and are valid until **2028-10-26**. The
renewed dates were confirmed on the card and the three certificates are listed
by OpenSC, PKCS#11 and NSS. The stack reads them without a PIN; T7–T9 are closed
except for the boards' signing PIN prompt.

### 5.3 Open items

| Item | Why it is open | Next action |
|---|---|---|
| T8 on the boards | The signing key is `CKA_ALWAYS_AUTHENTICATE` and `pinentry` cannot prompt headless | Xvfb + x11vnc session (`docs/02-aarch64.md` §6) |
| TLS 1.3 | RSA-PSS is required and the key only provides `CKM_RSA_PKCS` | Documented limitation; use TLS 1.2 |
| Servers without the DNIe CA | If the acceptable CA list lacks `AC DNIE 004`, Firefox sends an empty certificate and asks for no PIN | Use a CA list with the DNIe issuer; see `docs/10-headless-browser.md` §5.2 |

---

## 6. How to verify once the reader is connected

```bash
cd ~/dni-e
./scripts/verify-stack.sh
./scripts/verify-card.sh
```

Expected output:

```
Card state: Card inserted
ATR: 3B 7F 96 ...
OpenSC recognized: dnie
3 certificates visible
```

If it says `Unresponsive card`, turn the DNIe around: the chip must face the
reader contacts.

Then:

- **Authentication:** Firefox → Cl@ve/AEAT → certificate → PIN.
- **Signing:** `autofirma` → Sign → PDF → certificate → PIN.

---

## 7. Technical findings

1. **Multiarch path on Debian.** OpenSC lives at
   `/usr/lib/<tripleta>/opensc-pkcs11.so`; it is now configurable at runtime and
   at build time.
2. **p11-kit format.** On Debian the `.module` file uses `module: <absolute path>`.
3. **p11-kit merges the entry** with OpenSC because they share library identity.
   Cosmetic; the module still loads.
4. **Autofirma and Java.** The launcher requires 17, which is absent in Debian 13.
   Patched to 21/25: it works.
5. **Autofirma package is `any`.** There is nothing native to port.
6. **OpenSC accepts DNIe 4.0** (its ATR table masks the version byte).

---

## 8. Artifacts

- Repo: `~/dni-e`; copy at `~/dni-e` on both machines.
- Documentation: `docs/00` to `docs/10`.
- Arch shim package: `packaging/arch/`.
- Debian setup: `scripts/setup-debian.sh`.
- Tests: `tests/test-shim-paths.sh`, `scripts/verify-*.sh`.

---

## Handover

The stack is complete up to T6 on both boards, and T7–T9 are closed at the
TLS/PKCS#11 layer. Remaining work: the signing PIN prompt on the boards (VNC).
See [NEXT-STEPS.md](NEXT-STEPS.md) for the checklist, commands and known risks.
