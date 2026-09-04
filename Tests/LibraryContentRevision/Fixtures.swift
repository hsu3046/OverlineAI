import Foundation

// Replace peripheral UI types and disk cleanup; library and backup logic are production code.
enum AppTab: String, Equatable {
    case capture, library, insights, community
}

enum InsightPrompt: String, Equatable {
    case questions, connect, expand, digest
}

enum HighlightSnapshotStore {
    static func cleanup() {}
    static func clearResetBackup() {}
}

// Shadows Foundation.UserDefaults in this test module, including calls from Models.swift.
// No test reads or writes the user's real preferences or library backup.
nonisolated final class UserDefaults: @unchecked Sendable {
    static let standard = UserDefaults()
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        lock.withLock { values[key] }
    }

    func set(_ value: Data, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    func removeObject(forKey key: String) {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
