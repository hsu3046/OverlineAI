import Foundation

nonisolated struct BookMetadataCandidate: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let author: String
    let summary: String
    let publisher: String
    let publishedDate: String
    let isbn: String
    let coverURLString: String
    let source: BookMetadataSource

    var sourceTitle: String {
        switch source {
        case .manual:
            "Manual"
        case .kakao:
            "Kakao"
        case .aladin:
            "Aladin"
        case .google:
            "Google"
        }
    }
}

nonisolated struct BookMetadataSearchResult {
    let candidates: [BookMetadataCandidate]
    let infoMessage: String?
}

nonisolated struct BookMetadataSearchClient {
    private let apiClient: OverlineAPIClient

    init(apiClient: OverlineAPIClient = OverlineAPIClient()) {
        self.apiClient = apiClient
    }

    func search(query: String) async throws -> BookMetadataSearchResult {
        let trimmedQuery = query.trimmed
        guard !trimmedQuery.isEmpty else {
            return BookMetadataSearchResult(candidates: [], infoMessage: nil)
        }

        let response: BookMetadataServerResponse = try await apiClient.get(
            path: "api/v1/books/search",
            queryItems: [URLQueryItem(name: "q", value: trimmedQuery)]
        )
        return BookMetadataSearchResult(
            candidates: response.items,
            infoMessage: response.message
        )
    }
}

nonisolated private struct BookMetadataServerResponse: Decodable {
    let items: [BookMetadataCandidate]
    let message: String?
}
