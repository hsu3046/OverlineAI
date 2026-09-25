import CoreGraphics

nonisolated enum OCRVerticalSelection {
    static func score(lineRect: CGRect, points: [CGPoint]) -> CGFloat? {
        guard !points.isEmpty, lineRect.width > 0, lineRect.height > 0 else { return nil }
        // Use column width for proximity; using column height selects adjacent columns.
        let allowance = max(lineRect.width * 0.65, 10)
        let nearby = points.filter {
            abs($0.x - lineRect.midX) <= lineRect.width / 2 + allowance &&
                $0.y >= lineRect.minY - 12 && $0.y <= lineRect.maxY + 12
        }
        guard let distance = nearby.map({ abs($0.x - lineRect.midX) }).min() else { return nil }
        let closeness = 1 - min(distance / (lineRect.width / 2 + allowance), 1)
        let coverage = min(CGFloat(nearby.count) / CGFloat(points.count), 1)
        let score = closeness * 0.65 + coverage * 0.35
        return score >= 0.40 ? score : nil
    }
}
