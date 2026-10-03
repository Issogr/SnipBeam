#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/build-app.sh
swiftc -parse-as-library Tests/PerformanceFixture.swift -o build/performance-fixture
build/performance-fixture &
FIXTURE_PID=$!
trap 'kill "$FIXTURE_PID" 2>/dev/null || true' EXIT
sleep 1
SNIPBEAM_SANDBOX_PROBE="$ROOT/Package.swift" \
    build/SnipBeam.app/Contents/MacOS/SnipBeam --performance-test
