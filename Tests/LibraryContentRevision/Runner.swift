import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

@MainActor
private final class DelayedResponse {
    private var response: CheckedContinuation<String, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func generate() async -> String {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        response?.resume(returning: "Delayed insight from the original library")
        response = nil
    }
}

@main
@MainActor
struct LibraryContentRevisionTests {
    static func main() async {
        do {
            try await runCheck(ProcessInfo.processInfo.arguments[1])
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func runCheck(_ scenario: String) async throws {
        let originalBook = ReadingBook(
            title: "Original book", author: "Test author", summary: "",
            coverTheme: .forest, highlights: []
        )
        let library = ReadingLibrary(books: [originalBook], includePersistedHighlights: false)
        if scenario == "bookmark" {
            let record = library.addReadingRecord(
                to: originalBook.id, startedAt: .now, endedAt: nil,
                status: .paused, rating: nil, review: "", bookmarkPage: 128
            )!
            let encoded = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(ReadingRecord.self, from: encoded)
            try require(decoded.bookmarkPage == 128, "Bookmark must survive serialization")
            var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            legacy.removeValue(forKey: "bookmarkPage")
            let legacyRecord = try JSONDecoder().decode(ReadingRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
            try require(legacyRecord.bookmarkPage == nil, "Old records must decode without bookmark")
            library.updateReadingRecord(
                record.id, in: originalBook.id, startedAt: record.startedAt, endedAt: .now,
                status: .completed, rating: nil, review: "", bookmarkPage: 128
            )
            try require(library.books[0].readingRecords[0].bookmarkPage == 128, "Completed records must retain bookmark")
            library.updateReadingRecord(
                record.id, in: originalBook.id, startedAt: record.startedAt, endedAt: nil,
                status: .reading, rating: nil, review: "", bookmarkPage: nil
            )
            try require(library.books[0].readingRecords[0].bookmarkPage == nil, "Clearing bookmark must persist")
            try require(ReadingRecord(startedAt: .now, status: .reading, bookmarkPage: -1).bookmarkPage == nil, "Negative page must be rejected")
            print("PASS: bookmark")
            return
        }
        if scenario == "ocr-metadata" {
            let original = library.addCapturedHighlight(
                text: "Original OCR text", memo: "", language: .english,
                bookID: originalBook.id
            )
            library.updateHighlight(
                original.id, text: original.text, memo: "User memo",
                pageReference: "p.99", tagsText: "#manual",
                stickyTone: .mint
            )
            let latest = library.highlight(with: original.id)!
            let corrected = library.applyAutomaticOCRCorrection(
                "Corrected OCR text", to: original.id, expectedHighlight: original
            )
            try require(corrected?.text == "Corrected OCR text", "Metadata must not block correction")
            try require(corrected?.memo == latest.memo && corrected?.tags == latest.tags
                && corrected?.pageReference == latest.pageReference
                && corrected?.stickyTone == latest.stickyTone, "Preserve user metadata")
            let stale = library.applyAutomaticOCRCorrection(
                "Stale correction", to: original.id, expectedHighlight: original
            )
            try require(stale == nil, "Changed text must reject stale correction")
            print("PASS: ocr-metadata")
            return
        }
        let originalRevision = library.contentRevision
        let response = DelayedResponse()
        let task = Task { @MainActor in
            let revision = library.contentRevision
            let body = await response.generate()
            return library.addInsight(
                expectedContentRevision: revision, categoryRaw: "expand", prompt: "Test question",
                body: body, sourceCount: 1, sourceHighlightIDs: [UUID()]
            )
        }
        await response.waitUntilStarted()

        var expectedSaved = false
        switch scenario {
        case "unchanged":
            expectedSaved = true
        case "replace", "same-ids":
            var importedBook = originalBook
            if scenario == "replace" { importedBook.id = UUID() }
            importedBook.title = "Imported book"
            let importedInsight = LibraryInsight(categoryRaw: "digest", prompt: "Imported", body: "Imported insight", sourceCount: 0)
            library.replaceLibrary(with: LibraryStateSnapshot(
                books: [importedBook], insights: [importedInsight], selectedBookID: importedBook.id
            ))
        case "reset":
            library.resetLibrary()
        case "restore":
            let snapshot = LibraryStateSnapshot(books: [originalBook], insights: [], selectedBookID: originalBook.id)
            UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: "overline.librarySnapshot.resetBackup.v1")
            try require(library.restoreLastResetBackup(), "Restore failed")
        case "failed-restore":
            UserDefaults.standard.removeObject(forKey: "overline.librarySnapshot.resetBackup.v1")
            try require(!library.restoreLastResetBackup(), "Missing backup should fail")
            expectedSaved = true
        case "repeated-replacement":
            let snapshot = LibraryStateSnapshot(books: [originalBook], insights: [], selectedBookID: originalBook.id)
            library.replaceLibrary(with: snapshot)
            let firstReplacementRevision = library.contentRevision
            library.replaceLibrary(with: snapshot)
            try require(library.contentRevision != firstReplacementRevision, "Identical replacement reused a revision")
        default:
            throw TestFailure(description: "Unknown scenario: \(scenario)")
        }

        let expectedBooks = library.books
        let expectedInsights = library.savedInsights
        response.finish()
        let saved = await task.value

        try require((saved != nil) == expectedSaved, "Unexpected save result for \(scenario)")
        try require(library.books == expectedBooks, "Completion modified books")
        if expectedSaved {
            try require(library.contentRevision == originalRevision, "Ordinary insight save changed library revision")
            try require(library.savedInsights.count == expectedInsights.count + 1, "Current result was not saved")
        } else {
            try require(library.contentRevision != originalRevision, "Whole-library replacement did not advance revision")
            try require(library.savedInsights == expectedInsights, "Stale result contaminated replacement library")
        }
        print("PASS: \(scenario)")
    }
}
