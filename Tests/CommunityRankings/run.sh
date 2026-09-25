#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-ranking-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
    "$ROOT/Overline/CommunityModels.swift" \
    "$ROOT/Overline/OverlineAPIClient.swift" \
    "$ROOT/Overline/CommunityViewModel.swift" \
    "$ROOT/Tests/CommunityRankings/Fixtures.swift" \
    "$ROOT/Tests/CommunityRankings/Runner.swift" \
    -o "$BUILD_DIR/ranking-tests"
"$BUILD_DIR/ranking-tests"
