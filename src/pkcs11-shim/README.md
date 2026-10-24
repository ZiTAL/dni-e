# PKCS#11 compatibility module for DNIe

`libpkcs11-dnie.so` is the name used by official guides and many applications.
The official module is a closed-source x86-64 binary.

This shim exposes the same name and ABI, but **delegates to OpenSC**, which is
free software (LGPL) and available for aarch64 and riscv64.

```
Firefox ──PKCS#11──▶ libpkcs11-dnie.so (this shim) ──dlopen──▶ opensc-pkcs11.so
```

## Build and test

```bash
make
make test
```

`make test` lists the DNIe slots and objects through `pkcs11-tool`.
It does not ask for a PIN.

## Install

```bash
sudo make install
```

Installs:

- `/usr/lib/libpkcs11-dnie.so`
- `/usr/share/p11-kit/modules/dnie-compat.module`
- `/usr/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example`

The p11-kit registration uses a distinct name (`dnie-compat`) so it cannot be
confused with the official module.

## Configuration

Module resolution order:

1. `DNIE_COMPAT_MODULE=/exact/path/opensc-pkcs11.so` (authoritative)
2. `DNIE_COMPAT_SEARCH_PATH=/dir1:/dir2`
3. `/etc/dnie-compat.conf` (`module=`, `search=`, `multiarch=`)
4. `DNIE_COMPAT_MULTIARCH=aarch64-linux-gnu`
5. `make MULTIARCH=riscv64-linux-gnu`
6. Built-in paths and `glob`

Diagnostics:

```bash
DNIE_COMPAT_DEBUG=1 pkcs11-tool --module /usr/lib/libpkcs11-dnie.so -L
```

## What it does not do

- It does not implement PKCS#11: everything comes from OpenSC.
- It does not impersonate the official module identity (`C_GetInfo` returns
  OpenSC data).
- It does not include or modify DGP/FNMT module code.

## License

GPL-3.0-or-later. See `LICENSE`.
