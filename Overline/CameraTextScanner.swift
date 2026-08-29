@preconcurrency import AVFoundation
import CoreImage
import Observation
import OSLog
import SwiftUI
import UIKit
@preconcurrency import Vision

nonisolated private let cameraLifecycleLogger = Logger(subsystem: "aib.Overline", category: "CameraLifecycle")

struct CameraRecognizedTextLine: Identifiable, Hashable {
    let id: String
    let text: String
    let boundingBox: CGRect
    let quadrilateral: CameraTextQuadrilateral?
    let confidence: VNConfidence
    let readingIndex: Int

    nonisolated init(
        id: String? = nil,
        text: String,
        boundingBox: CGRect,
        quadrilateral: CameraTextQuadrilateral? = nil,
        confidence: VNConfidence,
        readingIndex: Int = .max
    ) {
        self.id = id ?? Self.stableID(text: text, boundingBox: boundingBox)
        self.text = text
        self.boundingBox = boundingBox
        self.quadrilateral = quadrilateral
        self.confidence = confidence
        self.readingIndex = readingIndex
    }

    private nonisolated static func stableID(text: String, boundingBox: CGRect) -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let x = Int((boundingBox.minX * 1000).rounded())
        let y = Int((boundingBox.midY * 1000).rounded())
        let width = Int((boundingBox.width * 1000).rounded())
        return "\(normalizedText)|\(x)|\(y)|\(width)"
    }

    func displayRect(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> CGRect {
        CameraVisionGeometry.displayRect(
            for: boundingBox,
            in: size,
            videoAspectRatio: videoAspectRatio
        )
    }

    func displaySamplePoints(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> [CGPoint] {
        guard let corners = quadrilateral?.displayCorners(in: size, videoAspectRatio: videoAspectRatio), corners.count == 4 else {
            return displayRect(in: size, videoAspectRatio: videoAspectRatio).samplePoints
        }

        let topMidpoint = midpoint(corners[0], corners[1])
        let rightMidpoint = midpoint(corners[1], corners[2])
        let bottomMidpoint = midpoint(corners[2], corners[3])
        let leftMidpoint = midpoint(corners[3], corners[0])
        let center = midpoint(topMidpoint, bottomMidpoint)
        return corners + [topMidpoint, rightMidpoint, bottomMidpoint, leftMidpoint, center]
    }

    func displayThickness(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> CGFloat {
        guard let corners = quadrilateral?.displayCorners(in: size, videoAspectRatio: videoAspectRatio), corners.count == 4 else {
            return displayRect(in: size, videoAspectRatio: videoAspectRatio).height
        }

        let leftHeight = hypot(corners[0].x - corners[3].x, corners[0].y - corners[3].y)
        let rightHeight = hypot(corners[1].x - corners[2].x, corners[1].y - corners[2].y)
        return max((leftHeight + rightHeight) / 2, 1)
    }

    private func midpoint(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (firstPoint.x + secondPoint.x) / 2,
            y: (firstPoint.y + secondPoint.y) / 2
        )
    }

    fileprivate nonisolated func applying(_ transform: CameraVisionCoordinateTransform) -> CameraRecognizedTextLine {
        CameraRecognizedTextLine(
            id: id,
            text: text,
            boundingBox: transform.rect(boundingBox),
            quadrilateral: quadrilateral.map(transform.quadrilateral),
            confidence: confidence,
            readingIndex: readingIndex
        )
    }
}

struct CameraTextQuadrilateral: Hashable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    nonisolated init(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    nonisolated init(rectangle: VNRectangleObservation) {
        self.init(
            topLeft: rectangle.topLeft,
            topRight: rectangle.topRight,
            bottomRight: rectangle.bottomRight,
            bottomLeft: rectangle.bottomLeft
        )
    }

    func displayCorners(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft].map {
            CameraVisionGeometry.displayPoint(
                for: $0,
                in: size,
                videoAspectRatio: videoAspectRatio
            )
        }
    }
}

