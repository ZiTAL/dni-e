# 06 — DNIe 4.0 coverage in OpenSC

**Date:** 2026-10-24
**Phase:** F6 (preliminary analysis)
**Status:** 🟡 the driver accepts the 4.0 ATR and has the required operations; real PIN validation pending

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

- **Contact interface:** full coverage is expected; the driver is ready for the
  4.0 ATR.
- **NFC/PACE:** out of scope for this project (requires a contactless reader and
  is not needed for desktop authentication or signing).
- **Residual risk:** low, but it cannot be closed without testing login and
  signing with valid certificates.

## 6. Criteria to close F6

| Test | Status |
|---|---|
| `opensc-tool -n` = dnie | ✅ |
| Certificate listing | ✅ |
| PIN login | ⏳ requires valid certificates |
| PKCS#11 signing (`C_Sign`) | ⏳ |
| Autofirma with the same PIN | ⏳ |

If any fails, the order of action is: APDU trace → compare with `jmulticard` →
patch `card-dnie.c` → upstream.
