#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/SnipBeam.app}"
IDENTITY="${SIGNING_IDENTITY:--}"
OPTIONS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
    OPTIONS+=(--options runtime --timestamp)
fi
codesign "${OPTIONS[@]}" \
    --entitlements "$ROOT/Resources/SnipBeam.entitlements" "$APP"
codesign --verify --strict "$APP"
