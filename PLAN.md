# PLAN — DNIe on aarch64 and riscv64

**Status:** v1 draft · 2026-10-24
**Scope:** Linux (Arch/Manjaro, Debian/Ubuntu)
**Goal:** make the DNIe libraries and applications work on ARM64 and RISC-V 64 machines.

---

## 0. Executive summary

`libpkcs11-dnie` (commercial name **MultiCard PKCS11**) is a **closed-source**
x86-64 binary with no source code, under a "custom" license that allows
redistributing the original binary but not modifying it. **There is no build for
aarch64 or riscv64, and it cannot be rebuilt.**

Therefore "porting the libraries" does not mean translating the binary; it means
**delivering a functionally equivalent native stack**:

1. **OpenSC** (LGPL) as the PKCS#11 module, with its `card-dnie.c` driver.
2. A **compatibility shim** named `libpkcs11-dnie.so` that forwards the PKCS#11
   ABI to OpenSC, so applications and guides that expect the official path work
   unchanged.
3. **Autofirma + jmulticard** (Java, GPL/EUPL), which are architecture-independent.
4. Real packaging for **ALARM/Arch RISC-V** and **Debian riscv64**, with tests on
   hardware.

The serious engineering work is not packaging: it is **covering the DNIe 4.0
operations** that OpenSC may not implement, using `jmulticard` (LGPL/EUPL) as a
reference and, where needed, verifying the official module's behaviour with
reverse engineering (REA + Ghidra).

**Expected outcome:** a user with a reader and a DNIe can install a package and
perform web authentication and electronic signing on aarch64 and riscv64,
without the official binary.

---

## 1. Objectives

1. Detect the reader and the card on aarch64 and riscv64 (`pcscd` + `ccid`).
2. Expose the DNIe certificates and keys through PKCS#11.
3. Web authentication (Firefox) on both architectures.
4. Document signing with Autofirma on both architectures.
5. Reproducible installation through native packages.
6. Document limits, differences and troubleshooting.

## 2. Non-goals

- Rebuilding or "translating" the official binary (`libpkcs11-dnie.so`).
  Technically impossible without source.
- Windows and macOS.
- PIN bypass, private key extraction or any attack on the card.
- Replacing the FNMT/DGP as issuer: this is an independent implementation, not
  an official one.

---

## 3. Technical reality (why the plan looks like this)

| Component | Source | x86-64 | aarch64 | riscv64 | Strategy |
|---|---|---|---|---|---|
| `libpkcs11-dnie.so` (official) | ❌ closed | ✅ binary | ❌ | ❌ | **Not ported**. Replaced by OpenSC + shim |
| `libpkcs11-dnie-{cryptopp,asn1,asn1skeletons}` | ❌ closed | ✅ | ❌ | ❌ | Internal to the official module; not needed |
| OpenSC (`opensc-pkcs11.so`) | ✅ LGPL | ✅ | ✅ buildable | ✅ buildable | **Base of the port** |
| `card-dnie.c` (DNIe driver) | ✅ LGPL | ✅ 3.0 | ✅ | ✅ | Reference; possible 4.0 extension |
| `jmulticard` | ✅ LGPL/EUPL | ✅ Java | ✅ Java | ✅ Java | Protocol reference (PACE, CWA 14890, APDUs) |
| Autofirma | ✅ GPL/EUPL | ✅ | ✅ Java | ✅ Java | Package and test |
| `pcsclite`, `ccid` | ✅ | ✅ | ✅ | ✅ | Distribution packages |
| Firefox | ✅ | ✅ | ✅ | ⚠️ distribution-dependent | Reference browser |
| Chromium | ✅ | ✅ | ✅ | ⚠️ very limited | Not blocking |
| pinentry / libassuan | ✅ | ✅ | ✅ | ✅ | Only used by the official module; not applicable |

**Conclusion:** 90% of the stack is already portable. The remaining 10% is
(a) name/path compatibility, (b) real DNIe 4.0 coverage, and (c) packaging and
validation on hardware.

### 3.1 Why emulating the binary does not work

An x86-64 `.so` cannot be loaded inside an aarch64/riscv64 Firefox: the ELF has
a different machine type. Box64/QEMU can run a complete x86-64 process, but they
cannot mix libraries across architectures. Emulating an entire x86 browser would
be fragile, slow and insecure. Discarded as a solution; kept only as a
point-in-time diagnostic.

---

## 4. Target architecture

