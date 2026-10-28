# Next steps after certificate renewal

**Status captured:** 2026-10-27 · release `v0.2.2`

**Update 2026-10-26:** the certificates were renewed and verified on the card
(valid until 2028-10-26). Step 1 is complete; continue at step 2.

**Update 2026-10-27 (ARM64 board):** T1–T6 and T10 revalidated; the Firefox
profile was created at `~/.mozilla/dnie-profile`; the Debian package was
upgraded to 0.2.1. A stale OpenSC cache was hiding the renewed certificates
(see `docs/02-aarch64.md` §4); `pkcs15-tool --clear-cache` fixes it and
`verify-card.sh` now does it automatically. T7–T9 still need the interactive
PIN test.

**Update 2026-10-27 (x86-64, GUI):** the PIN is confirmed correct and the card
logs in. Firefox shows the DNIe authentication certificate and asks for the PIN,
but after the PIN it still sends an empty certificate list. Software
certificates in the same setup are sent and verified, so the remaining issue is
specific to Firefox/NSS + OpenSC; see `docs/10-headless-browser.md` §5.2.

**Update 2026-10-27 (ARM64 board, PIN):** T9 passes for the authentication key
(`pkcs11-tool --test`: RSA-PKCS, SHA1/SHA256/RIPEMD160/MD5). The signing key
needs a context-specific PIN and OpenSC's `pinentry` fails on the headless
board. T7 fails with GnuTLS 3.8.9 (empty Certificate) and with OpenSSL 3.5 +
pkcs11-provider 1.2.0 (invalid key handle); T8 fails headless on the same
`pinentry` prompt. A VNC session is required to close T7/T8 on the board; see
`docs/02-aarch64.md` §6. *(Diagnosis superseded on 2026-10-28: the blocker was
OpenSC's DNIe user-consent prompt, not a PIN; see the update below.)*

**Update 2026-10-28:** documentation reconciled with the results above
(`REPORT.md`, `docs/00`, `docs/04`, `docs/05`, `docs/06`). T7 is closed with
GnuTLS, Chromium (TLS 1.2) and Firefox. T8/T9 were still open at that point and
were closed later the same day on the ARM64 board (next update).

**Update 2026-10-28 (Firefox):** the empty-certificate failure was re-tested
under Xvfb with Firefox 158.0.1 and OpenSC 0.27.1. Firefox completes client
authentication with OpenSC and with the shim, automatic and chooser, fresh and
real profile, TLS 1.2 with and without `-client_sigalgs`, and against AEAT. The
empty list is reproducible when the server does not advertise the DNIe issuer
in its acceptable CA list. See `docs/10-headless-browser.md` §5.2.

**Update 2026-10-28 (T8/T9 on the ARM64 board):** T9 signs with the signing key
(`SHA256-RSA-PKCS`, signature verified) and T8 signs PAdES with Autofirma
through the shim; `pdfsig` reports *Signature is Valid*. The blocker was not a
PIN but OpenSC's DNIe user-consent prompt (`dnie_ask_user_consent`), which
returns `Not allowed` without a console. Use a dedicated `OPENSC_CONF` with
`user_consent_enabled = false` for automated signing. `-store dni`
(jmulticard) still needs a console; use `-store pkcs11:…`. See
`docs/02-aarch64.md` §6.1.

**Update 2026-10-28 (riscv64 board):** with the reader and card on the
VisionFive 2, T9 signs with the signing key (signature verified), T8 signs
PAdES with Autofirma (`openssl cms` verifies it), and T7 completes TLS client
authentication with GnuTLS against AEAT. Clear the OpenSC cache after the
renewal (`pkcs15-tool --clear-cache`); the board was listing the 2022 IDs. See
`docs/05-riscv64.md` §7.

This is the handover document. The stack is installed and validated up to T6 on
both boards; T7–T9 are closed on x86-64, aarch64 and riscv64.

---

## 1. Where we are

| Item | Value |
|---|---|
| Repository | https://github.com/ZiTAL/dni-e |
| Release | https://github.com/ZiTAL/dni-e/releases/tag/v0.2.2 |
| ARM64 board | Orange Pi 5, Debian 13, full stack + reader + Autofirma |
| RISC-V board | VisionFive 2, Debian 13, full stack + Autofirma |
| Reader | Alcor Micro AU9540 (CCID), currently on the ARM64 board |
| Card | DNIe 4.0, ATR `3B 7F 96 … 04 21 03 90 00` |
| Certificates | renewed 2026-10-26, valid until 2028-10-26 |

Validated without PIN: T1–T6 on both boards, plus 21 shim tests on x86-64,
aarch64 and riscv64. See `REPORT.md` and `docs/`.

## 2. Test status and blockers

| Test | State |
|---|---|
| T7 — TLS authentication on a site | ✅ GnuTLS/PKCS#11, Chromium and Firefox on TLS 1.2, including GnuTLS on riscv64. Firefox needs the server to advertise the DNIe issuer in its CA list |
| T8 — PDF signing with Autofirma | ✅ x86-64 (2026-10-26), ARM64 and riscv64 (2026-10-28, `-store pkcs11:…`, signature verified) |
| T9 — `C_Sign` through PKCS#11 | ✅ x86-64 (via T8), ARM64 and riscv64 authentication and signing keys (2026-10-28) |

The PIN is **not** changed by renewal. It is the one in the DNIe letter.
**Three wrong attempts block the card.**

## 3. After the renewal, step by step

### Step 1 — verify the new dates

With the card inserted:

```bash
cd ~/dni-e
./scripts/verify-card.sh
```

Then check the dates directly:

```bash
for id in $(pkcs15-tool --list-certificates | awk '/^X.509/{f=1} f&&/ID *:/{print $3; f=0}'); do
  pkcs15-tool --read-certificate "$id" | openssl x509 -noout -enddate
done
```

Expected after renewal: the two personal certificates show
`Oct 26 14:51:34 2028 GMT` instead of `Oct 18 06:37:49 2024 GMT`. This was
confirmed on 2026-10-26.

### Step 2 — Firefox profile

The ARM64 board had no Firefox profile before. If Firefox has never been
opened there, create a profile with the module already loaded:

```bash
cd ~/dni-e
./scripts/make-firefox-profile.sh /tmp/ff-dnie /usr/lib/libpkcs11-dnie.so
```

For a normal GUI profile, open Firefox once, close it, and run:

```bash
./scripts/setup-browser.sh /usr/lib/libpkcs11-dnie.so
```

### Step 3 — T7, browser authentication

Option A, with a graphical session (or Xvfb + VNC, see
`docs/10-headless-browser.md`):

1. Open a site that requests a certificate (Cl@ve, AEAT, Seguridad Social).
2. Choose the DNIe certificate.
3. Enter the PIN.

If Firefox sends an empty certificate and does not ask for the PIN, check that
the site's acceptable CA list contains `AC DNIE 004`; NSS filters the DNIe
certificate out otherwise (`docs/10-headless-browser.md` §5.2). TLS 1.3 also
fails because the key does not support RSA-PSS; force TLS 1.2 if needed.

Option B, fully headless, with OpenSSL and PKCS#11:

```bash
export DNIE_PIN='...'
openssl s_client -connect sede.example.gob.es:443 \
  -provider pkcs11 -provider default \
  -cert 'pkcs11:token=DNI%20electrónico;object=CertAutenticacion;type=cert' \
  -key  'pkcs11:token=DNI%20electrónico;object=CertAutenticacion;type=private' \
  -passin env:DNIE_PIN
unset DNIE_PIN
```

### Step 4 — T8, signing with Autofirma

Graphical: launch `autofirma-dnie`, choose **Firmar**, select a PDF, choose
`CertFirmaDigital`, enter the PIN.

Headless:

```bash
OPENSC_CONF=/tmp/dnie-headless.conf \
autofirma-dnie sign -i input.pdf -o signed.pdf -format pades -algorithm sha256 \
  -store 'pkcs11:/usr/lib/libpkcs11-dnie.so' \
  -alias CertFirmaDigital -password "$PIN"
```

The config file disables the DNIe user-consent popup for automated signing:

```ini
app default {
	card_driver dnie {
		user_consent_enabled = false;
	}
}
```

Use `autofirma-dnie listaliases -store pkcs11:/usr/lib/libpkcs11-dnie.so` to
see the aliases. `-store dni` (jmulticard) needs a console for the PIN and
fails headless.

### Step 5 — T9, PKCS#11 signing (optional)

```bash
pkcs11-tool --module /usr/lib/libpkcs11-dnie.so --login --pin "$PIN" --test
```

For the signing key (which triggers the user-consent check), use a dedicated
config and sign explicit data:

```bash
OPENSC_CONF=/tmp/dnie-headless.conf pkcs11-tool \
  --module /usr/lib/libpkcs11-dnie.so --sign --login \
  --id 4630… --mechanism SHA256-RSA-PKCS -i data -o data.sig
```

Do not use this to guess the PIN.

### Step 6 — record the result

Update `REPORT.md` and `docs/06-dnie4.md` with the new dates and the outcome of
T7–T9. If signing fails only for DNIe 4.0, open phase F6: APDU trace, compare
with `jmulticard`, patch `card.c` in OpenSC upstream.

## 4. Quick reference

```bash
# stack and card
cd ~/dni-e
./scripts/verify-stack.sh
./scripts/verify-card.sh
./tests/test-shim-paths.sh
./tests/test-nss.sh
./tests/test-browser-tls.sh

# headless Firefox profile
./scripts/make-firefox-profile.sh /tmp/ff-dnie /usr/lib/libpkcs11-dnie.so

# browser module setup for existing profiles
./scripts/setup-browser.sh /usr/lib/libpkcs11-dnie.so

# reinstall / repair
sudo ./install.sh --system
sudo ./install.sh --system --autofirma-jar /path/to/autofirma.jar

# Debian package
sudo dpkg -i dnie-pkcs11-compat_0.2.2_arm64.deb
```

## 5. Known issues and risks

| Issue | Action |
|---|---|
| Reader re-enumerates (`LIBUSB_ERROR_IO`) | Reset the USB port and restart `pcscd` (see `docs/02-aarch64.md`) |
| Old certificate IDs after renewal | `pkcs15-tool --clear-cache` (OpenSC does not invalidate its cache) |
| `pdfsig` 26.08 says "Signature is Invalid" | False negative; verify with `openssl cms` (`docs/04-autofirma.md` §4.1) |
| Firefox profile has no module | Run `make-firefox-profile.sh` or `setup-browser.sh` after the first launch |
| Headless browser asks for the PIN | Not scriptable with a supported API; use `openssl s_client` with PKCS#11, or Xvfb + VNC/XTEST |
| Autofirma shows no certificates | Autofirma not restarted, or the reader is unresponsive |
| `C_Sign` fails with `CKR_FUNCTION_FAILED` headless | OpenSC asks for user consent before signing; use `user_consent_enabled = false` in a dedicated config (`docs/02-aarch64.md` §6.1) |
| OpenSC cannot sign with DNIe 4.0 | Phase F6: APDU trace + `jmulticard` reference + patch |
| riscv64 browser automation | No usable Chromium; Firefox headless works, TLS test via OpenSSL |

## 6. Release and signature

`v0.2.2` assets: tarballs for aarch64, riscv64, x86-64, armv7l, ppc64le and
s390x; Debian packages for amd64 and arm64 (the riscv64 `.deb` was not
published — use the tarball or build it from it); `SHA256SUMS`, its signature
and the public key.

```bash
gpg --import dnie-release-key.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

Signing key fingerprint: `90E9197F3D36A666A8AF35FB99B38DA239882575`.

The private key was generated without a passphrase and lives in the local
`~/.gnupg`. For CI signing, export it into the `GPG_PRIVATE_KEY` and
`GPG_KEY_ID` GitHub secrets, then remove or protect the local copy.

## 7. Where everything lives

| Content | Location |
|---|---|
| Source | `~/dni-e` on both boards and `/home/projects/dni-e` on the workstation |
| Main docs | `README.md`, `INSTALL.md`, `PLAN.md`, `REPORT.md`, `docs/00`–`10` |
| Installer | `install.sh` (`--binary` for release tarballs) |
| Debian packaging | `packaging/debian/` |
| Arch packaging | `packaging/arch/` |
| Release builder | `scripts/build-release.sh` |
| Signature | `scripts/sign-release.sh` |
| Multiarch results | `docs/09-multiarch-validation.md` |
| Headless browser | `docs/10-headless-browser.md` |

## 8. Checklist

- [x] Renew the DNIe certificates in person (done 2026-10-26).
- [x] Insert the card and confirm the new `notAfter` dates (valid until 2028-10-26).
- [x] Run `verify-card.sh` and `test-nss.sh` on the ARM64 board (2026-10-27).
- [x] Create/refresh the Firefox profile (`~/.mozilla/dnie-profile`, 2026-10-27).
- [x] T10: clean package install on the ARM64 board (`0.2.1`, 2026-10-27).
- [x] T7: TLS client auth validated with GnuTLS/PKCS#11 (2026-10-26).
- [x] T7 (Firefox): client auth validated on x86-64 under Xvfb (automatic and
  chooser, OpenSC and shim, AEAT TLS 1.2); see `docs/10-headless-browser.md`
  §5.2. The 2026-10-27 empty list is reproducible only when the server's CA
  list lacks `AC DNIE 004`.
- [x] T7 (Chromium): client auth with the DNIe completed on TLS 1.2 + `RSA+SHA256` (2026-10-27); TLS 1.3 fails because it requires RSA-PSS. See `docs/10-headless-browser.md` §5.3.
- [x] T8: PAdES signed on x86-64 (2026-10-26), ARM64 and riscv64
  (2026-10-28, `-store pkcs11:…`; `openssl cms` verifies it).
- [x] T9: `C_Sign` validated on x86-64 (via T8), and on ARM64 and riscv64 with
  the authentication and signing keys (2026-10-28, signatures verified).
- [x] Update `REPORT.md` and `docs/06-dnie4.md` (2026-10-28).
