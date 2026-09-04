#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-backup-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcrun swiftc -swift-version 6 -parse-as-library \
    "$ROOT/Overline/LibraryBackup.swift" \
    "$ROOT/Tests/LibraryBackupCodec/Fixtures.swift" \
    "$ROOT/Tests/LibraryBackupCodec/Runner.swift" \
    -o "$BUILD_DIR/backup-codec-tests"
"$BUILD_DIR/backup-codec-tests"
