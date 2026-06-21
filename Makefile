# Copyright (c) 2026 macwlt contributors.
# SPDX-License-Identifier: Apache-2.0

TARGET ?= macwlt
PREFIX ?= /usr/local

SRC := $(wildcard src/*.m)
BUILD_DIR := build
BIN := $(BUILD_DIR)/$(TARGET)
# No entitlements: Secure Enclave access here needs none. A restricted
# entitlement (keychain-access-groups / app-sandbox) on an ad-hoc signature is
# rejected by amfid and AMFI SIGKILLs the process at launch (the 137 error).
ENTITLEMENTS ?=
CODESIGN_IDENTITY ?= -

CC := clang
CFLAGS ?= -fobjc-arc -Wall -Wextra
LDLIBS ?= -framework Foundation -framework Security -framework AppKit -framework Cocoa
CODESIGN ?= codesign

.PHONY: build install clean

build: $(BIN)

$(BIN): $(SRC) $(ENTITLEMENTS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)
	$(CODESIGN) --force --options runtime --sign $(CODESIGN_IDENTITY) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) $@

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install $(BIN) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

clean:
	rm -rf $(BUILD_DIR)
