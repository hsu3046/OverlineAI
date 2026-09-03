import Foundation

nonisolated enum OverlineAPIConfiguration {
    private static let baseURLInfoKey = "OverlineAPIBaseURL"

    static var baseURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: baseURLInfoKey) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmed
        guard
            !trimmedValue.isEmpty,
            !trimmedValue.hasPrefix("$("),
            let url = URL(string: trimmedValue),
            url.scheme == "https"
        else {
            return nil
        }
        return url
    }

    static var privacyPolicyURL: URL? {
        baseURL?.appendingPathComponent("privacy")
    }
}

nonisolated struct OverlineAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let baseURL: URL?
    private let timeoutInterval: TimeInterval = 12

    init(
        session: URLSession = .shared,
        baseURL: URL? = OverlineAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func nearbyPlaces(
        latitude: Double,
        longitude: Double,
        radius: Int,
        kind: CommunityPlaceKind
    ) async throws -> CommunityListResponse<CommunityPlace> {
        try await post(
            path: "api/v1/places",
            body: NearbyPlacesRequest(
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                kind: kind.rawValue
            )
        )
    }

    func articles(
        title: String,
        author: String,
        source: CommunityArticleSource,
        sort: CommunityArticleSort
    ) async throws -> CommunityListResponse<CommunityArticle> {
        try await post(
            path: "api/v1/articles",
            body: ArticleSearchRequest(
                title: title,
                author: author,
                source: source.rawValue,
                sort: sort.rawValue
            )
        )
    }

    func rankings(
        kind: CommunityRankingKind,
        category: CommunityRankingCategory
    ) async throws -> CommunityListResponse<CommunityRankingItem> {
        try await get(
            path: "api/v1/rankings",
            queryItems: [
                URLQueryItem(name: "kind", value: kind.rawValue),
                URLQueryItem(name: "category", value: category.rawValue)
            ]
        )
    }

    func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        guard let baseURL else { throw OverlineAPIError.missingServerURL }

        let endpoint = path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw OverlineAPIError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw OverlineAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await decodedResponse(for: request)
    }

    func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        guard let baseURL else { throw OverlineAPIError.missingServerURL }

        let url = path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        return try await decodedResponse(for: request)
    }

    private func decodedResponse<Response: Decodable>(for request: URLRequest) async throws -> Response {

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OverlineAPIError.timedOut
        } catch let error as URLError where [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ].contains(error.code) {
            throw OverlineAPIError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OverlineAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = (try? decoder.decode(APIErrorEnvelope.self, from: data).error) ?? ""
            throw OverlineAPIError.requestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw OverlineAPIError.invalidResponse
        }
    }
}

nonisolated private struct NearbyPlacesRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let radius: Int
    let kind: String
}

nonisolated private struct ArticleSearchRequest: Encodable {
    let title: String
    let author: String
    let source: String
    let sort: String
}

nonisolated enum OverlineAPIError: LocalizedError {
    case missingServerURL
    case invalidURL
    case invalidResponse
    case timedOut
    case networkUnavailable
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            "Overline 서버 연결이 아직 설정되지 않았습니다."
        case .invalidURL:
            "서버 요청 주소를 만들 수 없습니다."
        case .invalidResponse:
            "서버 응답을 읽을 수 없습니다. 잠시 후 다시 시도해 주세요."
        case .timedOut:
            "응답이 지연되고 있습니다. 네트워크 상태를 확인해 주세요."
        case .networkUnavailable:
            "인터넷에 연결할 수 없습니다. 네트워크 상태를 확인해 주세요."
        case .requestFailed(let statusCode, let message):
            if statusCode == 429 {
                "요청이 잠시 제한되었습니다. 잠시 후 다시 시도해 주세요."
            } else if message.isEmpty {
                "정보를 불러오지 못했습니다. (\(statusCode))"
            } else {
                message
            }
        }
    }
}

nonisolated private struct APIErrorEnvelope: Decodable {
    let error: String
}
