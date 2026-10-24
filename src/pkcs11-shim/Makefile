# SPDX-License-Identifier: GPL-3.0-or-later
CC      ?= cc
# Default multiarch tripleta (Debian/Ubuntu). Override with:
#   make MULTIARCH=aarch64-linux-gnu
#   make MULTIARCH=            (disables /usr/lib/<tripleta>/ paths)
MULTIARCH := $(shell $(CC) -print-multiarch 2>/dev/null)

# Paths are fully overridable for non-FHS systems (Guix, Nix):
#   make PREFIX=/gnu/store/... LIBDIR=/gnu/store/.../lib \
#        P11KIT_MODULEDIR=/gnu/store/.../share/p11-kit/modules \
#        MODULE_PATH=/gnu/store/.../lib/opensc-pkcs11.so
CONFIG_FILE     ?= /etc/dnie-compat.conf
MODULE_PATH     ?=
PREFIX          ?= /usr
LIBDIR          ?= $(PREFIX)/lib
P11KIT_MODULEDIR ?= $(PREFIX)/share/p11-kit/modules
DOCDIR          ?= $(PREFIX)/share/doc/dnie-pkcs11-compat

CFLAGS  ?= -O2
CFLAGS  += -fPIC -Wall -Wextra -fstack-protector-strong -fvisibility=hidden
CPPFLAGS += -DDNIE_COMPAT_MULTIARCH=\"$(MULTIARCH)\"
CPPFLAGS += -DDNIE_COMPAT_CONFIG_FILE=\"$(CONFIG_FILE)\"
ifneq ($(strip $(MODULE_PATH)),)
CPPFLAGS += -DDNIE_COMPAT_DEFAULT_MODULE=\"$(MODULE_PATH)\"
endif

SOFLAGS := -shared -Wl,-soname,libpkcs11-dnie.so \
           -Wl,-z,relro -Wl,-z,now -Wl,-z,defs
LDLIBS  := -ldl -pthread
LDFLAGS ?=
DESTDIR ?=

TARGET  := libpkcs11-dnie.so

.PHONY: all clean test install uninstall

all: $(TARGET)

$(TARGET): dnie_shim.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SOFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

test: $(TARGET)
	pkcs11-tool --module ./$(TARGET) -L
	pkcs11-tool --module ./$(TARGET) -O

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(LIBDIR)/$(TARGET)
	install -d $(DESTDIR)$(P11KIT_MODULEDIR)
	sed 's|@LIBDIR@|$(LIBDIR)|g' dnie-compat.module.in \
	  > $(DESTDIR)$(P11KIT_MODULEDIR)/dnie-compat.module
	chmod 644 $(DESTDIR)$(P11KIT_MODULEDIR)/dnie-compat.module
	install -Dm644 dnie-compat.conf.example $(DESTDIR)$(DOCDIR)/dnie-compat.conf.example

uninstall:
	rm -f $(DESTDIR)$(LIBDIR)/$(TARGET)
	rm -f $(DESTDIR)$(P11KIT_MODULEDIR)/dnie-compat.module
	rm -f $(DESTDIR)$(DOCDIR)/dnie-compat.conf.example

clean:
	rm -f $(TARGET)
