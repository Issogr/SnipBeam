#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/build/SnipBeam.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SnipBeam" "$APP/Contents/MacOS/SnipBeam"
cp Resources/Info.plist "$APP/Contents/Info.plist"

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
"$ROOT/scripts/sign-app.sh" "$APP"
printf 'Built %s\n' "$APP"
