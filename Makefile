# Copyright (c) 2026 macwlt contributors.
# SPDX-License-Identifier: Apache-2.0

TARGET ?= macwlt
PREFIX ?= /usr/local

ALL_SRC := $(shell find src -type f -name '*.m' | sort)
APP_SRC := $(filter-out src/xpc/%,$(ALL_SRC))
CORE_SRC := $(shell find src/core -type f -name '*.m' | sort)
SIGNING_SERVICE_SRC := $(filter-out src/core/SigningServiceClient.m,$(filter-out src/ui/%,$(filter-out src/xpc/%,$(ALL_SRC)))) \
	src/xpc/SigningServiceMain.m
HEADERS := $(shell find src -type f -name '*.h' | sort)
TEST_SRCS := $(shell find tests -type f -name '*.m' | sort)
TEST_CORE_SRCS := \
	src/core/Address.m \
	src/core/HardenedBuffer.m \
	src/core/HardenedShareWindow.m \
	src/core/hex.m \
	src/core/macwlt.m \
	src/core/PSBT.m \
	src/core/SEKeyManager.m \
	src/core/SigningServiceClient.m \
	src/core/SigningService.m \
	src/core/SigningServiceListenerDelegate.m \
	src/core/SigningShareSet.m \
	src/core/WalletAddressDerivation.m \
	src/core/WalletEnvelopeManager.m \
	src/core/WalletPublicKeyDerivation.m \
	src/core/WalletSigner.m \
	src/core/WalletShareEnvelope.m
BUILD_DIR := build
BIN := $(BUILD_DIR)/$(TARGET)
LIB := $(BUILD_DIR)/libmacwlt.dylib
TEST_BUNDLE_NAME := MacwltCoreTests
TEST_BUNDLE := $(BUILD_DIR)/$(TEST_BUNDLE_NAME).xctest
TEST_BIN := $(TEST_BUNDLE)/Contents/MacOS/$(TEST_BUNDLE_NAME)
TEST_INFO_PLIST := tests/MacwltCoreTests-Info.plist
APP_BUNDLE_ID ?= com.macwlt.App
APP_BUNDLE := $(BUILD_DIR)/macwlt.app
APP_BUNDLE_BIN := $(APP_BUNDLE)/Contents/MacOS/$(TARGET)
APP_INFO_PLIST := src/ui/macwlt-Info.plist
SIGNING_SERVICE_BUNDLE_ID ?= com.macwlt.SigningService
SIGNING_SERVICE_BUNDLE := $(BUILD_DIR)/$(SIGNING_SERVICE_BUNDLE_ID).xpc
SIGNING_SERVICE_BIN := $(SIGNING_SERVICE_BUNDLE)/Contents/MacOS/$(SIGNING_SERVICE_BUNDLE_ID)
APP_SIGNING_SERVICE_BUNDLE := $(APP_BUNDLE)/Contents/XPCServices/$(SIGNING_SERVICE_BUNDLE_ID).xpc
SIGNING_SERVICE_INFO_PLIST := src/xpc/com.macwlt.SigningService-Info.plist
SIGNING_SERVICE_ENTITLEMENTS ?= src/xpc/signing-service.entitlements
WALLY_DIR := vendor/libwally-core
WALLY_BUILD_DIR := $(BUILD_DIR)/libwally-core
WALLY_CONFIGURE := $(WALLY_DIR)/configure
WALLY_MAKEFILE := $(WALLY_BUILD_DIR)/Makefile
WALLY_BUILD_STAMP := $(WALLY_BUILD_DIR)/.built
WALLY_LIB := $(WALLY_BUILD_DIR)/src/.libs/libwallycore.a
WALLY_SECP256K1_LIB := $(WALLY_BUILD_DIR)/src/secp256k1/.libs/libsecp256k1.a
XKCP_DIR := vendor/XKCP
XKCP_TARGET ?= generic64
XKCP_LIB := $(XKCP_DIR)/bin/$(XKCP_TARGET)/libXKCP.a
# Ad-hoc builds cannot use restricted entitlements; AMFI kills faked ones.
ENTITLEMENTS ?=
CODESIGN_IDENTITY ?= -
CODESIGN_OPTIONS ?=

CC := $(shell xcrun --find clang 2>/dev/null || command -v clang)
MACOSX_SDK ?= $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
export SDKROOT := $(MACOSX_SDK)
CPPFLAGS ?=
CFLAGS ?= -fobjc-arc -Wall -Wextra
LDFLAGS ?=
CPPFLAGS += -DWALLY_ABI_NO_ELEMENTS \
	-I$(WALLY_DIR)/include \
	-I$(WALLY_DIR)/src/secp256k1/include \
	-I$(XKCP_DIR)/bin/.build/$(XKCP_TARGET)/libXKCP.a \
	-I$(XKCP_DIR)/bin/$(XKCP_TARGET)/libXKCP.a.headers
