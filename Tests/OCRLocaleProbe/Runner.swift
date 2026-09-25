import AppKit
import Vision

// A desktop diagnostic, not an iPhone camera acceptance test.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct Sample {
    let name: String
    let lines: [String]
    let vertical: Bool
    let language: String
}

func render(_ sample: Sample) -> CGImage {
    let image = NSImage(size: NSSize(width: 1200, height: 1200))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1200, height: 1200).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black
    ]
    for (column, line) in sample.lines.enumerated() {
        if sample.vertical {
            // Upright glyph columns isolate reading order; this is not full Japanese typesetting.
            for (row, character) in line.enumerated() {
                (String(character) as NSString).draw(
                    at: NSPoint(x: 1000 - column * 100, y: 1080 - row * 50),
                    withAttributes: attributes
                )
            }
        } else {
            (line as NSString).draw(at: NSPoint(x: 80, y: 1080 - column * 80), withAttributes: attributes)
        }
    }
    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

func normalized(_ text: String) -> String {
    text.filter { !$0.isWhitespace }
}

func characterErrorRate(expected: String, actual: String) -> Double {
    let a = Array(normalized(expected)), b = Array(normalized(actual))
    var previous = Array(0...b.count)
    for (i, left) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, right) in b.enumerated() {
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1))
        }
        previous = current
    }
    return Double(previous[b.count]) / Double(max(a.count, 1))
}

@main
enum Probe {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let samples = [
            Sample(name: "ko-horizontal", lines: ["오늘은 도서관에서 책을 읽었다.", "마음에 남는 문장을 기록했다."], vertical: false, language: "ko-KR"),
            Sample(name: "ja-horizontal", lines: ["今日は図書館で本を読みました。", "心に残る言葉を書き留めました。"], vertical: false, language: "ja-JP"),
            Sample(name: "ja-vertical", lines: ["今日は図書館で本を読む", "心に残る言葉を記録する", "明日も新しい本を開こう"], vertical: true, language: "ja-JP"),
            Sample(name: "en-horizontal", lines: ["Today I read a book at the library.", "I wrote down a sentence to remember."], vertical: false, language: "en-US")
        ]
        var results: [[String: Any]] = []
        for sample in samples {
            let image = render(sample)
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(sample.name + ".png"))
            for languages in [["ko-KR", "en-US", "ja-JP"], [sample.language]] {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = languages
                request.automaticallyDetectsLanguage = true
                let supported = try request.supportedRecognitionLanguages()
                let start = Date()
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = OCRLineJoiner.joined(lines)
                results.append([
                    "sample": sample.name, "languages": languages,
                    "revision": request.revision, "supportedLanguages": supported,
                    "elapsedSeconds": Date().timeIntervalSince(start),
                    "expected": sample.lines.joined(separator: sample.language == "en-US" ? " " : ""),
                    "rawLines": lines, "joined": joined,
                    "whitespaceInsensitiveCER": characterErrorRate(expected: sample.lines.joined(), actual: joined),
                    "boxes": observations.map { ["x": $0.boundingBox.minX, "y": $0.boundingBox.minY, "width": $0.boundingBox.width, "height": $0.boundingBox.height] }
                ])
                print("\(sample.name) \(languages): \(joined)")
            }
        }
        let report: [String: Any] = [
            "platform": ProcessInfo.processInfo.operatingSystemVersionString,
            "scope": "Synthetic desktop Vision baseline; whitespace excluded from CER; no camera, ruby or real-book coverage.",
            "results": results
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("results.json"))
    }
}
