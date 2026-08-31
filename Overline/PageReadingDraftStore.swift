import Foundation
import UIKit

nonisolated struct PageReadingDraftPage: Codable, Equatable, Sendable {
    let text: String
    let language: CaptureLanguage
    let recognizedLineCount: Int
    let omittedLineCount: Int
}

nonisolated struct PageReadingDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date
    let currentPageIndex: Int
    let activeCueIndex: Int
    let pages: [PageReadingDraftPage]

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date? = nil,
        expiresAt: Date,
        currentPageIndex: Int,
        activeCueIndex: Int,
        pages: [PageReadingDraftPage]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.expiresAt = expiresAt
        self.currentPageIndex = currentPageIndex
        self.activeCueIndex = activeCueIndex
        self.pages = pages
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case expiresAt
        case currentPageIndex
        case activeCueIndex
        case pages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        currentPageIndex = try container.decode(Int.self, forKey: .currentPageIndex)
        activeCueIndex = try container.decode(Int.self, forKey: .activeCueIndex)
        pages = try container.decode([PageReadingDraftPage].self, forKey: .pages)
    }
}

private nonisolated struct PageReadingDraftArchive: Codable {
    static let currentVersion = 1

    let version: Int
    let drafts: [PageReadingDraft]

    init(drafts: [PageReadingDraft]) {
        version = Self.currentVersion
        self.drafts = drafts
    }
}

private nonisolated struct DecodedPageReadingDraftArchive {
    let drafts: [PageReadingDraft]
    let needsRewrite: Bool
}

actor PageReadingDraftStore {
    static let shared = PageReadingDraftStore()
    nonisolated static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let maximumDraftCount = 3

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

    func load(now: Date = .now) async -> [PageReadingDraft] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let data: Data
        do {
            data = try await readProtectedData()
        } catch {
            return []
        }

        let decodedArchive: DecodedPageReadingDraftArchive
        do {
            decodedArchive = try decodeArchive(from: data)
        } catch {
            try? deleteFile()
            return []
        }

        let drafts = normalized(decodedArchive.drafts, now: now)
        if decodedArchive.needsRewrite || drafts != decodedArchive.drafts {
            try? persist(drafts)
        }
        return drafts
    }

    @discardableResult
    func save(_ draft: PageReadingDraft, now: Date = .now) async throws -> [PageReadingDraft] {
        guard
            isValid(draft),
            draft.expiresAt > draft.createdAt,
            draft.expiresAt > now
        else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        var drafts = await load(now: now)
        drafts.removeAll { $0.id == draft.id }
        drafts.append(draft)
        drafts = normalized(drafts, now: now)
        try persist(drafts)
        return drafts
    }

    @discardableResult
    func delete(id: PageReadingDraft.ID, now: Date = .now) async throws -> [PageReadingDraft] {
        var drafts = await load(now: now)
        drafts.removeAll { $0.id == id }
        try persist(drafts)
        return drafts
    }

    func removeIfExpired(now: Date = .now) async {
        _ = await load(now: now)
    }

    private func decodeArchive(from data: Data) throws -> DecodedPageReadingDraftArchive {
        let decoder = JSONDecoder()
        if let archive = try? decoder.decode(PageReadingDraftArchive.self, from: data) {
            return DecodedPageReadingDraftArchive(
                drafts: archive.drafts,
                needsRewrite: archive.version != PageReadingDraftArchive.currentVersion
            )
        }

        let legacyDraft = try decoder.decode(PageReadingDraft.self, from: data)
        return DecodedPageReadingDraftArchive(drafts: [legacyDraft], needsRewrite: true)
    }

    private func normalized(_ drafts: [PageReadingDraft], now: Date) -> [PageReadingDraft] {
        var draftsByID: [PageReadingDraft.ID: PageReadingDraft] = [:]
        for draft in drafts where isValid(draft) && draft.expiresAt > now {
            if let existing = draftsByID[draft.id], existing.updatedAt >= draft.updatedAt {
                continue
            }
            draftsByID[draft.id] = draft
        }

        return draftsByID.values
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(Self.maximumDraftCount)
            .map { $0 }
    }

    private func persist(_ drafts: [PageReadingDraft]) throws {
        guard !drafts.isEmpty else {
            try deleteFile()
            return
        }

        try prepareFolder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(PageReadingDraftArchive(drafts: drafts))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try excludeFromBackup(fileURL)
    }

    private func deleteFile() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func readProtectedData() async throws -> Data {
        while true {
            do {
                return try Data(contentsOf: fileURL)
            } catch {
                guard
                    Self.isProtectedFileAccessError(error),
                    await isProtectedDataUnavailable()
                else {
                    throw error
                }

                try await waitForProtectedData()
            }
        }
    }

    private func isProtectedDataUnavailable() async -> Bool {
        await MainActor.run {
            !UIApplication.shared.isProtectedDataAvailable
        }
    }

    private func waitForProtectedData() async throws {
        let notifications = NotificationCenter.default.notifications(
            named: UIApplication.protectedDataDidBecomeAvailableNotification
        )
        guard await isProtectedDataUnavailable() else { return }

        for await _ in notifications {
            try Task.checkCancellation()
            guard await isProtectedDataUnavailable() else { return }
        }

        throw CancellationError()
    }

    private static func isProtectedFileAccessError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoPermission.rawValue {
            return true
        }

        guard let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return underlyingError.domain == NSPOSIXErrorDomain
            && [
                Int(POSIXErrorCode.EACCES.rawValue),
                Int(POSIXErrorCode.EPERM.rawValue)
            ]
            .contains(underlyingError.code)
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
