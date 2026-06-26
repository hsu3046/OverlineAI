import Foundation

struct OCRTextRefinementRequest: Sendable {
    var selectedText: String
    var pageText: String
    var selectedLines: [String] = []
    var pageLines: [String] = []
    var language: CaptureLanguage
    var selectedLineCount: Int
    var allowsBoundaryTrimming: Bool
}

struct OCRTextRefiner {
    func refinedText(for request: OCRTextRefinementRequest) async -> String {
        let locallyCleanedText = Self.localCleanup(request.selectedText)
        return request.allowsBoundaryTrimming
            ? Self.conservativeBoundaryTrim(locallyCleanedText)
            : locallyCleanedText
    }

    private static func localCleanup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
                    .trimmed
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmed
    }

    private static func conservativeBoundaryTrim(_ text: String) -> String {
        let leadingTrimmedText = text.replacingOccurrences(
            of: #"^["“”‘’']?(?:거야|거지|거다|말이다|것이다|것이었다)[.!?。！？]["”’']?\s+"#,
            with: "",
            options: .regularExpression
        )

        let trailingTrimmedText = trimmingTrailingIncompleteFragment(leadingTrimmedText)
        return localCleanup(trailingTrimmedText)
    }

    private static func trimmingTrailingIncompleteFragment(_ text: String) -> String {
        let trimmedText = text.trimmed
        guard
            !trimmedText.isEmpty,
            !endsAtSentenceBoundary(trimmedText),
            let sentenceEndIndex = lastSentenceBoundaryEndIndex(in: trimmedText)
        else {
            return trimmedText
        }

        let suffix = String(trimmedText[sentenceEndIndex...]).trimmed
        guard !suffix.isEmpty else { return trimmedText }

        let suffixComparableLength = comparable(suffix).count
        let looksLikeOpenQuote = suffix.first.map { "\"“‘'".contains($0) } ?? false
        guard suffixComparableLength <= 10 || looksLikeOpenQuote else {
            return trimmedText
        }

        return String(trimmedText[..<sentenceEndIndex]).trimmed
    }

    private static func endsAtSentenceBoundary(_ text: String) -> Bool {
        guard let lastCharacter = text.last else { return false }
        if ".!?。！？".contains(lastCharacter) {
            return true
        }

        let closingQuoteCharacters = "\"”’'"
        guard closingQuoteCharacters.contains(lastCharacter) else {
            return false
        }

        let droppedClosingQuotes = text.dropLast()
            .trimmingCharacters(in: CharacterSet(charactersIn: closingQuoteCharacters).union(.whitespacesAndNewlines))
        guard let previousCharacter = droppedClosingQuotes.last else { return false }
        return ".!?。！？".contains(previousCharacter)
    }

    private static func lastSentenceBoundaryEndIndex(in text: String) -> String.Index? {
        var boundaryIndex: String.Index?
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if ".!?。！？".contains(text[cursor]) {
                var endIndex = text.index(after: cursor)
                while endIndex < text.endIndex, "\"”’'".contains(text[endIndex]) {
                    endIndex = text.index(after: endIndex)
                }
                boundaryIndex = endIndex
            }
            cursor = text.index(after: cursor)
        }

        return boundaryIndex
    }

    private static func comparable(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]"#, with: "", options: .regularExpression)
    }
}
