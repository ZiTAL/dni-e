# 02 — aarch64 (Orange Pi 5)

**Host:** ARM64 board · Orange Pi 5 · Debian 13 (trixie) · kernel 6.1.115
**Date:** 2026-10-24
**Status:** ✅ stack and reader validated (T1–T6); signing pending certificate renewal

---

## 1. Installed

| Package | Version |
|---|---|
| `pcscd` | 2.3.3-1 |
| `libccid` | 1.6.2-1 |
| `pcsc-tools` | 1.7.3-1 |
| `opensc` | 0.26.1-2 |
| `opensc-pkcs11` | 0.26.1-2 |
| `p11-kit` | 0.25.5-3 |
| `openjdk-21-jre` | 21.0.12.1 |
| `libnss3-tools`, `xvfb`, `xauth` | (for Autofirma and tests) |

Service: `pcscd.socket` and `pcscd.service` **active**.

OpenSC module on Debian: `/usr/lib/aarch64-linux-gnu/opensc-pkcs11.so`.

## 2. Deployed shim

```
/usr/lib/libpkcs11-dnie.so                    ELF aarch64, SONAME libpkcs11-dnie.so
/usr/share/p11-kit/modules/dnie-compat.module
```

## 3. polkit: required on headless / SSH access

pcscd authorizes clients through polkit. On a headless machine or over SSH
there is no active local session, so the default policy denies
`org.debian.pcsc-lite.access_pcsc` and the reader appears "missing" even though
`lsusb` shows it:

```
IsClientAuthorized() Process ... is NOT authorized for action: access_pcsc
Rejected unauthorized PC/SC client
```

Fix installed at `/etc/polkit-1/rules.d/50-pcscd.rules` (template:
`packaging/polkit/50-pcscd.rules`), allowing the `plugdev` group. The user must
also belong to `plugdev`; `scripts/setup-debian.sh` adds `$SUDO_USER` to the
group when needed.

```javascript
polkit.addRule(function(action, subject) {
    if ((action.id == "org.debian.pcsc-lite.access_pcsc" ||
         action.id == "org.debian.pcsc-lite.access_card") &&
        subject.isInGroup("plugdev")) {
        return polkit.Result.YES;
    }
});
```

Then `systemctl restart polkit`. `scripts/setup-debian.sh` installs the rule and
the group membership automatically.

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
| T5 — `pkcs11-tool -L/-O` through the shim | ✅ token `DNI electrónico`, 3 certs and public keys |
| T6 — NSS (Firefox layer) lists the certificates | ✅ 3 certs through the shim (`tests/test-nss.sh`) |

### USB re-enumeration (`LIBUSB_ERROR_IO`)

If `lsusb` shows the reader but `pcscd` logs:

```
ReadUSB() read failed: LIBUSB_ERROR_IO
Open Port ... Failed
Alcor Micro AU9540 init failed
```

the USB device is in a bad state (flaky port, cable or power). Reset the port:

```bash
ls /sys/bus/usb/devices            # find the reader, for example 6-1
echo -n 6-1 | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo -n 6-1 | sudo tee /sys/bus/usb/drivers/usb/bind
sudo systemctl restart pcscd.socket
systemctl is-active pcscd.socket
pcsc_scan
```

If it keeps happening, use a different USB port (prefer USB 3.0), avoid hubs
and try a shorter cable. The AU9540 is a full-speed device and works on USB
3.0 ports.

## 5. Autofirma

The AUR package (contents `any`) was installed with the launcher adapted to
Java 21:

```
/usr/bin/autofirma                              (launcher, _java_version="21")
/usr/share/java/autofirma/autofirma.jar         46 MB
```

| Test | Result |
|---|---|
| GUI start under Xvfb | ✅ stays alive (timeout 124) |
| XAdES signing with a test PKCS#12 | ✅ 5,108 bytes, `SignatureValue` present |
| PAdES signing of a PDF | ✅ 55,364 bytes, `ByteRange` present |
| PKCS#11 store signing (SoftHSM) | ✅ 5,114 bytes, `SignatureValue` present |

Autofirma shows the real DNIe certificates once they are valid and the card responds.

## 6. Missing

None for T1–T6. The certificates were renewed on 2026-10-26; T7–T9 are pending
the PIN tests.

## 7. Reproduce

```bash
sudo ./scripts/setup-debian.sh
./scripts/verify-stack.sh
./scripts/verify-card.sh
```
