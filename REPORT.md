# Autonomous session report

**Date:** 2026-10-24
**Scope:** deploy and validate the DNIe stack on an ARM64 host (Orange Pi 5) and a RISC-V host (VisionFive 2).
**Outcome:** both machines have the full stack installed and validated; only a physical reader and renewed certificates are missing.

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
| USB reader | ❌ not connected | ❌ not connected |

**No PIN attempt has been spent.** Everything was tested without a card or with
laboratory stores (PKCS#12 and SoftHSM).

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
| 13 configurable-path tests | ✅ | ✅ |

The PKCS#11 test is the important one: it is exactly the path the DNIe will use
(Autofirma → PKCS#11 module → card). It was done with SoftHSM because there is
no reader yet; replacing SoftHSM with `libpkcs11-dnie.so` keeps the same flow.

---

## 3. Configurable module paths

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

## 5. What you need to do

### 5.1 USB reader (both)

**Neither machine has a reader connected.** The ARM64 host only sees a serial
adapter and the RISC-V host only a VIA Labs hub. Connect a CCID reader to each
(the AU9540 from the desktop works; any CCID reader around €10 also works).

### 5.2 Certificates

They expired on **2024-10-18**. Without renewal, real authentication and signing
cannot be tested. Renewal is in person.

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
- Documentation: `docs/00` to `docs/06`.
- Arch shim package: `packaging/arch/`.
- Debian setup: `scripts/setup-debian.sh`.
- Tests: `tests/test-shim-paths.sh`, `scripts/verify-*.sh`.
