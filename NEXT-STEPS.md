# Next steps after certificate renewal

**Status captured:** 2026-10-25 · release `v0.2.1`

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

This is the handover document. Everything is installed and validated up to
T6; T7–T9 only need the DNIe certificates to be renewed.

---

## 1. Where we are

| Item | Value |
|---|---|
| Repository | https://github.com/ZiTAL/dni-e |
| Release | https://github.com/ZiTAL/dni-e/releases/tag/v0.2.1 |
| ARM64 board | Orange Pi 5, Debian 13, full stack + reader + Autofirma |
| RISC-V board | VisionFive 2, Debian 13, full stack + Autofirma |
| Reader | Alcor Micro AU9540 (CCID), currently on the ARM64 board |
| Card | DNIe 4.0, ATR `3B 7F 96 … 04 21 03 90 00` |
| Certificates | renewed 2026-10-26, valid until 2028-10-26 |

Validated without PIN: T1–T6 on both boards, plus 21 shim tests on x86-64,
aarch64 and riscv64. See `REPORT.md` and `docs/`.

## 2. What is blocked

| Test | Needs |
|---|---|
| T7 — TLS authentication on a site | valid certificate + PIN |
| T8 — PDF signing with Autofirma | valid certificate + PIN |
| T9 — `C_Sign` through PKCS#11 | valid certificate + PIN |

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
autofirma-dnie sign -i input.pdf -o signed.pdf -format pades \
  -store 'pkcs11:/usr/lib/libpkcs11-dnie.so' -password "$PIN"
```

### Step 5 — T9, PKCS#11 signing (optional)

```bash
pkcs11-tool --module /usr/lib/libpkcs11-dnie.so --login --pin "$PIN" --test
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
sudo dpkg -i dnie-pkcs11-compat_0.2.1_arm64.deb
```

## 5. Known issues and risks

| Issue | Action |
|---|---|
| Reader re-enumerates (`LIBUSB_ERROR_IO`) | Reset the USB port and restart `pcscd` (see `docs/02-aarch64.md`) |
| Firefox profile has no module | Run `make-firefox-profile.sh` or `setup-browser.sh` after the first launch |
| Headless browser asks for the PIN | Not scriptable; use `openssl s_client` with PKCS#11 or Xvfb + VNC |
| Autofirma shows no certificates | Autofirma not restarted, or the reader is unresponsive |
| OpenSC cannot sign with DNIe 4.0 | Phase F6: APDU trace + `jmulticard` reference + patch |
| riscv64 browser automation | No usable Chromium; Firefox headless works, TLS test via OpenSSL |

## 6. Release and signature

`v0.2.1` assets: tarballs for aarch64, riscv64, x86-64, armv7l, ppc64le and
s390x; Debian packages for arm64 and riscv64; `SHA256SUMS`, its signature and
the public key.

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
- [ ] T7 (Firefox): GUI reproduces the empty-certificate failure (2026-10-27); needs an NSS/OpenSC fix or a browser workaround.
- [x] T8: PAdES signed on x86-64 (2026-10-26); boards pending.
- [x] T9: covered by T8 (Autofirma uses `C_Sign` through PKCS#11).
- [ ] Update `REPORT.md` and `docs/06-dnie4.md`.
