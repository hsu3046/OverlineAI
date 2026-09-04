#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-credential-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcrun swiftc -swift-version 6 -default-isolation MainActor -warnings-as-errors -parse-as-library \
    "$ROOT/Overline/LLMSettings.swift" \
    "$ROOT/Tests/LegacyCredentialCleanup/Runner.swift" \
    -o "$BUILD_DIR/credential-cleanup-tests"
"$BUILD_DIR/credential-cleanup-tests"
