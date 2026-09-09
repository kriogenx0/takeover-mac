BUILD_DIR := build
APP_NAME := Takeover.app
APP_SRC := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME)
APP_DST := /Applications/$(APP_NAME)
BUNDLE_ID := alexvaos.Takeover

CLI_NAME := takeover
CLI_SRC := $(BUILD_DIR)/Build/Products/Release/$(CLI_NAME)
PREFIX ?= /usr/local
CLI_DST := $(PREFIX)/bin/$(CLI_NAME)

PROJECT := Takeover.xcodeproj

.DEFAULT_GOAL := dev

.PHONY: test install install-open dev cli install-cli verify-sign reset-tcc

dev:
	@echo "Building $(APP_NAME) (Debug)..."
	xcodebuild -project Takeover.xcodeproj -scheme Takeover -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build
	@echo "Launching $(APP_NAME)..."
	-killall Takeover 2>/dev/null; true
	open "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)"

# Unit tests for the app target. (TakeoverUITests is intentionally excluded — it
# boots the full app and is slow/flaky for a plain `make test`.)
test:
	@if command -v xcodebuild > /dev/null 2>&1; then \
		echo "Running Takeover unit tests..."; \
		xcodebuild -project $(PROJECT) -scheme Takeover -configuration Debug \
			-destination 'platform=macOS' -only-testing:TakeoverTests test; \
	else \
		echo "Error: 'xcodebuild' not found in PATH — install Xcode."; \
		exit 1; \
	fi
	@echo "Tests completed successfully!"

install:
	@echo "Building $(APP_NAME)..."
	xcodebuild -project $(PROJECT) -scheme Takeover -configuration Release \
		-derivedDataPath $(BUILD_DIR) build
	@echo "Installing to /Applications..."
	-killall Takeover 2>/dev/null; true
	@# Update in place (preserve the bundle path/inode) instead of rm -rf + cp -R.
	@# --delete removes files that no longer exist in the fresh build.
	mkdir -p "$(APP_DST)"
	rsync -a --delete "$(APP_SRC)/" "$(APP_DST)/"
	@$(MAKE) --no-print-directory verify-sign
	@echo "$(APP_NAME) installed successfully!"

install-open: install
	open "$(APP_DST)"

# Build the `takeover` command-line tool (same Xcode project, TakeoverCLI target).
cli:
	@echo "Building $(CLI_NAME)..."
	xcodebuild -project $(PROJECT) -scheme TakeoverCLI -configuration Release \
		-derivedDataPath $(BUILD_DIR) build
	@echo "Built: $(CLI_SRC)"

install-cli: cli
	@echo "Installing $(CLI_NAME) to $(PREFIX)/bin..."
	install -d "$(PREFIX)/bin"
	install -m 0755 "$(CLI_SRC)" "$(CLI_DST)"
	@echo "$(CLI_NAME) installed to $(CLI_DST)"

# Fails the build if the signature is broken, and prints the designated
# requirement so any drift in the signing identity (which is what silently
# revokes Full Disk Access / App Management grants) is visible on every install.
verify-sign:
	@echo "Verifying code signature..."
	codesign --verify --deep --strict --verbose=2 "$(APP_DST)"
	@echo "Designated requirement:"
	@codesign -d --requirements - "$(APP_DST)" 2>&1 | sed -n 's/^designated => /  /p'

# Convenience for iterating on the permissions flow: forget every TCC grant for
# the app so the next launch re-prompts from a clean slate.
reset-tcc:
	-tccutil reset SystemPolicyAllFiles $(BUNDLE_ID)
	-tccutil reset SystemPolicyAppBundles $(BUNDLE_ID)
	-tccutil reset AppleEvents $(BUNDLE_ID)
	@echo "TCC grants reset for $(BUNDLE_ID)."
