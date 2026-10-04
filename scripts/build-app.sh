#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "${BUILD_NUMBER:-}" && ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    printf 'BUILD_NUMBER must be a positive integer.\n' >&2
    exit 2
fi

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="$ROOT/build/SnipBeam.app"
# Always package a fresh bundle so removed resources cannot survive into a release.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SnipBeam" "$APP/Contents/MacOS/SnipBeam"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [[ ! -f Resources/AppIcon.icns ]]; then
    swift scripts/make-icon.swift "$ROOT/build/AppIcon.iconset"
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
for resource in Resources/*; do
    case "$resource" in
        *.plist|*.entitlements) ;;
        *) cp -R "$resource" "$APP/Contents/Resources/" ;;
    esac
done
cp LICENSE "$APP/Contents/Resources/LICENSE"
"$ROOT/scripts/sign-app.sh" "$APP"
printf 'Built %s\n' "$APP"
