import Foundation

nonisolated struct WidgetQuote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let bookID: UUID
    let text: String
    let bookTitle: String
    let author: String
    let page: String
    let tone: String
    let createdAt: Date
}

nonisolated struct WidgetBook: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let author: String
    let bookmark: Int?
    let readingUpdatedAt: Date?
    var coverURL: String? = nil
}

nonisolated struct ReadingWidgetSnapshot: Codable, Equatable, Sendable {
    var quotes: [WidgetQuote] = []
    var books: [WidgetBook] = []
    var schema = 1

    var readingBooks: [WidgetBook] {
        books.filter { $0.readingUpdatedAt != nil }
            .sorted { $0.readingUpdatedAt! > $1.readingUpdatedAt! }
    }

    func candidates(bookID: UUID?) -> [WidgetQuote] {
        Array(quotes.filter { bookID == nil || $0.bookID == bookID }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
            .prefix(50))
    }
}

nonisolated enum QuoteSchedule {
    static let interval: TimeInterval = 5 * 60
    static let timelineDuration: TimeInterval = 6 * 60 * 60
    static let maximumTimelineCovers = 3

    static func coverBookIDs(in quotes: [WidgetQuote?]) -> [UUID] {
        var seen = Set<UUID>()
        return Array(quotes.compactMap { $0?.bookID }
            .filter { seen.insert($0).inserted }
            .prefix(maximumTimelineCovers))
    }

    // Stable shuffle: a timeline reload must not change the quote in the same slot.
    static func quote(in quotes: [WidgetQuote], at date: Date) -> WidgetQuote? {
        let ordered = quotes.sorted {
            let lhs = stableHash($0.id.uuidString), rhs = stableHash($1.id.uuidString)
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }
        guard !ordered.isEmpty else { return nil }
        let slot = Int(floor(date.timeIntervalSince1970 / interval))
        return ordered[((slot % ordered.count) + ordered.count) % ordered.count]
    }

    static func dates(from now: Date) -> [Date] {
        let next = (floor(now.timeIntervalSince1970 / interval) + 1) * interval
        let count = Int(timelineDuration / interval)
        return [now] + (0..<count).map { Date(timeIntervalSince1970: next + Double($0) * interval) }
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

nonisolated struct WidgetRankingItem: Codable, Sendable, Identifiable {
    let id: String
    let rank: Int
    let title: String
    let author: String
    var source: String? = nil
}

nonisolated enum WidgetLanguage {
    static let preferenceKey = "overline.appLanguage"

    static func resolve(selection: String?, preferred: String) -> String {
        let requested = selection == "system" ? preferred : (selection ?? preferred)
        let code = Locale(identifier: requested).language.languageCode?.identifier ?? "ko"
        return ["ko", "ja", "en"].contains(code) ? code : "ko"
    }

    static var current: String {
        let selection = UserDefaults(suiteName: WidgetStore.group)?.string(forKey: preferenceKey)
        let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "ko"
        return resolve(selection: selection, preferred: preferred)
    }
}

nonisolated struct WidgetRankings: Codable, Sendable {
    let items: [WidgetRankingItem]
    let fetchedAt: String
    var cachedAt: Date?

    func isFresh(at now: Date) -> Bool {
        guard let cachedAt else { return false }
        return now >= cachedAt && now.timeIntervalSince(cachedAt) < 86400
    }

    var sourceDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: fetchedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: fetchedAt)
    }
}

nonisolated enum WidgetLink: Equatable {
    case capture
    case book(UUID)
    case quote(UUID)
    case rankings(String)

    var url: URL {
        switch self {
        case .capture: URL(string: "bzogak://capture")!
        case .book(let id): URL(string: "bzogak://book/\(id.uuidString)")!
        case .quote(let id): URL(string: "bzogak://quote/\(id.uuidString)")!
        case .rankings(let kind): URL(string: "bzogak://rankings/\(kind == "loans" ? "loans" : "bestseller")")!
        }
    }

    init?(url: URL) {
        guard url.scheme == "bzogak", url.query == nil, url.fragment == nil else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "capture" where parts.isEmpty: self = .capture
        case "book" where parts.count == 1:
            guard let id = UUID(uuidString: parts[0]) else { return nil }; self = .book(id)
        case "quote" where parts.count == 1:
            guard let id = UUID(uuidString: parts[0]) else { return nil }; self = .quote(id)
        case "rankings" where parts.count == 1 && ["loans", "bestseller"].contains(parts[0]):
            self = .rankings(parts[0])
        default: return nil
        }
    }
}

nonisolated struct WidgetStore {
    static let group = "group.vote.aib.bzogak"
    static let quoteKind = "BZOGAKQuotes"
    static let rankingKind = "BZOGAKRankings"
    let directory: URL

    init(directory: URL? = nil) throws {
        guard let directory = directory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.directory = directory
    }

    func readSnapshot() throws -> ReadingWidgetSnapshot {
        try read(ReadingWidgetSnapshot.self, name: "reading-v1.json")
    }

    @discardableResult func writeSnapshot(_ snapshot: ReadingWidgetSnapshot) throws -> Bool {
        if let previous = try? readSnapshot(), previous == snapshot { return false }
        try write(snapshot, name: "reading-v1.json")
        return true
    }

    func readRankings(kind: String, language: String) throws -> WidgetRankings {
        try read(WidgetRankings.self, name: rankingFile(kind, language: language))
    }

    func writeRankings(_ rankings: WidgetRankings, kind: String, language: String) throws {
        try write(rankings, name: rankingFile(kind, language: language))
    }

    private func rankingFile(_ kind: String, language: String) -> String {
        let safeLanguage = ["ko", "ja", "en"].contains(language) ? language : "ko"
        return "rankings-\(safeLanguage)-\(kind == "loans" ? "loans" : "bestseller").json"
    }

    private func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        guard data.count <= 4_000_000 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 4_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        #if os(iOS)
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        #endif
    }
}
