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
