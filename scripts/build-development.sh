#!/bin/bash
# Local build using the installed SDK and existing compiled assets. No installation or library access.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/drivelens-development.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
APP_NAME=DriveLens-Polished
DEFINES=(-D LOCAL_DEVELOPMENT)
if [[ "${1:-}" == --preview ]]; then
    APP_NAME=DriveLens-DesignPreview
    DEFINES=(-D DESIGN_PREVIEW)
fi
ASSET_APP=.derivedData/Build/Products/Debug/DriveLens.app
if [[ ! -f "$ASSET_APP/Contents/Resources/Assets.car" ]]; then
    printf 'An existing Xcode build is required for compiled app assets.\n' >&2
    exit 1
fi
SOURCES=()
while IFS= read -r path; do SOURCES+=("$path"); done < <(find DriveLens -name '*.swift' | sort)
if [[ "${1:-}" == --preview ]]; then SOURCES+=(LocalSupport/Tests/DesignPreviewState.swift); fi
swiftc -O -whole-module-optimization "${DEFINES[@]}" \
    -sdk "${DESIGN_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}" \
    -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "${TMPDIR:-/tmp}/drivelens-development-cache" \
    "${SOURCES[@]}" -lsqlite3 -o "$BUILD_DIR/DriveLens"
APP_PATH="dist/$APP_NAME.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/DriveLens" "$APP_PATH/Contents/MacOS/DriveLens"
cp "$ASSET_APP/Contents/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ASSET_APP/Contents/Resources/Assets.car" "$APP_PATH/Contents/Resources/Assets.car"
cp "$ASSET_APP/Contents/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ "${1:-}" == --preview ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.DriveLens.DesignPreview' "$APP_PATH/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName DriveLens Design Preview' "$APP_PATH/Contents/Info.plist"
fi
codesign --force --sign - --entitlements DriveLens/DriveLens.entitlements "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf 'Built %s/%s (local ad-hoc signed development bundle)\n' "$PWD" "$APP_PATH"
