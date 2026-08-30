import Foundation

nonisolated enum AutomaticOCRCorrectionValidator {
    static func validatedCorrection(originalText: String, candidateText: String) -> String? {
        let original = normalizedText(originalText)
        let candidate = normalizedText(candidateText)

        guard !original.isEmpty, !candidate.isEmpty, original != candidate else { return nil }
        guard !hasSuspiciousHeading(candidate) else { return nil }

        let lengthRatio = Double(candidate.count) / Double(max(original.count, 1))
        guard (0.92...1.08).contains(lengthRatio) else { return nil }

        let originalComparable = comparableText(original)
        let candidateComparable = comparableText(candidate)
        guard !originalComparable.isEmpty, !candidateComparable.isEmpty else { return nil }

        let comparableRatio = Double(candidateComparable.count) / Double(max(originalComparable.count, 1))
        guard (0.95...1.05).contains(comparableRatio) else { return nil }
        guard digitRuns(in: original) == digitRuns(in: candidate) else { return nil }

        let maximumCount = max(originalComparable.count, candidateComparable.count)
        let maximumDistance = min(12, max(2, Int(ceil(Double(maximumCount) * 0.04))))
        let distance = boundedEditDistance(
            Array(originalComparable),
            Array(candidateComparable),
            limit: maximumDistance
        )
        guard distance <= maximumDistance else { return nil }

        let sentenceDelta = abs(sentenceBoundaryCount(in: original) - sentenceBoundaryCount(in: candidate))
        guard sentenceDelta <= 1 else { return nil }

        return candidate
    }

    private static func normalizedText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
                    .trimmed
            }

        var normalizedLines: [String] = []
        var previousWasEmpty = false
        for line in lines {
            if line.isEmpty {
                if !previousWasEmpty, !normalizedLines.isEmpty {
                    normalizedLines.append("")
                }
                previousWasEmpty = true
            } else {
                normalizedLines.append(line)
                previousWasEmpty = false
            }
        }

        while normalizedLines.last?.isEmpty == true {
            normalizedLines.removeLast()
        }

        return normalizedLines
            .joined(separator: "\n")
            .normalizedQuotesForStorage
            .trimmed
    }

    private static func comparableText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]"#, with: "", options: .regularExpression)
    }

    private static func digitRuns(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\p{Nd}+"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func sentenceBoundaryCount(in text: String) -> Int {
        text.filter { ".!?。！？".contains($0) }.count
    }

    private static func hasSuspiciousHeading(_ text: String) -> Bool {
        let compactPrefix = text.prefix(24).lowercased()
        return ["교정된 텍스트", "수정된 텍스트", "교정 결과", "수정 결과", "corrected text"]
            .contains { compactPrefix.contains($0) }
    }

    private static func boundedEditDistance(
        _ lhs: [Character],
        _ rhs: [Character],
        limit: Int
    ) -> Int {
        guard abs(lhs.count - rhs.count) <= limit else { return limit + 1 }
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)

        for lhsIndex in lhs.indices {
            var current = Array(repeating: limit + 1, count: rhs.count + 1)
            current[0] = lhsIndex + 1
            let lowerBound = max(0, lhsIndex - limit)
            let upperBound = min(rhs.count - 1, lhsIndex + limit)
            var rowMinimum = limit + 1

            if lowerBound <= upperBound {
                for rhsIndex in lowerBound...upperBound {
                    let substitutionCost = lhs[lhsIndex] == rhs[rhsIndex] ? 0 : 1
                    let insertion = current[rhsIndex] + 1
                    let deletion = previous[rhsIndex + 1] + 1
                    let substitution = previous[rhsIndex] + substitutionCost
                    let value = min(insertion, deletion, substitution)
                    current[rhsIndex + 1] = value
                    rowMinimum = min(rowMinimum, value)
                }
            }

            if rowMinimum > limit { return limit + 1 }
            previous = current
        }

        return previous[rhs.count]
    }
}
