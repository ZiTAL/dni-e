# 08 — Universal installation

**Goal:** install the DNIe stack on any Linux machine, on any architecture where
OpenSC and (optionally) Java are available, without prebuilt per-architecture
binaries.

---

## 1. Quick start

### From a release tarball (no compiler)

Download the asset for `uname -m` from the
[releases page](https://github.com/ZiTAL/dni-e/releases), then:

```bash
sha256sum -c SHA256SUMS --ignore-missing
tar xzf dnie-pkcs11-compat-0.1.0-aarch64.tar.gz
cd dnie-pkcs11-compat-0.1.0-aarch64
sudo ./install.sh --binary --system
```

### From source

```bash
git clone https://github.com/ZiTAL/dni-e.git
cd dni-e

# User prefix (no root for the shim; system steps are skipped with a warning)
./install.sh --prefix "$HOME/.local"

# System-wide (recommended)
sudo ./install.sh --system
```

### Debian/Ubuntu package

On Debian and derivatives, the release also provides a `.deb`:

```bash
sudo apt-get install -y opensc p11-kit pcscd
sudo dpkg -i dnie-pkcs11-compat_0.2.0_arm64.deb
sudo apt-get -f install
```

### Verify signatures

```bash
sha256sum -c SHA256SUMS --ignore-missing
gpg --import dnie-release-key.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
```

Fingerprint: `90E9197F3D36A666A8AF35FB99B38DA239882575`.

Then:

```bash
./scripts/verify-stack.sh
./scripts/verify-card.sh     # with the DNIe inserted, chip facing the contacts
```

## 2. Options

| Option | Effect |
|---|---|
| `--system` | Install into `/usr`, install packages and manage the service |
| `--prefix DIR` | Install prefix (default `/usr/local`) |
| `--binary` | Use the prebuilt module in `prebuilt/` (release tarballs) |
| `--no-deps` | Do not install distribution packages |
| `--no-browser` | Do not touch Firefox/Chrome NSS databases |
| `--autofirma-jar FILE` | Install Autofirma from an existing jar |
| `--dry-run` | Show what would be done |
| `--uninstall` | Remove the files installed by this script |
| `-h, --help` | Usage |

## 3. What the installer does

1. Detects the package manager (`apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`,
   `xbps-install`, `emerge`) and installs `pcsc-lite`, `ccid`, `opensc`,
   `p11-kit`, NSS tools, a C compiler and `make` when missing.
2. Builds the shim for the current architecture.
3. Installs:
   - `<prefix>/lib/libpkcs11-dnie.so`
   - `<prefix>/lib/libpkcs11-fnmtdnie.so` (alias for FNMT guides)
   - `<prefix>/share/p11-kit/modules/dnie-compat.module`
   - documentation example
4. Enables `pcscd` (systemd, OpenRC or a warning for other init systems).
5. Installs the polkit rule for headless/SSH access and adds the invoking user
   to `plugdev` when those exist.
6. Optionally adds the module to every Firefox profile and to
   `~/.pki/nssdb` (Chrome/Chromium), with backups.
7. Optionally installs Autofirma (jar + launcher + desktop entry).

## 4. Supported distributions

| Family | Package manager | OpenSC location |
|---|---|---|
| Debian, Ubuntu, Mint, Raspbian | `apt` | `/usr/lib/<tripleta>/opensc-pkcs11.so` |
| Fedora, RHEL, CentOS | `dnf` / `yum` | `/usr/lib64/opensc-pkcs11.so` |
| Arch, Manjaro, ALARM, Arch RISC-V | `pacman` | `/usr/lib/opensc-pkcs11.so` |
| openSUSE | `zypper` | `/usr/lib64/opensc-pkcs11.so` |
| Alpine | `apk` (musl) | `/usr/lib/opensc-pkcs11.so` |
| Void Linux | `xbps-install` | `/usr/lib/opensc-pkcs11.so` |
| Gentoo | `emerge` | `/usr/lib/opensc-pkcs11.so` |
| NixOS | — | `/run/current-system/sw/lib/…` or `MODULE_PATH` |
| Guix | — | `guix.scm` / `MODULE_PATH` |

## 5. Architectures

The shim is portable C and has been built for:

| Architecture | Status |
|---|---|
| x86-64 | ✅ native |
| i386 | ✅ native `gcc -m32`; ⏳ no release asset |
| aarch64 | ✅ native (Orange Pi 5) + musl/Alpine |
| riscv64 | ✅ native (VisionFive 2) + musl/Alpine under QEMU |
| armv7l | ✅ cross-built (release asset) |
| ppc64le | ✅ cross-built (release asset) |
| s390x | ✅ cross-built + musl/Alpine under QEMU (big-endian) |

The real dependency is **OpenSC** for the target architecture. Debian trixie
packages it for amd64, arm64, armel, armhf, i386, ppc64el, riscv64 and s390x.
See [09-multiarch-validation.md](09-multiarch-validation.md).

## 6. Autofirma

Autofirma is an architecture-independent Java application. There is no reliable
universal download URL, so the installer does not fetch it. Provide a jar:

```bash
sudo ./install.sh --system --autofirma-jar /path/to/autofirma.jar
```

It installs:

- `<prefix>/share/java/autofirma/autofirma.jar`
- `<prefix>/bin/autofirma-dnie` (launcher)
- `<prefix>/share/applications/autofirma-dnie.desktop`

The launcher finds any **Java >= 17** (`JAVA_HOME`, `/usr/lib/jvm/*`, `PATH`),
so it works with Java 17, 21, 26… independent of the distribution.

Requirement: a JRE 17+ for the architecture. Where the distribution does not
provide one (for example Debian 13, which ships Java 21), any recent JRE works.

## 7. Browsers

`scripts/setup-browser.sh` is called by the installer and can also be run alone:

```bash
./scripts/setup-browser.sh /usr/local/lib/libpkcs11-dnie.so
./scripts/setup-browser.sh /usr/local/lib/libpkcs11-dnie.so --remove
```

It configures every Firefox profile found in `~/.mozilla/firefox` and
`~/.config/mozilla/firefox`, plus `~/.pki/nssdb` for Chrome/Chromium. Each
database is backed up as `<db>.dnie-backup.<timestamp>`.

Browsers must be restarted afterwards.

## 8. Uninstall

```bash
sudo ./install.sh --system --uninstall
```

It removes the shim, the alias, the p11-kit registration, the Autofirma files
it installed and the polkit rule (only if it matches the shipped one). It does
**not** remove distribution packages.

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `lsusb` shows the reader but PC/SC does not | polkit denies `access_pcsc` | Install `packaging/polkit/50-pcscd.rules`; user must be in `plugdev` |
| `opensc-tool -n` says no readers | `pcscd` not running | `systemctl enable --now pcscd.socket` (or OpenRC equivalent) |
| `LIBUSB_ERROR_IO` / reader init failed | USB device in a bad state | Reset the port: unbind/bind the device and restart `pcscd` (see docs/02) |
| `dpkg`/`rpm` conflict with the FNMT package | Both provide `libpkcs11-fnmtdnie.so` | Remove the official package or use `--prefix` |
| Browser does not list certificates | Module not loaded or browser not restarted | `./scripts/setup-browser.sh <module>` and restart |
| Autofirma says no certificates | DNIe certificates expired | Renew them in person |
| `make` cannot find `cc` | No compiler | Install `build-essential` / `base-devel` / `build-base` |

## 10. Security notes

- The installer is a script in the repository; it is **not** a `curl | sh`
  bootstrap. Read it before running it.
- Everything is built from source on the target machine; no prebuilt binaries
  are downloaded.
- The polkit rule grants PC/SC access to the `plugdev` group. Remove the file
  to restore the distribution default.
- The project is GPL-3.0-or-later and does not redistribute the official
  DGP/FNMT module.
