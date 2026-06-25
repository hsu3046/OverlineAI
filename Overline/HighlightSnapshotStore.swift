import Foundation

enum HighlightSnapshotStore {
    private static let folderName = "HighlightSnapshots"
    private static let resetBackupFolderName = "HighlightSnapshotsResetBackup"

    static func save(_ data: Data, for highlightID: Highlight.ID) -> String? {
        let fileName = "\(highlightID.uuidString).jpg"

        do {
            let url = try preparedFolderURL().appendingPathComponent(fileName)
            try data.write(to: url, options: [.atomic])
            applyLocalOnlyResourceValues(to: url)
            return fileName
        } catch {
            return nil
        }
    }

    static var storagePolicyLabel: String {
        guard
            let url = try? preparedFolderURL(),
            let resourceValues = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]),
            resourceValues.isExcludedFromBackup == true
        else {
            return "로컬 저장 · 백업 제외 확인 필요"
        }

        return "로컬 저장 · 백업 제외"
    }

    static func url(for fileName: String?) -> URL? {
        guard let fileName, !fileName.trimmed.isEmpty else { return nil }
        return folderURL.appendingPathComponent(fileName)
    }

    static func delete(_ fileName: String?) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanup(keeping fileNames: Set<String>) {
        guard
            let folderURL = try? preparedFolderURL(),
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        for url in urls where !fileNames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func backupForReset(fileNames: Set<String>) {
        guard
            !fileNames.isEmpty,
            let backupFolderURL = try? preparedResetBackupFolderURL(emptyFirst: true)
        else {
            return
        }

        for fileName in fileNames {
            guard
                let sourceURL = url(for: fileName),
                FileManager.default.fileExists(atPath: sourceURL.path)
            else {
                continue
            }

            let destinationURL = backupFolderURL.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            applyLocalOnlyResourceValues(to: destinationURL)
        }
    }

    static func restoreResetBackup(fileNames: Set<String>) {
        guard
            !fileNames.isEmpty,
            let primaryFolderURL = try? preparedFolderURL()
        else {
            return
        }

        for fileName in fileNames {
            let sourceURL = resetBackupFolderURL.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

            let destinationURL = primaryFolderURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            applyLocalOnlyResourceValues(to: destinationURL)
        }
    }

    static func clearResetBackup() {
        try? FileManager.default.removeItem(at: resetBackupFolderURL)
    }

    private static var folderURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(folderName, isDirectory: true)
    }

    private static var resetBackupFolderURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(resetBackupFolderName, isDirectory: true)
    }

    private static func preparedFolderURL() throws -> URL {
        let url = folderURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        applyLocalOnlyResourceValues(to: url)

        return url
    }

    private static func preparedResetBackupFolderURL(emptyFirst: Bool) throws -> URL {
        let url = resetBackupFolderURL
        if emptyFirst {
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        applyLocalOnlyResourceValues(to: url)

        return url
    }

    private static func applyLocalOnlyResourceValues(to url: URL) {
        var url = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)

        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
