import Foundation

// Lightweight payload fixtures isolate the archive codec from the iOS app and its storage.
// These are not substitutes for testing the production model schema or library replacement.
nonisolated struct LibraryStateSnapshot: Codable, Sendable {
    var books: [BackupBook] = []
    var insights: [BackupItem] = []
    var selectedBookID: UUID?

    var isEmpty: Bool { books.isEmpty && insights.isEmpty }
}

nonisolated struct BackupBook: Codable, Sendable {
    var id = UUID()
    var title = "Test book"
    var highlights: [BackupItem] = []
    var readingRecords: [BackupItem] = []
}

nonisolated struct BackupItem: Codable, Sendable {
    var id = UUID()
    var text = "Test passage"
}
