import AppKit
import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum TestFailure: Error { case assertion(String) }

@main
struct Runner {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure.assertion(message) }
    }

    static func main() async throws {
        try SentenceTests.run()
        guard #available(macOS 26.0, *) else {
            throw TestFailure.assertion("Requires macOS 26 or newer")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for (first, second) in [("今日は本を読みます。", "明日は手紙を書きます。"), ("오늘은 책을 읽습니다.", "내일은 편지를 씁니다.")] {
            let text = first + " " + second
            let image = NSImage(size: NSSize(width: 1600, height: 240))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 1600, height: 240).fill()
            (text as NSString).draw(at: NSPoint(x: 40, y: 100), withAttributes: [
                .font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black
            ])
            image.unlockFocus()
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let recognized = try await OCRDocumentRecognizer.recognize(in: cgImage)
            func display(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX * 1600, y: (1 - rect.maxY) * 240, width: rect.width * 1600, height: rect.height * 240)
            }
            let inputs = recognized.enumerated().map { index, line in
                OCRSentenceSelectionLine(id: String(index), text: line.text, rect: display(line.boundingBox),
                    isVertical: line.isVertical, characterBoxes: line.characterBoxes.map { $0.map(display) })
            }
            guard let target = inputs.first(where: { $0.text.contains(second) }), let range = target.text.range(of: second) else {
                throw TestFailure.assertion("generated sentence not recognized")
            }
            let lower = target.text.distance(from: target.text.startIndex, to: range.lowerBound)
            let upper = target.text.distance(from: target.text.startIndex, to: range.upperBound)
            let boxes = target.characterBoxes[lower..<upper].compactMap { $0 }
            try require(boxes.count >= 4, "not enough real glyph boxes")
            let points = [CGPoint(x: boxes[1].midX, y: boxes[1].midY),
                          CGPoint(x: boxes[boxes.count - 2].midX, y: boxes[boxes.count - 2].midY)]
            let slices = OCRSentenceSelector.select(lines: inputs, points: points)
            let selected = slices.map { slice in String(Array(inputs.first { $0.id == slice.lineID }!.text)[slice.range]) }.joined()
            try require(selected == second, "real OCR glyphs selected wrong sentence: \(selected)")
            let snapshots = slices.compactMap { slice -> String? in
                let line = inputs.first { $0.id == slice.lineID }!
                return OCRSentenceSelector.fragment(text: line.text, characterBoxes: line.characterBoxes,
                    lineRect: line.rect, range: slice.range)?.text
            }
            try require(snapshots.count == slices.count && snapshots.joined() == second,
                        "real OCR selection could not form matching highlight/save snapshot")
        }
        print("PASS real Vision glyphs → second sentence only (Korean/Japanese)")
        let fixtures: [(String, String)] = [
            ("ko-horizontal", "오늘은 도서관에서 책을 읽었다. 마음에 남는 문장을 기록했다."),
            ("ja-horizontal", "今日は図書館で本を読みました。心に残る言葉を書き留めました。"),
            ("ja-vertical", "今日は図書館で本を読む心に残る言葉を記録する明日も新しい本を開こう"),
            ("en-horizontal", "Today I read a book at the library. I wrote down a sentence to remember.")
        ]
        for (name, expected) in fixtures {
            let url = root.appendingPathComponent("docs/validation/ocr-locale-2026-09-15/\(name).png")
            let image = NSImage(contentsOf: url)!
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let lines = try await OCRDocumentRecognizer.recognize(in: cgImage)
            try require(lines.allSatisfy { $0.characterBoxes.count == $0.text.count }, "character geometry count differs from text")
            let text = OCRLineJoiner.joined(lines.map(\.text))
            try require(text == expected, "\(name): unexpected transcript: \(text)")
            if name == "ja-vertical" {
                try require(lines.count == 3 && lines.allSatisfy(\.isVertical), "vertical direction missing")
                try require(zip(lines, lines.dropFirst()).allSatisfy { $0.boundingBox.midX > $1.boundingBox.midX }, "column order must be right-to-left")
                try require(lines.allSatisfy { $0.boundingBox.height > $0.boundingBox.width * 3 }, "vertical boxes lost")
                try require(lines.allSatisfy {
                    $0.topLeft.y > $0.bottomLeft.y && $0.topLeft.x < $0.topRight.x &&
                    $0.topRight.y > $0.bottomRight.y
                }, "vertical corners must use image-relative roles")
            }
            print("PASS \(name): exact text, \(lines.count) lines")
        }
        try require(OCRLineJoiner.joined(["「本を読む。」", "次のページへ。"]) == "「本を読む。」次のページへ。", "Japanese closing quote spacing")
        try require(OCRLineJoiner.joined(["책을 읽었다.", "다음 장을 펼쳤다."]) == "책을 읽었다. 다음 장을 펼쳤다.", "Korean spacing regression")
        try require(OCRLineJoiner.joined(["Hello,", "world!"]) == "Hello, world!", "English spacing regression")
        print("PASS punctuation/spacing regressions")

        let right = CameraRecognizedTextLine(id: "right", text: "「本を読む。」", boundingBox: CGRect(x: 0.7, y: 0.2, width: 0.04, height: 0.6), readingIndex: 0, isVertical: true)
        let left = CameraRecognizedTextLine(id: "left", text: "次のページへ。", boundingBox: CGRect(x: 0.6, y: 0.2, width: 0.04, height: 0.6), readingIndex: 1, isVertical: true)
        let assembled = OCRTextAssembler(pageLines: [left, right, right], selectedLines: [left, right], boundaryTrimming: .none).assembledText()
        try require(assembled == "「本を読む。」次のページへ。", "assembler: reading order, deduplication, spacing")
        let selected = OCRTextAssembler(pageLines: [right, left], selectedLines: [left], boundaryTrimming: .none).assembledText()
        try require(selected == "次のページへ。", "assembler included unselected column")
        let column = CGRect(x: 100, y: 20, width: 20, height: 400)
        let stroke = [CGPoint(x: 111, y: 80), CGPoint(x: 111, y: 200)]
        try require(OCRVerticalSelection.score(lineRect: column, points: stroke) != nil, "vertical stroke not selected")
        try require(OCRVerticalSelection.score(lineRect: column.offsetBy(dx: 50, dy: 0), points: stroke) == nil, "adjacent column selected")
        try require(OCRVerticalSelection.score(lineRect: column, points: [CGPoint(x: 110, y: 500)]) == nil, "out-of-range stroke selected")
        try require(OCRVerticalSelection.score(lineRect: column, points: []) == nil, "empty stroke selected")
        print("PASS vertical selection and production assembler")
        let start = CGPoint(x: 100, y: 100)
        for end in [CGPoint(x: 100, y: 180), CGPoint(x: 100, y: 20), CGPoint(x: 180, y: 100), CGPoint(x: 20, y: 100)] {
            try require(OCRHighlighterGesture.canBegin(from: start, to: end), "stroke start rejected")
            let bounds = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            try require(OCRHighlighterGesture.isValidLine(bounds: bounds, pathLength: 80), "horizontal/vertical line rejected")
        }
        try require(!OCRHighlighterGesture.canBegin(from: start, to: CGPoint(x: 102, y: 102)), "tap jitter began stroke")
        try require(!OCRHighlighterGesture.isValidLine(bounds: CGRect(x: 0, y: 0, width: 2, height: 30), pathLength: 31), "short stroke accepted")
        print("PASS four-direction stroke start/finish, jitter and short-stroke rejection")

        // Optional private screenshot: report counts only; do not save book text or the image.
        if CommandLine.arguments.count > 2 {
            let image = NSImage(contentsOfFile: CommandLine.arguments[2])!
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let lines = try await OCRDocumentRecognizer.recognize(in: cgImage)
            let vertical = lines.filter(\.isVertical)
            try require(vertical.count >= 8, "private screenshot: too few vertical lines")
            try require(vertical.reduce(0) { $0 + $1.text.count } >= 200, "private screenshot: missing body")
            print("PASS private screenshot: \(vertical.count) vertical lines, \(vertical.reduce(0) { $0 + $1.text.count }) characters (not an accuracy score)")
        }
    }
}
