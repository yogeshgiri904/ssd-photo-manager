#!/bin/bash
set -euo pipefail

if ! xcodebuild -version >/dev/null 2>&1; then
    printf 'Full Xcode is required. Install Xcode, open it to complete setup, then run:\n' >&2
    printf 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/package-dmg.sh\n' >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/dist"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/drivelens-package.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$OUTPUT_DIR"
xcodebuild -quiet \
    -project "$PROJECT_ROOT/DriveLens.xcodeproj" \
    -scheme DriveLens \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/build" \
    -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

APP_PATH="$WORK_DIR/build/Build/Products/Release/DriveLens.app"
codesign --verify --deep --strict "$APP_PATH"
BUILT_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/DriveLens")"
for REQUIRED_ARCH in arm64 x86_64; do
    case " $BUILT_ARCHS " in
        *" $REQUIRED_ARCH "*) ;;
        *) printf 'Missing required architecture: %s\n' "$REQUIRED_ARCH" >&2; exit 1 ;;
    esac
done
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/DriveLens-$VERSION-universal.dmg"

mkdir -p "$WORK_DIR/image"
ditto "$APP_PATH" "$WORK_DIR/image/DriveLens.app"
ln -s /Applications "$WORK_DIR/image/Applications"
hdiutil create -volname DriveLens -srcfolder "$WORK_DIR/image" \
    -format UDZO "$WORK_DIR/DriveLens.dmg"
hdiutil verify "$WORK_DIR/DriveLens.dmg"
mv -f "$WORK_DIR/DriveLens.dmg" "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
printf '\nCreated: %s\n' "$DMG_PATH"
printf 'Ad-hoc signed. Not Developer ID signed or notarized. Requires macOS 14 or later.\n'
