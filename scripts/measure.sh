#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -B "$ROOT/scripts/live-check.py" --performance-test
