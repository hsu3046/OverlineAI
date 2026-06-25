import Foundation

struct LLMInsightSource {
    let bookTitle: String
    let text: String
    let memo: String
    let pageReference: String
    let tags: [String]
    let createdAt: Date
}

struct LLMInsightRequest {
    let provider: LLMProvider
    let modelID: String
    let apiKey: String
    let category: String
    let instruction: String
    let userPrompt: String
    let sources: [LLMInsightSource]
}

enum LLMInsightError: LocalizedError {
    case missingAPIKey(String)
    case invalidURL
    case invalidResponse
    case timedOut
    case networkUnavailable
    case emptyResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "\(provider) API 키를 먼저 입력해 주세요."
        case .invalidURL:
            "요청 주소를 만들 수 없습니다."
        case .invalidResponse:
            "AI 응답 형식이 예상과 다릅니다."
        case .timedOut:
            "AI 응답이 지연되고 있습니다. 네트워크나 모델 상태를 확인한 뒤 다시 시도해 주세요."
        case .networkUnavailable:
            "AI 서비스에 연결할 수 없습니다. 네트워크 상태를 확인해 주세요."
        case .emptyResponse:
            "AI가 비어 있는 응답을 반환했습니다."
        case .requestFailed(let statusCode, let message):
            if message.isEmpty {
                "AI 요청이 실패했습니다. (\(statusCode))"
            } else {
                "AI 요청이 실패했습니다. (\(statusCode)) \(message)"
            }
        }
    }
}

