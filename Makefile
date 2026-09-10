APP_NAME := Krasp
HAL_NAME := KraspHAL
CONFIGURATION ?= release
VERSION_YEAR ?= 2026
VERSION_MINOR ?= 1
BUILD_NUMBER ?= 1
VERSION ?= $(VERSION_YEAR).$(VERSION_MINOR).$(BUILD_NUMBER)
APP_BUNDLE_ID ?= io.github.pilshchikov.krasp
HAL_BUNDLE_ID ?= io.github.pilshchikov.krasp.hal
PKG_IDENTIFIER ?= io.github.pilshchikov.krasp.installer
CODESIGN_IDENTITY ?= -
CODESIGN_FLAGS ?= --force --timestamp=none
DIST_DIR := dist
ARTIFACT_ARCH := $(shell uname -m)
PKG_NAME := $(APP_NAME)-$(VERSION)-macos-$(ARTIFACT_ARCH).pkg
BUILD_DIR := .build/$(CONFIGURATION)
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
HAL_DIR := $(BUILD_DIR)/$(HAL_NAME).driver
HAL_CONTENTS_DIR := $(HAL_DIR)/Contents
HAL_MACOS_DIR := $(HAL_CONTENTS_DIR)/MacOS
DEEPFILTER_DIR := ThirdParty/DeepFilterNet
DEEPFILTER_REPO := https://github.com/Rikorose/DeepFilterNet.git
DEEPFILTER_REF ?= d375b2d8309e0935d165700c91da9de862a99c31
HUSH_MODEL := ThirdParty/Hush/advanced_dfnet16k_model_best_onnx.tar.gz
HUSH_MODEL_URL := https://huggingface.co/weya-ai/hush/resolve/main/onnx/advanced_dfnet16k_model_best_onnx.tar.gz
DEEPFILTER_LIB := $(DEEPFILTER_DIR)/target/release/libdf.dylib

.PHONY: build app hal neural sign-app dist verify install-hal install-hal-user uninstall-hal uninstall-hal-user run clean

build:
	swift build -c $(CONFIGURATION)

app: build hal neural
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	cp "Packaging/Info.plist" "$(CONTENTS_DIR)/Info.plist"
	cp -R "$(HAL_DIR)" "$(RESOURCES_DIR)/$(HAL_NAME).driver"
	cp "$(DEEPFILTER_LIB)" "$(RESOURCES_DIR)/libdf.dylib"
	cp "$(HUSH_MODEL)" "$(RESOURCES_DIR)/advanced_dfnet16k_model_best_onnx.tar.gz"
	cp "Sources/Krasp/Resources/AppIcon.icns" "$(RESOURCES_DIR)/AppIcon.icns"
	plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleName -string "$(APP_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleDisplayName -string "$(APP_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleIdentifier -string "$(APP_BUNDLE_ID)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleVersion -string "$(VERSION)" "$(CONTENTS_DIR)/Info.plist"
	$(MAKE) sign-app

hal:
	rm -rf "$(HAL_DIR)"
	mkdir -p "$(HAL_MACOS_DIR)"
	cp "HAL/$(HAL_NAME)/Info.plist" "$(HAL_CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleIdentifier -string "$(HAL_BUNDLE_ID)" "$(HAL_CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(HAL_CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleVersion -string "$(VERSION)" "$(HAL_CONTENTS_DIR)/Info.plist"
	clang -std=c11 -Wall -Wextra -Werror -fvisibility=hidden -bundle \
		-framework CoreAudio -framework CoreFoundation \
		-IShared \
		"HAL/$(HAL_NAME)/$(HAL_NAME).c" \
		-o "$(HAL_MACOS_DIR)/$(HAL_NAME)"
	plutil -lint "$(HAL_CONTENTS_DIR)/Info.plist"
	codesign $(CODESIGN_FLAGS) --sign "$(CODESIGN_IDENTITY)" "$(HAL_DIR)"

neural:
	test -f "$(HUSH_MODEL)" || (mkdir -p "ThirdParty/Hush" && curl -L --fail -o "$(HUSH_MODEL)" "$(HUSH_MODEL_URL)")
	test -d "$(DEEPFILTER_DIR)/.git" || (rm -rf "$(DEEPFILTER_DIR)" && git clone "$(DEEPFILTER_REPO)" "$(DEEPFILTER_DIR)")
	cd "$(DEEPFILTER_DIR)" && git checkout --detach "$(DEEPFILTER_REF)"
	cd "$(DEEPFILTER_DIR)/libDF" && cargo build --release --no-default-features --features capi

sign-app:
	codesign $(CODESIGN_FLAGS) --deep --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)"
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"

dist: app
	mkdir -p "$(DIST_DIR)"
	pkgbuild --component "$(APP_DIR)" \
		--install-location "/Applications" \
		--identifier "$(PKG_IDENTIFIER)" \
		--version "$(VERSION)" \
		"$(DIST_DIR)/$(PKG_NAME)"
	shasum -a 256 "$(DIST_DIR)/$(PKG_NAME)" > "$(DIST_DIR)/$(PKG_NAME).sha256"

verify:
	swift test -c $(CONFIGURATION)
	$(MAKE) hal
	clang -std=c11 -Wall -Wextra -Werror -framework CoreAudio -framework CoreFoundation Tests/HAL/RingTests.c -o "$(BUILD_DIR)/KraspRingTests"
	"$(BUILD_DIR)/KraspRingTests"
	plutil -lint Packaging/Info.plist HAL/$(HAL_NAME)/Info.plist

install-hal: hal
	sudo rm -rf "/Library/Audio/Plug-Ins/HAL/$(HAL_NAME).driver"
	sudo cp -R "$(HAL_DIR)" "/Library/Audio/Plug-Ins/HAL/$(HAL_NAME).driver"
	sudo killall coreaudiod

install-hal-user: hal
	mkdir -p "$$HOME/Library/Audio/Plug-Ins/HAL"
	rm -rf "$$HOME/Library/Audio/Plug-Ins/HAL/$(HAL_NAME).driver"
	cp -R "$(HAL_DIR)" "$$HOME/Library/Audio/Plug-Ins/HAL/$(HAL_NAME).driver"
	killall coreaudiod 2>/dev/null || true

uninstall-hal:
	sudo rm -rf "/Library/Audio/Plug-Ins/HAL/$(HAL_NAME).driver"
	sudo killall coreaudiod

uninstall-hal-user:
	rm -rf "$$HOME/Library/Audio/Plug-Ins/HAL/$(HAL_NAME).driver"
	killall coreaudiod 2>/dev/null || true

run: app
	open "$(APP_DIR)"

clean:
	rm -rf .build
