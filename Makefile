TARGET ?= macwlt
PREFIX ?= /usr/local

SRC := $(wildcard src/*.m)
BUILD_DIR := build
BIN := $(BUILD_DIR)/$(TARGET)
ENTITLEMENTS ?= macwlt.entitlements
CODESIGN_IDENTITY ?= -

CC := clang
CFLAGS ?= -fobjc-arc -Wall -Wextra
LDLIBS ?= -framework Foundation -framework Security
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
