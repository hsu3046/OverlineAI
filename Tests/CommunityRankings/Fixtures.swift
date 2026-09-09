import Foundation

nonisolated struct ReadingBook: Identifiable {
    let id: UUID
    let title: String
    let author: String
}

@MainActor final class ReadingLibrary {
    var books: [ReadingBook] = []
    var selectedBook: ReadingBook? { books.first }
    func book(with id: UUID) -> ReadingBook? { books.first { $0.id == id } }
}

extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated final class RankingURLProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var count = 0
        var hold = false
        var pending: RankingURLProtocol?
    }
    static let state = State()
    static var requestCount: Int { state.lock.withLock { state.count } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let held = Self.state.lock.withLock {
            Self.state.count += 1
            if Self.state.hold { Self.state.pending = self }
            return Self.state.hold
        }
        if !held { respond() }
    }
    override func stopLoading() {}

    func respond(status: Int = 200) {
        let url = request.url!
        let items: [[String: Any]] = [[
            "id": url.query!, "rank": 1, "title": url.query!,
            "author": "Test", "source": "test"
        ]]
        let body: [String: Any] = status == 200
            ? ["items": items, "fetchedAt": "2026-09-09T00:00:00Z"]
            : ["error": "Test failure"]
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func holdNext() { state.lock.withLock { state.hold = true } }
    static func release(status: Int = 200) {
        let pending = state.lock.withLock {
            let result = state.pending
            state.pending = nil
            state.hold = false
            return result
        }
        pending?.respond(status: status)
    }
}
