import Foundation
import UIKit

nonisolated struct PageReadingDraftPage: Codable, Equatable, Sendable {
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

    func load(now: Date = .now) async -> PageReadingDraft? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try await readProtectedData()
        } catch {
            return nil
        }

        do {
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

    func removeIfExpired(now: Date = .now) async {
        _ = await load(now: now)
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