struct CameraDetectedPage: Hashable {
    let boundingBox: CGRect
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    nonisolated init(
        boundingBox: CGRect,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        self.boundingBox = boundingBox
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    func displayPath(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> Path {
        let points = displayCorners(in: size, videoAspectRatio: videoAspectRatio)

        return Path { path in
            guard let firstPoint = points.first else { return }
            path.move(to: firstPoint)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }

    func displayCorners(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft].map {
            CameraVisionGeometry.displayPoint(
                for: $0,
                in: size,
                videoAspectRatio: videoAspectRatio
            )
        }
    }

    nonisolated var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

private enum CameraVisionGeometry {
    static func displayRect(
        for boundingBox: CGRect,
        in size: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGRect {
        let aspectFillRect = aspectFillRect(
            for: CGSize(width: videoAspectRatio, height: 1),
            in: size
        )
        let rect = CGRect(
            x: boundingBox.minX * size.width,
            y: (1 - boundingBox.maxY) * size.height,
            width: boundingBox.width * size.width,
            height: boundingBox.height * size.height
        )

        return CGRect(
            x: aspectFillRect.minX + rect.minX * aspectFillRect.width / max(size.width, 1),
            y: aspectFillRect.minY + rect.minY * aspectFillRect.height / max(size.height, 1),
            width: rect.width * aspectFillRect.width / max(size.width, 1),
            height: rect.height * aspectFillRect.height / max(size.height, 1)
        )
    }

    static func displayPoint(
        for normalizedPoint: CGPoint,
        in size: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGPoint {
        let aspectFillRect = aspectFillRect(
            for: CGSize(width: videoAspectRatio, height: 1),
            in: size
        )
        let imagePoint = CGPoint(
            x: normalizedPoint.x * size.width,
            y: (1 - normalizedPoint.y) * size.height
        )

        return CGPoint(
            x: aspectFillRect.minX + imagePoint.x * aspectFillRect.width / max(size.width, 1),
            y: aspectFillRect.minY + imagePoint.y * aspectFillRect.height / max(size.height, 1)
        )
    }

    private static func aspectFillRect(for sourceSize: CGSize, in targetSize: CGSize) -> CGRect {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            targetSize.width > 0,
            targetSize.height > 0
        else {
            return CGRect(origin: .zero, size: targetSize)
        }

        let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let fittedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return CGRect(
            x: (targetSize.width - fittedSize.width) / 2,
            y: (targetSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

fileprivate nonisolated enum CameraPageDetection {
    static func bestCandidate(
        from observations: [VNRectangleObservation],
        coordinateTransform: CameraVisionCoordinateTransform
    ) -> CameraDetectedPage? {
        observations
            .map {
                coordinateTransform.page(CameraDetectedPage(
                    boundingBox: $0.boundingBox,
                    topLeft: $0.topLeft,
                    topRight: $0.topRight,
                    bottomRight: $0.bottomRight,
                    bottomLeft: $0.bottomLeft
                ))
            }
            .filter(isUsableBookPage)
            .max { pageScore($0) < pageScore($1) }
    }

    static func inferredPage(from lines: [CameraRecognizedTextLine]) -> CameraDetectedPage? {
        let bodyRects = lines
            .map(\.boundingBox)
            .filter { rect in
                rect.width >= 0.16 && rect.height >= 0.006
            }

        guard bodyRects.count >= 4 else {
            return nil
        }

        let unionRect = bodyRects.dropFirst().reduce(bodyRects[0]) { partialResult, rect in
            partialResult.union(rect)
        }
        let medianHeight = median(bodyRects.map(\.height))
        let expandedBox = CGRect(
            x: unionRect.minX - max(0.055, medianHeight * 2.0),
            y: unionRect.minY - max(0.070, medianHeight * 2.5),
            width: unionRect.width + max(0.110, medianHeight * 4.0),
            height: unionRect.height + max(0.140, medianHeight * 5.0)
        )
        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        .standardized

        guard expandedBox.width >= 0.24, expandedBox.height >= 0.18 else {
            return nil
        }

        return CameraDetectedPage(
            boundingBox: expandedBox,
            topLeft: CGPoint(x: expandedBox.minX, y: expandedBox.maxY),
            topRight: CGPoint(x: expandedBox.maxX, y: expandedBox.maxY),
            bottomRight: CGPoint(x: expandedBox.maxX, y: expandedBox.minY),
            bottomLeft: CGPoint(x: expandedBox.minX, y: expandedBox.minY)
        )
    }

    private static func isUsableBookPage(_ page: CameraDetectedPage) -> Bool {
        let box = page.boundingBox.standardized
        let area = box.width * box.height
        let aspectRatio = box.width / max(box.height, 0.001)

        guard area >= 0.10, area <= 0.98 else { return false }
        guard box.width >= 0.26, box.height >= 0.24 else { return false }
        guard aspectRatio >= 0.32, aspectRatio <= 2.15 else { return false }
        guard abs(box.midX - 0.5) <= 0.48, abs(box.midY - 0.5) <= 0.48 else { return false }
        return true
    }

    private static func pageScore(_ page: CameraDetectedPage) -> CGFloat {
        let box = page.boundingBox.standardized
        let centerPenalty = abs(box.midX - 0.5) * 0.18 + abs(box.midY - 0.5) * 0.12
        let aspectPenalty = abs((box.width / max(box.height, 0.001)) - 0.72) * 0.05
        return page.area - centerPenalty - aspectPenalty
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sortedValues = values.sorted()
        guard !sortedValues.isEmpty else { return 0 }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }

        return sortedValues[middle]
    }
}

private extension CGRect {
    var samplePoints: [CGPoint] {
        [
            CGPoint(x: minX, y: minY),
            CGPoint(x: midX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: midY),
            CGPoint(x: midX, y: midY),
            CGPoint(x: maxX, y: midY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: midX, y: maxY),
            CGPoint(x: maxX, y: maxY)
        ]
    }
}

private extension CGImagePropertyOrientation {
    nonisolated var debugName: String {
        switch self {
        case .up:
            return "up"
        case .upMirrored:
            return "upMirrored"
        case .down:
            return "down"
        case .downMirrored:
            return "downMirrored"
        case .left:
            return "left"
        case .leftMirrored:
            return "leftMirrored"
        case .right:
            return "right"
        case .rightMirrored:
            return "rightMirrored"
        @unknown default:
            return "unknown"
        }
    }
}

struct OCRTextAssembler {
    private struct LayoutMetrics {
        let bodyLeft: CGFloat
        let bodyRight: CGFloat
        let medianHeight: CGFloat
        let medianWidth: CGFloat
        let medianGap: CGFloat
    }

    private struct Document {
        let text: String
        let lineSpans: [LineSpan]
    }

    private struct LineSpan {
        let line: CameraRecognizedTextLine
        let start: Int
        let end: Int
    }

    private struct SentenceSpan {
        let start: Int
        let end: Int
        let isClosed: Bool
    }

    let pageLines: [CameraRecognizedTextLine]
    let selectedLines: [CameraRecognizedTextLine]
    var trimsBoundaryFragments = true

    func assembledText() -> String {
        let selectedLines = sortedUnique(selectedLines)
        guard !selectedLines.isEmpty else { return "" }

        let selectedIDs = Set(selectedLines.map(\.id))
        let sourceLines = sortedUnique(pageLines).isEmpty ? selectedLines : sortedUnique(pageLines)
        let document = document(from: sourceLines)
        let selectedRanges = document.lineSpans
            .filter { selectedIDs.contains($0.line.id) }
            .map { $0.start..<$0.end }

        guard
            !document.text.isEmpty,
            !selectedRanges.isEmpty,
            let selectedStart = selectedRanges.map(\.lowerBound).min(),
            let selectedEnd = selectedRanges.map(\.upperBound).max()
        else {
            return fallbackText(from: selectedLines)
        }

        let sentenceSpans = sentenceSpans(in: document.text)
        var includedSpans = sentenceSpans.filter {
            shouldInclude(
                sentence: $0,
                selectedRanges: selectedRanges,
                selectedStart: selectedStart,
                selectedEnd: selectedEnd
            )
        }
        if trimsBoundaryFragments {
            includedSpans = trimmingBoundaryFragments(includedSpans, documentText: document.text)
        }

        guard !includedSpans.isEmpty else {
            return fallbackText(from: selectedLines)
        }

        return joinedText(for: includedSpans, in: document.text)
    }

    private func fallbackText(from lines: [CameraRecognizedTextLine]) -> String {
        cleanedOutput(document(from: lines).text)
    }

    private func document(from lines: [CameraRecognizedTextLine]) -> Document {
        let lines = sortedUnique(lines)
        guard !lines.isEmpty else {
            return Document(text: "", lineSpans: [])
        }

        let metrics = layoutMetrics(for: lines)
        var text = ""
        var offset = 0
        var spans: [LineSpan] = []

        for (index, line) in lines.enumerated() {
            let lineText = normalizedLineText(line.text)
            guard !lineText.isEmpty else { continue }

            if index > 0 {
                let separator = separator(
                    between: lines[index - 1],
                    and: line,
                    metrics: metrics
                )
                text += separator
                offset += separator.count
            }

            let start = offset
            text += lineText
            offset += lineText.count
            spans.append(LineSpan(line: line, start: start, end: offset))
        }

        return Document(text: text, lineSpans: spans)
    }

    private func separator(
        between previousLine: CameraRecognizedTextLine,
        and currentLine: CameraRecognizedTextLine,
        metrics: LayoutMetrics
    ) -> String {
        if shouldPreserveLineBreak(
            between: previousLine,
            and: currentLine,
            metrics: metrics
        ) {
            return "\n"
        }

        return OCRLineJoiner.inlineSeparator(
            between: normalizedLineText(previousLine.text),
            and: normalizedLineText(currentLine.text)
        )
    }

    private func shouldPreserveLineBreak(
        between previousLine: CameraRecognizedTextLine,
        and currentLine: CameraRecognizedTextLine,
        metrics: LayoutMetrics
    ) -> Bool {
        let verticalGap = max(previousLine.boundingBox.minY - currentLine.boundingBox.maxY, 0)
        let trailingRoom = metrics.bodyRight - previousLine.boundingBox.maxX
        let previousLineIsShort = trailingRoom > max(metrics.medianHeight * 2.4, 0.08)
            || previousLine.boundingBox.width < metrics.medianWidth * 0.72
        let currentLineIsIndented = currentLine.boundingBox.minX - metrics.bodyLeft > max(metrics.medianHeight * 1.35, 0.035)
        let gapIsLarge = verticalGap > max(metrics.medianHeight * 0.90, metrics.medianGap * 1.65)
        let previousLineIsClosed = Self.endsAtSentenceBoundary(previousLine.text)

        if gapIsLarge {
            return true
        }

        if currentLineIsIndented && (previousLineIsClosed || previousLineIsShort) {
            return true
        }

        if previousLineIsClosed && previousLineIsShort {
            return true
        }

        return false
    }

    private func shouldInclude(
        sentence: SentenceSpan,
        selectedRanges: [Range<Int>],
        selectedStart: Int,
        selectedEnd: Int
    ) -> Bool {
        let overlap = overlapLength(of: sentence.start..<sentence.end, with: selectedRanges)
        guard overlap > 0 else { return false }

        if sentence.start >= selectedStart && sentence.end <= selectedEnd {
            return true
        }

        let sentenceLength = max(sentence.end - sentence.start, 1)
        let overlapRatio = Double(overlap) / Double(sentenceLength)
        return overlapRatio >= 0.32
    }

    private func trimmingBoundaryFragments(_ spans: [SentenceSpan], documentText: String) -> [SentenceSpan] {
        var spans = spans

        if
            spans.count > 1,
            let firstSpan = spans.first,
            isLeadingTailFragment(substring(in: documentText, from: firstSpan.start, to: firstSpan.end))
        {
            spans.removeFirst()
        }

        if
            spans.count > 1,
            let lastSpan = spans.last,
            !lastSpan.isClosed,
            isTrailingOpenFragment(substring(in: documentText, from: lastSpan.start, to: lastSpan.end))
        {
            spans.removeLast()
        }

        return spans
    }

    private func isLeadingTailFragment(_ text: String) -> Bool {
        normalizedLineText(text)
            .range(
                of: #"^["“”‘’']?(?:거야|거지|거다|말이다|것이다|것이었다)[.!?。！？]["”’']?$"#,
                options: .regularExpression
            ) != nil
    }

    private func isTrailingOpenFragment(_ text: String) -> Bool {
        let trimmedText = normalizedLineText(text)
        guard !trimmedText.isEmpty else { return false }
        let comparableLength = comparable(trimmedText).count
        let startsWithQuote = trimmedText.first.map { "\"“‘'".contains($0) } ?? false
        return startsWithQuote || comparableLength <= 10
    }

    private func joinedText(for spans: [SentenceSpan], in documentText: String) -> String {
        var output = ""
        var previousEnd: Int?

        for span in spans {
            if let previousEnd {
                let gap = substring(in: documentText, from: previousEnd, to: span.start)
                output += gap.contains("\n") ? "\n" : " "
            }

            output += substring(in: documentText, from: span.start, to: span.end)
            previousEnd = span.end
        }

        return cleanedOutput(output)
    }

    private func sentenceSpans(in text: String) -> [SentenceSpan] {
        let characters = Array(text)
        var spans: [SentenceSpan] = []
        var sentenceStart = 0
        var index = 0

        while index < characters.count {
            if Self.isSentenceClosingPunctuation(characters[index]) {
                var sentenceEnd = index + 1
                while sentenceEnd < characters.count, Self.isClosingQuote(characters[sentenceEnd]) {
                    sentenceEnd += 1
                }

                let trimmedStart = firstNonWhitespaceIndex(in: characters, from: sentenceStart, to: sentenceEnd)
                if trimmedStart < sentenceEnd {
                    spans.append(SentenceSpan(start: trimmedStart, end: sentenceEnd, isClosed: true))
                }

                sentenceStart = firstNonWhitespaceIndex(in: characters, from: sentenceEnd, to: characters.count)
                index = sentenceStart
                continue
            }

            index += 1
        }

        let trimmedStart = firstNonWhitespaceIndex(in: characters, from: sentenceStart, to: characters.count)
        if trimmedStart < characters.count {
            spans.append(SentenceSpan(start: trimmedStart, end: characters.count, isClosed: false))
        }

        return spans
    }

    private func firstNonWhitespaceIndex(in characters: [Character], from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, characters[index].isWhitespace {
            index += 1
        }
        return index
    }

    private func overlapLength(of range: Range<Int>, with selectedRanges: [Range<Int>]) -> Int {
        selectedRanges.reduce(0) { partial, selectedRange in
            let lowerBound = max(range.lowerBound, selectedRange.lowerBound)
            let upperBound = min(range.upperBound, selectedRange.upperBound)
            return upperBound > lowerBound ? partial + (upperBound - lowerBound) : partial
        }
    }

    private func layoutMetrics(for lines: [CameraRecognizedTextLine]) -> LayoutMetrics {
        let minXs = lines.map(\.boundingBox.minX).sorted()
        let maxXs = lines.map(\.boundingBox.maxX).sorted()
        let heights = lines.map(\.boundingBox.height).sorted()
        let widths = lines.map(\.boundingBox.width).sorted()
        let gaps = zip(lines, lines.dropFirst())
            .map { previousLine, currentLine in
                max(previousLine.boundingBox.minY - currentLine.boundingBox.maxY, 0)
            }
            .sorted()

        return LayoutMetrics(
            bodyLeft: quantile(minXs, 0.18),
            bodyRight: quantile(maxXs, 0.82),
            medianHeight: max(quantile(heights, 0.50), 0.01),
            medianWidth: max(quantile(widths, 0.50), 0.01),
            medianGap: max(quantile(gaps, 0.50), 0.004)
        )
    }

    private func sortedUnique(_ lines: [CameraRecognizedTextLine]) -> [CameraRecognizedTextLine] {
        var seenIDs: Set<String> = []
        return lines
            .filter { !$0.text.trimmed.isEmpty }
            .filter { line in
                guard !seenIDs.contains(line.id) else { return false }
                seenIDs.insert(line.id)
                return true
            }
            .sorted(by: readingOrder)
    }

    private func readingOrder(_ lhs: CameraRecognizedTextLine, _ rhs: CameraRecognizedTextLine) -> Bool {
        if lhs.readingIndex != rhs.readingIndex {
            return lhs.readingIndex < rhs.readingIndex
        }

        let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        if yDelta > 0.025 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func quantile(_ values: [CGFloat], _ fraction: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let clampedFraction = min(max(fraction, 0), 1)
        let index = Int((CGFloat(values.count - 1) * clampedFraction).rounded())
        return values[index]
    }

    private func normalizedLineText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmed
    }

    private func cleanedOutput(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmed
    }

    private func substring(in text: String, from start: Int, to end: Int) -> String {
        guard start < end, start >= 0, end <= text.count else { return "" }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return String(text[startIndex..<endIndex])
    }

    private func comparable(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]"#, with: "", options: .regularExpression)
    }

    private static func endsAtSentenceBoundary(_ text: String) -> Bool {
        let trimmedText = text.trimmed
        guard let lastCharacter = trimmedText.last else { return false }

        if isSentenceClosingPunctuation(lastCharacter) {
            return true
        }

        guard isClosingQuote(lastCharacter) else { return false }
        let withoutClosingQuotes = trimmedText
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"”’'").union(.whitespacesAndNewlines))
        guard let previousCharacter = withoutClosingQuotes.last else { return false }
        return isSentenceClosingPunctuation(previousCharacter)
    }

    private static func isSentenceClosingPunctuation(_ character: Character) -> Bool {
        ".!?。！？".contains(character)
    }

    private static func isClosingQuote(_ character: Character) -> Bool {
        "\"”’'」』".contains(character)
    }
}

fileprivate enum CameraVisionCoordinateTransform: CaseIterable {
    case identity
    case rotateClockwise
    case rotateCounterClockwise

    nonisolated static func bestTransform(for lines: [CameraRecognizedTextLine]) -> CameraVisionCoordinateTransform {
        guard lines.count >= 2 else { return .identity }

        return allCases.max { lhs, rhs in
            score(lhs, for: lines) < score(rhs, for: lines)
        } ?? .identity
    }

    nonisolated var snapshotOrientation: CGImagePropertyOrientation {
        switch self {
        case .identity:
            return .up
        case .rotateClockwise:
            return .right
        case .rotateCounterClockwise:
            return .left
        }
    }

    nonisolated func point(_ point: CGPoint) -> CGPoint {
        let transformedPoint: CGPoint
        switch self {
        case .identity:
            transformedPoint = point
        case .rotateClockwise:
            transformedPoint = CGPoint(x: point.y, y: 1 - point.x)
        case .rotateCounterClockwise:
            transformedPoint = CGPoint(x: 1 - point.y, y: point.x)
        }

        return CGPoint(
            x: min(max(transformedPoint.x, 0), 1),
            y: min(max(transformedPoint.y, 0), 1)
        )
    }

    nonisolated func rect(_ rect: CGRect) -> CGRect {
        boundingBox(for: rect.normalizedCorners.map(point))
    }

    nonisolated func quadrilateral(_ quadrilateral: CameraTextQuadrilateral) -> CameraTextQuadrilateral {
        let orderedCorners = orderedCorners([
            point(quadrilateral.topLeft),
            point(quadrilateral.topRight),
            point(quadrilateral.bottomRight),
            point(quadrilateral.bottomLeft)
        ])

        return CameraTextQuadrilateral(
            topLeft: orderedCorners[0],
            topRight: orderedCorners[1],
            bottomRight: orderedCorners[2],
            bottomLeft: orderedCorners[3]
        )
    }

    nonisolated func page(_ page: CameraDetectedPage) -> CameraDetectedPage {
        let transformedCorners = [
            point(page.topLeft),
            point(page.topRight),
            point(page.bottomRight),
            point(page.bottomLeft)
        ]
        let orderedCorners = orderedCorners(transformedCorners)

        return CameraDetectedPage(
            boundingBox: boundingBox(for: transformedCorners),
            topLeft: orderedCorners[0],
            topRight: orderedCorners[1],
            bottomRight: orderedCorners[2],
            bottomLeft: orderedCorners[3]
        )
    }

    private nonisolated static func score(_ transform: CameraVisionCoordinateTransform, for lines: [CameraRecognizedTextLine]) -> CGFloat {
        let rects = lines.map { transform.rect($0.boundingBox) }
        let aspectScore = rects
            .map { rect in
                let aspectRatio = rect.width / max(rect.height, 0.0001)
                return min(max((aspectRatio - 0.8) / 3.2, 0), 1)
            }
            .reduce(CGFloat.zero, +) / CGFloat(max(rects.count, 1))

        let orderedRects = zip(lines, rects)
            .sorted { $0.0.readingIndex < $1.0.readingIndex }
            .map(\.1)
        let yCenters = orderedRects.map(\.midY)
        let topToBottomPairs = zip(yCenters, yCenters.dropFirst())
            .filter { previousY, nextY in
                previousY >= nextY - 0.015
            }
            .count
        let orderScore = yCenters.count > 1
            ? CGFloat(topToBottomPairs) / CGFloat(yCenters.count - 1)
            : 0.5

        return aspectScore * 0.72 + orderScore * 0.28
    }

    private nonisolated func orderedCorners(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count == 4 else {
            return [CGPoint.zero, CGPoint.zero, CGPoint.zero, CGPoint.zero]
        }

        let sortedByY = points.sorted {
            if abs($0.y - $1.y) > 0.001 {
                return $0.y > $1.y
            }
            return $0.x < $1.x
        }
        let top = sortedByY.prefix(2).sorted { $0.x < $1.x }
        let bottom = sortedByY.suffix(2).sorted { $0.x < $1.x }

        return [
            top[0],
            top[1],
            bottom[1],
            bottom[0]
        ]
    }

    private nonisolated func boundingBox(for points: [CGPoint]) -> CGRect {
        guard let firstPoint = points.first else { return .zero }

        return points.dropFirst()
            .reduce(CGRect(origin: firstPoint, size: .zero)) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }
            .standardized
    }
}

private extension CGRect {
    nonisolated var normalizedCorners: [CGPoint] {
        [
            CGPoint(x: minX, y: maxY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: minY)
        ]
    }
}

nonisolated enum CameraDeviceSelection {
    static let preferredDisplayedZoomFactor: CGFloat = 1.5

    static let preferredDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .builtInTripleCamera,
        .builtInDualWideCamera
    ]

    static func preferredBackCamera() -> AVCaptureDevice? {
        for deviceType in preferredDeviceTypes {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [deviceType],
                mediaType: .video,
                position: .back
            )

            if let device = discoverySession.devices.first {
                return device
            }
        }

        return AVCaptureDevice.default(for: .video)
    }

    static func logSelectedCamera(_ camera: AVCaptureDevice) {
        let constituentTypes = camera.constituentDevices
            .map(\.deviceType.rawValue)
            .joined(separator: ",")
        let switchFactors = camera.virtualDeviceSwitchOverVideoZoomFactors
            .map { String(format: "%.2f", $0.doubleValue) }
            .joined(separator: ",")
        let logger = Logger(subsystem: "aib.Overline", category: "CameraScanner")

        logger.info(
            "camera_selected type=\(camera.deviceType.rawValue, privacy: .public) name=\(camera.localizedName, privacy: .public) virtual=\(camera.isVirtualDevice, privacy: .public) constituents=\(constituentTypes, privacy: .public) switch_factors=\(switchFactors, privacy: .public)"
        )
    }

    static func configureMacroFallbackBehavior(for camera: AVCaptureDevice) {
        let logger = Logger(subsystem: "aib.Overline", category: "CameraScanner")

        guard camera.isVirtualDevice, !camera.constituentDevices.isEmpty else {
            logger.info(
                "camera_macro_switching_skipped reason=non_virtual type=\(camera.deviceType.rawValue, privacy: .public)"
            )
            return
        }

        do {
            try camera.lockForConfiguration()
            defer {
                camera.unlockForConfiguration()
            }

            let fallbackDevices = camera.supportedFallbackPrimaryConstituentDevices
            if !fallbackDevices.isEmpty {
                camera.fallbackPrimaryConstituentDevices = fallbackDevices
            }

            camera.setPrimaryConstituentDeviceSwitchingBehavior(
                .auto,
                restrictedSwitchingBehaviorConditions: []
            )

            let fallbackTypes = fallbackDevices
                .map(\.deviceType.rawValue)
                .joined(separator: ",")
            logger.info(
                "camera_macro_switching_enabled behavior=auto fallback_constituents=\(fallbackTypes, privacy: .public)"
            )
        } catch {
            logger.error(
                "camera_macro_switching_failed type=\(camera.deviceType.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func logActivePrimaryConstituent(_ camera: AVCaptureDevice) {
        let logger = Logger(subsystem: "aib.Overline", category: "CameraScanner")

        guard camera.isVirtualDevice else {
            logger.info(
                "camera_active_constituent_skipped reason=non_virtual type=\(camera.deviceType.rawValue, privacy: .public)"
            )
            return
        }

        let activeDevice = camera.activePrimaryConstituent
        logger.info(
            "camera_active_constituent type=\(activeDevice?.deviceType.rawValue ?? "nil", privacy: .public) name=\(activeDevice?.localizedName ?? "nil", privacy: .public) behavior=\(camera.activePrimaryConstituentDeviceSwitchingBehavior.rawValue, privacy: .public) restricted=\(camera.activePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditions.rawValue, privacy: .public) zoom=\(camera.videoZoomFactor, privacy: .public)"
        )
    }

    static func observeActivePrimaryConstituent(_ camera: AVCaptureDevice) -> NSKeyValueObservation? {
        guard camera.isVirtualDevice else { return nil }

        return camera.observe(\.activePrimaryConstituent, options: [.initial, .new]) { observedCamera, _ in
            Self.logActivePrimaryConstituent(observedCamera)
        }
    }

    static func applyPreferredCenterCropZoom(to camera: AVCaptureDevice) {
        let logger = Logger(subsystem: "aib.Overline", category: "CameraScanner")
        let minimumZoomFactor = camera.minAvailableVideoZoomFactor
        let maximumZoomFactor = camera.maxAvailableVideoZoomFactor
        let targetZoomFactor = preferredVideoZoomFactor(for: camera)
        let displayMultiplier = displayZoomFactorMultiplier(for: camera)
        let appliedZoomFactor = min(
            max(targetZoomFactor, minimumZoomFactor),
            maximumZoomFactor
        )

        guard appliedZoomFactor > minimumZoomFactor else {
            logger.info(
                "camera_zoom_skipped display_target=\(preferredDisplayedZoomFactor, privacy: .public) display_multiplier=\(displayMultiplier, privacy: .public) target_video=\(targetZoomFactor, privacy: .public) min=\(minimumZoomFactor, privacy: .public) max=\(maximumZoomFactor, privacy: .public)"
            )
            return
        }

        do {
            try camera.lockForConfiguration()
            camera.videoZoomFactor = appliedZoomFactor
            camera.unlockForConfiguration()

            logger.info(
                "camera_zoom_applied display_target=\(preferredDisplayedZoomFactor, privacy: .public) display_multiplier=\(displayMultiplier, privacy: .public) target_video=\(targetZoomFactor, privacy: .public) applied=\(appliedZoomFactor, privacy: .public) min=\(minimumZoomFactor, privacy: .public) max=\(maximumZoomFactor, privacy: .public)"
            )
        } catch {
            logger.error(
                "camera_zoom_failed display_target=\(preferredDisplayedZoomFactor, privacy: .public) display_multiplier=\(displayMultiplier, privacy: .public) target_video=\(targetZoomFactor, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func preferredVideoZoomFactor(for camera: AVCaptureDevice) -> CGFloat {
        guard camera.isVirtualDevice else {
            return preferredDisplayedZoomFactor
        }

        if #available(iOS 18.0, *) {
            let displayMultiplier = camera.displayVideoZoomFactorMultiplier
            if displayMultiplier > 0 {
                return preferredDisplayedZoomFactor / displayMultiplier
            }
        }

        if
            camera.isVirtualDevice,
            let firstSwitchOverFactor = camera.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue,
            firstSwitchOverFactor > 1
        {
            return CGFloat(firstSwitchOverFactor)
        }

        return preferredDisplayedZoomFactor
    }

    private static func displayZoomFactorMultiplier(for camera: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            return camera.displayVideoZoomFactorMultiplier
        }

        return 1
    }
}

enum CameraScannerStatus: Equatable {
    case idle
    case requestingPermission
    case running
    case unavailable(String)

    var debugName: String {
        switch self {
        case .idle: "idle"
        case .requestingPermission: "requesting_permission"
        case .running: "running"
        case .unavailable: "unavailable"
        }
    }
}

@MainActor
@Observable
final class CameraTextScanner {
    @ObservationIgnored private let core: CameraTextScannerCore
    @ObservationIgnored private var recognitionWindowTask: Task<Void, Never>?
    @ObservationIgnored private var selectedLineCache: [CameraRecognizedTextLine.ID: CameraRecognizedTextLine] = [:]
    @ObservationIgnored private var lifecycleRequestSequence = 0

    var status: CameraScannerStatus = .idle
    var lines: [CameraRecognizedTextLine] = []
    var detectedPage: CameraDetectedPage?
    var frameBrightness: Float?
    var isTorchOn = false
    var isAnalyzingText = false
    var recognitionUpdateCount = 0
    var frozenFrameImage: UIImage?

    var session: AVCaptureSession {
        core.session
    }

    init(core: CameraTextScannerCore = CameraTextScannerCore()) {
        self.core = core
        core.onLines = { [weak self] lines in
            Task { @MainActor in
                self?.lines = lines
                self?.recognitionUpdateCount += 1
            }
        }
        core.onPage = { [weak self] page in
            Task { @MainActor in
                self?.detectedPage = page
            }
        }
        core.onBrightness = { [weak self] brightness in
            Task { @MainActor in
                self?.frameBrightness = brightness
            }
        }
        core.onFrozenFrame = { [weak self] image in
            Task { @MainActor in
                self?.frozenFrameImage = image
            }
        }
        core.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.status = .unavailable(message)
            }
        }
    }

    static func makePrepared() async -> CameraTextScanner {
        let core = await Task.detached(priority: .userInitiated) {
            CameraTextScannerCore()
        }.value
        return CameraTextScanner(core: core)
    }

    var canUseLiveCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        switch status {
        case .running, .requestingPermission:
            true
        case .idle:
            CameraDeviceSelection.preferredBackCamera() != nil
        case .unavailable:
            false
        }
        #endif
    }

    var canToggleTorch: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        core.isTorchAvailable
        #endif
    }

