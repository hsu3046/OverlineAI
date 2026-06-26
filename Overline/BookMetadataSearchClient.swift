import Foundation

struct BookMetadataCandidate: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let summary: String
    let publisher: String
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

struct BookMetadataSearchResult {
    let candidates: [BookMetadataCandidate]
    let infoMessage: String?
}

enum BookMetadataAPIKeyStore {
    private static let kakaoRESTAPIKeyInfoKey = "KakaoRESTAPIKey"
    private static let aladinTTBKeyInfoKey = "AladinTTBKey"

    static func kakaoRESTAPIKey() -> String {
        bundledAPIKey(infoDictionaryKey: kakaoRESTAPIKeyInfoKey)
    }

    static func aladinTTBKey() -> String {
        bundledAPIKey(infoDictionaryKey: aladinTTBKeyInfoKey)
    }

    private static func bundledAPIKey(infoDictionaryKey: String) -> String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String else {
            return ""
        }

        let trimmedKey = key.trimmed
        guard !trimmedKey.hasPrefix("$(") else { return "" }
        return trimmedKey
    }
}

struct BookMetadataSearchClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let timeoutInterval: TimeInterval = 12

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String) async throws -> BookMetadataSearchResult {
        let trimmedQuery = query.trimmed
        guard !trimmedQuery.isEmpty else {
            return BookMetadataSearchResult(candidates: [], infoMessage: nil)
        }

        let kakaoKey = BookMetadataAPIKeyStore.kakaoRESTAPIKey()
        let aladinKey = BookMetadataAPIKeyStore.aladinTTBKey()

        guard !kakaoKey.isEmpty || !aladinKey.isEmpty else {
            throw BookMetadataSearchError.missingMetadataAPIKeys
        }

        var aladinFailure: Error?

        if !aladinKey.isEmpty {
            do {
                let aladinResults = try await searchAladin(query: trimmedQuery, apiKey: aladinKey)
                if !aladinResults.isEmpty {
                    return BookMetadataSearchResult(
                        candidates: aladinResults,
                        infoMessage: "Aladin 도서 API 결과입니다."
                    )
                }

                if kakaoKey.isEmpty {
                    return BookMetadataSearchResult(
                        candidates: [],
                        infoMessage: "Aladin 검색 결과가 없습니다."
                    )
                }
            } catch {
                aladinFailure = error
                if kakaoKey.isEmpty {
                    throw error
                }
            }
        }

        do {
            let kakaoResults = try await searchKakao(query: trimmedQuery, apiKey: kakaoKey)
            let message: String
            if let aladinFailure {
                message = kakaoResults.isEmpty
                    ? "Aladin 연결에 실패했고 Kakao 검색 결과도 없습니다."
                    : "Aladin 연결에 실패해 Kakao 결과를 표시합니다. \(aladinFailure.localizedDescription)"
            } else if !aladinKey.isEmpty {
                message = kakaoResults.isEmpty
                    ? "Aladin과 Kakao 검색 결과가 없습니다."
                    : "Aladin 결과가 없어 Kakao 결과를 표시합니다."
            } else {
                message = "Kakao 도서 API 결과입니다."
            }
            return BookMetadataSearchResult(candidates: kakaoResults, infoMessage: message)
        } catch {
            if let aladinFailure {
                throw BookMetadataSearchError.fallbackFailed(
                    aladinMessage: aladinFailure.localizedDescription,
                    kakaoMessage: error.localizedDescription
                )
            }

            throw error
        }
    }

    private func searchKakao(query: String, apiKey: String) async throws -> [BookMetadataCandidate] {
        let primaryTarget = kakaoPrimaryTarget(for: query)
        let primaryQuery = primaryTarget == "isbn" ? query.filter(\.isNumber) : query
        let primaryResults = try await searchKakao(query: primaryQuery, apiKey: apiKey, target: primaryTarget)

        if !primaryResults.isEmpty || primaryTarget == nil {
            return primaryResults
        }

        return try await searchKakao(query: query, apiKey: apiKey, target: nil)
    }

    private func searchKakao(query: String, apiKey: String, target: String?) async throws -> [BookMetadataCandidate] {
        var components = URLComponents(string: "https://dapi.kakao.com/v3/search/book")
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "sort", value: "accuracy"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: "10")
        ]
        if let target {
            queryItems.append(URLQueryItem(name: "target", value: target))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { throw BookMetadataSearchError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        let data = try await responseData(for: request, serviceName: "Kakao 도서 API")
        let response = try decoder.decode(KakaoBookSearchResponse.self, from: data)

        return response.documents.compactMap { document in
            let title = (document.title ?? "").strippingHTML.trimmed
            guard !title.isEmpty else { return nil }

            return BookMetadataCandidate(
                id: "kakao-\(document.isbn ?? "")-\(title)",
                title: title,
                author: (document.authors ?? []).joined(separator: ", ").trimmed,
                summary: (document.contents ?? "").strippingHTML.trimmed,
                publisher: (document.publisher ?? "").trimmed,
                isbn: (document.isbn ?? "").trimmed,
                coverURLString: (document.thumbnail ?? "").normalizedHTTPSURLString,
                source: .kakao
            )
        }
    }

    private func searchAladin(query: String, apiKey: String) async throws -> [BookMetadataCandidate] {
        let digits = query.filter(\.isNumber)
        if digits.count == 10 || digits.count == 13 {
            let lookupResults = try await searchAladinLookup(isbn: digits, apiKey: apiKey)
            if !lookupResults.isEmpty {
                return lookupResults
            }
        }

        let titleResults = try await searchAladinSearch(query: query, queryType: "Title", apiKey: apiKey)
        if !titleResults.isEmpty || digits.count == 10 || digits.count == 13 {
            return titleResults
        }

        return try await searchAladinSearch(query: query, queryType: "Keyword", apiKey: apiKey)
    }

    private func searchAladinLookup(isbn: String, apiKey: String) async throws -> [BookMetadataCandidate] {
        var components = URLComponents(string: "https://www.aladin.co.kr/ttb/api/ItemLookUp.aspx")
        components?.queryItems = [
            URLQueryItem(name: "TTBKey", value: apiKey),
            URLQueryItem(name: "ItemId", value: isbn),
            URLQueryItem(name: "ItemIdType", value: isbn.count == 13 ? "ISBN13" : "ISBN"),
            URLQueryItem(name: "Cover", value: "Big"),
            URLQueryItem(name: "Output", value: "JS"),
            URLQueryItem(name: "Version", value: "20131101")
        ]

        guard let url = components?.url else { throw BookMetadataSearchError.invalidURL }
        return try await aladinCandidates(for: url)
    }

    private func searchAladinSearch(query: String, queryType: String, apiKey: String) async throws -> [BookMetadataCandidate] {
        var components = URLComponents(string: "https://www.aladin.co.kr/ttb/api/ItemSearch.aspx")
        components?.queryItems = [
            URLQueryItem(name: "TTBKey", value: apiKey),
            URLQueryItem(name: "Query", value: query),
            URLQueryItem(name: "QueryType", value: queryType),
            URLQueryItem(name: "MaxResults", value: "10"),
            URLQueryItem(name: "Start", value: "1"),
            URLQueryItem(name: "SearchTarget", value: "Book"),
            URLQueryItem(name: "Sort", value: "Accuracy"),
            URLQueryItem(name: "Cover", value: "Big"),
            URLQueryItem(name: "Output", value: "JS"),
            URLQueryItem(name: "Version", value: "20131101")
        ]

        guard let url = components?.url else { throw BookMetadataSearchError.invalidURL }
        return try await aladinCandidates(for: url)
    }

    private func aladinCandidates(for url: URL) async throws -> [BookMetadataCandidate] {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await responseData(for: request, serviceName: "Aladin 도서 API")
        let response = try decoder.decode(AladinBookSearchResponse.self, from: data)

        if let errorCode = response.errorCode {
            let detail = response.errorMessage?.trimmed ?? ""
            let message = detail.isEmpty ? "오류 코드 \(errorCode)" : detail
            throw BookMetadataSearchError.apiError(serviceName: "Aladin 도서 API", message: message)
        }

        return (response.item ?? []).compactMap { item in
            let title = (item.title ?? "").strippingHTML.trimmed
            guard !title.isEmpty else { return nil }

            let isbnValues = [item.isbn, item.isbn13]
                .compactMap { $0?.trimmed }
                .filter { !$0.isEmpty }
                .uniqued()

            return BookMetadataCandidate(
                id: "aladin-\(isbnValues.joined(separator: "-"))-\(title)",
                title: title,
                author: (item.author ?? "").strippingHTML.trimmed,
                summary: (item.description ?? "").strippingHTML.trimmed,
                publisher: (item.publisher ?? "").trimmed,
                isbn: isbnValues.joined(separator: " "),
                coverURLString: (item.cover ?? "").normalizedHTTPSURLString,
                source: .aladin
            )
        }
    }

    private func responseData(for request: URLRequest, serviceName: String) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw BookMetadataSearchError.timedOut
        } catch let error as URLError where [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ].contains(error.code) {
            throw BookMetadataSearchError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookMetadataSearchError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BookMetadataSearchError.requestFailed(
                serviceName: serviceName,
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data)
            )
        }

        return data
    }

    private func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)?.trimmed ?? ""
        }

        if let message = object["message"] as? String {
            return message
        }

        if let message = object["errorMessage"] as? String {
            return message
        }

        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            if let message = error["error"] as? String {
                return message
            }
        }

        return ""
    }

    private func kakaoPrimaryTarget(for query: String) -> String? {
        let digits = query.filter(\.isNumber)
        if digits.count == 10 || digits.count == 13 {
            return "isbn"
        }

        return "title"
    }
}

