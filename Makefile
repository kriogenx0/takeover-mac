# Takeover — native macOS SwiftUI app (+ TakeoverCLI)
# Run `make help` for a grouped list of targets.

APP         := Takeover
SCHEME      := Takeover
CLI_SCHEME  := TakeoverCLI
CLI_NAME    := takeover
PROJECT     := Takeover.xcodeproj
BUNDLE_ID   := alexvaos.Takeover

BUILD_DIR   := build
DEV_APP     := $(BUILD_DIR)/Build/Products/Debug/$(APP).app
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/$(APP).app
CLI_SRC     := $(BUILD_DIR)/Build/Products/Release/$(CLI_NAME)

DMG         := $(BUILD_DIR)/$(APP).dmg

INSTALL_DST := /Applications/$(APP).app
PREFIX      ?= /usr/local
CLI_DST     := $(PREFIX)/bin/$(CLI_NAME)

# A Mac without an "Apple Development" identity (e.g. a fresh Mac with only
# Xcode installed) signs Release builds ad hoc instead, so build/install/cli
# still work there. Ad hoc signatures change on every build, so Full Disk
# Access has to be granted again after each reinstall.
HAS_DEV_ID  := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development" && echo yes)
ifeq ($(HAS_DEV_ID),yes)
SIGN_FLAGS  :=
else
SIGN_FLAGS  := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
endif

.DEFAULT_GOAL := all

.PHONY: all help setup dev open close test build install uninstall reinstall \
        package cli install-cli verify-sign reset-tcc clean

##@ Common

all: setup dev ## Default. Same as `make setup dev`.

help: ## Show this help, grouped by category.
	@awk 'BEGIN {FS = ":.*##"; printf "\nTakeover make targets\n"} \
		/^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next} \
		/^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""

##@ Setup

setup: ## Set up the environment if needed: check the toolchain, resolve SPM deps.
	@command -v xcodebuild >/dev/null || { echo "error: xcodebuild not found (install Xcode)"; exit 1; }
	@xcodebuild -version | head -n 1
	@echo "Resolving Swift package dependencies..."
	@xcodebuild -resolvePackageDependencies -project $(PROJECT) -scheme $(SCHEME) -quiet
	@if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then \
		echo "note: no \"Apple Development\" signing identity found — Release builds"; \
		echo "      (build/install/cli) will be signed ad hoc."; \
	fi

##@ Development

dev: ## Build a debug .app (replacing any previous one) and open it.
	-killall $(APP) 2>/dev/null; true
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) -quiet build
	open "$(DEV_APP)"

open: ## Open the already-built dev app (run `make dev` first if there isn't one).
	@if [ ! -d "$(DEV_APP)" ]; then \
		echo "No dev build at $(DEV_APP) yet — run 'make dev' first."; exit 1; \
	fi
	open "$(DEV_APP)"

close: ## Kill the running app. Only if native.
	-killall $(APP) 2>/dev/null; true

# Unit tests for the app target. (TakeoverUITests is intentionally excluded — it
# boots the full app and is slow/flaky for a plain `make test`.)
test: ## Run the unit-test suite.
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -only-testing:TakeoverTests test
	@echo "Tests completed successfully!"

##@ Production

build: ## Build for production (Release), no install.
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) -quiet build $(SIGN_FLAGS)
	@echo "==> $(RELEASE_APP)"

install: build ## Build for production and install to /Applications.
	-killall $(APP) 2>/dev/null; true
	@# Update in place (preserve the bundle path/inode) instead of rm -rf + cp -R.
	@# --delete removes files that no longer exist in the fresh build.
	mkdir -p "$(INSTALL_DST)"
	rsync -a --delete "$(RELEASE_APP)/" "$(INSTALL_DST)/"
	@$(MAKE) --no-print-directory verify-sign
	open "$(INSTALL_DST)"
	@echo "$(APP).app installed to $(INSTALL_DST)"

uninstall: close ## make close. Remove from /Applications, if installed.
	@if [ -d "$(INSTALL_DST)" ]; then \
		rm -rf "$(INSTALL_DST)"; echo "Uninstalled $(INSTALL_DST)"; \
	else \
		echo "$(APP) is not installed"; \
	fi

reinstall: uninstall install ## make uninstall, make install.

# For installing on another Mac without Xcode: copy the .dmg over, open it and
# drag Takeover to Applications. It isn't notarized, so the first launch
# needs right-click > Open (or System Settings > Privacy & Security > Open Anyway).
package: build ## Build for production and package it as build/Takeover.dmg.
	@rm -rf "$(BUILD_DIR)/dmg" "$(DMG)"
	mkdir -p "$(BUILD_DIR)/dmg"
	ditto "$(RELEASE_APP)" "$(BUILD_DIR)/dmg/$(APP).app"
	ln -s /Applications "$(BUILD_DIR)/dmg/Applications"
	hdiutil create -volname "$(APP)" -srcfolder "$(BUILD_DIR)/dmg" -ov -format UDZO "$(DMG)" -quiet
	@rm -rf "$(BUILD_DIR)/dmg"
	@echo "==> $(DMG)"

##@ CLI

cli: ## Build the `takeover` command-line tool (TakeoverCLI target).
	xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) -quiet build $(SIGN_FLAGS)
	@echo "==> $(CLI_SRC)"

install-cli: cli ## Install the CLI to $(PREFIX)/bin.
	install -d "$(PREFIX)/bin"
	install -m 0755 "$(CLI_SRC)" "$(CLI_DST)"
	@echo "$(CLI_NAME) installed to $(CLI_DST)"

##@ Diagnostics

# Fails if the signature is broken, and prints the designated requirement so
# any drift in the signing identity (which is what silently revokes Full Disk
# Access / App Management grants) is visible on every install.
verify-sign: ## Verify the installed app's code signature.
	@echo "Verifying code signature..."
	codesign --verify --deep --strict --verbose=2 "$(INSTALL_DST)"
	@echo "Designated requirement:"
	@codesign -d --requirements - "$(INSTALL_DST)" 2>&1 | sed -n 's/^designated => /  /p'

reset-tcc: ## Forget every TCC grant for the app (re-prompt from a clean slate).
	-tccutil reset SystemPolicyAllFiles $(BUNDLE_ID)
	-tccutil reset SystemPolicyAppBundles $(BUNDLE_ID)
	-tccutil reset AppleEvents $(BUNDLE_ID)
	@echo "TCC grants reset for $(BUNDLE_ID)."

##@ Maintenance

clean: ## Clean existing builds.
	rm -rf $(BUILD_DIR)
	@echo "Cleaned $(BUILD_DIR)"
