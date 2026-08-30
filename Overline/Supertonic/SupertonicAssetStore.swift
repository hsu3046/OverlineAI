import CryptoKit
import Foundation

@MainActor
final class SupertonicAssetStore {
    static let downloadSizeDescription = "약 401MB"

    private(set) var state: SupertonicAssetState = .unavailable

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let revisionDirectory: URL
    private let markerURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        rootDirectory = applicationSupport.appendingPathComponent("Supertonic", isDirectory: true)
        revisionDirectory = rootDirectory.appendingPathComponent(Self.modelRevision, isDirectory: true)
        markerURL = revisionDirectory.appendingPathComponent("installed.txt")
        state = Self.hasCompleteInstallation(at: revisionDirectory, markerURL: markerURL, fileManager: fileManager)
            ? .installed
            : .unavailable
    }

    var modelPaths: SupertonicModelPaths? {
        guard state.isInstalled else { return nil }
        return SupertonicModelPaths(
            onnxDirectory: revisionDirectory.appendingPathComponent("onnx", isDirectory: true),
            voiceStyleDirectory: revisionDirectory.appendingPathComponent("voice_styles", isDirectory: true)
        )
    }

    func install(progressChanged: @escaping @MainActor (SupertonicAssetState) -> Void) async {
        if case .downloading = state { return }
        if state.isInstalled { return }

        state = .downloading(progress: 0)
        progressChanged(state)

        do {
            try prepareDirectories()
            let totalBytes = Double(Self.files.reduce(0) { $0 + $1.size })
            var completedBytes: Int64 = 0

            for file in Self.files {
                try Task.checkCancellation()
                let destination = revisionDirectory.appendingPathComponent(file.relativePath)

                if try await Self.isValidFile(at: destination, manifest: file) {
                    completedBytes += file.size
                    let progress = min(Double(completedBytes) / totalBytes, 1)
                    state = .downloading(progress: progress)
                    progressChanged(state)
                    continue
                }

                try? fileManager.removeItem(at: destination)
                try ensureAvailableStorage(requiredBytes: file.size)
                let temporaryURL = destination.appendingPathExtension("download")
                try? fileManager.removeItem(at: temporaryURL)

                let baseCompletedBytes = completedBytes
                try await SupertonicFileDownloader.download(
                    from: file.remoteURL,
                    to: temporaryURL
                ) { receivedBytes in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let boundedReceived = min(max(receivedBytes, 0), file.size)
                        let progress = min(
                            Double(baseCompletedBytes + boundedReceived) / totalBytes,
                            1
                        )
                        self.state = .downloading(progress: progress)
                        progressChanged(self.state)
                    }
                }

                guard try await Self.isValidFile(at: temporaryURL, manifest: file) else {
                    try? fileManager.removeItem(at: temporaryURL)
                    throw SupertonicError.invalidDownload(file.filename)
                }

                try fileManager.moveItem(at: temporaryURL, to: destination)
                completedBytes += file.size
            }

            try Self.modelRevision.write(
                to: markerURL,
                atomically: true,
                encoding: .utf8
            )
            try applyStorageAttributes()
            state = .installed
            progressChanged(state)
        } catch is CancellationError {
            state = .unavailable
            progressChanged(state)
        } catch {
            state = .failed(message: error.localizedDescription)
            progressChanged(state)
        }
    }

    func remove() throws {
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
        state = .unavailable
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: revisionDirectory.appendingPathComponent("onnx", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.createDirectory(
            at: revisionDirectory.appendingPathComponent("voice_styles", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try applyStorageAttributes()
    }

    private func ensureAvailableStorage(requiredBytes: Int64) throws {
        let values = try rootDirectory.deletingLastPathComponent().resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let availableCapacity = values.volumeAvailableCapacityForImportantUsage else { return }
        let requiredCapacity = requiredBytes + 150_000_000
        guard availableCapacity >= requiredCapacity else {
            throw SupertonicError.insufficientStorage
        }
    }

    private func applyStorageAttributes() throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootDirectory = rootDirectory
        try rootDirectory.setResourceValues(values)

        var protectedURLs = [self.rootDirectory]
        if let enumerator = fileManager.enumerator(
            at: self.rootDirectory,
            includingPropertiesForKeys: nil
        ) {
            protectedURLs.append(contentsOf: enumerator.compactMap { $0 as? URL })
        }
        for url in protectedURLs {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
    }

    private static func hasCompleteInstallation(
        at revisionDirectory: URL,
        markerURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard
            fileManager.fileExists(atPath: markerURL.path),
            (try? String(contentsOf: markerURL, encoding: .utf8)) == modelRevision
        else {
            return false
        }

        return files.allSatisfy { file in
            let url = revisionDirectory.appendingPathComponent(file.relativePath)
            guard
                let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = values.fileSize
            else {
                return false
            }
            return Int64(fileSize) == file.size
        }
    }

    private nonisolated static func isValidFile(
        at url: URL,
        manifest: SupertonicAssetManifest
    ) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            guard
                let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                let size = values.fileSize,
                Int64(size) == manifest.size
            else {
                return false
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return digest == manifest.sha256
        }.value
    }
}

private extension SupertonicAssetStore {
    static let modelRevision = "3cadd1ee6394adea1bd021217a0e650ede09a323"
    static let modelBaseURL = URL(
        string: "https://huggingface.co/Supertone/supertonic-3/resolve/\(modelRevision)"
    )!

    static let files: [SupertonicAssetManifest] = [
        .init(path: "onnx/duration_predictor.onnx", size: 3_700_147, sha256: "c3eb91414d5ff8a7a239b7fe9e34e7e2bf8a8140d8375ffb14718b1c639325db"),
        .init(path: "onnx/text_encoder.onnx", size: 36_416_150, sha256: "c7befd5ea8c3119769e8a6c1486c4edc6a3bc8365c67621c881bbb774b9902ff"),
        .init(path: "onnx/vector_estimator.onnx", size: 256_534_781, sha256: "883ac868ea0275ef0e991524dc64f16b3c0376efd7c320af6b53f5b780d7c61c"),
        .init(path: "onnx/vocoder.onnx", size: 101_424_195, sha256: "085de76dd8e8d5836d6ca66826601f615939218f90e519f70ee8a36ed2a4c4ba"),
        .init(path: "onnx/tts.json", size: 8_253, sha256: "42078d3aef1cd43ab43021f3c54f47d2d75ceb4e75f627f118890128b06a0d09"),
        .init(path: "onnx/unicode_indexer.json", size: 277_676, sha256: "9bf7346e43883a81f8645c81224f786d43c5b57f3641f6e7671a7d6c493cb24f"),
        .init(path: "voice_styles/F1.json", size: 292_046, sha256: "bbdec6ee00231c2c742ad05483df5334cab3b52fda3ba38e6a07059c4563dbc2"),
        .init(path: "voice_styles/F2.json", size: 292_423, sha256: "7c722c6a72707b1a77f035d67f0d1351ba187738e06f7683e8c72b1df3477fc6"),
        .init(path: "voice_styles/F3.json", size: 290_794, sha256: "12f6ef2573baa2defa1128069cb59f203e3ab67c92af77b42df8a0e3a2f7c6ab"),
        .init(path: "voice_styles/F4.json", size: 291_808, sha256: "c2fa764c1225a76dfc3e2c73e8aa4f70d9ee48793860eb34c295fff01c2e032b"),
        .init(path: "voice_styles/F5.json", size: 291_479, sha256: "45966e73316415626cf41a7d1c6f3b4c70dbc1ba2bee5c1978ef0ce33244fc8d"),
        .init(path: "voice_styles/M1.json", size: 291_748, sha256: "e35604687f5d23694b8e91593a93eec0e4eca6c0b02bb8ed69139ab2ea6b0a5b"),
        .init(path: "voice_styles/M2.json", size: 292_055, sha256: "b76cbf62bac707c710cf0ae5aba5e31eea1a6339a9734bfae33ab98499534a50"),
        .init(path: "voice_styles/M3.json", size: 290_198, sha256: "ea1ac35ccb91b0d7ecad533a2fbd0eec10c91513d8951e3b25fbba99954e159b"),
        .init(path: "voice_styles/M4.json", size: 291_522, sha256: "ca8eefad4fcd989c9379032ff3e50738adc547eeb5e221b82593a6d7b3bac303"),
        .init(path: "voice_styles/M5.json", size: 291_469, sha256: "dd22b92740314321f8ae11c5e87f8dd60d060f15dd3a632b5adf77f471f77af2"),
        .init(path: "LICENSE", size: 15_007, sha256: "0d944a9110fed9a9602d60e0423a272903e7bd21ab060490774efc77c2275e9f")
    ]
}

private struct SupertonicAssetManifest: Sendable {
    let relativePath: String
    let size: Int64
    let sha256: String

    init(path: String, size: Int64, sha256: String) {
        relativePath = path
        self.size = size
        self.sha256 = sha256
    }

    var filename: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    var remoteURL: URL {
        SupertonicAssetStore.modelBaseURL
            .appendingPathComponent(relativePath)
            .appending(queryItems: [URLQueryItem(name: "download", value: "true")])
    }
}

private final class SupertonicFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false
    private var session: URLSession?

    private init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func download(
        from remoteURL: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let downloader = SupertonicFileDownloader(destination: destination, progress: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                downloader.lock.withLock {
                    downloader.continuation = continuation
                }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.waitsForConnectivity = true
                configuration.timeoutIntervalForRequest = 90
                configuration.timeoutIntervalForResource = 3_600
                let session = URLSession(configuration: configuration, delegate: downloader, delegateQueue: nil)
                downloader.session = session
                session.downloadTask(with: remoteURL).resume()
            }
        } onCancel: {
            downloader.session?.invalidateAndCancel()
            downloader.complete(with: .failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            complete(with: .success(()))
        } catch {
            complete(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            complete(with: .failure(error))
        }
    }

    private func complete(with result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}
