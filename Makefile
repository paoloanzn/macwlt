# Copyright (c) 2026 macwlt contributors.
# SPDX-License-Identifier: Apache-2.0

TARGET ?= macwlt
PREFIX ?= /usr/local

SRC := $(shell find src -type f -name '*.m' | sort)
BUILD_DIR := build
BIN := $(BUILD_DIR)/$(TARGET)
WORDLIST := bip39-2048.txt
WORDLIST_INC := $(BUILD_DIR)/bip39_wordlist.inc
# Ad-hoc builds cannot use restricted entitlements; AMFI kills faked ones.
ENTITLEMENTS ?=
CODESIGN_IDENTITY ?= -
CODESIGN_OPTIONS ?=

CC := clang
SECP256K1_PREFIX ?= $(shell brew --prefix secp256k1)
OPENSSL_PREFIX ?= $(shell brew --prefix openssl@3)
CPPFLAGS ?=
CFLAGS ?= -fobjc-arc -Wall -Wextra
LDFLAGS ?=
CPPFLAGS += -I$(SECP256K1_PREFIX)/include -I$(OPENSSL_PREFIX)/include
LDFLAGS += -L$(SECP256K1_PREFIX)/lib -L$(OPENSSL_PREFIX)/lib
LDLIBS ?= -framework Foundation -framework Security -framework AppKit -framework Cocoa
LDLIBS += -lsecp256k1 -lcrypto -lz
CODESIGN ?= codesign

.PHONY: build install clean

build: $(BIN)

$(WORDLIST_INC): $(WORDLIST)
	@mkdir -p $(BUILD_DIR)
	gzip -cn9 $< | xxd -i > $@

$(BIN): $(SRC) $(WORDLIST_INC) $(ENTITLEMENTS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $(SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) $@

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install $(BIN) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

clean:
	rm -rf $(BUILD_DIR)
