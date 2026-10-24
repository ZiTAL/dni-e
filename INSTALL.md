# DNIe on Linux — installation

This document covers the release tarballs (`aarch64`, `riscv64`) and a source
install. The goal is a working DNIe stack: reader, PKCS#11 module, browsers and
optional document signing with Autofirma.

## Requirements

- Linux (any distribution).
- A CCID USB smartcard reader and a DNIe card.
- Root or `sudo` for a system-wide install.
- For Autofirma: Java 17 or newer.

## Option A — release tarball (no compiler needed)

Download the asset matching the machine (`uname -m`):

| Architecture | Asset |
|---|---|
| ARM64 | `dnie-pkcs11-compat-0.1.0-aarch64.tar.gz` |
| RISC-V 64 | `dnie-pkcs11-compat-0.1.0-riscv64.tar.gz` |

Verify and install:

```bash
sha256sum -c SHA256SUMS --ignore-missing
tar xzf dnie-pkcs11-compat-0.1.0-aarch64.tar.gz
cd dnie-pkcs11-compat-0.1.0-aarch64
sudo ./install.sh --binary --system
```

The installer uses the prebuilt `prebuilt/libpkcs11-dnie.so`, installs
OpenSC/pcsc-lite/ccid if needed, registers the module with p11-kit, configures
polkit/plugdev and optionally the browsers.

## Option B — from source

```bash
git clone https://github.com/ZiTAL/dni-e.git
cd dni-e
sudo ./install.sh --system
```

This compiles the shim for the current architecture.

## User prefix (no root)

```bash
./install.sh --prefix "$HOME/.local"
```

The shim and the p11-kit registration go under `$HOME/.local`. System steps
(service, polkit) are skipped with a warning.

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

To do it manually later:

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
the reader contacts.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `lsusb` shows the reader but PC/SC does not | polkit: install `packaging/polkit/50-pcscd.rules`; user must be in `plugdev` |
| No readers | `systemctl enable --now pcscd.socket` (or OpenRC equivalent) |
| Browser shows no certificates | restart the browser; check `tests/test-nss.sh` |
| Autofirma shows no certificates | DNIe certificates expired; renew them in person |
| Package conflict with the FNMT module | both provide `libpkcs11-fnmtdnie.so`; remove one |

Full guide: `docs/08-universal-install.md`.

## Uninstall

```bash
sudo ./install.sh --system --uninstall
```

Removes the shim, alias, p11-kit registration, Autofirma files and the polkit
rule installed by this project. Distribution packages are kept.

## License

GPL-3.0-or-later. This project is an independent implementation based on
OpenSC and is not the official DGP/FNMT module.
