import UIKit
import Vision

enum OCRTextRecognizerError: LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "이미지를 읽을 수 없습니다."
        case .noTextFound:
            "이미지에서 글자를 찾지 못했습니다."
        }
    }
}

struct OCRTextRecognitionResult {
    let text: String
    let lineCount: Int
    let inferredPageReference: String?
}

struct OCRTextRecognizer {
    func recognizeText(in image: UIImage) async throws -> String {
        try await recognizeTextResult(in: image).text
    }

    func recognizeTextResult(in image: UIImage) async throws -> OCRTextRecognitionResult {
        guard let cgImage = image.cgImage else {
            throw OCRTextRecognizerError.invalidImage
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )

            try handler.perform([request])

            // Preserve Vision's reading order. Geometry-only sorting can scramble rotated or skewed book pages.
            let recognizedLines = (request.results ?? [])
                .compactMap { observation -> OCRLine? in
                    guard let text = observation.topCandidates(1).first?.string.trimmed, !text.isEmpty else {
                        return nil
                    }
                    return OCRLine(text: text, box: observation.boundingBox)
                }

            let lines = recognizedLines.map(\.text)

            let text = lines.joined(separator: " ").trimmedForOCR
            guard !text.isEmpty else {
                throw OCRTextRecognizerError.noTextFound
            }

            let inferredPageReference = PageReferenceInference.inferredPageReference(
                from: recognizedLines.map {
                    PageReferenceLine(text: $0.text, boundingBox: $0.box)
                }
            )

            return OCRTextRecognitionResult(
                text: text,
                lineCount: lines.count,
                inferredPageReference: inferredPageReference
            )
        }
        .value
    }
}

private struct OCRLine {
    let text: String
    let box: CGRect
}

private extension String {
    nonisolated var trimmedForOCR: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