```
┌──────────────────────────────────────────────────────────┐
│ Applications                                             │
│  Firefox / Chromium        Autofirma (Java)              │
│        │                        │                        │
│        │ PKCS#11                │ JCA/JCE + JMulticard    │
│        ▼                        ▼                        │
│  libpkcs11-dnie.so  ──shim──▶  opensc-pkcs11.so          │
│  (compatibility)               (LGPL, multi-arch)        │
│                                   │                      │
├───────────────────────────────────┼──────────────────────┤
│ PC/SC: pcsclite + ccid + pcscd    ▼                      │
│                              USB reader                  │
└──────────────────────────────────────────────────────────┘
```

Two paths, one piece of hardware:

- **PKCS#11** (browsers and native apps): shim → OpenSC.
- **Java** (Autofirma): jmulticard talks to PC/SC directly.

---

## 5. Phases

Each phase has a deliverable and an acceptance criterion. No phase is closed
until its criterion is met.

### F0 — Laboratory setup

**Tasks**
- Repository structure in `~/dni-e`.
- Toolchain: `base-devel`, `git`, `cmake`, `ninja`, `pkg-config`, `jdk17-openjdk`,
  `maven`, `pcsc-lite` headers, `openssl`.
- Pin reference versions (OpenSC, Autofirma, pcsc-lite, ccid).
- Document available hardware: aarch64 board, riscv64 board, reader(s), DNIe.
- Snapshot of the current working x86-64 state (OpenSC + Firefox).

**Deliverable:** `docs/00-environment.md` with versions, hardware and baseline.
**Acceptance:** reproduce the current x86-64 flow (reader + card + certificates listed).

---

### F1 — Inventory and compatibility matrix

