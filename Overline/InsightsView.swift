import Foundation
import OSLog
import SwiftUI

private let insightMetricsLogger = Logger(subsystem: "aib.Overline", category: "InsightMetrics")

struct InsightsView: View {
    @Environment(ReadingLibrary.self) private var library
    @Environment(AppIntentRouter.self) private var intentRouter
    @State private var question = "더 파고들 개념과 반론은?"
    @State private var selectedPrompt: InsightPrompt = .expand
    @State private var selectedBookIDs: Set<ReadingBook.ID> = []
    @State private var selectedHighlightIDs: Set<Highlight.ID> = []
    @State private var isSourcePickerPresented = false
    @State private var isLLMSettingsPresented = false
    @State private var llmSettings = LLMSettingsStore()
    @State private var isGeneratingInsight = false
    @State private var insightErrorMessage: String?
    @State private var showsInsightSavedAlert = false
    @State private var presentedDetailInsight: LibraryInsight?
    @State private var presentedSourceInsight: LibraryInsight?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                InsightWorkspaceHeader(
                    settings: llmSettings,
                    openSettings: { isLLMSettingsPresented = true }
                )

                InsightComposer(
                    question: $question,
                    selectedPrompt: $selectedPrompt,
                    selectedCount: selectedSourceCount,
                    canSubmit: selectedSourceCount > 0 && !isGeneratingInsight,
                    isSubmitting: isGeneratingInsight,
                    errorMessage: insightErrorMessage,
                    openPicker: { isSourcePickerPresented = true },
                    submit: requestInsightGeneration
                )

                if !library.savedInsights.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        InsightSectionHeader(
                            title: "저장됨",
                            systemImage: "tray.full",
                            trailingText: "\(library.savedInsights.count)"
                        )

