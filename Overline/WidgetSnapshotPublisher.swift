import Foundation
import OSLog
import WidgetKit

@MainActor enum WidgetSnapshotPublisher {
    private static let logger = Logger(subsystem: "vote.aib.bzogak", category: "Widgets")

    static func publish(books: [ReadingBook]) {
        var widgetBooks: [WidgetBook] = []
        var quotes: [WidgetQuote] = []
        for book in books {
            let record = book.readingRecords.max { $0.updatedAt < $1.updatedAt }
            widgetBooks.append(WidgetBook(
                id: book.id, title: String(book.title.prefix(200)), author: String(book.author.prefix(120)),
                bookmark: record?.status == .reading ? record?.bookmarkPage : nil,
                readingUpdatedAt: record?.status == .reading ? record?.updatedAt : nil,
                coverURL: book.coverURLString
            ))
            for highlight in book.highlights where highlight.source == .capture && !highlight.text.trimmed.isEmpty {
                quotes.append(WidgetQuote(
                    id: highlight.id, bookID: book.id, text: String(highlight.text.prefix(800)),
                    bookTitle: String(book.title.prefix(200)), author: String(book.author.prefix(120)),
                    page: String(highlight.pageReference.prefix(40)), tone: highlight.stickyTone.rawValue,
                    createdAt: highlight.createdAt
                ))
            }
        }
        quotes.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        let recentQuotes = Array(quotes.prefix(500))
        let quoteBooks = Set(recentQuotes.map(\.bookID))
        let readingIDs = Set(widgetBooks.filter { $0.readingUpdatedAt != nil }
            .sorted { $0.readingUpdatedAt! > $1.readingUpdatedAt! }.prefix(100).map(\.id))
        let snapshot = ReadingWidgetSnapshot(quotes: recentQuotes,
            books: widgetBooks.filter { quoteBooks.contains($0.id) || readingIDs.contains($0.id) })
        do {
            if try WidgetStore().writeSnapshot(snapshot) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.quoteKind)
            }
        } catch {
            // Widget export failure must never interrupt the primary library save.
            logger.error("Widget snapshot export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