    var isLowLight: Bool {
        guard let frameBrightness else { return false }
        return frameBrightness < 0.28
    }

    func start(owner: String = "unspecified") {
        lifecycleRequestSequence += 1
        let requestID = lifecycleRequestSequence
        cameraLifecycleLogger.info(
            "camera_start_requested owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) status=\(self.status.debugName, privacy: .public) session_running=\(self.session.isRunning, privacy: .public)"
        )

        #if targetEnvironment(simulator)
        status = .unavailable("시뮬레이터에서는 카메라 대신 목업 캡처를 사용합니다.")
        cameraLifecycleLogger.info(
            "camera_start_skipped owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) reason=simulator"
        )
        return
        #else
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .authorized:
            status = .running
            core.start(requestID: requestID, owner: owner)
        case .notDetermined:
            status = .requestingPermission
            cameraLifecycleLogger.info(
                "camera_authorization_requested owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public)"
            )
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.status = .running
                        self?.core.start(requestID: requestID, owner: owner)
                    } else {
                        self?.status = .unavailable("카메라 권한이 필요합니다.")
                        cameraLifecycleLogger.error(
                            "camera_authorization_denied owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public)"
                        )
                    }
                }
            }
        default:
            status = .unavailable("카메라 권한이 필요합니다.")
            cameraLifecycleLogger.error(
                "camera_start_blocked owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) reason=authorization"
            )
        }
        #endif
    }

    func stop(clearRecognitionResults: Bool = true, owner: String = "unspecified") {
        lifecycleRequestSequence += 1
        let requestID = lifecycleRequestSequence
        cameraLifecycleLogger.info(
            "camera_stop_requested owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) status=\(self.status.debugName, privacy: .public) session_running=\(self.session.isRunning, privacy: .public)"
        )
        stopSwipeRecognition(clearResults: clearRecognitionResults)
        core.stop(requestID: requestID, owner: owner)
        if isTorchOn {
            setTorch(false)
        }
    }

    func beginSwipeRecognition(
        duration: TimeInterval = 3.2,
        resetResults: Bool = true,
        maxFrames: Int = 4,
        minimumFrameInterval: TimeInterval = 0.22
    ) {
        if resetResults || !isAnalyzingText {
            lines.removeAll()
            recognitionUpdateCount = 0
            selectedLineCache.removeAll()
        }

        core.activateRecognition(
            for: duration,
            maxFrames: maxFrames,
            minimumFrameInterval: minimumFrameInterval
        )
        isAnalyzingText = true

        recognitionWindowTask?.cancel()
        recognitionWindowTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.stopSwipeRecognition()
            }
        }
    }

    func beginFrozenFrameRecognition() {
        guard let frozenFrameImage else {
            beginSwipeRecognition()
            return
        }

        stopSwipeRecognition(clearResults: false)
        lines.removeAll()
        recognitionUpdateCount = 0
        selectedLineCache.removeAll()
        isAnalyzingText = true

        recognitionWindowTask = Task { [weak self, frozenFrameImage] in
            let result = try? await CameraFrozenFrameRecognizer.recognize(in: frozenFrameImage)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }

                if let result {
                    self.lines = result.lines
                    self.detectedPage = result.page
                    self.recognitionUpdateCount += 1
                    self.core.storeDetectedPage(result.page)
                }
            }

            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.isAnalyzingText = false
                self.recognitionWindowTask = nil
            }
        }
    }

    func recognizeFrozenPage() async throws -> CameraFrozenFrameRecognitionResult {
        guard let frozenFrameImage else {
            throw OCRTextRecognizerError.invalidImage
        }

        return try await CameraFrozenFrameRecognizer.recognize(in: frozenFrameImage)
    }

    func stopSwipeRecognition(clearResults: Bool = true) {
        recognitionWindowTask?.cancel()
        recognitionWindowTask = nil
        core.deactivateRecognition()
        isAnalyzingText = false

        if clearResults {
            lines.removeAll()
            selectedLineCache.removeAll()
        }
    }

    func freezeNextFrame() {
        frozenFrameImage = nil
        core.requestFreezeFrame()
    }

    func clearFrozenFrame() {
        core.cancelFreezeFrameRequest()
        core.clearSnapshot()
        frozenFrameImage = nil
    }

    func cacheSelectedLines(for selectedIDs: Set<CameraRecognizedTextLine.ID>) {
        for line in lines where selectedIDs.contains(line.id) {
            selectedLineCache[line.id] = line
        }
    }

    func clearSelectedLineCache() {
        selectedLineCache.removeAll()
    }

    func selectedLineSnapshots(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> [CameraRecognizedTextLine] {
        selectedLines(for: selectedIDs)
    }

    func text(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> String {
        OCRTextAssembler(
            pageLines: lines,
            selectedLines: selectedLines(for: selectedIDs)
        )
        .assembledText()
    }

    func averageConfidence(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> Float? {
        let confidences = selectedLines(for: selectedIDs)
            .map(\.confidence)

        guard !confidences.isEmpty else { return nil }
        return confidences.reduce(0, +) / Float(confidences.count)
    }

    func inferredPageReference() -> String? {
        PageReferenceInference.inferredPageReference(
            from: lines.map {
                PageReferenceLine(text: $0.text, boundingBox: $0.boundingBox)
            },
            pageBoundingBox: detectedPage?.boundingBox
        )
    }

    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    private func setTorch(_ enabled: Bool) {
        core.setTorchEnabled(enabled) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let isEnabled):
                    self?.isTorchOn = isEnabled
                case .failure(let error):
                    self?.isTorchOn = false
                    self?.status = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    private func selectedLines(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> [CameraRecognizedTextLine] {
        let liveMatches = lines.filter { selectedIDs.contains($0.id) }
        guard !liveMatches.isEmpty else {
            let cachedMatches = selectedLineCache.values
                .filter { selectedIDs.contains($0.id) }
                .sorted(by: readingOrder)
            return deduplicatedSelection(cachedMatches)
        }

        var mergedLines = liveMatches
        let liveIDs = Set(liveMatches.map(\.id))
        let cachedMatches = selectedLineCache.values
            .filter { selectedIDs.contains($0.id) && !liveIDs.contains($0.id) }
        mergedLines.append(contentsOf: cachedMatches)
        return deduplicatedSelection(mergedLines.sorted(by: readingOrder))
    }

    private func readingOrder(_ lhs: CameraRecognizedTextLine, _ rhs: CameraRecognizedTextLine) -> Bool {
        // Prefer Vision's reading order; coordinate sorting is only a fallback for legacy cached lines.
        if lhs.readingIndex != rhs.readingIndex {
            return lhs.readingIndex < rhs.readingIndex
        }

        let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        if yDelta > 0.025 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func deduplicatedSelection(_ lines: [CameraRecognizedTextLine]) -> [CameraRecognizedTextLine] {
        lines.reduce(into: [CameraRecognizedTextLine]()) { result, line in
            let normalizedText = line.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let hasEquivalentLine = result.contains { existingLine in
                existingLine.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedText &&
                    abs(existingLine.boundingBox.midY - line.boundingBox.midY) < 0.025
            }

            if !hasEquivalentLine {
                result.append(line)
            }
        }
    }
}

private enum CameraFrozenFrameRecognizer {
    static func recognize(in image: UIImage) async throws -> CameraFrozenFrameRecognitionResult {
        guard let cgImage = image.cgImage else {
            throw CameraScannerError.cameraUnavailable
        }

        return try await Task.detached(priority: .userInitiated) {
            let documentRequest = VNDetectDocumentSegmentationRequest()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
            textRequest.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: .up,
                options: [:]
            )

            try handler.perform([documentRequest, textRequest])

            let rawRecognizedLines = (textRequest.results ?? [])
                .enumerated()
                .compactMap { index, observation -> CameraRecognizedTextLine? in
                    guard
                        let candidate = observation.topCandidates(1).first,
                        !candidate.string.trimmed.isEmpty
                    else {
                        return nil
                    }

                    let textRange = candidate.string.startIndex..<candidate.string.endIndex
                    let recognizedTextBox = (try? candidate.boundingBox(for: textRange)) ?? nil

                    return CameraRecognizedTextLine(
                        text: candidate.string.trimmed,
                        boundingBox: recognizedTextBox?.boundingBox ?? observation.boundingBox,
                        quadrilateral: recognizedTextBox.map(CameraTextQuadrilateral.init(rectangle:)),
                        confidence: candidate.confidence,
                        readingIndex: index
                    )
                }

            let coordinateTransform = CameraVisionCoordinateTransform.bestTransform(for: rawRecognizedLines)
            let recognizedLines = rawRecognizedLines.map { $0.applying(coordinateTransform) }
            let visionPage = CameraPageDetection.bestCandidate(
                from: documentRequest.results ?? [],
                coordinateTransform: coordinateTransform
            )
            let fallbackPage = CameraPageDetection.inferredPage(from: recognizedLines)
            let detectedPage = visionPage ?? fallbackPage
            let detectionSource = visionPage != nil ? "vision" : (fallbackPage != nil ? "text_fallback" : "none")
            let detectedArea = Double(detectedPage?.area ?? 0)

            Logger(subsystem: "aib.Overline", category: "CameraScanner").info(
                "camera_page_detection_frozen source=\(detectionSource, privacy: .public) candidates=\((documentRequest.results ?? []).count, privacy: .public) line_count=\(recognizedLines.count, privacy: .public) area=\(detectedArea, format: .fixed(precision: 3), privacy: .public)"
            )

            return CameraFrozenFrameRecognitionResult(
                lines: recognizedLines,
                page: detectedPage
            )
        }
        .value
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let owner: String

    final class Coordinator {
        let owner: String

        init(owner: String) {
            self.owner = owner
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: owner)
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if #available(iOS 26.0, *), view.previewLayer.isDeferredStartSupported {
            view.previewLayer.isDeferredStartEnabled = false
        }
        cameraLifecycleLogger.info(
            "camera_preview_attached owner=\(owner, privacy: .public) session_running=\(session.isRunning, privacy: .public)"
        )
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
            cameraLifecycleLogger.info(
                "camera_preview_reassigned owner=\(owner, privacy: .public) session_running=\(session.isRunning, privacy: .public)"
            )
        }
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        cameraLifecycleLogger.info(
            "camera_preview_detached owner=\(coordinator.owner, privacy: .public) session_running=\(uiView.previewLayer.session?.isRunning ?? false, privacy: .public)"
        )
    }
}

final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraFrozenFrameRecognitionResult {
    let lines: [CameraRecognizedTextLine]
    let page: CameraDetectedPage?
}

private nonisolated final class CameraCIContextProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedContext: CIContext?

    func createCGImage(_ image: CIImage, from rect: CGRect) -> CGImage? {
        context().createCGImage(image, from: rect)
    }

    func warmUp() {
        _ = context()
    }

    private func context() -> CIContext {
        lock.lock()
        defer { lock.unlock() }

        if let cachedContext {
            return cachedContext
        }

        let context = CIContext()
        cachedContext = context
        return context
    }
}

nonisolated final class CameraTextScannerCore: @unchecked Sendable {
    private struct StartContext {
        let requestID: Int
        let owner: String
        let requestedAt: TimeInterval
    }

    let session = AVCaptureSession()
    var onLines: (([CameraRecognizedTextLine]) -> Void)?
    var onPage: ((CameraDetectedPage?) -> Void)?
    var onBrightness: ((Float?) -> Void)?
    var onFrozenFrame: ((UIImage) -> Void)?
    var onFailure: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(
        label: "aib.overline.camera.session",
        qos: .userInitiated
    )
    private let visionQueue = DispatchQueue(label: "aib.overline.camera.vision", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sampleBufferDelegate = CameraSampleBufferDelegate()
    private let ciContextProvider = CameraCIContextProvider()
    private let snapshotLock = NSLock()
    private let freezeLock = NSLock()
    private let lifecycleLock = NSLock()

    private var isConfigured = false
    private var isRecognizingFrame = false
    private var lastPageDetectionTime = Date.distantPast
    private var cameraDevice: AVCaptureDevice?
    private var activePrimaryConstituentObservation: NSKeyValueObservation?
    private var latestDetectedPage: CameraDetectedPage?
    private var pageMissCount = 0
    private let recognitionLock = NSLock()
    private var recognitionDeadline = Date.distantPast
    private var recognitionGeneration = 0
    private var recognitionFrameCount = 0
    private var recognitionMaxFrameCount = 4
    private var recognitionMinimumFrameInterval: TimeInterval = 0.22
    private var lastRecognitionTime = Date.distantPast
    private var shouldFreezeNextFrame = false
    private var activeStartContext: StartContext?
    private var firstFrameLoggedRequestID: Int?

    init() {
        sampleBufferDelegate.owner = self
    }

    func requestFreezeFrame() {
        freezeLock.lock()
        shouldFreezeNextFrame = true
        freezeLock.unlock()
    }

    func cancelFreezeFrameRequest() {
        freezeLock.lock()
        shouldFreezeNextFrame = false
        freezeLock.unlock()
    }

    func clearSnapshot() {
        snapshotLock.lock()
        latestDetectedPage = nil
        pageMissCount = 0
        snapshotLock.unlock()
    }

    func activateRecognition(
        for duration: TimeInterval,
        maxFrames: Int,
        minimumFrameInterval: TimeInterval
    ) {
        recognitionLock.lock()
        recognitionGeneration += 1
        recognitionFrameCount = 0
        recognitionMaxFrameCount = max(maxFrames, 1)
        recognitionMinimumFrameInterval = max(minimumFrameInterval, 0.05)
        lastRecognitionTime = .distantPast
        recognitionDeadline = max(recognitionDeadline, Date().addingTimeInterval(duration))
        recognitionLock.unlock()
    }

    func deactivateRecognition() {
        recognitionLock.lock()
        recognitionGeneration += 1
        recognitionDeadline = .distantPast
        recognitionLock.unlock()
        clearSnapshot()
    }

    func start(requestID: Int, owner: String) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let queueWaitMilliseconds = Self.elapsedMilliseconds(since: requestedAt)
            cameraLifecycleLogger.info(
                "camera_start_queue_entered owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) queue_wait_ms=\(queueWaitMilliseconds, privacy: .public) session_running=\(self.session.isRunning, privacy: .public) configured=\(self.isConfigured, privacy: .public)"
            )
            self.recordStartContext(
                StartContext(requestID: requestID, owner: owner, requestedAt: requestedAt)
            )

            guard !session.isRunning else {
                cameraLifecycleLogger.info(
                    "camera_start_skipped owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) reason=already_running"
                )
                return
            }

            do {
                let operationStartedAt = ProcessInfo.processInfo.systemUptime
                if !isConfigured {
                    try configureSession()
                    isConfigured = true
                }

                if !session.isRunning {
                    session.startRunning()
                }

                if let cameraDevice {
                    CameraDeviceSelection.applyPreferredCenterCropZoom(to: cameraDevice)
                    CameraDeviceSelection.logActivePrimaryConstituent(cameraDevice)
                }

                let operationMilliseconds = Self.elapsedMilliseconds(since: operationStartedAt)
                let totalMilliseconds = Self.elapsedMilliseconds(since: requestedAt)
                cameraLifecycleLogger.info(
                    "camera_start_completed owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) operation_ms=\(operationMilliseconds, privacy: .public) total_ms=\(totalMilliseconds, privacy: .public) session_running=\(self.session.isRunning, privacy: .public)"
                )

                let warmupDate = Date()
                visionQueue.async { [weak self] in
                    guard let self else { return }
                    self.lastPageDetectionTime = warmupDate
                    self.ciContextProvider.warmUp()
                }
            } catch {
                cameraLifecycleLogger.error(
                    "camera_start_failed owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                onFailure?(error.localizedDescription)
            }
        }
    }

    func stop(requestID: Int, owner: String) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let queueWaitMilliseconds = Self.elapsedMilliseconds(since: requestedAt)
            cameraLifecycleLogger.info(
                "camera_stop_queue_entered owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) queue_wait_ms=\(queueWaitMilliseconds, privacy: .public) session_running=\(self.session.isRunning, privacy: .public)"
            )
            let operationStartedAt = ProcessInfo.processInfo.systemUptime
            if session.isRunning {
                session.stopRunning()
            }
            let operationMilliseconds = Self.elapsedMilliseconds(since: operationStartedAt)
            let totalMilliseconds = Self.elapsedMilliseconds(since: requestedAt)
            cameraLifecycleLogger.info(
                "camera_stop_completed owner=\(owner, privacy: .public) request_id=\(requestID, privacy: .public) operation_ms=\(operationMilliseconds, privacy: .public) total_ms=\(totalMilliseconds, privacy: .public) session_running=\(self.session.isRunning, privacy: .public)"
            )
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high
        if #available(iOS 26.0, *) {
            session.automaticallyRunsDeferredStart = true
        }

        defer {
            session.commitConfiguration()
        }

        guard let camera = CameraDeviceSelection.preferredBackCamera() else {
            throw CameraScannerError.cameraUnavailable
        }
        cameraDevice = camera
        activePrimaryConstituentObservation = CameraDeviceSelection.observeActivePrimaryConstituent(camera)
        CameraDeviceSelection.logSelectedCamera(camera)
        CameraDeviceSelection.configureMacroFallbackBehavior(for: camera)
        CameraDeviceSelection.applyPreferredCenterCropZoom(to: camera)

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraScannerError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if #available(iOS 26.0, *), videoOutput.isDeferredStartSupported {
            videoOutput.isDeferredStartEnabled = true
        }
        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: visionQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CameraScannerError.cannotAddOutput
        }
        session.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.videoRotationAngle = 90
    }

    fileprivate func handle(_ sampleBuffer: CMSampleBuffer) {
        logFirstFrameIfNeeded()
        let now = Date()
        guard !isRecognizingFrame else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        captureFrozenFrameIfNeeded(from: pixelBuffer)

        guard let recognitionToken = activeRecognitionToken(at: now) else {
            return
        }

        guard claimRecognitionFrame(for: recognitionToken, at: now) else {
            return
        }

        isRecognizingFrame = true

        let textRequest = VNRecognizeTextRequest()
        let shouldRefreshPage = now.timeIntervalSince(lastPageDetectionTime) > 1.8
        let documentRequest = shouldRefreshPage ? VNDetectDocumentSegmentationRequest() : nil
        if shouldRefreshPage {
            lastPageDetectionTime = now
        }
        var requests: [VNRequest] = []
        if let documentRequest {
            requests.append(documentRequest)
        }
        requests.append(textRequest)

        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
        textRequest.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )
            .perform(requests)

            // Preserve Vision's reading order. Fixed y/x sorting breaks on rotated or strongly skewed pages.
            let rawRecognizedLines = (textRequest.results ?? [])
                .enumerated()
                .compactMap { index, observation -> CameraRecognizedTextLine? in
                    guard
                        let candidate = observation.topCandidates(1).first,
                        !candidate.string.trimmed.isEmpty
                    else {
                        return nil
                    }

                    let textRange = candidate.string.startIndex..<candidate.string.endIndex
                    let recognizedTextBox = (try? candidate.boundingBox(for: textRange)) ?? nil

                    return CameraRecognizedTextLine(
                        text: candidate.string.trimmed,
                        boundingBox: recognizedTextBox?.boundingBox ?? observation.boundingBox,
                        quadrilateral: recognizedTextBox.map(CameraTextQuadrilateral.init(rectangle:)),
                        confidence: candidate.confidence,
                        readingIndex: index
                    )
                }
            let coordinateTransform = CameraVisionCoordinateTransform.bestTransform(for: rawRecognizedLines)
            let recognizedLines = rawRecognizedLines.map { $0.applying(coordinateTransform) }

            guard isRecognitionTokenCurrent(recognitionToken) else {
                isRecognizingFrame = false
                return
            }

            onBrightness?(averageBrightness(from: pixelBuffer))

            if let documentRequest {
                let detectedPage = CameraPageDetection.bestCandidate(
                    from: documentRequest.results ?? [],
                    coordinateTransform: coordinateTransform
                )
                let displayPage = resolvedDisplayPage(for: detectedPage)
                onPage?(displayPage)
            }

            onLines?(recognizedLines)
        } catch {
            snapshotLock.lock()
            latestDetectedPage = nil
            pageMissCount = 0
            snapshotLock.unlock()
            onPage?(nil)
        }

        isRecognizingFrame = false
    }

    private func recordStartContext(_ context: StartContext) {
        lifecycleLock.lock()
        activeStartContext = context
        firstFrameLoggedRequestID = nil
        lifecycleLock.unlock()
    }

    private func logFirstFrameIfNeeded() {
        lifecycleLock.lock()
        guard
            let context = activeStartContext,
            firstFrameLoggedRequestID != context.requestID
        else {
            lifecycleLock.unlock()
            return
        }
        firstFrameLoggedRequestID = context.requestID
        lifecycleLock.unlock()

        let elapsedMilliseconds = Self.elapsedMilliseconds(since: context.requestedAt)
        cameraLifecycleLogger.info(
            "camera_first_frame owner=\(context.owner, privacy: .public) request_id=\(context.requestID, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
        )
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Int {
        Int(max(0, (ProcessInfo.processInfo.systemUptime - start) * 1_000).rounded())
    }

    private func activeRecognitionToken(at date: Date) -> Int? {
        recognitionLock.lock()
        let token = recognitionDeadline > date ? recognitionGeneration : nil
        recognitionLock.unlock()
        return token
    }

    private func isRecognitionTokenCurrent(_ token: Int) -> Bool {
        recognitionLock.lock()
        let isCurrent = recognitionGeneration == token
        recognitionLock.unlock()
        return isCurrent
    }

    private func claimRecognitionFrame(for token: Int, at date: Date) -> Bool {
        recognitionLock.lock()
        defer {
            recognitionLock.unlock()
        }

        guard recognitionGeneration == token else {
            return false
        }

        guard recognitionFrameCount < recognitionMaxFrameCount else {
            return false
        }

        guard date.timeIntervalSince(lastRecognitionTime) >= recognitionMinimumFrameInterval else {
            return false
        }

        recognitionFrameCount += 1
        lastRecognitionTime = date
        return true
    }

    private func averageBrightness(from pixelBuffer: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4
        let stepX = max(width / 24, 1)
        let stepY = max(height / 24, 1)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total: Float = 0
        var sampleCount: Float = 0

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let blue = Float(buffer[offset])
                let green = Float(buffer[offset + 1])
                let red = Float(buffer[offset + 2])
                total += (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }
        return min(max(total / sampleCount, 0), 1)
    }

    private func captureFrozenFrameIfNeeded(from pixelBuffer: CVPixelBuffer) {
        freezeLock.lock()
        let shouldFreeze = shouldFreezeNextFrame
        shouldFreezeNextFrame = false
        freezeLock.unlock()

        guard shouldFreeze else { return }
        let orientation = frozenFrameDisplayOrientation(for: pixelBuffer)
        guard let image = image(from: pixelBuffer, orientation: orientation) else { return }

        #if DEBUG
        let pixelWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pixelHeight = CVPixelBufferGetHeight(pixelBuffer)
        let imageWidth = image.cgImage?.width ?? 0
        let imageHeight = image.cgImage?.height ?? 0
        Logger(subsystem: "aib.Overline", category: "CameraScanner").info(
            "camera_freeze_frame pixel=\(pixelWidth, privacy: .public)x\(pixelHeight, privacy: .public) orientation=\(orientation.debugName, privacy: .public) image=\(imageWidth, privacy: .public)x\(imageHeight, privacy: .public)"
        )
        #endif

        onFrozenFrame?(image)
    }

    private func frozenFrameDisplayOrientation(for pixelBuffer: CVPixelBuffer) -> CGImagePropertyOrientation {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // AVCaptureVideoDataOutput can deliver either portrait buffers after videoRotationAngle
        // or raw landscape buffers, depending on the active connection/device path. The freeze
        // overlay must be physically portrait to match AVCaptureVideoPreviewLayer's aspect fill.
        return height >= width ? .up : .right
    }

    private func image(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        guard let cgImage = ciContextProvider.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    func storeDetectedPage(_ detectedPage: CameraDetectedPage?) {
        snapshotLock.lock()
        if let detectedPage {
            latestDetectedPage = detectedPage
            pageMissCount = 0
        } else {
            latestDetectedPage = nil
            pageMissCount = 0
        }
        snapshotLock.unlock()
    }

    private func resolvedDisplayPage(for detectedPage: CameraDetectedPage?) -> CameraDetectedPage? {
        snapshotLock.lock()
        defer {
            snapshotLock.unlock()
        }

        if let detectedPage {
            latestDetectedPage = detectedPage
            pageMissCount = 0
            return detectedPage
        }

        pageMissCount += 1
        if pageMissCount < 3 {
            return latestDetectedPage
        }

        latestDetectedPage = nil
        return nil
    }

    private func cropRect(
        for boundingBoxes: [CGRect],
        pageBoundingBox: CGRect?,
        in imageSize: CGSize
    ) -> CGRect? {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let lineRects = boundingBoxes.map { box in
            CGRect(
                x: box.minX * imageSize.width,
                y: (1 - box.maxY) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
        }
        let pageRect = pageBoundingBox.map { box in
            CGRect(
                x: box.minX * imageSize.width,
                y: (1 - box.maxY) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            .insetBy(dx: -imageSize.width * 0.015, dy: -imageSize.height * 0.015)
            .intersection(imageBounds)
        }

        guard var cropRect = lineRects.first else { return nil }
        for rect in lineRects.dropFirst() {
            cropRect = cropRect.union(rect)
        }

        let minWidth = imageSize.width * 0.78
        let minHeight = imageSize.height * 0.20
        cropRect = cropRect.insetBy(
            dx: -max(24, imageSize.width * 0.045),
            dy: -max(26, cropRect.height * 1.4)
        )

        if cropRect.width < minWidth {
            cropRect = cropRect.insetBy(dx: -(minWidth - cropRect.width) / 2, dy: 0)
        }

        if cropRect.height < minHeight {
            cropRect = cropRect.insetBy(dx: 0, dy: -(minHeight - cropRect.height) / 2)
        }

        let cropBounds = pageRect?.isNull == false ? pageRect ?? imageBounds : imageBounds
        let boundedRect = cropRect.intersection(cropBounds).intersection(imageBounds).integral
        guard boundedRect.width >= 2, boundedRect.height >= 2 else { return nil }
        return boundedRect
    }

    var isTorchAvailable: Bool {
        if let cameraDevice {
            return cameraDevice.hasTorch
        }

        return CameraDeviceSelection.preferredBackCamera()?.hasTorch == true
    }

    func setTorchEnabled(_ enabled: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard
                let camera = cameraDevice ?? CameraDeviceSelection.preferredBackCamera(),
                camera.hasTorch,
                camera.isTorchAvailable
            else {
                completion(.failure(CameraScannerError.torchUnavailable))
                return
            }

            do {
                try camera.lockForConfiguration()
                defer {
                    camera.unlockForConfiguration()
                }

                if enabled {
                    try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    camera.torchMode = .off
                }

                completion(.success(camera.torchMode == .on))
            } catch {
                completion(.failure(CameraScannerError.cannotSetTorch))
            }
        }
    }
}

nonisolated private final class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    weak var owner: CameraTextScannerCore?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        owner?.handle(sampleBuffer)
    }
}

private enum CameraScannerError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case torchUnavailable
    case cannotSetTorch

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "카메라를 사용할 수 없습니다."
        case .cannotAddInput:
            "카메라 입력을 연결할 수 없습니다."
        case .cannotAddOutput:
            "카메라 프레임 출력을 연결할 수 없습니다."
        case .torchUnavailable:
            "이 기기에서는 플래시를 사용할 수 없습니다."
        case .cannotSetTorch:
            "플래시를 전환할 수 없습니다."
        }
    }
}

private extension CGFloat {
    nonisolated func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
