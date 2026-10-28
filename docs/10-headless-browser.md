# 10 — Headless browsers and the DNIe PIN

**Date:** 2026-10-25, updated 2026-10-28
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
| T7 with the **DNIe** | ⚠️ the hardware-token PIN is a native dialog: needs Xvfb + VNC, or XTEST injection against a virtual display |

Firefox, Chromium, Playwright and Selenium all reach the same wall: the PKCS#11
token PIN is requested by NSS through a native dialog. There is no supported API
to type it from an automation script; on a virtual display it can be injected
with `xdotool` (XTEST), as done for the Firefox validation in §5.2.

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

### 5.2 Firefox: validated, and why an empty certificate can appear

On 2026-10-27 a graphical session (Firefox 158, real card, correct PIN) showed
the DNIe certificate in the chooser and then sent an **empty** certificate
list. On 2026-10-28 the same machine and card were tested again, and Firefox
completed client authentication in every configuration tried:

| Configuration | Result |
|---|---|
| OpenSC direct, `security.default_personal_cert = Select Automatically` | ✅ |
| OpenSC direct, chooser (`Ask Every Time`) with a software certificate present | ✅ |
| Shim `libpkcs11-dnie.so` → OpenSC, automatic and chooser | ✅ |
| Copy of the user's real profile (`AutoFirma ROOT` + OpenSC) | ✅ |
| Server with `-client_sigalgs RSA+SHA256` and with the default TLS 1.2 list | ✅ |
| Real site: `https://www1.agenciatributaria.gob.es/` (TLS 1.2) | ✅ TLS client auth; the site returns its own 403 identity page |

In the successful runs the server receives the client `Certificate`
(0e1c bytes), `ClientKeyExchange` and `CertificateVerify`, and OpenSC logs
`C_Login` and `C_Sign = CKR_OK`. The AEAT 403 is an application-level
"identification error" page: the TLS handshake and the client certificate were
accepted.

**Reproducible cause of an empty list: the server's acceptable CA list.**
NSS filters the client certificate before asking for the PIN when the
`CertificateRequest` does not advertise the DNIe issuer. With a server that
uses only a test CA:

```bash
openssl s_server -accept 8444 -cert srv.crt -key srv.key \
  -Verify 1 -CAfile test-ca.pem -tls1_2 -www        # no AC DNIE 004
```

Firefox sends an empty `Certificate` (`peer did not return a certificate`) and
never opens the PIN dialog. With `-CAfile` containing the DNIe intermediate
(`CertCAIntermediaDGP`, CN=AC DNIE 004) the handshake completes.

The exact 2026-10-27 failure (chooser, then PIN, then empty list) could not be
reproduced. The CA file used by that test server is the main suspect: a CA list
without AC DNIE 004 produces the same server message. To check a server, run
`openssl s_server` with the DNIe intermediate in `-CAfile`, or compare with
Chromium against the same endpoint.

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

Firefox, against a TLS 1.2 server whose acceptable CA list contains
`AC DNIE 004`, also completes the handshake; see §5.2. Chromium remains the
easier browser to automate.

The `--ssl-version-max=tls1.2` flag was verified locally: with it Chromium
negotiates TLS 1.2 (server log shows `write key exchange` / `write server
done`); without it the same browser negotiates TLS 1.3 (`TLSv1.3 write
encrypted extensions`).

The AEAT endpoint `www1.agenciatributaria.gob.es:443` requests a client
certificate and lists `AC DNIE 004`, `AC DNIE 005` and `AC DNIE 006` among its
acceptable CAs. Chromium shows the DNIe authentication certificate for that
site. Completing the PIN dialog in an automated session is timing-sensitive
(the modal closes when the connection times out), so the final page must be
confirmed in a manual run.

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

- Certificates were renewed on 2026-10-26 (valid until 2028-10-26). T7 is
  closed with GnuTLS, Chromium (TLS 1.2) and Firefox; T8/T9 are closed on
  x86-64. The signing PIN prompt on the boards is still open.
- A server that does not advertise the DNIe issuer in its acceptable CA list
  makes Firefox send an empty certificate without asking for the PIN.
- Playwright's bundled Firefox is not available for every architecture; the
  tests use the system Chromium through `executablePath`.
- On riscv64 there is no usable Chromium package in Debian trixie; Firefox
  headless works, but client-certificate automation is limited to the
  `openssl s_client` path.
