import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Vision

nonisolated struct OCRDocumentLine: Sendable {
    let text: String
    let boundingBox: CGRect
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    let confidence: Float
    let isVertical: Bool
    let characterBoxes: [CGRect?]
}

/// Document recognition supplies vertical text and reading order unavailable in the legacy request.
@available(iOS 26.0, macOS 26.0, *)
nonisolated enum OCRDocumentRecognizer {
    static func recognize(in image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> [OCRDocumentLine] {
        try Task.checkCancellation()
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = AppLocale.ocrRecognitionLanguages.map {
            Locale.Language(identifier: $0)
        }
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        let documents = try await request.perform(on: image, orientation: orientation)
        try Task.checkCancellation()
        // Preserve the document engine's ordering, including mixed horizontal/vertical pages.
        return documents.flatMap { document in
            document.document.text.lines.compactMap { line in
                let text = line.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let isVertical = line.textDirection == .topToBottom
                let candidate = line.topCandidates(1).first
                let characterBoxes = candidate.map { candidate in
                    OCRCharacterGeometry.boxes(text: text, source: candidate.string) {
                        candidate.boundingBox(for: $0)?.boundingBox.cgRect
                    }
                } ?? []
                // Vision names corners along the text baseline. For a vertical line its
                // topLeft is the image's topRight. Convert to image-relative corner roles
                // once, so camera hit testing and highlight bands use the same geometry.
                return OCRDocumentLine(
                    text: text,
                    boundingBox: line.boundingBox.cgRect,
                    topLeft: isVertical ? line.bottomLeft.cgPoint : line.topLeft.cgPoint,
                    topRight: isVertical ? line.topLeft.cgPoint : line.topRight.cgPoint,
                    bottomRight: isVertical ? line.topRight.cgPoint : line.bottomRight.cgPoint,
                    bottomLeft: isVertical ? line.bottomRight.cgPoint : line.bottomLeft.cgPoint,
                    confidence: line.confidence,
                    isVertical: isVertical,
                    characterBoxes: characterBoxes
                )
            }
        }
    }
}

nonisolated enum OCRCharacterGeometry {
    static func boxes(text: String, source: String, box: (Range<String.Index>) -> CGRect?) -> [CGRect?] {
        guard let range = source.range(of: text) else { return [] }
        var cursor = range.lowerBound
        var result: [CGRect?] = []
        while cursor < range.upperBound {
            let end = source.index(after: cursor)
            result.append(box(cursor..<end))
            cursor = end
        }
        return result
    }
}
