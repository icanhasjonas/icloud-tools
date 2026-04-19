BINARY := icloud
BUILD_DIR := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(BINARY)
DEBUG_BIN := $(BUILD_DIR)/debug/$(BINARY)
INSTALL_DIR := ~/.local/bin
VERSION_FILE := Sources/icloud/Version.swift
VERSION := $(shell sed -n 's/let version = "\(.*\)"/\1/p' $(VERSION_FILE))

.PHONY: build release install clean bump formula version

build:
	swift build

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

# Usage: make bump v=0.8.0
bump:
	@test -n "$(v)" || (echo "usage: make bump v=0.8.0" && exit 1)
	@echo 'let version = "$(v)"' > $(VERSION_FILE)
	@echo "bumped to $(v)"

# Full release: make tag v=0.8.0
tag: bump release
	git add $(VERSION_FILE)
	git commit -m "Bump version to $(v)"
	git tag v$(v)
	git push origin main --tags
	@echo "tagged v$(v) and pushed"

# Update homebrew tap formula after tagging
formula:
	@scripts/update-formula.sh $(VERSION)
