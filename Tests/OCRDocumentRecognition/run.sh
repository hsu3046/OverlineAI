#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzogak-document-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
python3 - "$ROOT" "$BUILD_DIR" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Overline/CameraTextScanner.swift').read_text()
# Compile the production assembler verbatim rather than a copied implementation.
boundary = source[source.index('nonisolated enum OCRBoundaryTrimming:'):source.index('enum OCRPageMarginMetadataFilter')]
assembler = source[source.index('struct OCRTextAssembler {'):source.index('fileprivate enum CameraVisionCoordinateTransform:')]
(Path(sys.argv[2]) / 'Assembler.swift').write_text('import Foundation\n' + boundary + assembler)
PY
xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/Overline/AppLocale.swift" \
    "$ROOT/Overline/OCRDocumentRecognizer.swift" "$ROOT/Overline/OCRLineJoiner.swift" \
    "$ROOT/Overline/OCRVerticalSelection.swift" "$BUILD_DIR/Assembler.swift" \
    "$ROOT/Overline/OCRHighlighterGesture.swift" \
    "$ROOT/Overline/OCRSentenceSelector.swift" "$ROOT/Tests/OCRDocumentRecognition/SentenceTests.swift" \
    "$ROOT/Tests/OCRDocumentRecognition/Fixtures.swift" \
    "$ROOT/Tests/OCRDocumentRecognition/Runner.swift" -o "$BUILD_DIR/tests"
"$BUILD_DIR/tests" "$ROOT" "$@"
