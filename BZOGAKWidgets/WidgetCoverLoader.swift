import CryptoKit
import Foundation
import ImageIO

enum WidgetCoverLoader {
    static func images(for books: [WidgetBook]) async -> [UUID: Data] {
        await withTaskGroup(of: (UUID, Data?).self) { group in
            var remaining = books.makeIterator()
            // Bound image decoding and network work within the widget extension's memory budget.
            for _ in 0..<3 {
                guard let book = remaining.next() else { break }
                group.addTask { (book.id, await thumbnail(book.coverURL)) }
            }
            var result: [UUID: Data] = [:]
            for await (id, data) in group {
                result[id] = data
                if let book = remaining.next() {
                    group.addTask { (book.id, await thumbnail(book.coverURL)) }
                }
            }
            return result
        }
    }

    private static func thumbnail(_ value: String?) async -> Data? {
        guard let value, let url = URL(string: value), url.scheme == "https" else { return nil }
        let filename = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
        let cache = try? WidgetStore().directory.appendingPathComponent("covers", isDirectory: true)
        let file = cache?.appendingPathComponent(filename)
        if let file, let data = try? Data(contentsOf: file), data.count < 250_000,
           CGImageSourceCreateWithData(data as CFData, nil) != nil { return data }
        do {
            let request = URLRequest(url: url, timeoutInterval: 5)
            let (download, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: download) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4_000_000,
                  let source = CGImageSourceCreateWithURL(download as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160
                  ] as CFDictionary) else { return nil }
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            let data = bytes as Data
            if let cache, let file {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }
            return data
        } catch {
            // Covers are optional; an offline widget must still show its saved text.
            return nil
        }
    }
}
