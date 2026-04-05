# Cocxy Terminal - Build & Distribution
# Usage:
#   make build        - Build release binary
#   make app          - Create .app bundle
#   make dmg          - Create DMG installer
#   make clean        - Remove build artifacts

PRODUCT_NAME = Cocxy Terminal
BUNDLE_ID = com.cocxy.terminal
VERSION = 0.1.0
BUILD_DIR = .build/release
APP_DIR = $(BUILD_DIR)/$(PRODUCT_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

.PHONY: build app dmg clean

# Build release binary (universal: arm64 + x86_64)
build:
	swift build -c release

# Create macOS .app bundle from the release binary
app: build
	@echo "Creating $(PRODUCT_NAME).app bundle..."
	@rm -rf "$(APP_DIR)"
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	@# Copy binary
	@cp "$(BUILD_DIR)/CocxyTerminal" "$(MACOS_DIR)/Cocxy Terminal"
	@# Generate Info.plist
	@cat > "$(CONTENTS_DIR)/Info.plist" << 'PLIST'\
<?xml version="1.0" encoding="UTF-8"?>\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\
<plist version="1.0">\
<dict>\
	<key>CFBundleName</key>\
	<string>Cocxy Terminal</string>\
	<key>CFBundleDisplayName</key>\
	<string>Cocxy Terminal</string>\
	<key>CFBundleIdentifier</key>\
	<string>$(BUNDLE_ID)</string>\
	<key>CFBundleVersion</key>\
	<string>$(VERSION)</string>\
	<key>CFBundleShortVersionString</key>\
	<string>$(VERSION)</string>\
	<key>CFBundleExecutable</key>\
	<string>Cocxy Terminal</string>\
	<key>CFBundlePackageType</key>\
	<string>APPL</string>\
	<key>LSMinimumSystemVersion</key>\
	<string>14.0</string>\
	<key>NSHighResolutionCapable</key>\
	<true/>\
	<key>NSSupportsAutomaticGraphicsSwitching</key>\
	<true/>\
	<key>LSApplicationCategoryType</key>\
	<string>public.app-category.developer-tools</string>\
</dict>\
</plist>
PLIST
	@echo "$(PRODUCT_NAME).app created at $(APP_DIR)"

# Create DMG disk image
dmg: app
	@echo "Creating DMG..."
	@rm -f "$(BUILD_DIR)/CocxyTerminal-$(VERSION).dmg"
	@hdiutil create -volname "$(PRODUCT_NAME)" \
		-srcfolder "$(APP_DIR)" \
		-ov -format UDZO \
		"$(BUILD_DIR)/CocxyTerminal-$(VERSION).dmg"
	@echo "DMG created at $(BUILD_DIR)/CocxyTerminal-$(VERSION).dmg"

clean:
	@rm -rf "$(APP_DIR)"
	@rm -f "$(BUILD_DIR)/CocxyTerminal-*.dmg"
	swift package clean
