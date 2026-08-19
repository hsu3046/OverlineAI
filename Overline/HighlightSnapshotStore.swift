import Foundation

enum HighlightSnapshotStore {
    // Legacy cleanup only. Current captures never write source images to disk.
    private static let folderName = "HighlightSnapshots"
    private static let resetBackupFolderName = "HighlightSnapshotsResetBackup"

    static func cleanup() {
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue,
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }

        if let remainingURLs = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ), remainingURLs.isEmpty {
            try? FileManager.default.removeItem(at: folderURL)
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
}
