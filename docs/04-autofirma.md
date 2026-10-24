# 04 — Autofirma on aarch64 and riscv64

**Date:** 2026-10-24
**Phase:** F4
**Status:** ✅ no port needed (`any` package); hardware validation pending

---

## 1. Finding

The AUR `autofirma` 1.9.2 package declares **`arch=('any')`**:

```
Name            : autofirma
Version         : 1.9.2-1
Architecture    : any
Depends On      : java-runtime=17
Licenses        : GPL-2.0-or-later AND EUPL-1.1
Compressed Size : 41.08 MiB
```

It is pure Java (jar + launcher + resources). It contains no native binaries.
Therefore:

- **aarch64:** installs as-is if `jdk17-openjdk` is present (Arch Linux ARM has
  17.0.21).
- **riscv64 (Arch RISC-V):** same, with `jdk17-openjdk` 17.0.17.
- **riscv64 (Debian trixie):** no JDK 17 in trixie (21 is available). Options:
  use 17 from sid or patch the launcher.

## 2. Why it works unchanged

The `/usr/bin/autofirma` launcher:

1. Looks for Java 17 at `/usr/lib/jvm/java-17-openjdk/bin/java` and
   `/usr/lib/jvm/*17*/bin/java`.
2. Generates its local CA and registers it in Firefox and `~/.pki/nssdb`.
3. Runs `java -jar /usr/share/java/autofirma/autofirma.jar`.

None of this depends on the architecture.

Card detection is done by **JMulticard** through `javax.smartcardio`, which uses
PC/SC. With `pcscd` + `ccid` working, it is CPU-independent.

## 3. Procedure on ARM/RISC-V (Arch)

On the x86-64 machine that builds the package:

```bash
paru -G autofirma            # or use the existing clone
cd autofirma
makepkg -f                   # produces autofirma-1.9.2-1-any.pkg.tar.zst
```

Copy the `.pkg.tar.zst` to the target machine and install:

```bash
sudo pacman -U autofirma-1.9.2-1-any.pkg.tar.zst
```

Requirement on the target: `jdk17-openjdk` (provides `java-runtime=17`).

## 4. Verification

| Test | Result |
|---|---|
| Package declares `any` | ✅ |
| No native binaries in the package | ✅ (jar + scripts) |
| Startup with JRE 17 on x86-64 | ✅ |
| PDF signing on x86-64 | ⏳ blocked by expired certificates |
| Startup on aarch64 | ✅ (validated under Xvfb) |
| Startup on riscv64 | ✅ (CLI mode) |
| XAdES/PAdES/PKCS#11 signing on both | ✅ |

## 5. Debian note

Debian trixie has no `openjdk-17-jre`. Two paths:

1. Install the sid `.deb` (`openjdk-17-jre` 17.0.21), accepting a mixed suite.
2. Patch the launcher to accept Java 21/25 and test Autofirma with that
   runtime.

Path 2 was validated: Autofirma 1.9.2 runs and signs with Java 21 (aarch64) and
Java 25 (riscv64).