CFLAGS += $(if $(MACOSX_SDK),-isysroot $(MACOSX_SDK))
LDLIBS ?= -framework Foundation -framework Security -framework AppKit -framework Cocoa
LDLIBS += $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB) -lz
CODESIGN ?= codesign
SELECTED_DEVDIR := $(shell xcode-select -p)
FALLBACK_XCODE_DEVDIR ?= /Applications/Xcode.app/Contents/Developer
DEVDIR ?= $(if $(wildcard $(SELECTED_DEVDIR)/usr/bin/xctest),$(SELECTED_DEVDIR),$(FALLBACK_XCODE_DEVDIR))
XCTEST_PLATFORM := $(DEVDIR)/Platforms/MacOSX.platform/Developer
XCTEST_FRAMEWORKS := $(XCTEST_PLATFORM)/Library/Frameworks
XCTEST := $(DEVDIR)/usr/bin/xctest
TEST_CPPFLAGS := -DWALLY_ABI_NO_ELEMENTS \
	-I. \
	-I$(WALLY_DIR)/include \
	-I$(WALLY_DIR)/src/secp256k1/include \
	-I$(XKCP_DIR)/bin/.build/$(XKCP_TARGET)/libXKCP.a \
	-I$(XKCP_DIR)/bin/$(XKCP_TARGET)/libXKCP.a.headers
TEST_CFLAGS := -fobjc-arc -g -O0 -Wall -Wextra -Werror \
	-fmodules \
	-fmodules-cache-path=$(BUILD_DIR)/ModuleCache \
	-F$(XCTEST_FRAMEWORKS) \
	-iframework $(XCTEST_FRAMEWORKS) \
	$(if $(MACOSX_SDK),-isysroot $(MACOSX_SDK))
TEST_LDFLAGS := -bundle -ObjC \
	-F$(XCTEST_FRAMEWORKS) \
	-framework XCTest \
	-framework Foundation \
	-framework Security \
	-framework AppKit \
	-framework Cocoa \
	-Wl,-rpath,$(XCTEST_FRAMEWORKS)
XCTEST_FILTER := $(if $(FILTER),-XCTest $(FILTER),)

.PHONY: build test install clean submodules signing-service app-bundle

build: $(BIN) $(LIB) signing-service app-bundle

signing-service: $(SIGNING_SERVICE_BIN)

app-bundle: $(APP_BUNDLE_BIN) $(APP_SIGNING_SERVICE_BUNDLE)

test: $(TEST_BIN)
	$(XCTEST) $(XCTEST_FILTER) $(TEST_BUNDLE)

submodules:
	git submodule update --init --recursive

$(WALLY_CONFIGURE): .gitmodules
	git submodule update --init --recursive
	cd $(WALLY_DIR) && ./tools/autogen.sh

$(WALLY_MAKEFILE): $(WALLY_CONFIGURE)
	@mkdir -p $(WALLY_BUILD_DIR)
	cd $(WALLY_BUILD_DIR) && SDKROOT="$(MACOSX_SDK)" CC="$(CC)" ../../$(WALLY_DIR)/configure \
		--disable-shared \
		--enable-static \
		--disable-tests \
		--disable-elements \
		--disable-elements-abi

$(WALLY_BUILD_STAMP): $(WALLY_MAKEFILE)
	$(MAKE) -C $(WALLY_BUILD_DIR)
	@touch $@

$(WALLY_LIB) $(WALLY_SECP256K1_LIB): $(WALLY_BUILD_STAMP)

$(XKCP_LIB):
	$(MAKE) -C $(XKCP_DIR) $(XKCP_TARGET)/libXKCP.a

$(BIN): $(APP_SRC) $(HEADERS) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB) $(ENTITLEMENTS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $(APP_SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) $@

$(LIB): $(CORE_SRC) $(HEADERS) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -dynamiclib -install_name @rpath/libmacwlt.dylib -o $@ $(CORE_SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $@

$(SIGNING_SERVICE_BIN): $(SIGNING_SERVICE_SRC) $(HEADERS) $(SIGNING_SERVICE_INFO_PLIST) $(SIGNING_SERVICE_ENTITLEMENTS) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB)
	@mkdir -p $(SIGNING_SERVICE_BUNDLE)/Contents/MacOS
	cp $(SIGNING_SERVICE_INFO_PLIST) $(SIGNING_SERVICE_BUNDLE)/Contents/Info.plist
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $(SIGNING_SERVICE_SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(if $(SIGNING_SERVICE_ENTITLEMENTS),--entitlements $(SIGNING_SERVICE_ENTITLEMENTS)) $(SIGNING_SERVICE_BUNDLE)

$(APP_BUNDLE_BIN): $(BIN) $(APP_INFO_PLIST)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(APP_INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	cp $(BIN) $@

$(APP_SIGNING_SERVICE_BUNDLE): $(SIGNING_SERVICE_BIN) $(APP_BUNDLE_BIN)
	@mkdir -p $(APP_BUNDLE)/Contents/XPCServices
	ditto $(SIGNING_SERVICE_BUNDLE) $@
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(APP_BUNDLE)

$(TEST_BIN): $(TEST_SRCS) $(TEST_CORE_SRCS) $(HEADERS) $(TEST_INFO_PLIST) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB)
	@mkdir -p $(dir $@)
	cp $(TEST_INFO_PLIST) $(TEST_BUNDLE)/Contents/Info.plist
	$(CC) $(TEST_CPPFLAGS) $(TEST_CFLAGS) $(TEST_LDFLAGS) $(LDFLAGS) -o $@ $(TEST_SRCS) $(TEST_CORE_SRCS) $(LDLIBS)

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install $(BIN) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) -C $(XKCP_DIR) clean
