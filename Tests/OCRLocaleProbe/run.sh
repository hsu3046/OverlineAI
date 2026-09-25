#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-ocr-probe.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
OUTPUT="${1:-$BUILD_DIR/results}"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/Overline/OCRLineJoiner.swift" "$ROOT/Tests/OCRLocaleProbe/Runner.swift" \
    -o "$BUILD_DIR/ocr-probe"
"$BUILD_DIR/ocr-probe" "$OUTPUT"
