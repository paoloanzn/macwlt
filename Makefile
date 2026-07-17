# Copyright (c) 2026 macwlt contributors.
# SPDX-License-Identifier: Apache-2.0

TARGET ?= macwlt
PREFIX ?= /usr/local

CORE_SRC := $(shell find packages/core/src -type f -name '*.m' | sort)
CLIENT_CORE_SRC := \
	packages/core/src/SigningServiceClient.m \
	packages/core/src/macwlt.m
APP_SRC := \
	packages/core/src/SigningServiceClient.m \
	packages/core/src/WalletService.m \
	packages/core/src/hex.m \
	packages/ui/src/WalletViewController.m \
	packages/ui/src/macwlt.m
SIGNING_SERVICE_SRC := $(filter-out packages/core/src/SigningServiceClient.m packages/core/src/WalletService.m packages/core/src/macwlt.m,$(CORE_SRC)) \
	packages/xpc/src/SigningServiceMain.m
HEADERS := $(shell find packages/core/src packages/ui/src packages/xpc/src -type f -name '*.h' | sort)
TEST_SRCS := $(shell find tests -type f -name '*.m' | sort)
TEST_CORE_SRCS := \
	packages/core/src/ARCH2FROSTLibrary.m \
	packages/core/src/ARCH2FROSTSigningEngine.m \
	packages/core/src/ARCH2FROSTWallet.m \
	packages/core/src/Address.m \
	packages/core/src/HardenedBuffer.m \
	packages/core/src/HardenedShareWindow.m \
	packages/core/src/hex.m \
	packages/core/src/macwlt.m \
	packages/core/src/PSBT.m \
	packages/core/src/SEKeyManager.m \
	packages/core/src/SigningServiceClient.m \
	packages/core/src/SigningService.m \
	packages/core/src/SigningServiceListenerDelegate.m \
	packages/core/src/SigningShareSet.m \
	packages/core/src/WalletAddressDerivation.m \
	packages/core/src/WalletEnvelopeManager.m \
	packages/core/src/WalletPublicKeyDerivation.m \
	packages/core/src/WalletSigner.m \
	packages/core/src/WalletShareEnvelope.m
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
APP_INFO_PLIST := packages/ui/src/macwlt-Info.plist
SIGNING_SERVICE_BUNDLE_ID ?= com.macwlt.SigningService
SIGNING_SERVICE_BUNDLE := $(BUILD_DIR)/$(SIGNING_SERVICE_BUNDLE_ID).xpc
SIGNING_SERVICE_BIN := $(SIGNING_SERVICE_BUNDLE)/Contents/MacOS/$(SIGNING_SERVICE_BUNDLE_ID)
APP_SIGNING_SERVICE_BUNDLE := $(APP_BUNDLE)/Contents/XPCServices/$(SIGNING_SERVICE_BUNDLE_ID).xpc
SIGNING_SERVICE_INFO_PLIST := packages/xpc/src/com.macwlt.SigningService-Info.plist
SIGNING_SERVICE_ENTITLEMENTS ?= packages/xpc/src/signing-service.entitlements
FROST_DIR := vendor/secp256k1-frost
FROST_SOURCE_DIR := $(BUILD_DIR)/secp256k1-frost-source
FROST_BUILD_DIR := $(BUILD_DIR)/secp256k1-frost
FROST_PATCH := patches/secp256k1-frost-secret-memory.patch
FROST_DYLIB := $(FROST_BUILD_DIR)/lib/libsecp256k1.6.dylib
FROST_BUILD_STAMP := $(FROST_BUILD_DIR)/.built
SIGNING_SERVICE_FRAMEWORKS := $(SIGNING_SERVICE_BUNDLE)/Contents/Frameworks
SIGNING_SERVICE_FROST_DYLIB := $(SIGNING_SERVICE_FRAMEWORKS)/libsecp256k1.6.dylib
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
	-DENABLE_MODULE_FROST_BIP340_MODE \
	-Ipackages/core/src \
	-I$(FROST_DIR)/include \
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
	-DENABLE_MODULE_FROST_BIP340_MODE \
	-I. \
	-Ipackages/core/src \
	-I$(FROST_DIR)/include \
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

.PHONY: build core test install clean submodules signing-service app-bundle

build: core signing-service app-bundle