                        ForEach(library.savedInsights) { insight in
                            SavedInsightCard(
                                insight: insight,
                                canShowSources: !(insight.sourceHighlightIDs ?? []).isEmpty,
                                openDetail: {
                                    presentedDetailInsight = insight
                                },
                                showSources: {
                                    presentedSourceInsight = insight
                                }
                            )
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .overlineBottomMenuCompaction()
        .background(OverlineCanvasBackground().ignoresSafeArea())
        .onAppear {
            _ = applyInsightSeed(intentRouter.request)
        }
        .onChange(of: intentRouter.request) { _, request in
            _ = applyInsightSeed(request)
        }
        .sheet(isPresented: $isSourcePickerPresented) {
            HighlightPickerSheet(
                books: library.books,
                selectedBookIDs: $selectedBookIDs,
                selectedHighlightIDs: $selectedHighlightIDs
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isLLMSettingsPresented) {
            LLMSettingsSheet(settings: llmSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedDetailInsight) { insight in
            InsightDetailSheet(
                insight: insight,
                sources: sourceEntries(for: insight),
                delete: {
                    library.deleteInsight(insight.id)
                    presentedDetailInsight = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedSourceInsight) { insight in
            InsightSourceSheet(
                insight: insight,
                sources: sourceEntries(for: insight)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("인사이트 저장됨", isPresented: $showsInsightSavedAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("생각 정리를 저장했습니다.")
        }
    }

    private var selectedSourceCount: Int {
        selectedSourceIDs.count
    }

    private var selectedSourceIDs: [Highlight.ID] {
        effectiveSelectedHighlightIDs(in: library.books)
    }

    private func selectedSourcePayload() -> (sources: [LLMInsightSource], ids: [Highlight.ID]) {
        let effectiveIDs = Set(selectedSourceIDs)
        var sources: [LLMInsightSource] = []
        var ids: [Highlight.ID] = []

        for book in library.books {
            for highlight in book.highlights where effectiveIDs.contains(highlight.id) {
                ids.append(highlight.id)
                sources.append(
                    LLMInsightSource(
                        bookTitle: book.title,
                        bookAuthor: book.author,
                        bookSummary: book.summary,
                        text: highlight.text,
                        memo: highlight.memo
                    )
                )
            }
        }

        return (sources, ids)
    }

    private func effectiveSelectedHighlightIDs(in books: [ReadingBook]) -> [Highlight.ID] {
        var seenIDs = Set<Highlight.ID>()
        var orderedIDs: [Highlight.ID] = []

        for book in books {
            let isBookSelected = selectedBookIDs.contains(book.id)
            for highlight in book.highlights where isBookSelected || selectedHighlightIDs.contains(highlight.id) {
                if seenIDs.insert(highlight.id).inserted {
                    orderedIDs.append(highlight.id)
                }
            }
        }

        return orderedIDs
    }

    private func sourceEntries(for insight: LibraryInsight) -> [InsightSourceEntry] {
        let sourceIDs = insight.sourceHighlightIDs ?? []
        return sourceIDs.compactMap { sourceID in
            for book in library.books {
                if let highlight = book.highlights.first(where: { $0.id == sourceID }) {
                    return InsightSourceEntry(bookTitle: book.title, highlight: highlight)
                }
            }

            return nil
        }
    }

    @discardableResult
    private func applyInsightSeed(_ request: AppIntentRequest?) -> Bool {
        guard request?.tab == .insights, let seed = request?.insightSeed else { return false }

        selectedBookIDs.removeAll()
        selectedHighlightIDs = seed.highlightIDs
        selectedPrompt = seed.prompt
        question = seed.question?.trimmed.isEmpty == false ? seed.question ?? seed.prompt.seedQuestion : seed.prompt.seedQuestion
        insightErrorMessage = nil
        return true
    }

    @MainActor
    private func requestInsightGeneration() {
        guard !isGeneratingInsight else { return }
        guard selectedSourceCount > 0 else { return }

        guard llmSettings.isReady(for: llmSettings.provider) else {
            logInsightGenerationBlocked(reason: "missing_auth_credential")
            insightErrorMessage = missingCredentialMessage(for: llmSettings.provider)
            isLLMSettingsPresented = true
            return
        }

        insightErrorMessage = nil
        Task {
            await saveGeneratedInsight()
        }
    }

    @MainActor
    private func saveGeneratedInsight() async {
        guard !isGeneratingInsight else { return }
        let payload = selectedSourcePayload()
        guard !payload.sources.isEmpty else { return }

        let prompt = question.trimmed.isEmpty ? selectedPrompt.seedQuestion : question.trimmed

        guard llmSettings.isReady(for: llmSettings.provider) else {
            insightErrorMessage = missingCredentialMessage(for: llmSettings.provider)
            isLLMSettingsPresented = true
            return
        }

        let provider = llmSettings.provider
        let modelID = llmSettings.selectedModelID
        let sourceCount = payload.sources.count
        let category = selectedPrompt.rawValue
        let startedAt = Date()

        isGeneratingInsight = true
        insightErrorMessage = nil
        logInsightGenerationRequested(
            provider: provider,
            category: category,
            sourceCount: sourceCount,
            hasCustomQuestion: !question.trimmed.isEmpty
        )
        LLMUsageMetricsStore.recordRequested()

        do {
            let generatedBody = try await LLMInsightClient().generateInsight(
                LLMInsightRequest(
                    provider: provider,
                    modelID: modelID,
                    credential: llmSettings.credential(for: provider),
                    category: selectedPrompt.title,
                    instruction: selectedPrompt.llmInstruction,
                    userPrompt: prompt,
                    sources: payload.sources
                )
            )

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                library.addInsight(
                    categoryRaw: selectedPrompt.rawValue,
                    prompt: prompt,
                    body: generatedBody,
                    sourceCount: sourceCount,
                    sourceHighlightIDs: payload.ids
                )
                question = ""
            }
            let durationMilliseconds = milliseconds(since: startedAt)
            logInsightGenerationCompleted(
                provider: provider,
                category: category,
                sourceCount: sourceCount,
                durationMilliseconds: durationMilliseconds
            )
            LLMUsageMetricsStore.recordCompleted()
            MVPReadinessStore.markVerified(
                .llmInsight,
                detail: "\(provider.title) · \(modelID) · \(sourceCount)조각 · \(durationMilliseconds)ms"
            )
            showsInsightSavedAlert = true
        } catch {
            insightErrorMessage = error.localizedDescription
            logInsightGenerationFailed(
                provider: provider,
                category: category,
                sourceCount: sourceCount,
                durationMilliseconds: milliseconds(since: startedAt),
                error: error
            )
            LLMUsageMetricsStore.recordFailed()
        }

        isGeneratingInsight = false
    }

    private func milliseconds(since date: Date) -> Int {
        Int((Date().timeIntervalSince(date) * 1000).rounded())
    }

    private func logInsightGenerationBlocked(reason: String) {
        insightMetricsLogger.info(
            "insight_generation_blocked reason=\(reason, privacy: .public)"
        )
    }

    private func missingCredentialMessage(for provider: LLMProvider) -> String {
        switch llmSettings.authMode(for: provider) {
        case .apiKey:
            return "\(provider.title) API 키를 먼저 입력해 주세요."
        case .subscription:
            return "\(provider.title) 구독 토큰을 먼저 연결해 주세요."
        }
    }

    private func logInsightGenerationRequested(
        provider: LLMProvider,
        category: String,
        sourceCount: Int,
        hasCustomQuestion: Bool
    ) {
        insightMetricsLogger.info(
            "insight_generation_requested provider=\(provider.rawValue, privacy: .public) category=\(category, privacy: .public) source_count=\(sourceCount, privacy: .public) has_custom_question=\(hasCustomQuestion, privacy: .public)"
        )
    }

    private func logInsightGenerationCompleted(
        provider: LLMProvider,
        category: String,
        sourceCount: Int,
        durationMilliseconds: Int
    ) {
        insightMetricsLogger.info(
            "insight_generation_completed provider=\(provider.rawValue, privacy: .public) category=\(category, privacy: .public) source_count=\(sourceCount, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public)"
        )
    }

    private func logInsightGenerationFailed(
        provider: LLMProvider,
        category: String,
        sourceCount: Int,
        durationMilliseconds: Int,
        error: Error
    ) {
        insightMetricsLogger.error(
            "insight_generation_failed provider=\(provider.rawValue, privacy: .public) category=\(category, privacy: .public) source_count=\(sourceCount, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public) error_code=\(error.insightMetricsCode, privacy: .public)"
        )
    }
}

private struct InsightWorkspaceHeader: View {
    let settings: LLMSettingsStore
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineAccent)
            Text("생각 정리하기")
                .font(.headline)
                .foregroundStyle(Color.overlineInk)

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.84))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI 설정")
            .accessibilityValue("\(settings.provider.title), \(settings.selectedModelTitle)")
        }
    }
}

