#!/bin/bash
# Universal local package using the installed Swift SDK and existing compiled app assets.
# No installation, catalogue access, signing-account access, or third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
BUILD_DIR="${PACKAGE_RESUME_DIR:-}"
if [[ -z "$BUILD_DIR" ]]; then BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/drivelens-final-package.XXXXXX"); fi
MOUNT_DIR=""
cleanup() {
    local result=$?
    if [[ -n "$MOUNT_DIR" ]]; then hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true; fi
    if [[ "$result" == 0 ]]; then
        rm -rf "$BUILD_DIR"
    else
        printf 'Build artifacts retained at %s\n' "$BUILD_DIR" >&2
    fi
}
trap cleanup EXIT
verify_architectures() {
    local architectures
    architectures="$(lipo -archs "$1")"
    case " $architectures " in *" arm64 "*) ;; *) return 1 ;; esac
    case " $architectures " in *" x86_64 "*) ;; *) return 1 ;; esac
}
SDK="${DESIGN_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
ASSET_APP="$PROJECT_ROOT/.derivedData/Build/Products/Debug/DriveLens.app"
test -f "$ASSET_APP/Contents/Resources/Assets.car"
mkdir -p dist "$BUILD_DIR/image/DriveLens.app/Contents/MacOS" "$BUILD_DIR/image/DriveLens.app/Contents/Resources"
# Freeze source inputs so the architectures always contain the same revision.
if [[ -z "${PACKAGE_RESUME_DIR:-}" ]]; then
ditto DriveLens "$BUILD_DIR/source/DriveLens"
SOURCES=()
while IFS= read -r path; do SOURCES+=("$path"); done < <(find "$BUILD_DIR/source/DriveLens" -name '*.swift' | sort)
for ARCH in arm64 x86_64; do
    printf 'Compiling optimized %s executable…\n' "$ARCH"
    swiftc -O -whole-module-optimization \
        -sdk "$SDK" -target "$ARCH-apple-macos14.0" \
        -module-cache-path "${TMPDIR:-/tmp}/drivelens-final-cache-$ARCH" \
        "${SOURCES[@]}" -lsqlite3 -o "$BUILD_DIR/DriveLens-$ARCH"
done
fi
APP_PATH="$BUILD_DIR/image/DriveLens.app"
lipo -create "$BUILD_DIR/DriveLens-arm64" "$BUILD_DIR/DriveLens-x86_64" -output "$APP_PATH/Contents/MacOS/DriveLens"
cp "$ASSET_APP/Contents/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ASSET_APP/Contents/Resources/Assets.car" "$APP_PATH/Contents/Resources/Assets.car"
cp "$ASSET_APP/Contents/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - --entitlements "$BUILD_DIR/source/DriveLens/DriveLens.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
verify_architectures "$APP_PATH/Contents/MacOS/DriveLens"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
DMG_NAME="DriveLens-$VERSION-universal-final.dmg"
GUIDE_PATH="$PROJECT_ROOT/LocalSupport/output/pdf/DriveLens-User-Guide.pdf"
if [[ -f "$GUIDE_PATH" ]]; then
    cp "$GUIDE_PATH" "$BUILD_DIR/image/DriveLens User Guide.pdf"
fi
if [[ -L "$BUILD_DIR/image/Applications" ]]; then
    test "$(readlink "$BUILD_DIR/image/Applications")" = /Applications
else
    ln -s /Applications "$BUILD_DIR/image/Applications"
fi
hdiutil create -ov -volname DriveLens -srcfolder "$BUILD_DIR/image" -format UDZO "$BUILD_DIR/$DMG_NAME"
hdiutil verify "$BUILD_DIR/$DMG_NAME"
mkdir -p "$BUILD_DIR/mounted"
MOUNT_DIR="$BUILD_DIR/mounted"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$BUILD_DIR/$DMG_NAME"
codesign --verify --deep --strict "$MOUNT_DIR/DriveLens.app"
verify_architectures "$MOUNT_DIR/DriveLens.app/Contents/MacOS/DriveLens"
cmp "$APP_PATH/Contents/MacOS/DriveLens" "$MOUNT_DIR/DriveLens.app/Contents/MacOS/DriveLens"
test "$(readlink "$MOUNT_DIR/Applications")" = /Applications
if [[ -f "$GUIDE_PATH" ]]; then
    cmp "$GUIDE_PATH" "$MOUNT_DIR/DriveLens User Guide.pdf"
fi
hdiutil detach "$MOUNT_DIR"
MOUNT_DIR=""
# Refuse to label a package current if source files changed during compilation.
diff -qr DriveLens "$BUILD_DIR/source/DriveLens"
mv -f "$BUILD_DIR/$DMG_NAME" "dist/$DMG_NAME"
(cd dist && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
printf '\nCreated %s/dist/%s\n' "$PROJECT_ROOT" "$DMG_NAME"
printf 'Verified: arm64 + x86_64, signed app, DMG integrity, mounted contents, Applications shortcut.\n'
printf 'Requires macOS 14+. Ad-hoc signed; not Developer ID signed or notarized.\n'
