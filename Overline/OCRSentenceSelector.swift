import Foundation
import CoreGraphics
import NaturalLanguage

nonisolated struct OCRSentenceSelectionLine {
    let id: String
    let text: String
    let rect: CGRect
    let isVertical: Bool
    let characterBoxes: [CGRect?]
}

nonisolated struct OCRSentenceSlice: Equatable {
    let lineID: String
    let range: Range<Int>
}

/// One stroke resolves to one sentence. Geometry is in display points; ranges count Characters.
nonisolated enum OCRSentenceSelector {
    private struct Span {
        let line: OCRSentenceSelectionLine
        let range: Range<Int>
    }

    static func fragment(text: String, characterBoxes: [CGRect?], lineRect: CGRect, range: Range<Int>) -> (text: String, rect: CGRect)? {
        let characters = Array(text)
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= characters.count else { return nil }
        if range == 0..<characters.count { return (text, lineRect) }
        guard characterBoxes.count == characters.count, range.allSatisfy({
            characters[$0].isWhitespace || characterBoxes[$0] != nil
        }) else { return nil }
        let boxes = characterBoxes[range].compactMap { $0 }
        guard let first = boxes.first else { return nil }
        return (String(characters[range]), boxes.dropFirst().reduce(first) { $0.union($1) })
    }

    static func select(lines: [OCRSentenceSelectionLine], points: [CGPoint]) -> [OCRSentenceSlice] {
        guard points.count >= 2 else { return [] }
        let candidates = lines.compactMap { line -> (OCRSentenceSelectionLine, CGFloat)? in
            guard let distance = distance(to: line, points: points, neighbors: lines) else { return nil }
            return (line, distance)
        }.sorted { $0.1 < $1.1 }
        guard let best = candidates.first else { return [] }
        if candidates.count > 1, candidates[1].1 - best.1 < 2 { return [] }

        var document = ""
        var spans: [Span] = []
        for line in lines {
            if !document.isEmpty { document += OCRLineJoiner.inlineSeparator(between: document, and: line.text) }
            let start = document.count
            document += line.text
            spans.append(Span(line: line, range: start..<document.count))
        }
        guard let anchor = spans.first(where: { $0.line.id == best.0.id }) else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = document
        let characters = Array(document)
        var sentences: [Range<Int>] = []
        tokenizer.enumerateTokens(in: document.startIndex..<document.endIndex) { range, _ in
            var start = document.distance(from: document.startIndex, to: range.lowerBound)
            var end = document.distance(from: document.startIndex, to: range.upperBound)
            while start < end, characters[start].isWhitespace { start += 1 }
            while end > start, characters[end - 1].isWhitespace { end -= 1 }
            if start < end { sentences.append(start..<end) }
            return true
        }
        let touching = sentences.filter { $0.overlaps(anchor.range) }
        guard !touching.isEmpty else { return [] }
        let sentence: Range<Int>
        if touching.count == 1 {
            sentence = touching[0]
        } else {
            // Do not guess a character position from proportional line width.
            guard anchor.line.characterBoxes.count == anchor.line.text.count else { return [] }
            let scored = touching.map { range -> (Range<Int>, CGFloat) in
                var score: CGFloat = 0
                for offset in 0..<anchor.line.text.count where range.contains(anchor.range.lowerBound + offset) {
                    guard let box = anchor.line.characterBoxes[offset] else { continue }
                    score += overlap(box: box, line: anchor.line, points: points)
                }
                return (range, score)
            }.sorted { $0.1 > $1.1 }
            guard let winner = scored.first, winner.1 > 0 else { return [] }
            if scored.count > 1, scored[1].1 >= winner.1 * 0.85 { return [] }
            sentence = winner.0
        }
        return spans.compactMap { span in
            let lower = max(span.range.lowerBound, sentence.lowerBound)
            let upper = min(span.range.upperBound, sentence.upperBound)
            guard lower < upper else { return nil }
            return OCRSentenceSlice(lineID: span.line.id,
                                    range: (lower - span.range.lowerBound)..<(upper - span.range.lowerBound))
        }
    }

    private static func distance(to line: OCRSentenceSelectionLine, points: [CGPoint], neighbors: [OCRSentenceSelectionLine]) -> CGFloat? {
        let rect = line.rect
        let thickness = line.isVertical ? rect.width : rect.height
        let length = line.isVertical ? rect.height : rect.width
        guard thickness > 0, length > 0, let first = points.first, let last = points.last else { return nil }
        let parallel = line.isVertical ? abs(last.y - first.y) : abs(last.x - first.x)
        let perpendicular = line.isVertical ? abs(last.x - first.x) : abs(last.y - first.y)
        guard parallel > perpendicular, parallel >= 14 else { return nil }
        let center = line.isVertical ? rect.midX : rect.midY
        let minAlong = line.isVertical ? rect.minY : rect.minX
        let maxAlong = line.isVertical ? rect.maxY : rect.maxX
        let startAlong = line.isVertical ? first.y : first.x
        let endAlong = line.isVertical ? last.y : last.x
        let overlap = min(max(startAlong, endAlong), maxAlong) - max(min(startAlong, endAlong), minAlong)
        guard overlap >= min(12, length * 0.1) else { return nil }
        let minCross = line.isVertical ? rect.minX : rect.minY
        let maxCross = line.isVertical ? rect.maxX : rect.maxY
        var beforeAllowance = max(thickness * 0.9, 10)
        var afterAllowance = beforeAllowance
        for other in neighbors where other.id != line.id && other.isVertical == line.isVertical {
            let otherMin = line.isVertical ? other.rect.minY : other.rect.minX
            let otherMax = line.isVertical ? other.rect.maxY : other.rect.maxX
            guard min(maxAlong, otherMax) > max(minAlong, otherMin) else { continue }
            let otherCrossMin = line.isVertical ? other.rect.minX : other.rect.minY
            let otherCrossMax = line.isVertical ? other.rect.maxX : other.rect.maxY
            if otherCrossMin >= maxCross { afterAllowance = min(afterAllowance, otherCrossMin - maxCross) }
            // The shared gap belongs to the preceding line's underline side. Do not
            // also nominate the next line from its top/left margin and recreate a tie.
            if otherCrossMax <= minCross { beforeAllowance = 0 }
        }
        // Resample by path length so touch event frequency does not bias the winner.
        let samples = sampled(points)
        let nearby = samples.filter {
            let along = line.isVertical ? $0.y : $0.x
            return along >= minAlong - 8 && along <= maxAlong + 8
        }
        guard !nearby.isEmpty else { return nil }
        let crossPositions = nearby.map { line.isVertical ? $0.x : $0.y }
        let accepted = crossPositions.filter { $0 >= minCross - beforeAllowance && $0 <= maxCross + afterAllowance }
        guard accepted.count * 4 >= crossPositions.count * 3 else { return nil }
        let costs = accepted.map { position -> CGFloat in
            if position >= minCross && position <= maxCross {
                // A stroke on the ink takes priority over a neighboring line's margin.
                return abs(position - center) * 0.25
            }
            if position > maxCross {
                // Horizontal underlines belong above the stroke; vertical margin marks
                // conventionally belong to the column to their left.
                return 5 + position - maxCross
            }
            return 5 + minCross - position + thickness * 0.5
        }
        return costs.reduce(0, +) / CGFloat(costs.count)
    }

    private static func overlap(box: CGRect, line: OCRSentenceSelectionLine, points: [CGPoint]) -> CGFloat {
        let along = points.map { line.isVertical ? $0.y : $0.x }
        guard let lower = along.min(), let upper = along.max() else { return 0 }
        return max(0, min(upper, line.isVertical ? box.maxY : box.maxX) - max(lower, line.isVertical ? box.minY : box.minX))
    }

    private static func sampled(_ points: [CGPoint]) -> [CGPoint] {
        var samples: [CGPoint] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 4))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                samples.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        if let last = points.last { samples.append(last) }
        return samples
    }
}