private struct InsightSectionHeader: View {
    let title: String
    let systemImage: String
    var trailingText: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineAccent)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.overlineInk)
            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
            }
            Spacer()
        }
    }
}

private struct LLMSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let settings: LLMSettingsStore
    @State private var isTestingConnection = false
    @State private var connectionTestResult: LLMConnectionTestResult?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("제공자", selection: providerBinding) {
                        ForEach(LLMProvider.allCases) { provider in
                            Label(provider.title, systemImage: provider.systemImage)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("모델", selection: modelBinding) {
                        ForEach(settings.provider.modelOptions) { model in
                            Text(model.title)
                            .tag(model.id)
                        }

                        if !selectedModelIsPreset {
                            Text(settings.selectedModelID)
                                .tag(settings.selectedModelID)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    LabeledContent("직접 모델 ID") {
                        TextField(settings.provider.defaultModelID, text: modelBinding)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("목록에 없는 모델도 제공자 문서의 모델 ID를 그대로 입력해 사용할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settings.provider.supportsSubscriptionAuth {
                        Picker("인증", selection: authModeBinding) {
                            ForEach(LLMAuthMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        LabeledContent("인증") {
                            Text("API 키")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    ForEach(LLMProvider.allCases) { provider in
                        LLMAPIKeyRow(
                            provider: provider,
                            apiKey: Binding(
                                get: { settings.apiKey(for: provider) },
                                set: { settings.setAPIKey($0, for: provider) }
                            )
                        )
                    }
                } header: {
                    Text("API 키")
                } footer: {
                    Text("API 키는 백업 경로로 유지됩니다. 현재 제공자가 API 키 인증으로 설정된 경우에만 사용합니다.")
                }

                Section {
                    ForEach(LLMProvider.allCases.filter(\.supportsSubscriptionAuth)) { provider in
                        LLMSubscriptionTokenRow(
                            provider: provider,
                            token: Binding(
                                get: { settings.subscriptionToken(for: provider) },
                                set: { settings.setSubscriptionToken($0, for: provider) }
                            )
                        )
                    }
                } header: {
                    Text("구독 연동 테스트")
                } footer: {
                    Text("OpenAI와 Claude 구독 토큰은 iOS Keychain에 이 기기 전용으로 저장됩니다. 브라우저 OAuth 자동 로그인은 다음 단계에서 붙일 수 있도록 호출 경로를 먼저 분리했습니다.")
                }

                Section {
                    LLMActiveModelSummary(settings: settings)
                }

                Section("연결 테스트") {
                    Button {
                        Task {
                            await testConnection()
                        }
                    } label: {
                        HStack {
                            Label("현재 모델 테스트", systemImage: "network")
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isTestingConnection || !settings.isReady(for: settings.provider))

                    if !settings.isReady(for: settings.provider) {
                        Text(connectionSetupHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let connectionTestResult {
                        Label(
                            connectionTestResult.message,
                            systemImage: connectionTestResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(connectionTestResult.isSuccess ? Color.overlineAccent : Color.overlineCoral)
                    }
                }

                Section("전송 안내") {
                    Text("선택한 글조각과 메모만 현재 AI 제공자로 전송됩니다. Overline은 캡처 내용을 자체 서버에 저장하지 않으며, 캡처 내용은 AI 학습에 사용되지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        PrivacyTransmissionPolicyView()
                    } label: {
                        Label("개인정보와 AI 전송", systemImage: "lock.shield")
                    }

                    NavigationLink {
                        OverlineTermsView()
                    } label: {
                        Label("이용 조건", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("AI 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    OverlineDoneToolbarButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { settings.provider },
            set: { settings.provider = $0 }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.selectedModelID },
            set: { settings.setSelectedModelID($0) }
        )
    }

    private var authModeBinding: Binding<LLMAuthMode> {
        Binding(
            get: { settings.authMode(for: settings.provider) },
            set: { settings.setAuthMode($0, for: settings.provider) }
        )
    }

    private var selectedModelIsPreset: Bool {
        settings.provider.modelOptions.contains { $0.id == settings.selectedModelID }
    }

    private var connectionSetupHint: String {
        switch settings.authMode(for: settings.provider) {
        case .apiKey:
            return "\(settings.provider.title) API 키를 입력하면 연결을 확인할 수 있습니다."
        case .subscription:
            return "\(settings.provider.title) 구독 토큰을 연결하면 현재 모델을 테스트할 수 있습니다."
        }
    }

    @MainActor
    private func testConnection() async {
        guard !isTestingConnection else { return }
        guard settings.isReady(for: settings.provider) else { return }

        let provider = settings.provider
        let modelID = settings.selectedModelID
        let startedAt = Date()

        isTestingConnection = true
        connectionTestResult = nil
        insightMetricsLogger.info(
            "llm_connection_test_requested provider=\(provider.rawValue, privacy: .public)"
        )

        do {
            let response = try await LLMInsightClient().generateInsight(
                LLMInsightRequest(
                    provider: provider,
                    modelID: modelID,
                    credential: settings.credential(for: provider),
                    category: "연결 테스트",
                    instruction: "연결이 정상인지 확인하기 위해 한 문장으로만 답하세요.",
                    userPrompt: "Overline AI 연결 테스트입니다. 정상이라면 짧게 확인했다고 답하세요.",
                    sources: [
                        LLMInsightSource(
                            bookTitle: "Overline Test",
                            bookAuthor: "Overline",
                            bookSummary: "독자가 책 속 글조각을 저장하고, 선택한 문장을 바탕으로 생각을 정리하는 테스트용 책입니다.",
                            text: "독서 메모를 안전하게 정리한다.",
                            memo: "연결 확인용 테스트 문장"
                        )
                    ]
                )
            )

            let preview = String(response.trimmed.prefix(120))
            connectionTestResult = LLMConnectionTestResult(
                isSuccess: true,
                message: preview.isEmpty ? "연결 확인 완료" : preview
            )
            MVPReadinessStore.markVerified(
                .llmInsight,
                detail: "\(provider.title) · \(modelID) 연결 테스트"
            )
            insightMetricsLogger.info(
                "llm_connection_test_completed provider=\(provider.rawValue, privacy: .public) duration_ms=\(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()), privacy: .public)"
            )
        } catch {
            connectionTestResult = LLMConnectionTestResult(
                isSuccess: false,
                message: error.localizedDescription
            )
            insightMetricsLogger.error(
                "llm_connection_test_failed provider=\(provider.rawValue, privacy: .public) duration_ms=\(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()), privacy: .public) error_code=\(error.insightMetricsCode, privacy: .public)"
            )
        }

        isTestingConnection = false
    }
}

private struct LLMConnectionTestResult {
    let isSuccess: Bool
    let message: String
}

private extension Error {
    var insightMetricsCode: String {
        guard let llmError = self as? LLMInsightError else {
            return String(describing: type(of: self))
        }

        switch llmError {
        case .missingCredential(_, let mode):
            return "missing_\(mode.rawValue)"
        case .unsupportedSubscription:
            return "unsupported_subscription"
        case .invalidURL:
            return "invalid_url"
        case .invalidResponse:
            return "invalid_response"
        case .timedOut:
            return "timed_out"
        case .networkUnavailable:
            return "network_unavailable"
        case .emptyResponse:
            return "empty_response"
        case .requestFailed(let statusCode, _):
            return "request_failed_\(statusCode)"
        }
    }
}

private struct PrivacyTransmissionPolicyView: View {
    private let policies: [PrivacyTransmissionPolicy] = [
        PrivacyTransmissionPolicy(
            systemImage: "iphone",
            title: "로컬 저장",
            body: "OCR로 저장한 글조각과 메모만 이 기기 안에 저장됩니다. 캡처 사진은 OCR 완료 후 폐기합니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "key",
            title: "API 키 보관",
            body: "API 키와 구독 토큰은 iOS Keychain에 이 기기 전용으로 저장됩니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "sparkles",
            title: "AI 전송 범위",
            body: "선택한 글조각과 메모만 현재 선택한 AI 제공자로 전송됩니다. 자동 분석이나 백그라운드 전송은 하지 않습니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "nosign",
            title: "학습 데이터 미사용",
            body: "Overline은 캡처 내용을 AI 학습 데이터로 사용하지 않습니다. 외부 제공자의 처리 조건은 사용자가 연결한 계정 약관을 따릅니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "book.closed",
            title: "표지 이미지",
            body: "도서 표지는 Kakao 또는 Aladin API가 제공한 URL만 참조하며, 앱 안에 표지 이미지를 복사 저장하지 않습니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "square.and.arrow.up",
            title: "공유",
            body: "공유 버튼은 사용자가 선택한 글조각이나 책 메모를 iOS 공유 시트로 넘길 때만 동작합니다. 책 원문 공유는 사적 이용 범위를 넘을 수 있어 매번 확인을 거칩니다."
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(policies) { policy in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: policy.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.overlineAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(policy.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.overlineInk)

                            Text(policy.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("클라우드 동기화는 v1 범위에 포함하지 않습니다.")
            }
        }
        .navigationTitle("개인정보와 AI")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyTransmissionPolicy: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let body: String
}

private struct OverlineTermsView: View {
    private let terms: [OverlineTerm] = [
        OverlineTerm(
            systemImage: "person.crop.circle",
            title: "개인 독서 메모",
            body: "OCR 캡처 결과는 글조각과 메모로만 저장됩니다. 원문 사진은 개인 기록에도 남기지 않습니다."
        ),
        OverlineTerm(
            systemImage: "sparkles",
            title: "요청할 때만 AI 전송",
            body: "인사이트 생성이나 연결 테스트를 누른 경우에만 선택한 글조각, 메모, 책 정보가 현재 선택한 AI 제공자로 전송됩니다."
        ),
        OverlineTerm(
            systemImage: "nosign",
            title: "학습 데이터 미사용",
            body: "Overline은 캡처 내용과 메모를 자체 AI 학습 데이터로 사용하지 않으며 별도 서버에 저장하지 않습니다."
        ),
        OverlineTerm(
            systemImage: "square.and.arrow.up",
            title: "공유 주의",
            body: "책 원문을 공개 채널이나 다른 사람에게 보내는 공유는 사적 이용 범위를 넘을 수 있습니다. 공유 전 직접 작성한 메모나 짧은 인용인지 확인해야 합니다."
        ),
        OverlineTerm(
            systemImage: "icloud.slash",
            title: "v1 로컬 우선",
            body: "v1에는 iCloud 동기화, 서버 저장, 소셜 공유, 전자책 연동을 포함하지 않습니다."
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(terms) { term in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: term.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.overlineAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(term.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.overlineInk)

                            Text(term.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("이 화면은 앱 사용 원칙 안내이며 법률 자문을 대체하지 않습니다.")
            }
        }
        .navigationTitle("이용 조건")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OverlineTerm: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let body: String
}

private struct LLMAPIKeyRow: View {
    let provider: LLMProvider
    @Binding var apiKey: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 24)
                .foregroundStyle(Color.overlineAccent)

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk)

                SecureField(provider.keyPlaceholder, text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .privacySensitive()
            }
        }
    }
}

private struct LLMSubscriptionTokenRow: View {
    let provider: LLMProvider
    @Binding var token: LLMSubscriptionToken

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: provider.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                    .foregroundStyle(Color.overlineAccent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                    Text(token.hasAccessToken ? "구독 토큰 연결됨" : "구독 토큰 없음")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(token.hasAccessToken ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.72))
                }

                Spacer()

                if token.hasAccessToken || !token.refreshToken.trimmed.isEmpty || !token.accountID.trimmed.isEmpty {
                    Button {
                        token = .empty
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(provider.title) 구독 토큰 삭제")
                }
            }

            SecureField("Access token", text: $token.accessToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption)
                .privacySensitive()

            switch provider {
            case .openai:
                TextField("ChatGPT account id (선택)", text: $token.accountID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .anthropic:
                SecureField("Refresh token (선택)", text: $token.refreshToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)
                    .privacySensitive()
            case .openrouter, .gemini:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LLMActiveModelSummary: View {
    let settings: LLMSettingsStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: settings.provider.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 24)
                .foregroundStyle(Color.overlineAccent)

            VStack(alignment: .leading, spacing: 3) {
                Text(settings.provider.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)
                Text(settings.selectedModelTitle)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
                Text(settings.authMode(for: settings.provider).title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.74))
            }

            Spacer()

            Image(systemName: settings.isReady(for: settings.provider) ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(settings.isReady(for: settings.provider) ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.68))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InsightComposer: View {
    @Binding var question: String
    @Binding var selectedPrompt: InsightPrompt
    let selectedCount: Int
    let canSubmit: Bool
    let isSubmitting: Bool
    let errorMessage: String?
    let openPicker: () -> Void
    let submit: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            promptSelector

            VStack(alignment: .leading, spacing: 8) {
                TextField("문장들에게 묻기", text: $question, axis: .vertical)
                    .font(.body)
                    .lineLimit(7...10)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)

                HStack {
                    Button(action: openPicker) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            if selectedCount > 0 {
                                Text("\(selectedCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.overlineMutedInk)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minWidth: 17, minHeight: 17)
                            }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(minWidth: 40, minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("글조각 선택")
                    .accessibilityValue("\(selectedCount)조각 선택됨")

                    Spacer()

                    Button(action: submit) {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        .foregroundStyle(canSubmit ? Color.overlineMutedInk : Color.overlineMutedInk.opacity(0.42))
                        .frame(width: 38, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .accessibilityLabel("인사이트 생성")
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.overlineCoral.opacity(0.86))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .insightGlassSurface(
                cornerRadius: 20,
                tint: Color.white.opacity(0.12),
                fillOpacity: 0.06,
                strokeOpacity: 0.28,
                shadowOpacity: 0.04,
                shadowRadius: 12
            )
        }
        .padding(14)
        .insightGlassSurface(
            cornerRadius: 24,
            tint: Color.overlineAccent.opacity(0.08),
            fillOpacity: 0.04,
            strokeOpacity: 0.34,
            shadowOpacity: 0.08,
            shadowRadius: 18
        )
    }

    @ViewBuilder
    private var promptSelector: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                promptButtons
            }
        } else {
            promptButtons
        }
    }

    private var promptButtons: some View {
        HStack(spacing: 6) {
            ForEach(InsightPrompt.allCases) { prompt in
                Button {
                    selectedPrompt = prompt
                    question = prompt.seedQuestion
                } label: {
                    PromptChip(prompt: prompt, isSelected: selectedPrompt == prompt)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private enum HighlightPickerMode: String, CaseIterable, Identifiable {
    case books
    case highlights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .books: "책"
        case .highlights: "글조각"
        }
    }
}

private struct HighlightPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let books: [ReadingBook]
    @Binding var selectedBookIDs: Set<ReadingBook.ID>
    @Binding var selectedHighlightIDs: Set<Highlight.ID>
    @State private var mode: HighlightPickerMode = .books
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            OverlineSheetHeader(title: "글조각 선택") {
                Color.clear
            } trailing: {
                OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "완료") {
                    dismiss()
                }
            }

            if !selectableHighlights.isEmpty {
                VStack(spacing: 10) {
                    HighlightPickerModeControl(mode: $mode)
                    OverlinePillSearchField(text: $searchText, prompt: "검색")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            List {
                if selectableHighlights.isEmpty {
                    ContentUnavailableView(
                        "선택할 글조각 없음",
                        systemImage: "text.viewfinder",
                        description: Text("캡처 탭에서 문장을 저장하면 인사이트에 사용할 수 있습니다.")
                    )
                } else if mode == .books {
                    if filteredBooks.isEmpty {
                        ContentUnavailableView(
                            "검색 결과 없음",
                            systemImage: "magnifyingglass",
                            description: Text("다른 검색어를 입력해 보세요.")
                        )
                    } else {
                        Section {
                            ForEach(filteredBooks) { book in
                                Button {
                                    toggle(book)
                                } label: {
                                    BookPickerRow(
                                        book: book,
                                        isSelected: selectedBookIDs.contains(book.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else if filteredBooksForHighlights.isEmpty {
                    ContentUnavailableView(
                        "검색 결과 없음",
                        systemImage: "magnifyingglass",
                        description: Text("다른 검색어를 입력해 보세요.")
                    )
                } else {
                    ForEach(filteredBooksForHighlights) { book in
                        let highlights = filteredHighlights(in: book)
                        Section(book.title) {
                            ForEach(highlights) { highlight in
                                let isIncludedByBook = selectedBookIDs.contains(book.id)
                                Button {
                                    guard !isIncludedByBook else { return }
                                    toggle(highlight)
                                } label: {
                                    HighlightPickerRow(
                                        highlight: highlight,
                                        isSelected: selectedHighlightIDs.contains(highlight.id) || isIncludedByBook,
                                        isIncludedByBook: isIncludedByBook
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationBackground(.thinMaterial)
    }

    private func toggle(_ book: ReadingBook) {
        if selectedBookIDs.contains(book.id) {
            selectedBookIDs.remove(book.id)
        } else {
            selectedBookIDs.insert(book.id)
        }
    }

    private func toggle(_ highlight: Highlight) {
        if selectedHighlightIDs.contains(highlight.id) {
            selectedHighlightIDs.remove(highlight.id)
        } else {
            selectedHighlightIDs.insert(highlight.id)
        }
    }

    private var selectableHighlights: [Highlight] {
        books.flatMap(\.highlights)
    }

    private var booksWithHighlights: [ReadingBook] {
        books.filter { !$0.highlights.isEmpty }
    }

    private var searchQuery: String {
        searchText.trimmed
    }

    private var filteredBooks: [ReadingBook] {
        guard !searchQuery.isEmpty else { return booksWithHighlights }
        return booksWithHighlights.filter { bookMatches($0) }
    }

    private var filteredBooksForHighlights: [ReadingBook] {
        booksWithHighlights.filter { !filteredHighlights(in: $0).isEmpty }
    }

    private func filteredHighlights(in book: ReadingBook) -> [Highlight] {
        guard !searchQuery.isEmpty else { return book.highlights }
        return book.highlights.filter { highlightMatches($0, in: book) }
    }

    private func bookMatches(_ book: ReadingBook) -> Bool {
        book.title.localizedCaseInsensitiveContains(searchQuery)
            || book.author.localizedCaseInsensitiveContains(searchQuery)
            || book.summary.localizedCaseInsensitiveContains(searchQuery)
    }

    private func highlightMatches(_ highlight: Highlight, in book: ReadingBook) -> Bool {
        book.title.localizedCaseInsensitiveContains(searchQuery)
            || highlight.text.localizedCaseInsensitiveContains(searchQuery)
            || highlight.pageReference.localizedCaseInsensitiveContains(searchQuery)
            || highlight.tags.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
    }
}

private struct HighlightPickerModeControl: View {
    @Binding var mode: HighlightPickerMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HighlightPickerMode.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        mode = item
                    }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == item ? Color.overlineInk : Color.overlineMutedInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: OverlinePillSearchField.height - 6)
                        .contentShape(Rectangle())
                        .background {
                            if mode == item {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.68))
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: OverlinePillSearchField.height)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
    }
}

struct OverlinePillSearchField: View {
    static let height: CGFloat = 42

    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.72))

            TextField(prompt, text: $text)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.62))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct BookPickerRow: View {
    let book: ReadingBook
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.55))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(2)

                if !book.author.trimmed.isEmpty {
                    Text(book.author)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.overlineMutedInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text("\(book.highlights.count)조각")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct HighlightPickerRow: View {
    let highlight: Highlight
    let isSelected: Bool
    let isIncludedByBook: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.55))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.overlineInk)
                    .lineSpacing(3)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(highlight.pageReference)
                    ForEach(highlight.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                    }
                    if isIncludedByBook {
                        Text("책으로 포함됨")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PromptChip: View {
    let prompt: InsightPrompt
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: prompt.systemImage)
                .font(.callout.weight(.semibold))
                .frame(width: 16)
            Text(prompt.title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(isSelected ? Color.overlineInk : Color.overlineMutedInk)
        .frame(maxWidth: .infinity, minHeight: 38)
        .insightGlassSurface(
            cornerRadius: 19,
            tint: isSelected ? Color.overlineHighlight.opacity(0.16) : Color.white.opacity(0.10),
            interactive: true,
            fillOpacity: isSelected ? 0.09 : 0.035,
            strokeOpacity: isSelected ? 0.42 : 0.22,
            shadowOpacity: isSelected ? 0.06 : 0.03,
            shadowRadius: 10
        )
        .contentShape(Capsule(style: .continuous))
    }
}

private struct InsightCategoryIcon: View {
    let prompt: InsightPrompt

    var body: some View {
        Image(systemName: prompt.systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(width: 18)
            .foregroundStyle(Color.overlineAccent)
            .padding(.top, 2)
    }
}

private struct InsightSourceEntry: Identifiable {
    let bookTitle: String
    let highlight: Highlight

    var id: Highlight.ID {
        highlight.id
    }
}

private struct InsightSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let insight: LibraryInsight
    let sources: [InsightSourceEntry]

    var body: some View {
        VStack(spacing: 0) {
            OverlineSheetHeader(title: "근거 글조각") {
                Color.clear
            } trailing: {
                OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "완료") {
                    dismiss()
                }
            }

            List {
                if sources.isEmpty {
                    ContentUnavailableView("근거 글조각 없음", systemImage: "doc.text.magnifyingglass")
                } else {
                    Section {
                        ForEach(sources) { source in
                            InsightSourceRow(source: source)
                        }
                    } footer: {
                        Text(insight.createdAt.overlineShortDate)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationBackground(.thinMaterial)
    }
}

private struct InsightSourceRow: View {
    let source: InsightSourceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.caption.weight(.bold))
                Text(source.bookTitle)
                Text(source.highlight.pageReference)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.overlineMutedInk.opacity(0.78))

            Text(source.highlight.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.overlineInk)
                .lineSpacing(4)
                .lineLimit(5)

            if !source.highlight.memo.isEmpty {
                Text(source.highlight.memo)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
                    .lineSpacing(3)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct InsightMarkdownText: View {
    let text: String
    var font: Font
    var foregroundStyle: Color
    var lineSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isDivider {
                    Divider()
                        .overlay(foregroundStyle.opacity(0.18))
                        .padding(.vertical, lineSpacing * 0.35)
                } else {
                    markdownText(segment.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func markdownText(_ value: String) -> some View {
        if let attributed = try? AttributedString(markdown: value) {
            Text(attributed)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(value)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segments: [InsightMarkdownSegment] {
        var result: [InsightMarkdownSegment] = []
        var buffer: [String] = []

        func flushBuffer() {
            let value = buffer.joined(separator: "\n").trimmed
            if !value.isEmpty {
                result.append(InsightMarkdownSegment(text: value, isDivider: false))
            }
            buffer.removeAll()
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmed
            if trimmedLine == "---" || trimmedLine == "***" || trimmedLine == "___" {
                flushBuffer()
                result.append(InsightMarkdownSegment(text: "", isDivider: true))
            } else {
                buffer.append(line)
            }
        }

        flushBuffer()
        return result.isEmpty ? [InsightMarkdownSegment(text: text, isDivider: false)] : result
    }
}

private struct InsightMarkdownSegment {
    let text: String
    let isDivider: Bool
}

private struct InsightDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let insight: LibraryInsight
    let sources: [InsightSourceEntry]
    let delete: () -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            OverlineSheetHeader(title: "인사이트") {
                OverlineSheetIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "인사이트 삭제",
                    tint: Color.overlineMutedInk.opacity(0.72),
                    font: .title2.weight(.regular)
                ) {
                    showsDeleteConfirmation = true
                }
            } trailing: {
                OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "완료") {
                    dismiss()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            InsightCategoryIcon(prompt: prompt)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(insight.prompt)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Color.overlineInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(insight.createdAt.overlineShortDate)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.overlineMutedInk.opacity(0.78))
                            }
                        }

                        InsightMarkdownText(
                            text: insight.body,
                            font: .body,
                            foregroundStyle: Color.overlineInk,
                            lineSpacing: 6
                        )
                    }
                    .padding(16)
                    .insightGlassSurface(
                        cornerRadius: 20,
                        tint: Color.white.opacity(0.12),
                        fillOpacity: 0.06,
                        strokeOpacity: 0.28,
                        shadowOpacity: 0.05,
                        shadowRadius: 14
                    )

                    if !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            InsightSectionHeader(
                                title: "근거 글조각",
                                systemImage: "doc.text",
                                trailingText: "\(sources.count)"
                            )

                            VStack(spacing: 0) {
                                ForEach(sources) { source in
                                    InsightSourceRow(source: source)
                                        .padding(.vertical, 10)

                                    if source.id != sources.last?.id {
                                        Divider()
                                            .opacity(0.42)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .insightGlassSurface(
                                cornerRadius: 18,
                                tint: Color.white.opacity(0.10),
                                fillOpacity: 0.045,
                                strokeOpacity: 0.24,
                                shadowOpacity: 0.04,
                                shadowRadius: 12
                            )
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .confirmationDialog("인사이트를 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                delete()
            }
            Button("취소", role: .cancel) {}
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationBackground(.thinMaterial)
    }

    private var prompt: InsightPrompt {
        InsightPrompt(rawValue: insight.categoryRaw) ?? .connect
    }
}

private struct SavedInsightCard: View {
    let insight: LibraryInsight
    let canShowSources: Bool
    let openDetail: () -> Void
    let showSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                InsightCategoryIcon(prompt: InsightPrompt(rawValue: insight.categoryRaw) ?? .connect)

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.prompt)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.overlineInk)
                        .lineLimit(2)

                    Text(insight.createdAt.overlineShortDate)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                InsightShareButton(item: insight.shareText)
            }

            InsightMarkdownText(
                text: insight.body,
                font: .subheadline,
                foregroundStyle: Color.overlineMutedInk,
                lineSpacing: 4
            )

            HStack(spacing: 10) {
                if canShowSources {
                    Button(action: showSources) {
                        Label("\(insight.sourceCount)조각", systemImage: "doc.text")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("근거 글조각 보기")
                } else {
                    Label("\(insight.sourceCount)조각", systemImage: "doc.text")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.overlineMutedInk.opacity(0.82))
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: openDetail)
        .accessibilityAddTraits(.isButton)
        .insightGlassSurface(
            cornerRadius: 16,
            tint: Color.white.opacity(0.11),
            fillOpacity: 0.055,
            strokeOpacity: 0.26,
            shadowOpacity: 0.05,
            shadowRadius: 14
        )
    }
}

private struct InsightShareButton: View {
    let item: String

    var body: some View {
        ShareLink(item: item) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 19, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.overlineMutedInk.opacity(0.46))
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("인사이트 공유")
    }
}

private extension LibraryInsight {
    var shareText: String {
        let parts = [prompt.trimmed, body.trimmed].filter { !$0.isEmpty }
        return parts.isEmpty ? "인사이트" : parts.joined(separator: "\n\n")
    }
}

enum InsightPrompt: String, CaseIterable, Identifiable, Sendable {
    case questions
    case connect
    case expand
    case digest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .questions: "질문"
        case .connect: "연결"
        case .expand: "확장"
        case .digest: "요약"
        }
    }

    var systemImage: String {
        switch self {
        case .questions: "questionmark.bubble"
        case .connect: "point.topleft.down.curvedto.point.bottomright.up"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .digest: "text.badge.checkmark"
        }
    }

    var seedQuestion: String {
        switch self {
        case .questions: "이 문장들이 나에게 던지는 질문은?"
        case .connect: "서로 다른 문장 사이의 공통 패턴은?"
        case .expand: "더 파고들 개념과 반론은?"
        case .digest: "이번 주 저장한 글조각을 한 문단으로 정리해줘"
        }
    }

    var llmInstruction: String {
        switch self {
        case .questions:
            "선택한 글조각들이 독자에게 남기는 핵심 질문을 1-2개로 뽑고, 왜 중요한지 설명하세요."
        case .connect:
            "여러 책이 섞여 있으면 공통 패턴을 교차 책 관점으로 찾고, 한 책 안의 글조각이면 반복되는 테마를 찾아 이름 붙이세요."
        case .expand:
            "글조각에서 더 파고들 개념, 반론, 다음 생각의 방향을 제안하세요."
        case .digest:
            "선택한 글조각을 최근 일주일 독서 흐름처럼 보고, 반복되는 키워드와 연결고리를 한 문단으로 압축하세요."
        }
    }
}

private extension View {
    @ViewBuilder
    func insightGlassSurface(
        cornerRadius: CGFloat,
        tint: Color = Color.white.opacity(0.12),
        interactive: Bool = false,
        fillOpacity: Double = 0.06,
        strokeOpacity: Double = 0.30,
        shadowOpacity: Double = 0.06,
        shadowRadius: CGFloat = 14
    ) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(fillOpacity))
                    }
                    .glassEffect(
                        .regular.tint(tint).interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .insightGlassChrome(
                        cornerRadius: cornerRadius,
                        strokeOpacity: strokeOpacity,
                        shadowOpacity: shadowOpacity,
                        shadowRadius: shadowRadius
                    )
            } else {
                self
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(fillOpacity))
                    }
                    .glassEffect(
                        .regular.tint(tint),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .insightGlassChrome(
                        cornerRadius: cornerRadius,
                        strokeOpacity: strokeOpacity,
                        shadowOpacity: shadowOpacity,
                        shadowRadius: shadowRadius
                    )
            }
        } else {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .insightGlassChrome(
                    cornerRadius: cornerRadius,
                    strokeOpacity: strokeOpacity,
                    shadowOpacity: shadowOpacity,
                    shadowRadius: shadowRadius
                )
        }
    }

    func insightGlassChrome(
        cornerRadius: CGFloat,
        strokeOpacity: Double,
        shadowOpacity: Double,
        shadowRadius: CGFloat
    ) -> some View {
        self
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity * 0.65), lineWidth: 0.6)
                    .blur(radius: 0.2)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: 24)
                    }
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowRadius * 0.42)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? 320
        var rows: [Row] = []
        var currentItems: [RowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = currentItems.isEmpty ? size.width : size.width + spacing

            if currentWidth + itemWidth > maxWidth, !currentItems.isEmpty {
                rows.append(Row(items: currentItems, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(RowItem(subview: subview, size: size))
            currentWidth += currentItems.count == 1 ? size.width : size.width + spacing
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems, height: currentHeight))
        }

        return rows
    }

    private struct Row {
        let items: [RowItem]
        let height: CGFloat
    }

    private struct RowItem {
        let subview: LayoutSubviews.Element
        let size: CGSize
    }
}

#Preview {
    NavigationStack {
        InsightsView()
            .navigationTitle("인사이트")
    }
    .environment(ReadingLibrary.preview)
}