core: $(LIB)

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

$(FROST_BUILD_STAMP): $(FROST_PATCH) $(shell find $(FROST_DIR) -type f)
	rm -rf $(FROST_SOURCE_DIR) $(FROST_BUILD_DIR)
	mkdir -p $(FROST_SOURCE_DIR)
	rsync -a --exclude .git/ $(FROST_DIR)/ $(FROST_SOURCE_DIR)/
	patch -d $(FROST_SOURCE_DIR) -p1 < $(abspath $(FROST_PATCH))
	cmake -S $(FROST_SOURCE_DIR) -B $(FROST_BUILD_DIR) \
		-DSECP256K1_ENABLE_MODULE_FROST=ON \
		-DSECP256K1_ENABLE_MODULE_FROST_BIP340_MODE=ON \
		-DSECP256K1_EXPERIMENTAL=ON \
		-DSECP256K1_BUILD_TESTS=OFF \
		-DSECP256K1_BUILD_EXHAUSTIVE_TESTS=OFF \
		-DSECP256K1_BUILD_BENCHMARK=OFF \
		-DSECP256K1_BUILD_EXAMPLES=OFF \
		-DBUILD_SHARED_LIBS=ON
	cmake --build $(FROST_BUILD_DIR)
	touch $@

$(FROST_DYLIB): $(FROST_BUILD_STAMP)

$(SIGNING_SERVICE_FROST_DYLIB): $(FROST_DYLIB)
	mkdir -p $(SIGNING_SERVICE_FRAMEWORKS)
	cp $(FROST_DYLIB) $@

$(BIN): $(APP_SRC) $(HEADERS) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB) $(ENTITLEMENTS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $(APP_SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) $@

$(LIB): $(CLIENT_CORE_SRC) $(HEADERS)
	@mkdir -p $(BUILD_DIR)
	$(CC) -I. $(CFLAGS) $(LDFLAGS) -dynamiclib -install_name @rpath/libmacwlt.dylib -o $@ $(CLIENT_CORE_SRC) -framework Foundation
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $@

$(SIGNING_SERVICE_BIN): $(SIGNING_SERVICE_SRC) $(HEADERS) $(SIGNING_SERVICE_INFO_PLIST) $(SIGNING_SERVICE_ENTITLEMENTS) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB) $(SIGNING_SERVICE_FROST_DYLIB)
	@mkdir -p $(SIGNING_SERVICE_BUNDLE)/Contents/MacOS
	cp $(SIGNING_SERVICE_INFO_PLIST) $(SIGNING_SERVICE_BUNDLE)/Contents/Info.plist
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -Wl,-rpath,@executable_path/../Frameworks -o $@ $(SIGNING_SERVICE_SRC) $(LDLIBS)
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(if $(filter-out -,$(CODESIGN_IDENTITY)),--entitlements $(SIGNING_SERVICE_ENTITLEMENTS)) $(SIGNING_SERVICE_BUNDLE)

$(APP_BUNDLE_BIN): $(BIN) $(APP_INFO_PLIST)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(APP_INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	cp $(BIN) $@

$(APP_SIGNING_SERVICE_BUNDLE): $(SIGNING_SERVICE_BIN) $(APP_BUNDLE_BIN)
	@mkdir -p $(APP_BUNDLE)/Contents/XPCServices
	ditto $(SIGNING_SERVICE_BUNDLE) $@
	$(CODESIGN) --force $(CODESIGN_OPTIONS) --sign $(CODESIGN_IDENTITY) $(APP_BUNDLE)

$(TEST_BIN): $(TEST_SRCS) $(TEST_CORE_SRCS) $(HEADERS) $(TEST_INFO_PLIST) $(WALLY_LIB) $(WALLY_SECP256K1_LIB) $(XKCP_LIB) $(FROST_DYLIB)
	@mkdir -p $(dir $@)
	cp $(TEST_INFO_PLIST) $(TEST_BUNDLE)/Contents/Info.plist
	$(CC) $(TEST_CPPFLAGS) $(TEST_CFLAGS) $(TEST_LDFLAGS) $(LDFLAGS) -o $@ $(TEST_SRCS) $(TEST_CORE_SRCS) $(LDLIBS)

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install $(BIN) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) -C $(XKCP_DIR) clean
