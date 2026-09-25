import CoreGraphics

nonisolated enum OCRHighlighterGesture {
    static func canBegin(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= 14
    }

    static func isValidLine(bounds: CGRect, pathLength: CGFloat) -> Bool {
        let majorLength = max(bounds.width, bounds.height)
        let minorLength = min(bounds.width, bounds.height)
        // The same threshold applies to horizontal underlines and vertical strokes.
        return majorLength >= 54 && pathLength >= 54 && majorLength >= max(minorLength * 1.12, 1)
    }
}
