import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let bzogakBackup = UTType(
        exportedAs: "vote.aib.bzogak.backup",
        conformingTo: .json
    )
}

nonisolated struct LibraryBackupArchive: Codable, Sendable {
    static let formatIdentifier = "vote.aib.bzogak.library-backup"
    static let currentFormatVersion = 1

    let format: String
    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let library: LibraryStateSnapshot
}

nonisolated struct LibraryBackupSummary: Equatable, Sendable {
    let bookCount: Int
    let highlightCount: Int
    let readingRecordCount: Int
    let insightCount: Int

    init(snapshot: LibraryStateSnapshot) {
        bookCount = snapshot.books.count
        highlightCount = snapshot.books.reduce(0) { $0 + $1.highlights.count }
        readingRecordCount = snapshot.books.reduce(0) { $0 + $1.readingRecords.count }
        insightCount = snapshot.insights.count
    }

    var description: String {
        "책 \(bookCount)권 · 글조각 \(highlightCount)개 · 독서 기록 \(readingRecordCount)개 · 인사이트 \(insightCount)개"
    }
}

nonisolated struct DecodedLibraryBackup: Sendable {
    let snapshot: LibraryStateSnapshot
    let summary: LibraryBackupSummary
    let exportedAt: Date
}

nonisolated enum LibraryBackupError: LocalizedError, Sendable {
    case emptyLibrary
    case fileTooLarge
    case invalidFile
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .emptyLibrary:
            "내보내거나 가져올 독서 기록이 없습니다."
        case .fileTooLarge:
            "백업 파일이 너무 큽니다. 50MB 이하의 파일을 선택해 주세요."
        case .invalidFile:
            "글조각 서랍에서 만든 올바른 백업 파일이 아닙니다."
        case let .unsupportedVersion(version):
            "이 앱에서 아직 지원하지 않는 백업 형식입니다. 앱을 업데이트한 뒤 다시 시도해 주세요. (버전 \(version))"
        }
    }
}

nonisolated enum LibraryBackupCodec {
    static let maximumFileSize = 50 * 1_024 * 1_024

    static func encode(
        snapshot: LibraryStateSnapshot,
        exportedAt: Date,
        appVersion: String
    ) throws -> Data {
        guard !snapshot.isEmpty else {
            throw LibraryBackupError.emptyLibrary
        }

        let archive = LibraryBackupArchive(
            format: LibraryBackupArchive.formatIdentifier,
            formatVersion: LibraryBackupArchive.currentFormatVersion,
            exportedAt: exportedAt,
            appVersion: appVersion,
            library: snapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(contentsOf url: URL) throws -> DecodedLibraryBackup {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let fileSize, fileSize > maximumFileSize {
            throw LibraryBackupError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumFileSize else {
            throw LibraryBackupError.fileTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive: LibraryBackupArchive
        do {
            archive = try decoder.decode(LibraryBackupArchive.self, from: data)
        } catch {
            throw LibraryBackupError.invalidFile
        }

        guard archive.format == LibraryBackupArchive.formatIdentifier else {
            throw LibraryBackupError.invalidFile
        }
        guard archive.formatVersion > 0,
              archive.formatVersion <= LibraryBackupArchive.currentFormatVersion else {
            throw LibraryBackupError.unsupportedVersion(archive.formatVersion)
        }

        let snapshot = try validated(archive.library)
        return DecodedLibraryBackup(
            snapshot: snapshot,
            summary: LibraryBackupSummary(snapshot: snapshot),
            exportedAt: archive.exportedAt
        )
    }

    private static func validated(_ snapshot: LibraryStateSnapshot) throws -> LibraryStateSnapshot {
        guard !snapshot.isEmpty else {
            throw LibraryBackupError.emptyLibrary
        }

        let bookIDs = snapshot.books.map(\.id)
        let highlights = snapshot.books.flatMap(\.highlights)
        let readingRecords = snapshot.books.flatMap(\.readingRecords)
        let insightIDs = snapshot.insights.map(\.id)

        guard Set(bookIDs).count == bookIDs.count,
              Set(highlights.map(\.id)).count == highlights.count,
              Set(readingRecords.map(\.id)).count == readingRecords.count,
              Set(insightIDs).count == insightIDs.count else {
            throw LibraryBackupError.invalidFile
        }

        var validatedSnapshot = snapshot
        if let selectedBookID = snapshot.selectedBookID,
           !Set(bookIDs).contains(selectedBookID) {
            validatedSnapshot.selectedBookID = snapshot.books.first?.id
        }
        return validatedSnapshot
    }
}

struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.bzogakBackup] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw LibraryBackupError.invalidFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
