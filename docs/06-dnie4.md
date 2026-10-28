# 06 — DNIe 4.0 coverage in OpenSC

**Date:** 2026-10-24, updated 2026-10-28
**Phase:** F6
**Status:** 🟢 the contact interface is covered: PIN login, `C_Sign` and TLS
client authentication work with the renewed 4.0 card (valid until 2028-10-26)
in GnuTLS, Chromium and Firefox, and Autofirma signs PAdES on x86-64, aarch64
and riscv64.

---

## 1. Starting point

Test card:

```
ATR: 3B 7F 96 00 00 00 6A 44 4E 49 65 10 01 01 55 04 21 03 90 00
```

Index 15 = `0x04` → generation 4.0.
`opensc-tool -n` returns `dnie` and `pkcs15-tool` lists the 3 certificates.

## 2. ATR table analysis

`src/libopensc/card-dnie.c`:

```c
{ "3B:7F:00:00:00:00:6A:44:4E:49:65:00:00:00:00:00:00:03:90:00",
  "FF:FF:00:FF:FF:FF:FF:FF:FF:FF:FF:00:00:00:00:00:00:FF:FF:FF",
  ... }
```

The mask uses `00` at positions 11–16, which is where the DNIe encodes the
version. That is why the same driver accepts 3.0 and 4.0 unchanged.

In addition:

```c
if (card->atr.value[15] >= DNIE_30_VERSION) { ... }
```

`value[15]` is `0x04` on the test card, so it takes the modern behaviour branch.

## 3. Implemented operations

| Function | Purpose |
|---|---|
| `dnie_sm_get_wrapped_apdu` / `dnie_sm_free_wrapped_apdu` | CWA 14890 secure channel |
| `dnie_set_security_env` | Key and algorithm selection |
| `dnie_compute_signature` | Signing |
| `dnie_decipher` | Decryption |
| `dnie_pin_verify` / `dnie_pin_change` | PIN |
| `dnie_select_file` / `dnie_read_binary` | PKCS#15 file system |
| `dnie_get_challenge`, `dnie_get_info`, `dnie_get_serialnr` | Support |

The secure channel, signing and PIN handling are exactly the operations the real
DNIe flow needs. There is no indication that 4.0 requires different APDUs over
the contact interface.

## 4. Comparison with jmulticard

`jmulticard` (LGPL/EUPL) implements:

- `Dnie3`, `Dnie3r1`, `Dnie3r2`, `ceressc`
- CWA 14890 (`DnieCwa14890Constants`)
- PACE/NFC (`BcPaceChannelHelper`, `PaceChat`)
- APDUs: `Verify`, `SignData`, `ChangePin`, `RetriesLeft`, `GetChipInfo`,
  `ReadBinary`, `ReadRecord`, `MseSet*`, `GeneralAuthenticate`

It serves as an executable reference if OpenSC fails on any operation.

## 5. Conclusion

- **Contact interface:** covered. Login, signing and TLS client authentication
  work with the 4.0 card and OpenSC 0.26.1; no driver patch was needed.
- **NFC/PACE:** out of scope for this project (requires a contactless reader and
  is not needed for desktop authentication or signing).
- **TLS algorithms:** the key only provides `CKM_RSA_PKCS`. TLS 1.2 with
  `RSA+SHA256` works; TLS 1.3 requires RSA-PSS and fails with
  `ERR_SSL_CLIENT_AUTH_NO_COMMON_ALGORITHMS`.
- **Firefox:** works with the DNIe when the server advertises the DNIe issuer
  in its acceptable CA list. If the list does not include `AC DNIE 004`, NSS
  filters the certificate out and sends an empty Certificate message without
  asking for the PIN.

### 5.1 PIN metadata caveat

OpenSC reports PIN1 as `stored_len: 8` and `Type: ascii-numeric`, but on the
test card the valid PIN is **alphanumeric and longer than 8 characters**. Do not
reject a PIN because it does not fit that metadata: the authoritative value is
the one in the DNIe letter. `scripts/check-pin.sh` reads it from the terminal
and verifies it against the card.

### 5.2 TLS client authentication with the 4.0 card

| Client | Result |
|---|---|
| GnuTLS 3.8.9 + PKCS#11 (`scripts/test-tls-auth.sh`) | ✅ sends both certificates, handshake completes (x86-64, 2026-10-26) |
| Chromium 155 + OpenSC, TLS 1.2 + `RSA+SHA256` | ✅ handshake completes, server verifies to `AC DNIE 004` (x86-64, 2026-10-27) |
| Chromium 155 + OpenSC, TLS 1.3 | ❌ `ERR_SSL_CLIENT_AUTH_NO_COMMON_ALGORITHMS` (needs RSA-PSS) |
| Firefox 158 + OpenSC, TLS 1.2, server advertises `AC DNIE 004` | ✅ automatic selection and chooser (x86-64, 2026-10-28) |
| Firefox against a server whose CA list lacks the DNIe issuer | ❌ empty Certificate, no PIN prompt |

The signing key works on the ARM64 board too (SHA256-RSA-PKCS, verified
signature) and Autofirma signs PAdES with it. The apparent "PIN prompt" was
OpenSC's DNIe **user-consent** dialog (`dnie_ask_user_consent`, pinentry
`CONFIRM`): headless it returns `Not allowed`, which surfaces as
`CKR_FUNCTION_FAILED`. A dedicated OpenSC config with
`user_consent_enabled = false` (for automated signing only) removes it; the
card PIN is still required. See `docs/02-aarch64.md` §6.1.
See `docs/10-headless-browser.md` §5.2–5.3 and `docs/02-aarch64.md` §6.

## 6. Criteria to close F6

| Test | Status |
|---|---|
| `opensc-tool -n` = dnie | ✅ |
| Certificate listing | ✅ |
| PIN login | ✅ (2026-10-26) |
| PKCS#11 signing (`C_Sign`), authentication key | ✅ ARM64 board, RSA-PKCS + SHA1/SHA256/RIPEMD160/MD5 (2026-10-27) |
| PKCS#11 signing (`C_Sign`), signing key | ✅ ARM64 board with a consent-free OpenSC config (2026-10-28); x86-64 via Autofirma |
| Autofirma with the same PIN | ✅ x86-64 and ARM64 (PAdES, 2026-10-28) |
| TLS client authentication | ✅ GnuTLS, Chromium and Firefox on TLS 1.2 |

F6 is closed for the contact interface. If an operation regresses, the order of
action is: APDU trace → compare with `jmulticard` → patch `card-dnie.c` →
upstream. The outstanding browser item is tracked separately as an NSS issue.
