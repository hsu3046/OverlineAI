import Foundation

@main struct WidgetTests {
    static func check(_ value: Bool) { precondition(value) }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_001)
        let bookID = UUID()
        let quotes = (0..<60).map { index in
            WidgetQuote(id: UUID(), bookID: bookID, text: "Sentence \(index)", bookTitle: "Book",
                author: "Author", page: "p.10", tone: "yellow", createdAt: now.addingTimeInterval(Double(index)))
        }
        let snapshot = ReadingWidgetSnapshot(quotes: quotes, books: [])
        let candidates = snapshot.candidates(bookID: nil)
        precondition(candidates.count == 50 && candidates.first?.id == quotes.last?.id)
        precondition(snapshot.candidates(bookID: UUID()).isEmpty)
        precondition(snapshot.candidates(bookID: bookID).count == 50)
        print("PASS recent 50 and book filtering")

        precondition(QuoteSchedule.quote(in: [], at: now) == nil)
        precondition(QuoteSchedule.quote(in: [quotes[0]], at: now)?.id == quotes[0].id)
        let cycle = (0..<50).compactMap {
            QuoteSchedule.quote(in: candidates, at: now.addingTimeInterval(Double($0) * QuoteSchedule.interval))?.id
        }
        precondition(Set(cycle).count == 50)
        precondition(QuoteSchedule.quote(in: candidates, at: now) == QuoteSchedule.quote(in: candidates.reversed(), at: now))
        precondition(QuoteSchedule.quote(in: candidates, at: now) == QuoteSchedule.quote(in: candidates, at: now.addingTimeInterval(1)))
        print("PASS stable shuffled cycle, empty and single quote")

        let dates = QuoteSchedule.dates(from: now)
        precondition(QuoteSchedule.interval == 300)
        precondition(dates.count == 73 && dates.first == now)
        precondition(dates.last!.timeIntervalSince(now) > 6 * 3600 - 300)
        precondition(dates.last!.timeIntervalSince(now) <= 6 * 3600)
        precondition(dates[1] > now && dates[1].timeIntervalSince(now) <= QuoteSchedule.interval)
        for index in 2..<dates.count { precondition(dates[index].timeIntervalSince(dates[index - 1]) == QuoteSchedule.interval) }
        print("PASS 5-minute intervals with a 6-hour timeline")

        let distinctBooks = (0..<50).map { index in
            WidgetQuote(id: UUID(), bookID: UUID(), text: "Quote \(index)", bookTitle: "Book",
                author: "", page: "", tone: "yellow", createdAt: now)
        }
        let coverIDs = QuoteSchedule.coverBookIDs(in: distinctBooks.map { Optional($0) })
        precondition(coverIDs.count == QuoteSchedule.maximumTimelineCovers)
        precondition(coverIDs == distinctBooks.prefix(3).map(\.bookID))
        print("PASS timeline cover downloads capped at three books")

        for link in [WidgetLink.capture, .book(bookID), .quote(quotes[0].id), .rankings("loans"), .rankings("bestseller")] {
            precondition(WidgetLink(url: link.url) == link)
        }
        for bad in ["https://capture", "bzogak://quote/not-a-uuid", "bzogak://rankings/unknown",
                    "bzogak://capture/extra", "bzogak://capture?delete=1"] {
            precondition(WidgetLink(url: URL(string: bad)!) == nil)
        }
        print("PASS deep-link validation")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WidgetStore(directory: directory)
        check(try store.writeSnapshot(snapshot))
        check(try !store.writeSnapshot(snapshot))
        check(try store.readSnapshot() == snapshot)
        try store.writeSnapshot(ReadingWidgetSnapshot())
        check(try store.readSnapshot().quotes.isEmpty)
        print("PASS atomic snapshot roundtrip and deletion")

        precondition(WidgetLanguage.resolve(selection: "ja", preferred: "ko") == "ja")
        precondition(WidgetLanguage.resolve(selection: "system", preferred: "en-US") == "en")
        let rankings = WidgetRankings(items: [WidgetRankingItem(id: "1", rank: 1, title: "本", author: "著者", source: "rakuten")],
            fetchedAt: "2026-09-09T00:00:00.123Z", cachedAt: now)
        precondition(rankings.isFresh(at: now.addingTimeInterval(86399)))
        precondition(!rankings.isFresh(at: now.addingTimeInterval(86400)))
        precondition(!rankings.isFresh(at: now.addingTimeInterval(-1)))
        precondition(rankings.sourceDate != nil)
        try store.writeRankings(rankings, kind: "bestseller", language: "ja")
        check(try store.readRankings(kind: "bestseller", language: "ja").cachedAt == now)
        check(try store.readRankings(kind: "bestseller", language: "ja").items.first?.source == "rakuten")
        do { _ = try store.readRankings(kind: "bestseller", language: "ko"); fatalError("Language cache leaked") }
        catch is CocoaError { }
        print("PASS language-isolated ranking cache, provider source, and fractional timestamp")

        try Data("broken".utf8).write(to: directory.appendingPathComponent("reading-v1.json"))
        do { _ = try store.readSnapshot(); fatalError("Corrupt snapshot accepted") }
        catch is DecodingError { print("PASS corrupt snapshot rejection") }
        try store.writeSnapshot(snapshot)
        check(try store.readSnapshot() == snapshot)
        print("PASS corrupt snapshot recovery")

    }
}
