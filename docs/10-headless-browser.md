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

## 5.1 Verified: T7 with GnuTLS

`scripts/test-tls-auth.sh` uses GnuTLS with the DNIe authentication certificate
and private key through PKCS#11. Against a local server that requests a client
certificate:

```
Successfully sent 2 certificate(s) to server.
Handshake was completed
RESULT: TLS client authentication OK
```

The local server's chain warning is only because it lacks the root
`AC RAIZ DNIE 2`; the client authentication itself is valid.

### 5.2 Verified: Firefox GUI still sends an empty certificate list

On 2026-10-27 the flow was repeated in a graphical session (Firefox 158, the
real card and the correct PIN):

1. Firefox opens its certificate chooser and lists
   `BILBAO BARTUREN, IBAN (AUTENTICACIÓN)` from `DNI electrónico`.
2. The DNIe PIN dialog appears. The PIN was verified independently with
   `pkcs15-tool --verify-pin` and `pkcs11-tool --login`, so it is correct.
3. After the PIN is accepted, Firefox sends an **empty** certificate list; the
   server logs `peer did not return a certificate`.

Control test: software certificates imported into the same profile — one with
`extendedKeyUsage=clientAuth` and one without EKU — are sent and verified by
the same server (`depth=0 CN=test-client`, `verify return:1`). So the test
server, the CA trust and Firefox's client-auth path are sound; the failure is
specific to the OpenSC/DNIe token.

The PKCS#11 objects look consistent: the private key `KprivAutenticacion` and
the certificate `CertAutenticacion` share the same CKA_ID, the key only has
sign/signRecover usage, and no `always authenticate` flag is reported. This is
an NSS/Firefox + OpenSC interaction to investigate, not a card or PIN issue.
Use `scripts/check-pin.sh` to confirm the PIN and the private objects without
exposing the PIN.

### 5.3 Chromium works with TLS 1.2 + RSA+SHA256

Chromium 155 with OpenSC in `~/.pki/nssdb` selects the DNIe authentication
certificate and **completes** the client-authentication handshake against a
local server when the server is forced to TLS 1.2 and requests `RSA+SHA256`
(PKCS#1 v1.5):

```bash
openssl s_server -accept 8444 -cert srv.crt -key srv.key \
  -Verify 1 -CAfile client-cas.pem \
  -tls1_2 -client_sigalgs RSA+SHA256 -www
```

Server log:

```
depth=1 ... CN=AC DNIE 004
verify error:num=2:unable to get issuer certificate
issuer= ... CN=AC RAIZ DNIE 2
verify return:1
depth=0 ... CN=... (AUTENTICACIÓN)
issuer= ... CN=AC DNIE 004
verify return:1
```

The page loaded. The chain warning only means the server does not have
`AC RAIZ DNIE 2`; the client certificate itself was accepted.

On the default TLS 1.3 server, Chromium fails with
`ERR_SSL_CLIENT_AUTH_NO_COMMON_ALGORITHMS`: TLS 1.3 requires RSA-PSS for RSA
client certificates, while the DNIe/OpenSC key only provides
`CKM_RSA_PKCS`. Forcing TLS 1.2 removes that restriction.

Firefox, against the same TLS 1.2 server, still offers the certificate and PIN
dialog but sends an empty Certificate message. The remaining problem is
specific to Firefox/NSS + OpenSC; Chromium is the working browser path on
x86-64.

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
