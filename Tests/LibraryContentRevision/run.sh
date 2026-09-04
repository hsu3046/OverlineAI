#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-library-revision-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
    "$ROOT/Overline/Models.swift" \
    "$ROOT/Overline/LibraryBackup.swift" \
    "$ROOT/Overline/OCRLineJoiner.swift" \
    "$ROOT/Tests/LibraryContentRevision/Fixtures.swift" \
    "$ROOT/Tests/LibraryContentRevision/Runner.swift" \
    -o "$BUILD_DIR/library-revision-tests"

for scenario in unchanged replace same-ids reset restore failed-restore repeated-replacement; do
    "$BUILD_DIR/library-revision-tests" "$scenario"
done