struct LLMInsightClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let timeoutInterval: TimeInterval = 45

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateInsight(_ request: LLMInsightRequest) async throws -> String {
        guard !request.apiKey.trimmed.isEmpty else {
            throw LLMInsightError.missingAPIKey(request.provider.title)
        }

        switch request.provider {
        case .openrouter:
            return try await generateOpenAICompatibleInsight(
                request,
                endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions"),
                extraHeaders: [
                    "HTTP-Referer": "https://overline.local",
                    "X-OpenRouter-Title": "Overline AI"
                ],
                usesMaxCompletionTokens: false
            )
        case .openai:
            return try await generateOpenAIResponsesInsight(request)
        case .anthropic:
            return try await generateAnthropicInsight(request)
        case .gemini:
            return try await generateGeminiInsight(request)
        }
    }

    private func generateOpenAIResponsesInsight(_ request: LLMInsightRequest) async throws -> String {
        guard let endpoint = URL(string: "https://api.openai.com/v1/responses") else {
            throw LLMInsightError.invalidURL
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey.trimmed)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": request.modelID,
            "instructions": systemPrompt(for: request),
            "input": userPrompt(for: request),
            "max_output_tokens": 700,
            "reasoning": [
                "effort": "low"
            ],
            "text": [
                "verbosity": "low"
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await responseData(for: urlRequest)
        let response = try decoder.decode(OpenAIResponsesResponse.self, from: data)
        let content = response.text.trimmed
        guard !content.isEmpty else { throw LLMInsightError.emptyResponse }
        return content
    }

    private func generateOpenAICompatibleInsight(
        _ request: LLMInsightRequest,
        endpoint: URL?,
        extraHeaders: [String: String],
        usesMaxCompletionTokens: Bool
    ) async throws -> String {
        guard let endpoint else { throw LLMInsightError.invalidURL }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey.trimmed)", forHTTPHeaderField: "Authorization")
        extraHeaders.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        var payload: [String: Any] = [
            "model": request.modelID,
            "messages": [
                ["role": "system", "content": systemPrompt(for: request)],
                ["role": "user", "content": userPrompt(for: request)]
            ],
            "temperature": 0.35
        ]

        if usesMaxCompletionTokens {
            payload["max_completion_tokens"] = 700
        } else {
            payload["max_tokens"] = 700
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await responseData(for: urlRequest)
        let response = try decoder.decode(OpenAICompatibleResponse.self, from: data)
        guard let content = response.choices.first?.message.content.trimmed, !content.isEmpty else {
            throw LLMInsightError.emptyResponse
        }
        return content
    }

    private func generateAnthropicInsight(_ request: LLMInsightRequest) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMInsightError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.apiKey.trimmed, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": request.modelID,
            "max_tokens": 700,
            "system": systemPrompt(for: request),
            "messages": [
                [
                    "role": "user",
                    "content": userPrompt(for: request)
                ]
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await responseData(for: urlRequest)
        let response = try decoder.decode(AnthropicMessageResponse.self, from: data)
        let content = response.content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmed

        guard !content.isEmpty else { throw LLMInsightError.emptyResponse }
        return content
    }

    private func generateGeminiInsight(_ request: LLMInsightRequest) async throws -> String {
        guard
            let escapedModel = request.modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent?key=\(request.apiKey.trimmed)")
        else {
            throw LLMInsightError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt(for: request)]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt(for: request)]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.35,
                "maxOutputTokens": 700
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await responseData(for: urlRequest)
        let response = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
        let content = response.candidates
            .flatMap(\.content.parts)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmed

        guard !content.isEmpty else { throw LLMInsightError.emptyResponse }
        return content
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMInsightError.timedOut
        } catch let error as URLError where [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ].contains(error.code) {
            throw LLMInsightError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMInsightError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMInsightError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data)
            )
        }

        return data
    }

    private func systemPrompt(for request: LLMInsightRequest) -> String {
        """
        당신은 독자가 캡처한 책 속 글조각을 바탕으로 짧고 깊은 인사이트를 만드는 한국어 독서 파트너입니다.
        원문을 길게 반복하지 말고, 선택된 글조각 사이의 의미를 연결하세요.
        여러 책에서 온 글조각이면 교차 책 패턴을 우선 찾고, 한 책의 글조각이면 반복되는 테마를 우선 찾으세요.
        요약 요청에서는 날짜 흐름을 보고 최근 읽기 흐름을 한 문단으로 정리하세요.
        답변은 2-4문장으로 간결하게 작성하세요.
        카테고리: \(request.category)
        작업 지시: \(request.instruction)
        """
    }

    private func userPrompt(for request: LLMInsightRequest) -> String {
        let bookCount = Set(request.sources.map(\.bookTitle)).count
        let sortedDates = request.sources.map(\.createdAt).sorted()
        let dateRange: String
        if let firstDate = sortedDates.first, let lastDate = sortedDates.last {
            dateRange = firstDate.overlineShortDate == lastDate.overlineShortDate
                ? firstDate.overlineShortDate
                : "\(firstDate.overlineShortDate) - \(lastDate.overlineShortDate)"
        } else {
            dateRange = "-"
        }

        let sourceText = request.sources.enumerated().map { index, source in
            let memo = source.memo.trimmed.isEmpty ? "" : "\n메모: \(source.memo)"
            let tags = source.tags.isEmpty ? "" : "\n태그: \(source.tags.joined(separator: " "))"
            return """
            \(index + 1). [\(source.bookTitle), \(source.pageReference), 저장 \(source.createdAt.overlineShortDate)]
            \(source.text)\(memo)\(tags)
            """
        }
        .joined(separator: "\n\n")

        return """
        사용자 질문:
        \(request.userPrompt)

        선택 범위:
        글조각 \(request.sources.count)개, 책 \(bookCount)권, 날짜 \(dateRange)

        선택한 글조각:
        \(sourceText)
        """
    }

    private func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)?.trimmed ?? ""
        }

        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            if let message = error["error"] as? String {
                return message
            }
        }

        if let message = object["message"] as? String {
            return message
        }

        return ""
    }
}

private struct OpenAICompatibleResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        struct Content: Decodable {
            let type: String?
            let text: String?
        }

        let content: [Content]?
    }

    let outputText: String?
    let output: [OutputItem]

    var text: String {
        if let outputText, !outputText.trimmed.isEmpty {
            return outputText
        }

        return output
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct AnthropicMessageResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}

private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]
        }

        let content: Content
    }

    let candidates: [Candidate]
}
