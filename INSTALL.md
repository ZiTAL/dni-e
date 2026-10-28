# DNIe on Linux — installation (v0.2.3)

This document covers the prebuilt packages (aarch64, riscv64, x86-64) and a
source install. The goal is a working DNIe stack: reader, PKCS#11 module,
browsers and optional document signing with Autofirma.

## Requirements

- Linux (any distribution).
- A CCID USB smartcard reader and a DNIe card.
- Root or `sudo` for a system-wide install.
- For Autofirma: Java 17 or newer.

## Assets

| Architecture | Tarball | Debian package |
|---|---|---|
| ARM64 | `dnie-pkcs11-compat-0.2.3-aarch64.tar.gz` | `dnie-pkcs11-compat_0.2.3_arm64.deb` |
| RISC-V 64 | `dnie-pkcs11-compat-0.2.3-riscv64.tar.gz` | `dnie-pkcs11-compat_0.2.3_riscv64.deb` |
| x86-64 | `dnie-pkcs11-compat-0.2.3-x86_64.tar.gz` | `dnie-pkcs11-compat_0.2.3_amd64.deb` |
| ARMv7 (32-bit) | `dnie-pkcs11-compat-0.2.3-armv7l.tar.gz` | — |
| ppc64le | `dnie-pkcs11-compat-0.2.3-ppc64le.tar.gz` | — |
| s390x | `dnie-pkcs11-compat-0.2.3-s390x.tar.gz` | — |

Also attached: `SHA256SUMS`, `SHA256SUMS.asc` and `dnie-release-key.asc`.

## Verify the download

```bash
sha256sum -c SHA256SUMS --ignore-missing

# Optional: verify the checksums signature
gpg --import dnie-release-key.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
```

Key fingerprint: `90E9197F3D36A666A8AF35FB99B38DA239882575`.

## Option A — Debian/Ubuntu package

```bash
sudo apt-get update
sudo apt-get install -y opensc p11-kit pcscd
sudo dpkg -i dnie-pkcs11-compat_0.2.3_arm64.deb
sudo apt-get -f install
```

On RISC-V, use the `riscv64` `.deb` or the tarball (Option B).
The package installs
`/usr/lib/libpkcs11-dnie.so`, the `libpkcs11-fnmtdnie.so` alias and the p11-kit
registration. It does not install Autofirma.

## Option B — release tarball (no compiler)

```bash
tar xzf dnie-pkcs11-compat-0.2.3-aarch64.tar.gz
cd dnie-pkcs11-compat-0.2.3-aarch64
sudo ./install.sh --binary --system
```

The installer uses `prebuilt/libpkcs11-dnie.so`, installs OpenSC/pcsc-lite/ccid
if needed, registers p11-kit, configures polkit/plugdev and optionally the
browsers.

## Option C — from source

```bash
git clone https://github.com/ZiTAL/dni-e.git
cd dni-e
sudo ./install.sh --system
```

## User prefix (no root)

```bash
./install.sh --prefix "$HOME/.local"
```

## Autofirma (document signing)

Autofirma is Java and architecture-independent, but it is not downloaded by the
installer. Provide a jar:

```bash
sudo ./install.sh --system --autofirma-jar /path/to/autofirma.jar
```

It installs `autofirma-dnie`, a launcher that finds any Java >= 17.

## Browsers

With `--system` (or a user prefix), the installer adds the module to every
Firefox profile and to Chrome/Chromium (`~/.pki/nssdb`), keeping backups.
Restart the browsers afterwards.

Manual refresh:

```bash
./scripts/setup-browser.sh /usr/lib/libpkcs11-dnie.so
```

## Verify

```bash
./scripts/verify-stack.sh      # dependencies, module, service, reader
./scripts/verify-card.sh       # reader, ATR, OpenSC and certificates (no PIN)
./tests/test-shim-paths.sh     # 21 module-resolution/security tests
./tests/test-nss.sh            # Firefox/NSS sees the certificates
```

Expected card output:

```
Card state: Card inserted
ATR: 3B 7F 96 ...
OpenSC recognizes: dnie
3 certificates visible
```

If the card says `Unresponsive card`, turn the DNIe around: the chip must face
the reader contact.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `lsusb` shows the reader but PC/SC does not | polkit: install `packaging/polkit/50-pcscd.rules`; user must be in `plugdev` |
| No readers | `systemctl enable --now pcscd.socket` (or OpenRC equivalent) |
| Browser shows no certificates | restart the browser; run `tests/test-nss.sh` |
| Autofirma shows no certificates | Restart Autofirma; check the card/reader |
| Package conflict with the FNMT module | both provide `libpkcs11-fnmtdnie.so`; remove one |

Full guide: `docs/08-universal-install.md`.

## Uninstall

Debian package:

```bash
sudo dpkg -r dnie-pkcs11-compat
```

Tarball/source:

```bash
sudo ./install.sh --system --uninstall
```

Distribution packages (OpenSC, pcscd) are kept.

## License

GPL-3.0-or-later. This project is an independent implementation based on
OpenSC and is not the official DGP/FNMT module.