**Tasks**
- Enumerate every required artifact and its status per architecture.
- Identify real native dependencies (not the official module's).
- Check repository availability: ALARM (aarch64), Arch RISC-V, Debian riscv64.
- Decide what is packaged and what comes from the distribution.

**Deliverable:** `docs/01-matrix.md` with component × architecture × origin.
**Acceptance:** no component left without a strategy.

---

### F2 — Base stack on aarch64

**Tasks**
- Install/build `pcsclite`, `ccid`, `pcsc-tools`, `opensc`.
- Verify `pcscd.socket` active and `pcsc_scan` detecting the reader.
- Verify `opensc-tool -n` → `dnie` and `pkcs15-tool --list-certificates`.
- Load the module in Firefox and validate authentication.
- Test with DNIe 3.0 and 4.0 if both are available.

**Deliverable:** `docs/02-aarch64.md` + verification scripts.
**Acceptance:** full web authentication on aarch64 with the correct PIN
(requires valid certificates).

**Progress (2026-10-26):** T1–T6 pass on the ARM64 board with the real DNIe
4.0 card. Certificates were renewed on 2026-10-26; T7–T9 are pending the PIN
tests.

---

### F3 — PKCS#11 compatibility (shim)

**Tasks**
- Implement `src/pkcs11-shim/` in C:
  - exports `C_GetFunctionList` and delegates to OpenSC's list;
  - `C_GetInfo` reports a neutral name ("DNIe PKCS#11 (OpenSC)") without
    impersonating the official module;
  - supports `dlopen` by path and by `soname`.
- Install as `/usr/lib/libpkcs11-dnie.so` (and `lib64` where applicable).
- Register in `p11-kit` (`/usr/share/p11-kit/modules/`).
- Test with: `pkcs11-tool`, Firefox, Chromium, and an app that hardcodes the
  official path.

**Deliverable:** `dnie-pkcs11-compat` package.
**Acceptance:** an official DNIe installation guide (pointing to
`libpkcs11-dnie.so`) works without editing paths.

**Open decision:** direct symlink vs shim. Start with a symlink (minimum effort)
and justify the shim only if there are behaviour or identity differences.

---

### F4 — Java applications (Autofirma)

**Tasks**
- Build Autofirma from source (`ctt-gob-es/clienteafirma`) with JDK 17.
- Verify the launcher does not assume x86 paths (`/usr/lib/jvm/java-17-openjdk`).
- Test PDF signing with the DNIe.
- Validate `afirma://` in Firefox.
- Review the existing AUR packaging and adapt it to multi-arch.

**Deliverable:** working `autofirma` package on aarch64 (and recipe for riscv64).
**Acceptance:** sign a test PDF with a valid certificate.

---

### F5 — riscv64

**Tasks**
- Prepare environment (Arch RISC-V or Debian riscv64) with toolchain.
- Build `pcsclite`, `ccid`, `opensc`; resolve dependencies.
- Verify reader + ATR + certificates.
- Browser: Firefox as target; document Chromium status.
- Autofirma with the distribution JDK 17.
- Measure and document performance limits.

**Deliverable:** `docs/05-riscv64.md` + packages.
**Acceptance:** same criterion as F2 on riscv64.

**Main risk:** browser and JDK availability in the chosen RISC-V distribution.

---

### F6 — DNIe 4.0 coverage (if F2/F5 find gaps)

**Tasks**
- Run the operation battery (login, authentication, signing) with the 4.0 card.
- Compare with `jmulticard` (`Dnie3`, `ceressc`, `PaceChat`, `GeneralAuthenticate`)
  and with `card-dnie.c`.
- Implement missing APDUs in OpenSC, with unit tests.
- If ambiguous, verify the official module's behaviour with REA/Ghidra
  (`CComm_DNIe_V5::setEAC2Channel`) and a real APDU trace.
- Send upstream patches to OpenSC.

**Deliverable:** patches + tests + `docs/06-dnie4.md`.
**Acceptance:** signing and authentication with DNIe 4.0 on both architectures.

**This is the real engineering phase.** The others are integration and packaging.

---

### F7 — Packaging

**Tasks**
- PKGBUILD for Arch/ALARM and Arch RISC-V:
  - `dnie-pkcs11-compat`
  - `autofirma` (or adaptation of the AUR package)
  - `dnie-stack` meta-package
- Debian: `libpkcs11-dnie-compat` with clear `Provides/Conflicts`.
- Pin checksums, versions and dependencies.
- Do not break official-module installations on x86-64.

**Deliverable:** `packaging/` + installable packages.
**Acceptance:** clean install on a machine with no prior DNIe setup, and
documented coexistence with the official module.

---

### F8 — Validation, documentation and upstream

**Tasks**
- Executed and signed test matrix (date, versions, architecture).
- Installation guides per distribution and architecture.
- Known limitations and diagnostics.
- Upstream PRs: OpenSC (if changed), AUR, documentation.
- Publish the repository with a clear license.

**Deliverable:** final documentation + release.
**Acceptance:** a third party can repeat the process using only the documentation.

---

### F9 — Universal installation

**Tasks**
- `install.sh` with package-manager detection (`apt`, `dnf`, `yum`, `pacman`,
  `zypper`, `apk`, `xbps-install`, `emerge`), prefix/system modes, dry-run and
  uninstall.
- `libpkcs11-fnmtdnie.so` alias for FNMT guides.
- Browser setup (Firefox profiles and Chrome NSS database) with backups.
- Portable Autofirma launcher that accepts any Java >= 17.
- polkit rule and `plugdev` membership automation.
- Debian package (`packaging/debian/`) with `Provides`/`Conflicts`.
- Tag-driven release workflow: cross-built tarballs for x86-64, aarch64,
  riscv64, armv7, ppc64le and s390x, native `.deb` on x86-64 and ARM64.
- Detached GPG signature for `SHA256SUMS` and public key export.

**Deliverable:** `install.sh`, `scripts/setup-browser.sh`,
`packaging/autofirma/`, `docs/08-universal-install.md`.
**Acceptance:** install and uninstall on x86-64, aarch64 and riscv64; 21 shim
tests pass; no architecture-specific code.

---

## 6. Test matrix

| # | Test | x86-64 | aarch64 | riscv64 | Needs PIN |
|---|---|---|---|---|---|
| T1 | `pcsc_scan` detects reader | ✅ | ✅ | ✅ | no |
| T2 | DNIe ATR | ✅ | ✅ | ✅ | no |
| T3 | `opensc-tool -n` = `dnie` | ✅ | ✅ | ✅ | no |
| T4 | `pkcs15-tool --list-certificates` (3 certs) | ✅ | ✅ | ✅ | no |
| T5 | `pkcs11-tool -L/-O` through the shim | ✅ | ✅ | ✅ | no |
| T6 | Firefox lists the certificates | | ✅ | ✅ | no |
| T7 | TLS authentication on a site | ✅ | | | **yes** |
| T8 | PDF signing with Autofirma | ✅ | | | **yes** |
| T9 | Signing through PKCS#11 (`C_Sign`) | ✅ | | | **yes** |
| T10 | Clean install from package | | ✅ | | no |

**Result (2026-10-26):** T7 was validated at the TLS layer with GnuTLS and
PKCS#11; the Firefox UI client-certificate path is still under investigation.
T8 and T9 were validated through Autofirma/PKCS#11 on x86-64.

**Result (2026-10-27):** on the ARM64 board, T1–T6 and T10 pass (clean
`dpkg` install of 0.2.1); T7–T9 still need the interactive PIN test. The board
was showing the pre-renewal certificates from a stale OpenSC cache; see
`docs/02-aarch64.md` §4.

**Result (2026-10-27, Firefox GUI):** with the correct PIN (verified with
`pkcs15-tool --verify-pin` and `pkcs11-tool --login`), Firefox lists the DNIe
authentication certificate, prompts for the PIN and then sends an empty
certificate list. Software certificates work against the same server, so T7
remains closed at the TLS/PKCS#11 layer and the Firefox UI path is a separate
NSS/OpenSC issue (`docs/10-headless-browser.md` §5.2).

**Golden rule:** T1–T6 and T10 do not spend PIN attempts. T7–T9 only with a
verified PIN and valid certificates. Never automate PIN attempts: 3 failures
block the card.

---

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| The official binary cannot be ported | High | Replace with OpenSC + shim; stated from day one |
| OpenSC does not fully cover DNIe 4.0 | High | F6 with jmulticard as reference; upstream patches |
| Expired certificates | High | Renew before T7–T9; meanwhile validate T1–T6 |
| Browser on riscv64 | Medium | Firefox; Chromium not blocking |
| JDK 17 on riscv64 | Medium | Distribution package; fallback: build |
| Autofirma assumes x86 paths | Low | Review launcher; packaging patch |
| USB reader on ARM boards | Low | Test standard CCID; avoid hubs |
| polkit denies PC/SC on headless/SSH | Medium | Install `packaging/polkit/50-pcscd.rules` (group `plugdev`); `setup-debian.sh` does it |
| Licensing | Medium | OpenSC LGPL, Autofirma GPL/EUPL, jmulticard LGPL/EUPL; do not redistribute a modified official binary |

---

## 8. Security hardening

Audit of the shim (the only executable code in this project) and fixes applied:

| # | Finding | Risk | Fix |
|---|---|---|---|
| S1 | `DNIE_COMPAT_*` read with `getenv`, so a setuid/setgid process could be redirected to an arbitrary `.so` | High | `secure_getenv(3)`; ignored in secure-execution mode |
| S2 | Config file could be a FIFO/device, blocking the process | Medium | require a regular file (`S_ISREG`) |
| S3 | Root could read a group/other-writable config | Medium | root requires `st_uid == 0` and no group/other write |
| S4 | Relative paths could load a module from the current directory | Medium | non-absolute paths ignored |
| S5 | Long search paths could truncate into a different path | Low | check `snprintf` result and skip truncation |
| S6 | Lazy initialization was not thread-safe | Medium | `pthread_once(3)` |
| S7 | All internal symbols exported | Low | `-fvisibility=hidden`, two exported symbols |
| S8 | No default hardening flags | Medium | stack protector, full RELRO, `BIND_NOW`, `-z defs` |
| S9 | User-controlled config in `$HOME` readable by root | Low | secure mode ignores it; ownership/permission checks |

Residual risks documented as out of scope: `LD_PRELOAD`/`LD_LIBRARY_PATH`
attacks on the host process, a compromised root account, and OpenSC's own
security. The shim never handles PIN material.

Security behaviour is covered by `tests/test-shim-paths.sh` (FIFO/directory
config, oversized paths, `BIND_NOW`, `GNU_RELRO`, exported-symbol count,
8-thread concurrency).

## 9. Portability and non-FHS systems (Guix/Nix)

Every install path is a make variable; nothing is hardcoded to `/usr`:

| Variable | Default |
|---|---|
| `PREFIX` | `/usr` |
| `LIBDIR` | `$(PREFIX)/lib` |
| `P11KIT_MODULEDIR` | `$(PREFIX)/share/p11-kit/modules` |
| `DOCDIR` | `$(PREFIX)/share/doc/dnie-pkcs11-compat` |
| `MODULE_PATH` | *(empty; OpenSC path embedded at build time)* |
| `MULTIARCH` | `cc -print-multiarch` (`MULTIARCH=` disables it) |
| `CONFIG_FILE` | `/etc/dnie-compat.conf` |
| `DESTDIR` | *(empty)* |

The p11-kit `.module` file is generated at install time from
`dnie-compat.module.in`, so `@LIBDIR@` follows `PREFIX`.

Configuration lookup: `DNIE_COMPAT_CONF` → `/etc/dnie-compat.conf` →
`$XDG_CONFIG_HOME/dnie-compat.conf` → `$HOME/.config/dnie-compat.conf`.
`/run/current-system/sw/lib/opensc-pkcs11.so` is a built-in NixOS candidate.

Guix recipe: `guix.scm` and [docs/07-portability.md](docs/07-portability.md).

## 10. Licenses and legal limits

- The project is licensed under **GPL-3.0-or-later** (see `LICENSE`).
- The official binary is **not** decompiled or rebuilt for redistribution: its
  license does not allow it and there is no source.
- The shim and OpenSC are independent implementations; the documentation states
  that they are **not** the official module.
- Reverse engineering for interoperability: allowed in the EU (Directive
  2009/24/EC, art. 6) and in Spain (TRLPI art. 100.2). Limited to protocol and
  compatibility.
- Forbidden: attacking the PIN, extracting keys, bypassing EAC/PACE for illicit
  purposes.

---

## 11. Repository layout

```
dni-e/
├── PLAN.md
├── README.md
├── REPORT.md
├── NEXT-STEPS.md
├── LICENSE
├── docs/
│   ├── 00-environment.md
│   ├── 01-matrix.md
│   ├── 02-aarch64.md
│   ├── 03-shim.md
│   ├── 04-autofirma.md
│   ├── 05-riscv64.md
│   ├── 06-dnie4.md
│   ├── 07-portability.md
│   ├── 08-universal-install.md
│   ├── 09-multiarch-validation.md
│   └── 10-headless-browser.md
├── guix.scm
├── install.sh
├── src/
│   └── pkcs11-shim/
│       ├── Makefile
│       ├── dnie_shim.c
│       ├── dnie-compat.module.in
│       └── dnie-compat.conf.example
├── packaging/
│   ├── arch/
│   ├── autofirma/
│   ├── debian/
│   └── polkit/
├── scripts/
│   ├── verify-stack.sh
│   ├── verify-card.sh
│   ├── setup-browser.sh
│   ├── setup-debian.sh
│   ├── build-release.sh
│   └── sign-release.sh
└── tests/
    ├── test-nss.sh
    ├── test-shim-paths.sh
    ├── test-shim-threads.c
    └── run-matrix.sh
```

---

## 12. Ordered backlog

1. F0: create repo, toolchain and x86-64 snapshot.
2. F1: component matrix (document).
3. F2: aarch64 base (pcsc + opensc) and T1–T4.
4. F3: PKCS#11 shim and T5.
5. F4: Autofirma on aarch64 and T8.
6. F5: riscv64 base and T1–T4.
7. F3/F4 on riscv64 and T6.
8. F6: DNIe 4.0 coverage (only if gaps exist).
9. F7: packages.
10. F8: documentation, signed matrix and upstream.
11. F9: universal installer, browser setup and portable Autofirma.

---

## 13. Definition of Done

- [ ] T1–T6 and T10 green on aarch64 and riscv64.
- [ ] T7–T9 green with valid certificates.
- [ ] Installable and reproducible packages on both architectures.
- [ ] The shim does not break existing x86-64 installations.
- [ ] Documentation sufficient for a third party to repeat it.
- [ ] Limitations and differences from the official module published.

---

## 14. Hardware prerequisites

| Element | Status |
|---|---|
| x86-64 development machine | ✅ available |
| CCID reader (AU9540 detected) | ✅ available |
| DNIe 4.0 | ✅ available (certificates renewed 2026-10-26) |
| aarch64 board | ✅ Orange Pi 5 |
| riscv64 board | ✅ VisionFive 2 |
| DNIe 3.0 for cross-testing | ❓ optional |

---

## 15. Note on the package name

To avoid confusion and legal issues, the package is called
**`dnie-pkcs11-compat`** (or `libpkcs11-dnie-compat`) and is **not** presented as
the official DGP/FNMT module. The shim may occupy
`/usr/lib/libpkcs11-dnie.so` for compatibility, but `C_GetInfo` and the
documentation identify it as an independent implementation based on OpenSC.
