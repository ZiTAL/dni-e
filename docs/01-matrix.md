# 01 — Component matrix per architecture

**Date:** 2026-10-24
**Phase:** F1 (inventory)
**Sources:** official Arch Linux ARM, Arch RISC-V, Debian trixie and AUR
repositories, queried on the date above.

---

## 1. Summary

- **aarch64:** the whole stack is packaged in Arch Linux ARM (including JDK 17,
  Firefox and Maven). Only Autofirma is missing, which is built from AUR.
- **riscv64 (Arch RISC-V):** the whole stack is in the `archriscv` repository
  (OpenSC 0.26.1, ccid, pcsclite, p11-kit, JDK 17, Maven, Firefox 144).
  Autofirma is built locally.
- **riscv64 (Debian trixie):** everything except JDK 17 (trixie ships OpenJDK 21;
  17 is in sid). Autofirma requires a launcher patch or the sid JDK.
- **Unrecoverable component:** the official `libpkcs11-dnie`. It does not exist
  for either architecture and cannot be built.

**Conclusion:** nothing in the base system needs porting. The work is
(a) the compatibility shim, (b) Autofirma, (c) DNIe 4.0 coverage and
(d) packaging.

---

## 2. Matrix

| Component | x86-64 (Manjaro) | aarch64 (Arch ARM) | riscv64 (Arch RISC-V) | riscv64 (Debian trixie) | Strategy |
|---|---|---|---|---|---|
| `pcsclite` | 2.5.1 ✅ | 2.5.3 ✅ | 2.4.1 ✅ | 2.3.3 ✅ | Repository |
| `ccid` | 1.8.3 ✅ | 1.8.4 ✅ | 1.7.1 ✅ | 1.6.2 ✅ | Repository |
| `pcsc-tools` | 1.7.5 ✅ | 1.7.5 ✅ | 1.7.4 ✅ | 1.7.3 ✅ | Repository |
| `opensc` | 0.27.1 ✅ | 0.27.1 ✅ | 0.26.1 ✅ | 0.26.1 ✅ | Repository (or build) |
| `p11-kit` | 0.26.5 ✅ | 0.26.5 ✅ | 0.26.2 ✅ | 0.25.5 ✅ | Repository |
| JDK 17 | 17.0.20 ✅ | 17.0.21 ✅ | 17.0.17 ✅ | ❌ (21 only; 17 in sid) | Repository / sid / patch |
| Maven | 3.9.16 ✅ | 3.10.0 ✅ | 3.9.12 ✅ | 3.9.9 ✅ | Repository |
| Firefox | 158 ✅ | 158 ✅ | 144 ✅ | 153 ESR ✅ | Repository |
| Autofirma | 1.9.2 ✅ (AUR) | 🔨 build | 🔨 build | 🔨 build | AUR / source |
| jmulticard | ✅ (jar) | ✅ (jar) | ✅ (jar) | ✅ (jar) | Pure Java |
| Official `libpkcs11-dnie` | 1.7.1 (binary) | ❌ | ❌ | ❌ | **Replace with OpenSC + shim** |
| `libpkcs11-dnie-{cryptopp,asn1}` | ✅ binary | ❌ | ❌ | ❌ | Not needed |

Legend: ✅ available · 🔨 must be built · ❌ unavailable.

---

## 3. Detail per architecture

### 3.1 aarch64 — Arch Linux ARM

```
opensc 0.27.1-2      ccid 1.8.4-1        pcsclite 2.5.3-1
pcsc-tools 1.7.5-1   p11-kit 0.26.5-1    jdk17-openjdk 17.0.21
maven 3.10.0-1       firefox 158.0.1-1
```

Autofirma: the AUR package exists and its build is pure Java; the `PKGBUILD`
must be checked for x86_64 assumptions (normally none) and the launcher must
find `java-17-openjdk`.

### 3.2 riscv64 — Arch RISC-V

```
opensc 0.26.1-1      ccid 1.7.1-1        pcsclite 2.4.1-1
pcsc-tools 1.7.4-1   p11-kit 0.26.2-1    jdk17-openjdk 17.0.17
maven 3.9.12-1       firefox 144.0-1
```

None of these packages is in the `archriscv-packages` `blacklist.txt`, so they
are rebuilt natively.

### 3.3 riscv64 — Debian trixie

```
opensc 0.26.1-2      libccid 1.6.2-1     pcscd 2.3.3-1
pcsc-tools 1.7.3-1   p11-kit 0.25.5-3    maven 3.9.9-1
firefox-esr 153.5.1
```

Gap: **there is no OpenJDK 17 in trixie** (21 is available). Options:

1. Install `openjdk-17-jre` from sid (risk of mixing suites).
2. Patch the Autofirma launcher to accept 21 (likely works; must be tested).
3. Use Arch for riscv64 as the primary platform.

---

## 4. Decisions taken

| # | Decision | Reason |
|---|---|---|
| D1 | PKCS#11 base: **OpenSC** | LGPL, DNIe driver, packaged on all three platforms |
| D2 | **Shim** `libpkcs11-dnie.so` → OpenSC | Compatibility with guides and apps that hardcode the official path |
| D3 | aarch64 and riscv64 on **Arch** as primary platform | Whole stack already packaged and current |
| D4 | Debian as secondary platform | JDK 17 missing; requires adaptation |
| D5 | Reference browser: **Firefox** | Available on all three; Chromium on riscv64 is unviable |
| D6 | Autofirma from source | No multi-arch binary; it is pure Java |
| D7 | Do not redistribute a modified official binary | "Custom" license; no source either |

---

## 5. Gaps and derived tasks

| Gap | Phase | Task |
|---|---|---|
| `libpkcs11-dnie.so` does not exist on ARM/RISC-V | F3 | C shim + install in `/usr/lib` and p11-kit registration |
| Autofirma is not packaged | F4 | Multi-arch PKGBUILD + signing test |
| Debian trixie lacks JDK 17 | F4/F7 | Test with 21 or use 17 from sid; document |
| DNIe 4.0 coverage in OpenSC must be verified | F6 | Operation battery with a 4.0 card |
| Firefox 144 on RISC-V vs 158 on x86 | F5 | Validate PKCS#11 module loading on 144 |
| ARM/RISC-V hardware | F2/F5 | Done: Orange Pi 5 and VisionFive 2 |

---

## 6. Matrix verification

Data was obtained with:

```bash
# Arch Linux ARM
curl -s https://archlinuxarm.org/packages/aarch64/<package>

# Arch RISC-V (flat repository listing)
curl -s https://mirrors.felixc.at/archriscv/repo/extra/ | grep '<package>-'

# Debian
curl -s https://packages.debian.org/trixie/riscv64/<package>
```

Repeat this query before closing F7, since versions change.
