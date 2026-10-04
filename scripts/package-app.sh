#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/build-app.sh
test "$(lipo -archs build/SnipBeam.app/Contents/MacOS/SnipBeam)" = arm64
ARCHIVE="$ROOT/build/SnipBeam-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent build/SnipBeam.app "$ARCHIVE"

# Check the actual downloadable artifact, including executable permissions and signature.
CHECK_DIR="$(mktemp -d "$ROOT/build/package-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k "$ARCHIVE" "$CHECK_DIR"
test -x "$CHECK_DIR/SnipBeam.app/Contents/MacOS/SnipBeam"
codesign --verify --strict --all-architectures "$CHECK_DIR/SnipBeam.app"
cd "$ROOT/build"
shasum -a 256 SnipBeam-macos-arm64.zip > SnipBeam-macos-arm64.zip.sha256
printf 'Packaged %s\n' "$ARCHIVE"
