# Copyright (c) 2026 macwlt contributors.
# SPDX-License-Identifier: Apache-2.0

TARGET ?= macwlt
PREFIX ?= /usr/local

SRC := $(shell find src -type f -name '*.m' | sort)
HEADERS := $(shell find src -type f -name '*.h' | sort)
TEST_SRC := tests/core_tests.m \
	src/core/Address.m \
	src/core/Bech32.m \
	src/core/hex.m \
	src/core/Mnemonic.m \
	src/core/PSBT.m \
	src/core/RIPEMD160.m
BUILD_DIR := build
BIN := $(BUILD_DIR)/$(TARGET)
TEST_BIN := $(BUILD_DIR)/core_tests
WORDLIST := bip39-2048.txt
WORDLIST_INC := $(BUILD_DIR)/bip39_wordlist.inc
WALLY_DIR := vendor/libwally-core
WALLY_BUILD_DIR := $(BUILD_DIR)/libwally-core
WALLY_CONFIGURE := $(WALLY_DIR)/configure
WALLY_MAKEFILE := $(WALLY_BUILD_DIR)/Makefile
WALLY_BUILD_STAMP := $(WALLY_BUILD_DIR)/.built
WALLY_LIB := $(WALLY_BUILD_DIR)/src/.libs/libwallycore.a
WALLY_SECP256K1_LIB := $(WALLY_BUILD_DIR)/src/secp256k1/.libs/libsecp256k1.a
# Ad-hoc builds cannot use restricted entitlements; AMFI kills faked ones.
ENTITLEMENTS ?=
CODESIGN_IDENTITY ?= -
CODESIGN_OPTIONS ?=

CC := clang
OPENSSL_PREFIX ?= $(shell brew --prefix openssl@3)
MACOSX_SDK ?= $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
CPPFLAGS ?=
CFLAGS ?= -fobjc-arc -Wall -Wextra
LDFLAGS ?=
CPPFLAGS += -DWALLY_ABI_NO_ELEMENTS -I$(WALLY_DIR)/include -I$(WALLY_DIR)/src/secp256k1/include -I$(OPENSSL_PREFIX)/include
CFLAGS += $(if $(MACOSX_SDK),-isysroot $(MACOSX_SDK))
LDFLAGS += -L$(OPENSSL_PREFIX)/lib
LDLIBS ?= -framework Foundation -framework Security -framework AppKit -framework Cocoa
LDLIBS += $(WALLY_LIB) $(WALLY_SECP256K1_LIB) -lcrypto -lz
CODESIGN ?= codesign

.PHONY: build test install clean submodules

build: $(BIN)

test: $(TEST_BIN)
	$(TEST_BIN)

submodules:
	git submodule update --init --recursive

$(WALLY_CONFIGURE): .gitmodules
	git submodule update --init --recursive
	cd $(WALLY_DIR) && ./tools/autogen.sh

$(WALLY_MAKEFILE): $(WALLY_CONFIGURE)
	@mkdir -p $(WALLY_BUILD_DIR)
	cd $(WALLY_BUILD_DIR) && CC="$(CC)" ../../$(WALLY_DIR)/configure \
		--disable-shared \
		--enable-static \
		--disable-tests \
		--disable-elements \
		--disable-elements-abi

$(WALLY_BUILD_STAMP): $(WALLY_MAKEFILE)
	$(MAKE) -C $(WALLY_BUILD_DIR)
	@touch $@

$(WALLY_LIB) $(WALLY_SECP256K1_LIB): $(WALLY_BUILD_STAMP)

$(WORDLIST_INC): $(WORDLIST)
	@mkdir -p $(BUILD_DIR)
	gzip -cn9 $< | xxd -i > $@

$(BIN): $(SRC) $(HEADERS) $(WORDLIST_INC) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(ENTITLEMENTS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $(SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) $@

$(TEST_BIN): $(TEST_SRC) $(HEADERS) $(WORDLIST_INC) $(WALLY_LIB) $(WALLY_SECP256K1_LIB)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -I. -o $@ $(TEST_SRC) $(LDLIBS)

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install $(BIN) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

clean:
	rm -rf $(BUILD_DIR)
