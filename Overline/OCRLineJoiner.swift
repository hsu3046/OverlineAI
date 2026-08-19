import Foundation

nonisolated enum OCRLineJoiner {
    static func joined(_ lines: [String]) -> String {
        let normalizedLines = lines
            .map(cleanedLine)
            .filter { !$0.isEmpty }

        guard let firstLine = normalizedLines.first else { return "" }

        return normalizedLines.dropFirst().reduce(firstLine) { output, line in
            output + inlineSeparator(between: output, and: line) + line
        }
        .cleanedOCRText
    }

    static func inlineSeparator(between previous: String, and next: String) -> String {
        guard
            let previousCharacter = previous.lastNonWhitespaceCharacter,
            let nextCharacter = next.firstNonWhitespaceCharacter
        else {
            return ""
        }

        if endsWithSpacingPunctuation(previous) {
            return " "
        }

        if previousCharacter.isCJKText || nextCharacter.isCJKText {
            return ""
        }

        return " "
    }

    private static func cleanedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmed
    }

    private static func endsWithSpacingPunctuation(_ text: String) -> Bool {
        let trimmedText = text.trimmed
        guard let lastCharacter = trimmedText.last else { return false }
        if ".!?;:,。！？；：、，".contains(lastCharacter) {
            return true
        }

        guard "\"”’'」』".contains(lastCharacter) else { return false }
        let strippedText = trimmedText
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"”’'」』").union(.whitespacesAndNewlines))
        guard let previousCharacter = strippedText.last else { return false }
        return ".!?;:,。！？；：、，".contains(previousCharacter)
    }
}

private extension String {
    nonisolated var firstNonWhitespaceCharacter: Character? {
        first { !$0.isWhitespace }
    }

    nonisolated var lastNonWhitespaceCharacter: Character? {
        reversed().first { !$0.isWhitespace }
    }

    nonisolated var cleanedOCRText: String {
        replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
            .trimmed
    }
}

private extension Character {
    nonisolated var isCJKText: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF,   // Hangul Jamo
                 0x3130...0x318F,   // Hangul Compatibility Jamo
                 0xAC00...0xD7AF,   // Hangul Syllables
                 0x3040...0x309F,   // Hiragana
                 0x30A0...0x30FF,   // Katakana
                 0x3400...0x4DBF,   // CJK Extension A
                 0x4E00...0x9FFF:   // CJK Unified Ideographs
                true
            default:
                false
            }
        }
    }
}
