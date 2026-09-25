#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-widget-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
    "$ROOT/WidgetShared/WidgetData.swift" "$ROOT/Tests/Widgets/Runner.swift" \
    -o "$BUILD_DIR/widget-tests"
"$BUILD_DIR/widget-tests"
