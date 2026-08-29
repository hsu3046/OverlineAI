import Foundation

nonisolated struct PageReadingDraftPage: Codable, Sendable {
    let text: String
    let language: CaptureLanguage
    let recognizedLineCount: Int
    let omittedLineCount: Int
}

nonisolated struct PageReadingDraft: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let expiresAt: Date
    let currentPageIndex: Int
    let activeCueIndex: Int
    let pages: [PageReadingDraftPage]
}

actor PageReadingDraftStore {
    static let shared = PageReadingDraftStore()
    nonisolated static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    private static let folderName = "TemporaryPageReading"
    private static let fileName = "reading-session.json"
    private static let maximumStoredCharacterCount = 500_000
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        fileURL = baseURL
            .appendingPathComponent(Self.folderName, isDirectory: true)
            .appendingPathComponent(Self.fileName, isDirectory: false)
    }

    func load(now: Date = .now) -> PageReadingDraft? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let draft = try JSONDecoder().decode(PageReadingDraft.self, from: data)
            guard isValid(draft), draft.expiresAt > now else {
                try? delete()
                return nil
            }
            return draft
        } catch {
            try? delete()
            return nil
        }
    }

    func save(_ draft: PageReadingDraft, now: Date = .now) throws {
        guard
            isValid(draft),
            draft.expiresAt > draft.createdAt,
            draft.expiresAt > now
        else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        try prepareFolder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(draft)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try excludeFromBackup(fileURL)
    }

    func delete() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func removeIfExpired(now: Date = .now) {
        _ = load(now: now)
    }

    private func prepareFolder() throws {
        let folderURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try excludeFromBackup(folderURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private func isValid(_ draft: PageReadingDraft) -> Bool {
        guard
            !draft.pages.isEmpty,
            draft.pages.count <= 10,
            draft.currentPageIndex >= 0,
            draft.currentPageIndex < draft.pages.count,
            draft.activeCueIndex >= 0
        else {
            return false
        }

        var characterCount = 0
        for page in draft.pages {
            guard !page.text.trimmed.isEmpty else { return false }
            characterCount += page.text.count
            guard characterCount <= Self.maximumStoredCharacterCount else { return false }
        }
        return true
    }
}
