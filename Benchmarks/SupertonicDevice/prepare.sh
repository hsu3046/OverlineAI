#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GENERATED_DIR="$ROOT_DIR/Generated"
ONNX_DIR="$GENERATED_DIR/onnx"
VOICE_DIR="$GENERATED_DIR/voice_styles"

SUPERTONIC_COMMIT="7e2804f96016a7028cb1ed627353c61c1e9dd281"
MODEL_REVISION="3cadd1ee6394adea1bd021217a0e650ede09a323"

mkdir -p "$ONNX_DIR" "$VOICE_DIR"

download() {
    url=$1
    destination=$2
    expected_size=$3

    if [ -f "$destination" ] && [ "$(wc -c < "$destination" | tr -d ' ')" = "$expected_size" ]; then
        printf 'Already prepared: %s\n' "$(basename "$destination")"
        return
    fi

    temporary_file="${destination}.download"
    rm -f "$temporary_file"
    printf 'Downloading: %s\n' "$(basename "$destination")"
    curl --fail --location --retry 3 --output "$temporary_file" "$url"

    actual_size=$(wc -c < "$temporary_file" | tr -d ' ')
    if [ "$actual_size" != "$expected_size" ]; then
        rm -f "$temporary_file"
        printf 'Size mismatch for %s: expected %s, received %s\n' \
            "$(basename "$destination")" "$expected_size" "$actual_size" >&2
        exit 1
    fi

    mv "$temporary_file" "$destination"
}

download \
    "https://raw.githubusercontent.com/supertone-inc/supertonic/$SUPERTONIC_COMMIT/swift/Sources/Helper.swift" \
    "$GENERATED_DIR/Helper.swift" \
    32254

MODEL_BASE="https://huggingface.co/Supertone/supertonic-3/resolve/$MODEL_REVISION"
download "$MODEL_BASE/onnx/duration_predictor.onnx?download=true" "$ONNX_DIR/duration_predictor.onnx" 3700147
download "$MODEL_BASE/onnx/text_encoder.onnx?download=true" "$ONNX_DIR/text_encoder.onnx" 36416150
download "$MODEL_BASE/onnx/vector_estimator.onnx?download=true" "$ONNX_DIR/vector_estimator.onnx" 256534781
download "$MODEL_BASE/onnx/vocoder.onnx?download=true" "$ONNX_DIR/vocoder.onnx" 101424195
download "$MODEL_BASE/onnx/tts.json?download=true" "$ONNX_DIR/tts.json" 8253
download "$MODEL_BASE/onnx/unicode_indexer.json?download=true" "$ONNX_DIR/unicode_indexer.json" 277676
download "$MODEL_BASE/voice_styles/F1.json?download=true" "$VOICE_DIR/F1.json" 292046
download "$MODEL_BASE/voice_styles/F2.json?download=true" "$VOICE_DIR/F2.json" 292423
download "$MODEL_BASE/voice_styles/F3.json?download=true" "$VOICE_DIR/F3.json" 290794
download "$MODEL_BASE/voice_styles/F4.json?download=true" "$VOICE_DIR/F4.json" 291808
download "$MODEL_BASE/voice_styles/F5.json?download=true" "$VOICE_DIR/F5.json" 291479
download "$MODEL_BASE/voice_styles/M1.json?download=true" "$VOICE_DIR/M1.json" 291748
download "$MODEL_BASE/voice_styles/M2.json?download=true" "$VOICE_DIR/M2.json" 292055
download "$MODEL_BASE/voice_styles/M3.json?download=true" "$VOICE_DIR/M3.json" 290198
download "$MODEL_BASE/voice_styles/M4.json?download=true" "$VOICE_DIR/M4.json" 291522
download "$MODEL_BASE/voice_styles/M5.json?download=true" "$VOICE_DIR/M5.json" 291469

if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'XcodeGen is required. Install it with: brew install xcodegen\n' >&2
    exit 1
fi

cd "$ROOT_DIR"
xcodegen generate
printf '\nReady: %s\n' "$ROOT_DIR/SupertonicDeviceBenchmark.xcodeproj"
