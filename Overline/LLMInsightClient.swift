import Foundation

struct LLMInsightSource {
    let bookTitle: String
    let bookAuthor: String
    let bookSummary: String
    let text: String
    let memo: String
}

struct LLMInsightRequest {
    let provider: LLMProvider
    let modelID: String
    let credential: LLMAuthCredential
    let category: String
    let instruction: String
    let userPrompt: String
    let sources: [LLMInsightSource]
}

struct LLMTagRequest {
    let provider: LLMProvider
    let modelID: String
    let credential: LLMAuthCredential
    let bookTitle: String
    let bookAuthor: String
    let bookSummary: String
    let text: String
    let memo: String
    let existingTags: [String]
}

private struct LLMGenerationProfile {
    let maxOutputTokens: Int
    let temperature: Double
    let openAIReasoningEffort: String
    let openAITextVerbosity: String
}

enum LLMInsightError: LocalizedError {
    case missingCredential(provider: String, mode: LLMAuthMode)
    case unsupportedSubscription(String)
    case invalidURL
    case invalidResponse
    case timedOut
    case networkUnavailable
    case emptyResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let provider, let mode):
            switch mode {
            case .apiKey:
                "\(provider) API 키를 먼저 입력해 주세요."
            case .subscription:
                "\(provider) 구독 토큰을 먼저 연결해 주세요."
            }
        case .unsupportedSubscription(let provider):
            "\(provider)은 아직 구독 연동을 지원하지 않습니다."
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
            switch request.credential {
            case .apiKey:
                return try await generateOpenAIResponsesInsight(request)
            case .subscription:
                return try await generateOpenAICodexSubscriptionInsight(request)
            }
        case .anthropic:
            return try await generateAnthropicInsight(request)
        case .gemini:
            return try await generateGeminiInsight(request)
        }
    }

    func generateTags(_ request: LLMTagRequest) async throws -> [String] {
        let response = try await generateInsight(
            LLMInsightRequest(
                provider: request.provider,
                modelID: request.modelID,
                credential: request.credential,
                category: "태그",
                instruction: "선택한 글조각에 붙일 검색 태그를 JSON으로만 반환하세요.",
                userPrompt: tagPrompt(for: request),
                sources: [
                    LLMInsightSource(
                        bookTitle: request.bookTitle,
                        bookAuthor: request.bookAuthor,
                        bookSummary: request.bookSummary,
                        text: request.text,
                        memo: request.memo
                    )
                ]
            )
        )

        return Self.normalizedTags(fromTagResponse: response)
    }

    private func generateOpenAIResponsesInsight(_ request: LLMInsightRequest) async throws -> String {
        guard let endpoint = URL(string: "https://api.openai.com/v1/responses") else {
            throw LLMInsightError.invalidURL
        }
        let profile = generationProfile(for: request)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(try apiKey(from: request))", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": request.modelID,
            "instructions": systemPrompt(for: request),
            "input": userPrompt(for: request),
            "max_output_tokens": profile.maxOutputTokens,
            "reasoning": [
                "effort": profile.openAIReasoningEffort
            ],
            "text": [
                "verbosity": profile.openAITextVerbosity
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
        let apiKey = try apiKey(from: request)
        let profile = generationProfile(for: request)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        extraHeaders.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        var payload: [String: Any] = [
            "model": request.modelID,
            "messages": [
                ["role": "system", "content": systemPrompt(for: request)],
                ["role": "user", "content": userPrompt(for: request)]
            ],
            "temperature": profile.temperature
        ]

        if usesMaxCompletionTokens {
            payload["max_completion_tokens"] = profile.maxOutputTokens
        } else {
            payload["max_tokens"] = profile.maxOutputTokens
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await responseData(for: urlRequest)
        let response = try decoder.decode(OpenAICompatibleResponse.self, from: data)
        guard let content = response.choices.first?.message.content.trimmed, !content.isEmpty else {
            throw LLMInsightError.emptyResponse
        }
        return content
    }

    private func generateOpenAICodexSubscriptionInsight(_ request: LLMInsightRequest) async throws -> String {
        let token = try subscriptionToken(from: request)
        guard let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses") else {
            throw LLMInsightError.invalidURL
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        urlRequest.setValue("Bearer \(token.accessToken.trimmed)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        urlRequest.setValue("responses=experimental", forHTTPHeaderField: "openai-beta")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "session_id")

        if !token.accountID.trimmed.isEmpty {
            urlRequest.setValue(token.accountID.trimmed, forHTTPHeaderField: "chatgpt-account-id")
        }

        let payload: [String: Any] = [
            "model": request.modelID,
            "instructions": systemPrompt(for: request),
            "input": [
                [
                    "role": "user",
                    "content": userPrompt(for: request)
                ]
            ],
            "stream": true,
            "store": false
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await responseData(for: urlRequest)
        let content = try openAICodexStreamText(from: data)
        guard !content.trimmed.isEmpty else { throw LLMInsightError.emptyResponse }
        return content.trimmed
    }

    private func generateAnthropicInsight(_ request: LLMInsightRequest) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMInsightError.invalidURL
        }
        let profile = generationProfile(for: request)
        let isSubscription = request.credential.mode == .subscription

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        if isSubscription {
            let token = try subscriptionToken(from: request)
            urlRequest.setValue("Bearer \(token.accessToken.trimmed)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("claude-code-20250219,oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        } else {
            urlRequest.setValue(try apiKey(from: request), forHTTPHeaderField: "x-api-key")
        }

        let payload: [String: Any] = [
            "model": request.modelID,
            "max_tokens": profile.maxOutputTokens,
            "system": anthropicSystemPayload(for: request, isSubscription: isSubscription),
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
        let apiKey = try apiKey(from: request)
        guard
            let escapedModel = request.modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent?key=\(apiKey)")
        else {
            throw LLMInsightError.invalidURL
        }
        let profile = generationProfile(for: request)

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
                "temperature": profile.temperature,
                "maxOutputTokens": profile.maxOutputTokens
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

    private func generationProfile(for request: LLMInsightRequest) -> LLMGenerationProfile {
        let base: (maxOutputTokens: Int, temperature: Double, effort: String, verbosity: String)

        switch request.category {
        case "질문":
            base = (1200, 0.35, "low", "low")
        case "요약":
            base = (1600, 0.25, "low", "low")
        case "연결":
            base = (2200, 0.35, "medium", "medium")
        case "확장":
            base = (2600, 0.4, "medium", "medium")
        case "태그":
            base = (180, 0.15, "low", "low")
        default:
            base = (1800, 0.35, "low", "low")
        }

        let sourceBoost = request.category == "태그" ? 0 : min(max(request.sources.count - 4, 0) * 80, 600)
        let modelBoost = request.category == "태그" ? 0 : (request.modelID.localizedCaseInsensitiveContains("thinking") ? 400 : 0)
        let maxOutputTokens = min(base.maxOutputTokens + sourceBoost + modelBoost, 3600)

        return LLMGenerationProfile(
            maxOutputTokens: maxOutputTokens,
            temperature: base.temperature,
            openAIReasoningEffort: base.effort,
            openAITextVerbosity: base.verbosity
        )
    }

    private func apiKey(from request: LLMInsightRequest) throws -> String {
        guard case .apiKey(let apiKey) = request.credential else {
            throw LLMInsightError.unsupportedSubscription(request.provider.title)
        }

        let trimmedAPIKey = apiKey.trimmed
        guard !trimmedAPIKey.isEmpty else {
            throw LLMInsightError.missingCredential(provider: request.provider.title, mode: .apiKey)
        }

        return trimmedAPIKey
    }

    private func subscriptionToken(from request: LLMInsightRequest) throws -> LLMSubscriptionToken {
        guard request.provider.supportsSubscriptionAuth else {
            throw LLMInsightError.unsupportedSubscription(request.provider.title)
        }

        guard case .subscription(let token) = request.credential else {
            throw LLMInsightError.missingCredential(provider: request.provider.title, mode: .subscription)
        }

        guard token.hasAccessToken else {
            throw LLMInsightError.missingCredential(provider: request.provider.title, mode: .subscription)
        }

        return token
    }

    private func anthropicSystemPayload(for request: LLMInsightRequest, isSubscription: Bool) -> Any {
        let prompt = systemPrompt(for: request)
        guard isSubscription else { return prompt }

        return [
            [
                "type": "text",
                "text": "You are Claude Code, Anthropic's official CLI for Claude."
            ],
            [
                "type": "text",
                "text": prompt
            ]
        ]
    }

    private func openAICodexStreamText(from data: Data) throws -> String {
        guard let rawText = String(data: data, encoding: .utf8) else {
            throw LLMInsightError.invalidResponse
        }

        var output = ""
        var completed = false

        for rawLine in rawText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }

            let jsonText = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard jsonText != "[DONE]", let data = jsonText.data(using: .utf8) else {
                continue
            }

            guard
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                continue
            }

            switch type {
            case "response.output_text.delta":
                output += object["delta"] as? String ?? ""
            case "response.completed":
                completed = true
                if output.trimmed.isEmpty, let response = object["response"] as? [String: Any] {
                    output = openAIResponsesText(from: response)
                }
            default:
                continue
            }
        }

        guard completed || !output.trimmed.isEmpty else {
            throw LLMInsightError.invalidResponse
        }

        return output
    }

    private func openAIResponsesText(from response: [String: Any]) -> String {
        if let outputText = response["output_text"] as? String, !outputText.trimmed.isEmpty {
            return outputText
        }

        guard let outputItems = response["output"] as? [[String: Any]] else {
            return ""
        }

        return outputItems
            .compactMap { item -> String? in
                guard let contentItems = item["content"] as? [[String: Any]] else { return nil }
                return contentItems
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
            }
            .joined(separator: "\n")
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
        당신은 Overline의 한국어 독서 인사이트 엔진입니다.
        입력은 사용자가 책을 읽다가 직접 선택한 글조각과 그 글조각이 속한 책의 배경 정보입니다.

        공통 원칙:
        - 선택한 글조각을 1차 근거로 삼으세요. 책 정보는 해석을 돕는 배경 맥락으로만 사용하세요.
        - 입력에 없는 사건, 주장, 수치, 저자의 의도를 새로 만들지 마세요.
        - 원문을 길게 베끼지 말고, 선택된 글조각들이 함께 드러내는 의미를 정리하세요.
        - OCR 때문에 문장이 중간에서 시작하거나 끝날 수 있습니다. 답변은 자연스럽고 완성된 한국어 문장으로 재구성하세요.
        - 답변은 사용자가 바로 저장해도 어색하지 않은 최종 문장이어야 합니다.
        - 별도의 머리말, 사과, 설명, "요약하면" 같은 상투어 없이 본문만 작성하세요.

        \(modeSystemPrompt(for: request))
        """
    }

    private func userPrompt(for request: LLMInsightRequest) -> String {
        let bookContext = bookContextText(for: request.sources)
        let userRequest = request.userPrompt.trimmed

        let sourceText = request.sources.enumerated().map { index, source in
            let memo = source.memo.trimmed.isEmpty ? "" : "\n메모: \(source.memo)"
            return """
            \(index + 1). [책: \(source.bookTitle)]
            \(source.text)\(memo)
            """
        }
        .joined(separator: "\n\n")

        var sections = [
            """
        작업 모드:
        \(request.category)
        """,

            """
        책 맥락:
        \(bookContext)
        """,

            """
        선택한 글조각:
        \(sourceText)
        """
        ]

        if !userRequest.isEmpty {
            sections.append(
                """
        사용자 요청:
        \(userRequest)
        """
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private func tagPrompt(for request: LLMTagRequest) -> String {
        let existingTags = request.existingTags.isEmpty ? "없음" : request.existingTags.joined(separator: ", ")

        return """
        이미 있는 태그:
        \(existingTags)

        작업:
        - 글조각을 나중에 다시 찾기 쉬운 태그 2-4개로 정리하세요.
        - 기존 태그가 적합하면 재사용해도 됩니다.
        - 책 전체 주제가 아니라, 선택된 글조각의 핵심 주제와 개념을 우선하세요.
        """
    }

    private func modeSystemPrompt(for request: LLMInsightRequest) -> String {
        switch request.category {
        case "질문":
            """
            현재 모드: 질문
            목적: 선택한 글조각이 독자에게 남기는 좋은 질문을 뽑는 것입니다.
            작성 규칙:
            - 단순 확인 질문이 아니라, 생각을 더 밀고 나가게 하는 질문을 만드세요.
            - 글조각의 핵심 긴장을 먼저 파악하고, 그 긴장이 드러나는 질문을 1-3개 제시하세요.
            - 각 질문은 짧고 선명해야 하며, 필요한 경우 한 문장으로 왜 중요한지 덧붙이세요.
            - 답을 단정하지 말고, 독자가 다음 메모를 이어갈 수 있게 여지를 남기세요.
            """
        case "연결":
            """
            현재 모드: 연결
            목적: 선택한 글조각들 사이의 공통 패턴, 반복되는 문제의식, 또는 대비되는 관점을 찾아 하나의 생각으로 묶는 것입니다.
            작성 규칙:
            - 여러 책이면 책 사이의 공통 구조를 우선 찾고, 한 책이면 선택된 글조각 안의 반복 테마를 찾으세요.
            - 단순 키워드 나열 대신, "무엇과 무엇이 어떻게 연결되는지"를 분명히 쓰세요.
            - 원문 표현을 그대로 이어붙이지 말고, 독자의 관점에서 붙일 수 있는 이름이나 문장으로 정리하세요.
            - 답변은 2-4문장으로 작성하세요.
            """
        case "확장":
            """
            현재 모드: 확장
            목적: 선택한 글조각에서 더 생각해볼 개념, 반론, 다음 탐구 방향을 제안하는 것입니다.
            작성 규칙:
            - 먼저 글조각의 핵심 주장이나 감각을 짧게 잡고, 그 다음 확장 가능한 방향을 제시하세요.
            - 반론은 원문을 부정하기보다, 원문이 놓치고 있을 가능성을 조심스럽게 여는 방식으로 쓰세요.
            - 추상적인 조언보다 독자가 바로 다음 메모로 이어갈 수 있는 생각의 갈래를 주세요.
            - 답변은 2-4문장으로 작성하세요.
            """
        case "요약":
            """
            현재 모드: 요약
            목적: 선택한 글조각들의 핵심을 하나의 자연스러운 문단으로 정리하는 것입니다.
            작성 규칙:
            - 선택된 글조각 전체가 함께 말하는 중심 생각을 한 문단으로 압축하세요.
            - 문장이 "하여", "그리고", "하지만" 같은 중간 접속이나 잘린 술어로 시작하지 않게 하세요.
            - 책 소개를 요약하지 말고, 선택한 글조각의 논지와 독자가 저장한 부분의 의미를 요약하세요.
            - 글조각이 같은 내용을 반복하면 반복을 줄이고 한 번의 선명한 문장으로 합치세요.
            - 답변은 2-3문장, 가능하면 한 문단으로 작성하세요.
            """
        case "태그":
            """
            현재 모드: 태그
            목적: 캡처된 글조각을 검색과 분류에 유용한 짧은 태그로 정리하는 것입니다.
            작성 규칙:
            - 반드시 JSON만 반환하세요. 형식: {"tags":["태그1","태그2"]}
            - 태그는 2-4개만 작성하세요.
            - # 기호, 설명 문장, 마크다운, 머리말을 넣지 마세요.
            - 태그는 짧은 한국어 명사형을 우선하세요.
            - "책", "글", "글조각", "문장", "인용", "메모", "독서", "한국어"처럼 너무 일반적인 태그는 쓰지 마세요.
            - 책 정보는 배경으로만 참고하고, 선택된 글조각의 핵심 주제와 개념을 우선하세요.
            """
        default:
            """
            현재 모드: \(request.category)
            작업 지시: \(request.instruction)
            답변은 선택한 글조각과 책 맥락만 근거로 2-4문장으로 작성하세요.
            """
        }
    }

    private func bookContextText(for sources: [LLMInsightSource]) -> String {
        var seenKeys = Set<String>()
        var bookContexts: [String] = []

        for source in sources {
            let key = "\(source.bookTitle)\n\(source.bookAuthor)\n\(source.bookSummary)"
            guard seenKeys.insert(key).inserted else { continue }

            let author = source.bookAuthor.trimmed.isEmpty ? "저자 정보 없음" : source.bookAuthor
            let summary = source.bookSummary.trimmed.isEmpty ? "책 소개 없음" : source.bookSummary
            bookContexts.append(
                """
                - 제목: \(source.bookTitle)
                  저자: \(author)
                  책 소개: \(summary)
                """
            )
        }

        return bookContexts.isEmpty ? "책 정보 없음" : bookContexts.joined(separator: "\n")
    }

    private static func normalizedTags(fromTagResponse response: String) -> [String] {
        let cleanedResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmed

        if
            let data = cleanedResponse.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        {
            if let dictionary = object as? [String: Any], let tags = dictionary["tags"] as? [String] {
                return normalizedTagList(tags)
            }

            if let tags = object as? [String] {
                return normalizedTagList(tags)
            }
        }

        let fallbackTags = cleanedResponse
            .components(separatedBy: CharacterSet(charactersIn: ",\n[]\"'`"))
        return normalizedTagList(fallbackTags)
    }

    private static func normalizedTagList(_ values: [String]) -> [String] {
        let genericTags: Set<String> = [
            "책", "글", "글조각", "문장", "인용", "메모", "독서", "한국어", "영어", "일본어",
            "내용", "생각", "요약", "핵심", "아이디어"
        ]
        var seenTags = Set<String>()
        var tags: [String] = []

        for value in values {
            let normalized = value
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}」』\"'`"))
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)

            guard normalized.count >= 2, normalized.count <= 20 else { continue }
            guard !genericTags.contains(normalized) else { continue }

            let tag = "#\(normalized)"
            guard seenTags.insert(tag).inserted else { continue }

            tags.append(tag)
            if tags.count == 4 { break }
        }

        return tags
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
