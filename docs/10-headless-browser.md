# 10 — Headless browsers and the DNIe PIN

**Date:** 2026-10-25
**Goal:** use Firefox/Chromium without a graphical session and understand exactly
what can and cannot be automated with the DNIe.

---

## 1. Short answer

| Task | Headless |
|---|---|
| Firefox/Chromium starts and navigates | ✅ |
| Load the PKCS#11 module in a profile | ✅ |
| T6 — list the DNIe certificates | ✅ |
| Client-certificate flow with a **software** certificate | ✅ |
| T7 with the **DNIe** | ❌ the hardware-token PIN is a native dialog |

Firefox, Chromium, Playwright and Selenium all reach the same wall: the PKCS#11
token PIN is requested by NSS through a native dialog. There is no supported API
to type it from an automation script.

## 2. Verified results

| Host | Playwright + Chromium client cert | Firefox headless | DNIe certs in profile |
|---|---|---|---|
| x86-64 | ✅ `status=200` | ✅ | no card |
| aarch64 (Orange Pi 5) | ✅ `status=200` | ✅ screenshot | ✅ 3 certs |
| riscv64 (VisionFive 2) | ⏳ no usable Chromium | ✅ screenshot | no card (reader on ARM64) |

## 3. Headless Firefox profile with the DNIe module

```bash
./scripts/make-firefox-profile.sh /tmp/ff-dnie /usr/lib/libpkcs11-dnie.so
```

It creates an NSS database, adds the module and writes a `user.js` with
`security.default_personal_cert = Select Automatically`. It does not need a
display and does not ask for a PIN.

Launch headless:

```bash
firefox-esr --headless --no-remote --profile /tmp/ff-dnie https://example.com
```

Certificate listing (T6):

```bash
certutil -L -d sql:/tmp/ff-dnie -h all
```

## 4. Client-certificate flow with a software certificate

```bash
./tests/test-browser-tls.sh
```

It generates a local CA, a server certificate and a client certificate, starts
`openssl s_server` requiring client authentication, checks `curl`, and then
drives headless Chromium with Playwright `clientCertificates`.

This validates the browser plumbing without a smartcard. It is also the test
that runs on CI.

## 5. Real T7 with the DNIe (headless)

The PIN must be supplied at the TLS layer, not by the browser. With OpenSSL 3
and a PKCS#11 provider:

```bash
export DNIE_PIN='...'          # do not leave it in shell history
openssl s_client -connect sede.example.gob.es:443 \
  -provider pkcs11 -provider default \
  -cert 'pkcs11:token=DNI%20electrónico;object=CertAutenticacion;type=cert' \
  -key  'pkcs11:token=DNI%20electrónico;object=CertAutenticacion;type=private' \
  -passin env:DNIE_PIN
unset DNIE_PIN
```

The URI is the one printed by `pkcs11-tool -O` or `pkcs15-tool --list-certificates`.
With the legacy engine, use `-engine pkcs11 -keyform engine`.

This validates the card's real TLS client authentication. It does not exercise
Firefox's UI, but it is the only fully headless path with a hardware token.

## 6. Real T7 with Firefox and a virtual display

If the browser UI is required:

```bash
Xvfb :99 -screen 0 1280x800x24 &
DISPLAY=:99 firefox-esr --profile /tmp/ff-dnie &
x11vnc -display :99 -localhost -nopw &
```

Then open an SSH tunnel to port 5900 and type the PIN in the VNC session. This
is the faithful browser test on a headless board.

## 7. Autofirma (T8/T9) headless

Autofirma has a CLI and can use a PKCS#11 token:

```bash
autofirma-dnie sign -i input.pdf -o signed.pdf -format pades \
  -store 'pkcs11:/usr/lib/libpkcs11-dnie.so' \
  -password "$PIN"
```

The PIN on the command line is visible in `ps` and shell history. Prefer the
VNC session for interactive use, or run this from a private shell with history
disabled.

For a pure PKCS#11 check of the signing operation:

```bash
pkcs11-tool --module /usr/lib/libpkcs11-dnie.so \
  --login --pin "$PIN" --test
```

Three wrong PIN attempts block the card. Do not use these commands to guess.

## 8. Caveats

- Certificates were renewed on 2026-10-26 (valid until 2028-10-26); T7–T9
  are now pending only the PIN tests.
- Playwright's bundled Firefox is not available for every architecture; the
  tests use the system Chromium through `executablePath`.
- On riscv64 there is no usable Chromium package in Debian trixie; Firefox
  headless works, but client-certificate automation is limited to the
  `openssl s_client` path.
