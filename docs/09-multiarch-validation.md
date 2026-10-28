# 09 — Multi-architecture validation

**Date:** 2026-10-25
**Goal:** verify that the shim builds and loads beyond the three primary
architectures, including musl and big-endian.

**Note (v0.2.2):** these results were obtained with the v0.2.1 shim. v0.2.2
changes only helper scripts, packaging and documentation; the shim source and
binary are unchanged.

---

## 1. Matrix

| Architecture | Build method | Build | Load / runtime | Notes |
|---|---|---|---|---|
| x86-64 | native (Manjaro) | ✅ | ✅ 21/21 tests | glibc |
| aarch64 | native (Orange Pi 5) | ✅ | ✅ T1–T6 with real card | glibc |
| aarch64 | Alpine chroot (musl) | ✅ | ✅ module loads | `C_Initialize` needs `pcscd` |
| riscv64 | native (VisionFive 2) | ✅ | ✅ T1–T6 with real card | glibc |
| riscv64 | Alpine + QEMU user | ✅ | ✅ module loads | musl, emulated |
| armv7l (32-bit) | cross `arm-linux-gnueabihf-gcc` | ✅ | ⏳ not run | tarball released |
| ppc64le | cross `powerpc64le-linux-gnu-gcc` | ✅ | ⏳ not run | tarball released |
| s390x (big-endian) | cross `s390x-linux-gnu-gcc` | ✅ | ✅ module loads under QEMU + musl | tarball released |
| i386 | native `gcc -m32` | ✅ | ⏳ not run | no release asset |

`C_Initialize` returning `CKR_GENERAL_ERROR` in the chroot/QEMU tests is expected:
`pcscd` is not running and there is no reader. The important part is that the
module is a valid ELF for the target and that `dlopen` succeeds.

## 2. Cross-build commands

On an aarch64 Debian host with the cross toolchains and target libc headers:

```bash
sudo apt-get install -y gcc-riscv64-linux-gnu gcc-arm-linux-gnueabihf \
  gcc-powerpc64le-linux-gnu gcc-s390x-linux-gnu \
  libc6-dev-riscv64-cross libc6-dev-armhf-cross \
  libc6-dev-ppc64el-cross libc6-dev-s390x-cross

ARCH=armv7l CC=arm-linux-gnueabihf-gcc VERSION=0.2.1 ./scripts/build-release.sh
ARCH=ppc64le CC=powerpc64le-linux-gnu-gcc VERSION=0.2.1 ./scripts/build-release.sh
ARCH=s390x CC=s390x-linux-gnu-gcc VERSION=0.2.1 ./scripts/build-release.sh
```

`libc6-dev-*-cross` is required: without it the cross compiler falls back to the
host headers and fails on `bits/wordsize.h`.

## 3. Alpine/musl (native aarch64)

```bash
curl -fsSL https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/aarch64/alpine-minirootfs-3.20.3-aarch64.tar.gz \
  -o /tmp/alpine.tar.gz
mkdir -p /tmp/alpine-aarch64
sudo tar -xzf /tmp/alpine.tar.gz -C /tmp/alpine-aarch64
sudo cp /etc/resolv.conf /tmp/alpine-aarch64/etc/resolv.conf
sudo cp -a src/pkcs11-shim /tmp/alpine-aarch64/src
sudo chroot /tmp/alpine-aarch64 /bin/sh -c '
  apk add --no-cache build-base opensc pcsc-lite file
  cd /src && make clean && make
  file libpkcs11-dnie.so
'
```

Result:

```
ELF 64-bit LSB shared object, ARM aarch64
/lib/ld-musl-aarch64.so.1
```

## 4. QEMU user-mode (riscv64 and s390x)

`qemu-user-static` registers binfmt handlers, so a foreign Alpine rootfs can be
entered with `chroot` directly:

```bash
sudo apt-get install -y qemu-user-static
# alpine-minirootfs-...-riscv64.tar.gz or ...-s390x.tar.gz
sudo tar -xzf /tmp/alpine-rv.tar.gz -C /tmp/alpine-riscv64
sudo cp /etc/resolv.conf /tmp/alpine-riscv64/etc/resolv.conf
sudo cp -a src/pkcs11-shim /tmp/alpine-riscv64/src
sudo chroot /tmp/alpine-riscv64 /bin/sh -c '
  apk add --no-cache build-base opensc pcsc-lite file
  cd /src && make clean && make
  file libpkcs11-dnie.so
'
```

Results:

```
riscv64: ELF 64-bit LSB shared object, UCB RISC-V, RVC, double-float ABI
s390x:   ELF 64-bit MSB shared object, IBM S/390
```

The s390x case is relevant because the shim has no endianness assumptions; the
big-endian build and load confirm it.

## 5. What is still hardware-dependent

- Real reader and card operations (T1–T6) were validated on **aarch64** and
  **riscv64** only.
- armv7, ppc64le and s390x have build-level validation; a real card test there
  needs the hardware and a CCID reader.
- Authentication and signing (T7–T9) were validated with the renewed
  certificates on x86-64, aarch64 and riscv64; they are not part of the
  cross-build or emulation matrix.

## 6. Release assets

`v0.2.1` publishes tarballs for:

- aarch64, riscv64, x86-64 (native builds);
- armv7l, ppc64le, s390x (cross builds);
- Debian packages for amd64, arm64 and riscv64;
- `SHA256SUMS` plus a detached GPG signature and the public key.

`v0.2.2` did not publish the riscv64 `.deb`. The release workflow now builds
it from the cross-compiled shim (`packaging/debian/build-prebuilt.sh`), so new
tags include it again.
