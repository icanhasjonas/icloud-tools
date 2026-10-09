BINARY := icloud
BUILD_DIR := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(BINARY)
INSTALL_DIR := ~/.local/bin
VERSION_FILE := Sources/icloud/Version.swift
VERSION := $(shell sed -n 's/let version = "\(.*\)"/\1/p' $(VERSION_FILE))

.PHONY: build test release install clean version publish publish-dry formula

build:
	swift build

test:
	swift test

release:
	swift build -c release --disable-sandbox

install: release
	@mkdir -p $(INSTALL_DIR)
	cp $(RELEASE_BIN) $(INSTALL_DIR)/$(BINARY)
	@echo "installed $(BINARY) $(VERSION) -> $(INSTALL_DIR)/$(BINARY)"

clean:
	swift package clean

version:
	@echo $(VERSION)

# Full release in one shot: make publish v=0.8.5
publish:
	@test -n "$(v)" || (echo "usage: make publish v=0.8.5" && exit 1)
	@scripts/release.sh $(v)

# Everything up to packaging, nothing committed or pushed: make publish-dry v=0.8.5
publish-dry:
	@test -n "$(v)" || (echo "usage: make publish-dry v=0.8.5" && exit 1)
	@scripts/release.sh $(v) --dry-run

# Re-push the tap formula for an already-published release
formula:
	@scripts/update-formula.sh $(VERSION)
