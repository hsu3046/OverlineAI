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
    private static let keychain = KeychainStringStore(service: "aib.Overline.book-metadata")
    private static let kakaoRESTAPIKeyAccount = "kakao-rest-api-key"

    static func kakaoRESTAPIKey() -> String {
        let storedKey = keychain.string(account: kakaoRESTAPIKeyAccount) ?? ""
        if !storedKey.trimmed.isEmpty {
            keychain.set(storedKey, account: kakaoRESTAPIKeyAccount)
        }
        return storedKey
    }

    static func setKakaoRESTAPIKey(_ key: String) {
        keychain.set(key.trimmed, account: kakaoRESTAPIKeyAccount)
    }
}

struct BookMetadataSearchClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let timeoutInterval: TimeInterval = 12

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, kakaoRESTAPIKey: String) async throws -> BookMetadataSearchResult {
        let trimmedQuery = query.trimmed
        guard !trimmedQuery.isEmpty else {
            return BookMetadataSearchResult(candidates: [], infoMessage: nil)
        }

        if !kakaoRESTAPIKey.trimmed.isEmpty {
            do {
                let kakaoResults = try await searchKakao(query: trimmedQuery, apiKey: kakaoRESTAPIKey)
                if !kakaoResults.isEmpty {
                    return BookMetadataSearchResult(
                        candidates: kakaoResults,
                        infoMessage: "Kakao 도서 API 결과입니다."
                    )
                }

                let googleResults = try await searchGoogle(query: trimmedQuery)
                return BookMetadataSearchResult(
                    candidates: googleResults,
                    infoMessage: "Kakao 결과가 없어 Google Books fallback 결과를 표시합니다."
                )
            } catch let kakaoError {
                do {
                    let googleResults = try await searchGoogle(query: trimmedQuery)
                    return BookMetadataSearchResult(
                        candidates: googleResults,
                        infoMessage: "Kakao 연결에 실패해 Google Books fallback 결과를 표시합니다. \(kakaoError.localizedDescription)"
                    )
                } catch let googleError {
                    throw BookMetadataSearchError.fallbackFailed(
                        kakaoMessage: kakaoError.localizedDescription,
                        googleMessage: googleError.localizedDescription
                    )
                }
            }
        }

        let googleResults = try await searchGoogle(query: trimmedQuery)
        return BookMetadataSearchResult(
            candidates: googleResults,
            infoMessage: "Google Books 결과입니다. Kakao 키를 입력하면 국내 도서를 우선 검색합니다."
        )
    }

    func testKakaoRESTAPIKey(_ apiKey: String) async throws {
        guard !apiKey.trimmed.isEmpty else {
            throw BookMetadataSearchError.missingKakaoAPIKey
        }

        _ = try await searchKakao(query: "책", apiKey: apiKey)
    }

    private func searchKakao(query: String, apiKey: String) async throws -> [BookMetadataCandidate] {
        var components = URLComponents(string: "https://dapi.kakao.com/v3/search/book")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "sort", value: "accuracy"),
            URLQueryItem(name: "size", value: "10")
        ]

        guard let url = components?.url else { throw BookMetadataSearchError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("KakaoAK \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")

        let data = try await responseData(for: request)
        let response = try decoder.decode(KakaoBookSearchResponse.self, from: data)

        return response.documents.map { document in
            BookMetadataCandidate(
                id: "kakao-\(document.isbn)-\(document.title)",
                title: document.title.strippingHTML.trimmed,
                author: document.authors.joined(separator: ", ").trimmed,
                summary: document.contents.strippingHTML.trimmed,
                publisher: document.publisher.trimmed,
                isbn: document.isbn.trimmed,
                coverURLString: document.thumbnail.normalizedHTTPSURLString,
                source: .kakao
            )
        }
    }

    private func searchGoogle(query: String) async throws -> [BookMetadataCandidate] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        components?.queryItems = [
            URLQueryItem(name: "q", value: googleQuery(from: query)),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "projection", value: "lite")
        ]

        guard let url = components?.url else { throw BookMetadataSearchError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval

        let data = try await responseData(for: request)
        let response = try decoder.decode(GoogleBooksResponse.self, from: data)

        return (response.items ?? []).compactMap { item in
            guard let title = item.volumeInfo.title?.trimmed, !title.isEmpty else { return nil }

            let isbn = item.volumeInfo.industryIdentifiers?
                .map(\.identifier)
                .filter { !$0.trimmed.isEmpty }
                .joined(separator: " ")
                ?? ""

            return BookMetadataCandidate(
                id: "google-\(item.id)",
                title: title,
                author: item.volumeInfo.authors?.joined(separator: ", ").trimmed ?? "",
                summary: item.volumeInfo.description?.strippingHTML.trimmed ?? "",
                publisher: item.volumeInfo.publisher?.trimmed ?? "",
                isbn: isbn,
                coverURLString: (item.volumeInfo.imageLinks?.thumbnail ?? item.volumeInfo.imageLinks?.smallThumbnail ?? "").normalizedHTTPSURLString,
                source: .google
            )
        }
    }

    private func responseData(for request: URLRequest) async throws -> Data {
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

    private func googleQuery(from query: String) -> String {
        let digits = query.filter(\.isNumber)
        if digits.count == 10 || digits.count == 13 {
            return "isbn:\(digits)"
        }

        return query
    }
}

enum BookMetadataSearchError: LocalizedError {
    case missingKakaoAPIKey
    case invalidURL
    case invalidResponse
    case timedOut
    case networkUnavailable
    case requestFailed(statusCode: Int, message: String)
    case fallbackFailed(kakaoMessage: String, googleMessage: String)

    var errorDescription: String? {
        switch self {
        case .missingKakaoAPIKey:
            return "Kakao REST API 키를 입력해 주세요."
        case .invalidURL:
            return "도서 검색 주소를 만들 수 없습니다."
        case .invalidResponse:
            return "도서 검색 응답을 읽을 수 없습니다."
        case .timedOut:
            return "도서 검색 응답이 지연되고 있습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
        case .networkUnavailable:
            return "도서 검색 서비스에 연결할 수 없습니다. 네트워크 상태를 확인해 주세요."
        case .requestFailed(let statusCode, let message):
            if statusCode == 429 {
                return "도서 검색 요청이 잠시 제한되었습니다. 잠시 후 다시 시도해 주세요."
            }
            if message.isEmpty {
                return "도서 검색에 실패했습니다. (\(statusCode))"
            }
            return "도서 검색에 실패했습니다. (\(statusCode)) \(message)"
        case .fallbackFailed(let kakaoMessage, let googleMessage):
            return "Kakao와 Google Books 검색이 모두 실패했습니다. Kakao: \(kakaoMessage) Google: \(googleMessage)"
        }
    }
}

private struct KakaoBookSearchResponse: Decodable {
    let documents: [KakaoBookDocument]
}

private struct KakaoBookDocument: Decodable {
    let title: String
    let contents: String
    let isbn: String
    let publisher: String
    let authors: [String]
    let thumbnail: String
}

private struct GoogleBooksResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let volumeInfo: VolumeInfo
    }

    struct VolumeInfo: Decodable {
        let title: String?
        let authors: [String]?
        let publisher: String?
        let description: String?
        let industryIdentifiers: [IndustryIdentifier]?
        let imageLinks: ImageLinks?
    }

    struct IndustryIdentifier: Decodable {
        let identifier: String
    }

    struct ImageLinks: Decodable {
        let smallThumbnail: String?
        let thumbnail: String?
    }

    let items: [Item]?
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