enum BookMetadataSearchError: LocalizedError {
    case missingMetadataAPIKeys
    case invalidURL
    case invalidResponse
    case timedOut
    case networkUnavailable
    case apiError(serviceName: String, message: String)
    case requestFailed(serviceName: String, statusCode: Int, message: String)
    case fallbackFailed(aladinMessage: String, kakaoMessage: String)

    var errorDescription: String? {
        switch self {
        case .missingMetadataAPIKeys:
            return "앱에 도서 검색 API 키가 포함되지 않았습니다."
        case .invalidURL:
            return "도서 검색 주소를 만들 수 없습니다."
        case .invalidResponse:
            return "도서 검색 응답을 읽을 수 없습니다."
        case .timedOut:
            return "도서 검색 응답이 지연되고 있습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
        case .networkUnavailable:
            return "도서 검색 서비스에 연결할 수 없습니다. 네트워크 상태를 확인해 주세요."
        case .apiError(let serviceName, let message):
            return "\(serviceName) 검색에 실패했습니다. \(message)"
        case .requestFailed(let serviceName, let statusCode, let message):
            if statusCode == 429 {
                return "\(serviceName) 요청이 잠시 제한되었습니다. 잠시 후 다시 시도해 주세요."
            }
            if message.isEmpty {
                return "\(serviceName) 검색에 실패했습니다. (\(statusCode))"
            }
            return "\(serviceName) 검색에 실패했습니다. (\(statusCode)) \(message)"
        case .fallbackFailed(let aladinMessage, let kakaoMessage):
            return "Aladin과 Kakao 검색이 모두 실패했습니다. Aladin: \(aladinMessage) Kakao: \(kakaoMessage)"
        }
    }
}

private struct KakaoBookSearchResponse: Decodable {
    let documents: [KakaoBookDocument]
}

private struct KakaoBookDocument: Decodable {
    let title: String?
    let contents: String?
    let isbn: String?
    let publisher: String?
    let authors: [String]?
    let thumbnail: String?
}

private struct AladinBookSearchResponse: Decodable {
    let item: [AladinBookItem]?
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case item
        case errorCode
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = try container.decodeIfPresent([AladinBookItem].self, forKey: .item)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)

        if let value = try? container.decodeIfPresent(String.self, forKey: .errorCode) {
            errorCode = value
        } else if let value = try? container.decodeIfPresent(Int.self, forKey: .errorCode) {
            errorCode = String(value)
        } else {
            errorCode = nil
        }
    }
}

private struct AladinBookItem: Decodable {
    let title: String?
    let author: String?
    let description: String?
    let isbn: String?
    let isbn13: String?
    let publisher: String?
    let cover: String?
}

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    var normalizedHTTPSURLString: String {
        if hasPrefix("http://") {
            return replacingOccurrences(of: "http://", with: "https://")
        }
        return self
    }

}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
