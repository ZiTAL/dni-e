# SPDX-License-Identifier: GPL-3.0-or-later
CC      ?= cc
# Default multiarch tripleta (Debian/Ubuntu). Override with:
#   make MULTIARCH=aarch64-linux-gnu
#   make MULTIARCH=            (disables /usr/lib/<tripleta>/ paths)
MULTIARCH := $(shell $(CC) -print-multiarch 2>/dev/null)
CONFIG_FILE ?= /etc/dnie-compat.conf
CFLAGS  ?= -O2
CFLAGS  += -fPIC -Wall -Wextra
CPPFLAGS += -DDNIE_COMPAT_MULTIARCH=\"$(MULTIARCH)\"
CPPFLAGS += -DDNIE_COMPAT_CONFIG_FILE=\"$(CONFIG_FILE)\"
SOFLAGS := -shared -Wl,-soname,libpkcs11-dnie.so
LDFLAGS ?=
PREFIX  ?= /usr
LIBDIR  ?= $(PREFIX)/lib
DESTDIR ?=

TARGET  := libpkcs11-dnie.so

.PHONY: all clean test install uninstall

all: $(TARGET)

$(TARGET): dnie_shim.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SOFLAGS) $(LDFLAGS) -o $@ $< -ldl

test: $(TARGET)
	pkcs11-tool --module ./$(TARGET) -L
	pkcs11-tool --module ./$(TARGET) -O

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(LIBDIR)/$(TARGET)
	install -Dm644 dnie-compat.module $(DESTDIR)$(PREFIX)/share/p11-kit/modules/dnie-compat.module
	install -Dm644 dnie-compat.conf.example $(DESTDIR)$(PREFIX)/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example

uninstall:
	rm -f $(DESTDIR)$(LIBDIR)/$(TARGET)
	rm -f $(DESTDIR)$(PREFIX)/share/p11-kit/modules/dnie-compat.module
	rm -f $(DESTDIR)$(PREFIX)/share/doc/dnie-pkcs11-compat/dnie-compat.conf.example

clean:
	rm -f $(TARGET)
