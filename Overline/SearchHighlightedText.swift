import SwiftUI

struct SearchHighlightedText: View {
    let text: String
    let query: String
    var font: Font
    var foregroundStyle: Color
    var lineSpacing: CGFloat = 0
    var lineLimit: Int?

    var body: some View {
        Text(highlightedText)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .lineSpacing(lineSpacing)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var highlightedText: AttributedString {
        var attributed = AttributedString(text)
        attributed.overlineApplySearchHighlight(query: query)
        return attributed
    }
}

extension AttributedString {
    mutating func overlineApplySearchHighlight(query: String) {
        let needle = query.trimmed
        guard !needle.isEmpty else { return }

        let searchable = String(characters)
        var lowerBound = searchable.startIndex

        while lowerBound < searchable.endIndex,
              let range = searchable.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: lowerBound..<searchable.endIndex
              ) {
            guard !range.isEmpty else { break }

            if let start = AttributedString.Index(range.lowerBound, within: self),
               let end = AttributedString.Index(range.upperBound, within: self) {
                self[start..<end].backgroundColor = Color.overlineHighlight.opacity(0.42)
            }

            lowerBound = range.upperBound
        }
    }
}
