import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

private func expectError(_ expected: LibraryBackupError, _ operation: () throws -> Void) throws {
    do {
        try operation()
    } catch let actual as LibraryBackupError {
        switch (expected, actual) {
        case (.invalidFile, .invalidFile), (.emptyLibrary, .emptyLibrary), (.fileTooLarge, .fileTooLarge):
            return
        case let (.unsupportedVersion(lhs), .unsupportedVersion(rhs)) where lhs == rhs:
            return
        default:
            throw TestFailure(description: "Expected \(expected), got \(actual)")
        }
    }
    throw TestFailure(description: "Expected \(expected), but operation succeeded")
}

private func decode(_ data: Data) throws -> DecodedLibraryBackup {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-test-\(UUID()).bzogak")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    return try LibraryBackupCodec.decode(contentsOf: url)
}

private func header(format: String = LibraryBackupArchive.formatIdentifier, version: Int) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["format": format, "formatVersion": version])
}

private func encode(_ snapshot: LibraryStateSnapshot) throws -> Data {
    try LibraryBackupCodec.encode(snapshot: snapshot, exportedAt: Date(timeIntervalSince1970: 1_700_000_000), appVersion: "1.0")
}

@main
struct BackupCodecTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("future version without old payload reports update required", {
                try expectError(.unsupportedVersion(2)) { _ = try decode(header(version: 2)) }
            }),
            ("future version with incompatible payload reports update required", {
                let data = try JSONSerialization.data(withJSONObject: [
                    "format": LibraryBackupArchive.formatIdentifier, "formatVersion": 2,
                    "exportedAt": 42, "appVersion": false, "library": "new schema",
                ])
                try expectError(.unsupportedVersion(2)) { _ = try decode(data) }
            }),
            ("wrong format remains invalid even with a future version", {
                try expectError(.invalidFile) { _ = try decode(header(format: "other-app", version: 2)) }
            }),
            ("zero and negative versions are unsupported", {
                for version in [0, -1] {
                    try expectError(.unsupportedVersion(version)) { _ = try decode(header(version: version)) }
                }
            }),
            ("current version missing payload and malformed headers remain invalid", {
                try expectError(.invalidFile) { _ = try decode(header(version: 1)) }
                for json in ["not json", "{}", "{\"format\":42,\"formatVersion\":1}", "{\"formatVersion\":\"2\"}"] {
                    try expectError(.invalidFile) { _ = try decode(Data(json.utf8)) }
                }
            }),
            ("current codec round trip preserves fixture data and metadata", {
                let book = BackupBook(highlights: [BackupItem()], readingRecords: [BackupItem()])
                let snapshot = LibraryStateSnapshot(books: [book], insights: [BackupItem()], selectedBookID: book.id)
                let result = try decode(encode(snapshot))
                try require(result.snapshot.books.first?.id == book.id, "Book identity changed")
                try require(result.snapshot.selectedBookID == book.id, "Selection changed")
                try require(result.summary == LibraryBackupSummary(snapshot: snapshot), "Summary changed")
                try require(result.exportedAt == Date(timeIntervalSince1970: 1_700_000_000), "Date changed")
            }),
            ("empty libraries and duplicate identities remain rejected", {
                try expectError(.emptyLibrary) { _ = try encode(LibraryStateSnapshot()) }
                let book = BackupBook()
                try expectError(.invalidFile) { _ = try decode(encode(LibraryStateSnapshot(books: [book, book]))) }
            }),
            ("export and import agree at the 50 MiB boundary", {
                var snapshot = LibraryStateSnapshot(books: [BackupBook(title: "")])
                let overhead = try encode(snapshot).count
                snapshot.books[0].title = String(repeating: "x", count: LibraryBackupCodec.maximumFileSize - overhead)
                let atLimit = try encode(snapshot)
                try require(atLimit.count == LibraryBackupCodec.maximumFileSize, "Boundary fixture is not exact")
                _ = try decode(atLimit)
                snapshot.books[0].title.append("x")
                try expectError(.fileTooLarge) { _ = try encode(snapshot) }
                var oversizedImport = atLimit
                oversizedImport.append(0x20)
                try expectError(.fileTooLarge) { _ = try decode(oversizedImport) }
            }),
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name): \(error)")
            }
        }
        if failures > 0 {
            print("\(failures) of \(tests.count) backup codec tests failed")
            exit(1)
        }
        print("All \(tests.count) backup codec tests passed")
    }
}
