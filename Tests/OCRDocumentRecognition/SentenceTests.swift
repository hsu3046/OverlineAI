import Foundation

enum SentenceTests {
    static func run() throws {
        func line(_ id: String, _ text: String, _ x: CGFloat, _ y: CGFloat, vertical: Bool = false) -> OCRSentenceSelectionLine {
            let boxes = Array(text).enumerated().map { offset, _ -> CGRect? in
                CGRect(x: x + (vertical ? 0 : CGFloat(offset) * 10),
                       y: y + (vertical ? CGFloat(offset) * 10 : 0), width: 10, height: 10)
            }
            return OCRSentenceSelectionLine(id: id, text: text,
                rect: CGRect(x: x, y: y, width: vertical ? 10 : CGFloat(text.count) * 10,
                             height: vertical ? CGFloat(text.count) * 10 : 10),
                isVertical: vertical, characterBoxes: boxes)
        }
        func selected(_ lines: [OCRSentenceSelectionLine], _ points: [CGPoint]) -> String {
            OCRSentenceSelector.select(lines: lines, points: points).map { slice in
                let source = lines.first { $0.id == slice.lineID }!
                return String(Array(source.text)[slice.range])
            }.joined()
        }
        let korean = line("ko", "첫 문장입니다. 다음 문장입니다.", 0, 40)
        let above = line("above", "위쪽 문장입니다.", 0, 20)
        let below = line("below", "아래 문장입니다.", 0, 60)
        let page = [above, korean, below]
        try Runner.require(selected(page, [CGPoint(x: 5, y: 47), CGPoint(x: 65, y: 47)]) == "첫 문장입니다.", "Korean neighbor or second sentence leaked")
        try Runner.require(selected(page, [CGPoint(x: 100, y: 45), CGPoint(x: 165, y: 45)]) == "다음 문장입니다.", "second sentence could not be targeted")
        try Runner.require(selected(page, [CGPoint(x: 5, y: 35), CGPoint(x: 65, y: 35)]) == "위쪽 문장입니다.", "underline in line gap should select the preceding line")
        for y: CGFloat in [50, 52, 54, 55, 57, 59] {
            try Runner.require(selected(page, [CGPoint(x: 5, y: y), CGPoint(x: 65, y: y)]) == "첫 문장입니다.", "underline rejected or selected next row at y=\(y)")
        }
        try Runner.require(selected(page, [CGPoint(x: 5, y: 62), CGPoint(x: 65, y: 62)]) == "아래 문장입니다.", "stroke on next row ink should select that row")
        let ja = line("ja", "本を読みます。次の文です。", 80, 0, vertical: true)
        let neighbor = line("ja-neighbor", "隣の文章です。", 60, 0, vertical: true)
        try Runner.require(selected([ja, neighbor], [CGPoint(x: 84, y: 5), CGPoint(x: 84, y: 60)]) == "本を読みます。", "Japanese neighboring column leaked")
        try Runner.require(selected([ja, neighbor], [CGPoint(x: 84, y: 120), CGPoint(x: 84, y: 80)]) == "次の文です。", "upward Japanese second sentence failed")
        try Runner.require(selected([ja, neighbor], [CGPoint(x: 75, y: 5), CGPoint(x: 75, y: 55)]) == "隣の文章です。", "vertical margin stroke should select preceding column")
        let continuation = [line("first", "これは長い", 80, 0, vertical: true), line("second", "一つの文です。別の文です。", 60, 0, vertical: true)]
        try Runner.require(selected(continuation, [CGPoint(x: 85, y: 0), CGPoint(x: 85, y: 45)]) == "これは長い一つの文です。", "cross-column sentence expansion failed")
        let decimal = line("decimal", "값은 3.14입니다. 다음 문장입니다.", 0, 0)
        try Runner.require(selected([decimal], [CGPoint(x: 5, y: 5), CGPoint(x: 90, y: 5)]) == "값은 3.14입니다.", "decimal split sentence")
        let quote = line("quote", "「本を読む。」次の文です。", 0, 0)
        try Runner.require(selected([quote], [CGPoint(x: 5, y: 5), CGPoint(x: 55, y: 5)]) == "「本を読む。」", "closing quote dropped")
        let noGeometry = OCRSentenceSelectionLine(id: korean.id, text: korean.text, rect: korean.rect, isVertical: false, characterBoxes: [])
        try Runner.require(selected([noGeometry], [CGPoint(x: 5, y: 45), CGPoint(x: 65, y: 45)]).isEmpty, "missing glyph geometry should not guess")
        try Runner.require(selected([korean], [CGPoint(x: 0, y: 45), CGPoint(x: 180, y: 45)]).isEmpty, "two equally touched sentences should not be saved together")
        let slices = OCRSentenceSelector.select(lines: [korean], points: [CGPoint(x: 100, y: 45), CGPoint(x: 165, y: 45)])
        guard let slice = slices.first, let fragment = OCRSentenceSelector.fragment(text: korean.text, characterBoxes: korean.characterBoxes, lineRect: korean.rect, range: slice.range) else {
            throw TestFailure.assertion("selected sentence could not form snapshot")
        }
        try Runner.require(fragment.text == "다음 문장입니다." && fragment.rect.minX == CGFloat(slice.range.lowerBound) * 10,
                           "stored text and highlight source range differ")
        try Runner.require(fragment.rect.width == CGFloat(slice.range.count) * 10, "highlight extends past sentence")
        try Runner.require(OCRSentenceSelector.fragment(text: korean.text, characterBoxes: [], lineRect: korean.rect, range: slice.range) == nil,
                           "missing geometry produced a misleading highlight")
        print("PASS sentence targeting: Korean/Japanese, neighbors, cross-column, quotes, decimals, ambiguity")
    }
}
