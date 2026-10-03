#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build
swiftc Sources/SnipBeam/Capture/CaptureRegion.swift \
    Sources/SnipBeam/Capture/CoordinateConverter.swift Sources/SnipBeam/Preview/FrameRenderer.swift \
    Tests/CoordinateChecks.swift \
    -o build/coordinate-checks
build/coordinate-checks
