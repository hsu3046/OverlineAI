import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let insightMetricsLogger = Logger(subsystem: "vote.aib.bzogak", category: "InsightMetrics")

struct InsightsView: View {
    @Environment(ReadingLibrary.self) private var library
    @Environment(AppIntentRouter.self) private var intentRouter
    @Environment(LLMSettingsStore.self) private var llmSettings
    var isActive = true
    @State private var question = ""
    @State private var selectedPrompt: InsightPrompt = .expand
    @State private var selectedBookIDs: Set<ReadingBook.ID> = []
    @State private var selectedHighlightIDs: Set<Highlight.ID> = []
    @State private var isSourcePickerPresented = false
    @State private var isLLMSettingsPresented = false
    @State private var isGeneratingInsight = false
    @State private var insightErrorMessage: String?
    @State private var showsInsightSavedAlert = false
    @State private var presentedDetailInsight: LibraryInsight?
    @State private var presentedSourceInsight: LibraryInsight?
    @State private var savedInsightSearchText = ""
    @State private var pendingDeletedInsight: PendingInsightUndo?
    @State private var undoDismissTask: Task<Void, Never>?

    @ViewBuilder
    var body: some View {
        if isActive {
            activeContent
        } else {
            Color.clear
        }
    }

    private var activeContent: some View {
        let selectedCount = selectedSourceCount
        let visibleSavedInsights = filteredSavedInsights

        return List {
            InsightWorkspaceHeader(
                settings: llmSettings,
                openSettings: { isLLMSettingsPresented = true }
            )
            .insightListRowChrome(top: 16, bottom: 12)

            InsightComposer(
                question: $question,
                selectedPrompt: $selectedPrompt,
                selectedCount: selectedCount,
                canSubmit: selectedCount > 0 && !isGeneratingInsight,
                isSubmitting: isGeneratingInsight,
                errorMessage: insightErrorMessage,
                openPicker: { isSourcePickerPresented = true },
                submit: requestInsightGeneration
            )
            .insightListRowChrome(top: 0, bottom: 16)

            if !library.savedInsights.isEmpty {
                InsightSectionHeader(
                    title: "저장됨",
                    systemImage: "tray.full",
                    trailingText: "\(library.savedInsights.count)"
                )
                .insightListRowChrome(top: 12, bottom: 8)

                OverlinePillSearchField(text: $savedInsightSearchText, prompt: "인사이트, 질문 검색")
                    .insightListRowChrome(top: 0, bottom: 10)

                if visibleSavedInsights.isEmpty && pendingDeletedInsight == nil {
                    ContentUnavailableView(
                        "검색 결과 없음",
                        systemImage: "magnifyingglass",
                        description: Text("다른 질문이나 키워드로 찾아보세요.")
                    )
                    .font(.overline(.caption))
                    .foregroundStyle(Color.overlineMutedInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .insightListRowChrome(top: 0, bottom: 16)
                } else {
                    ForEach(Array(visibleSavedInsights.enumerated()), id: \.element.id) { index, insight in
                        if pendingDeletedInsight?.visibleIndex == index {
                            OverlineInlineUndoRow(message: "인사이트 삭제됨", undo: restoreDeletedInsight)
                                .insightListRowChrome(top: 0, bottom: 12)
                        }

                        SavedInsightCard(
                            insight: insight,
                            searchQuery: savedInsightSearchText,
                            canShowSources: !(insight.sourceHighlightIDs ?? []).isEmpty,
                            openDetail: {
                                presentedDetailInsight = insight
                            },
                            showSources: {
                                presentedSourceInsight = insight
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteInsight(insight.id)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .insightListRowChrome(top: 0, bottom: 12)
                    }

                    if let pendingDeletedInsight, pendingDeletedInsight.visibleIndex >= visibleSavedInsights.count {
                        OverlineInlineUndoRow(message: "인사이트 삭제됨", undo: restoreDeletedInsight)
                            .insightListRowChrome(top: 0, bottom: 12)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .overlineBottomMenuCompaction()
        .onAppear {
            _ = applyInsightSeed(intentRouter.request)
        }
        .onChange(of: intentRouter.request) { _, request in
            clearPendingUndo(animated: false)
            _ = applyInsightSeed(request)
        }
        .onDisappear {
            clearPendingUndo(animated: false)
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
            OverlineSettingsSheet(settings: llmSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedDetailInsight) { insight in
            InsightDetailSheet(
                insight: insight,
                sources: sourceEntries(for: insight),
                delete: {
                    deleteInsight(insight.id)
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

    private func deleteInsight(_ insightID: LibraryInsight.ID) {
        let visibleIndex = filteredSavedInsights.firstIndex { $0.id == insightID } ?? 0

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            if let deletion = library.deleteInsightForUndo(insightID) {
                let pendingUndo = PendingInsightUndo(deletion: deletion, visibleIndex: visibleIndex)
                pendingDeletedInsight = pendingUndo
                scheduleUndoDismiss(for: pendingUndo.id)
            }
        }
    }

    private func restoreDeletedInsight() {
        guard let pendingDeletedInsight else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            library.restoreDeletedInsight(pendingDeletedInsight.deletion)
            clearPendingUndo(animated: false)
        }
    }

    private func scheduleUndoDismiss(for undoID: UUID) {
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard pendingDeletedInsight?.id == undoID else { return }
                clearPendingUndo(animated: true)
            }
        }
    }

    private func clearPendingUndo(animated: Bool) {
        undoDismissTask?.cancel()
        undoDismissTask = nil

        guard pendingDeletedInsight != nil else { return }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                pendingDeletedInsight = nil
            }
        } else {
            pendingDeletedInsight = nil
        }
    }

    private var selectedSourceIDs: [Highlight.ID] {
        effectiveSelectedHighlightIDs(in: library.books)
    }

    private var filteredSavedInsights: [LibraryInsight] {
        let query = savedInsightSearchText.trimmed
        guard !query.isEmpty else { return library.savedInsights }

        return library.savedInsights.filter { insightMatches($0, query: query) }
    }

    private func insightMatches(_ insight: LibraryInsight, query: String) -> Bool {
        let categoryTitle = InsightPrompt(rawValue: insight.categoryRaw)?.title ?? ""
        return insight.prompt.localizedCaseInsensitiveContains(query)
            || insight.body.localizedCaseInsensitiveContains(query)
            || categoryTitle.localizedCaseInsensitiveContains(query)
            || insight.createdAt.overlineShortDate.localizedCaseInsensitiveContains(query)
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
        question = seed.question?.trimmed ?? ""
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

        let prompt = question.trimmed
        let savedPrompt = prompt.isEmpty ? selectedPrompt.title : prompt

        guard llmSettings.isReady(for: llmSettings.provider) else {
            insightErrorMessage = missingCredentialMessage(for: llmSettings.provider)
            isLLMSettingsPresented = true
            return
        }

        let configuration = LLMTagProviderConfiguration(
            provider: llmSettings.provider,
            modelID: llmSettings.selectedModelID,
            credential: llmSettings.credential(for: llmSettings.provider)
        )
        let provider = configuration.provider
        let modelID = configuration.modelID
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
                    credential: configuration.credential,
                    category: selectedPrompt.title,
                    instruction: selectedPrompt.llmInstruction,
                    userPrompt: prompt,
                    sources: payload.sources
                )
            )

            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                library.addInsight(
                    categoryRaw: selectedPrompt.rawValue,
                    prompt: savedPrompt,
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
            llmSettings.handleRequestError(error, configuration: configuration)
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
        if !llmSettings.allowsExternalAIDataSharing {
            return "AI 설정에서 ‘외부 AI 사용’을 켜 주세요."
        }

        if llmSettings.isCredentialRejected(for: provider) {
            return "\(provider.title) 인증 또는 현재 모델 접근이 거부되었습니다. AI 설정에서 다시 연결하거나 모델을 확인해 주세요."
        }

        return "\(provider.title) API 키를 먼저 입력해 주세요."
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

private extension View {
    func insightListRowChrome(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    func settingsRowSeparator() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
    }
}

private struct PendingInsightUndo: Identifiable {
    let deletion: DeletedInsightSnapshot
    let visibleIndex: Int

    var id: UUID {
        deletion.id
    }
}

private struct InsightWorkspaceHeader: View {
    let settings: LLMSettingsStore
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.overline(.subheadline, weight: .semibold))
                .foregroundStyle(Color.overlineAccent)
            Text("생각 정리하기")
                .font(.overline(.headline))
                .foregroundStyle(Color.overlineInk)

            Spacer()

            OverlineSettingsButton(settings: settings, action: openSettings)
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
                .font(.overline(.subheadline, weight: .semibold))
                .foregroundStyle(Color.overlineAccent)
            Text(title)
                .font(.overline(.headline))
                .foregroundStyle(Color.overlineInk)
            if let trailingText {
                Text(trailingText)
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
            }
            Spacer()
        }
    }
}

enum OverlineSettingsDestination: Hashable {
    case textSpeech
}

private enum LLMModelPickerSelection: Hashable {
    case preset(String)
    case custom
}

struct OverlineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer
    let settings: LLMSettingsStore
    private let presentsTextSpeechDirectly: Bool
    @State private var navigationPath: [OverlineSettingsDestination]
    @State private var isTestingConnection = false
    @State private var connectionTestResult: LLMConnectionTestResult?
    @State private var showsResetConfirmation = false
    @State private var showsRestoreResetConfirmation = false
    @State private var backupDocument: LibraryBackupDocument?
    @State private var backupFilename = ""
    @State private var isBackupExporterPresented = false
    @State private var isBackupImporterPresented = false
    @State private var pendingBackupImport: DecodedLibraryBackup?
    @State private var showsBackupImportConfirmation = false
    @State private var backupNotice: LibraryBackupNotice?
    @State private var customModelProviders: Set<LLMProvider> = []
    @State private var customModelDrafts: [LLMProvider: String] = [:]

    init(
        settings: LLMSettingsStore,
        initialDestination: OverlineSettingsDestination? = nil
    ) {
        self.settings = settings
        presentsTextSpeechDirectly = initialDestination == .textSpeech
        _navigationPath = State(initialValue: initialDestination.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                Section {
                    LLMActiveModelSummary(settings: settings)
                        .settingsRowSeparator()
                } header: {
                    Text("현재 사용 중인 AI")
                }

                Section {
                    Toggle("외부 AI 사용", isOn: aiDataSharingBinding)
                        .tint(Color.overlineAccent)
                        .settingsRowSeparator()

                    Picker("제공자", selection: providerBinding) {
                        ForEach(LLMProvider.settingsOrder) { provider in
                            HStack(spacing: 10) {
                                LLMProviderIcon(provider: provider)
                                Text(provider.title)
                            }
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .settingsRowSeparator()

                    Picker("모델 선택", selection: modelPickerBinding) {
                        ForEach(settings.provider.modelOptions) { model in
                            Text(model.title)
                                .tag(LLMModelPickerSelection.preset(model.id))
                        }

                        Text("직접 입력")
                            .tag(LLMModelPickerSelection.custom)
                    }
                    .pickerStyle(.navigationLink)
                    .settingsRowSeparator()

                    if isEnteringCustomModelID {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("모델 ID") {
                                TextField(settings.provider.defaultModelID, text: customModelIDBinding)
                                    .multilineTextAlignment(.trailing)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.overline(.body))
                                    .foregroundStyle(.secondary)
                            }

                            Text("입력한 모델 ID를 목록에서 선택한 모델 대신 사용합니다.")
                                .font(.overline(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .settingsRowSeparator()
                    }

                    LLMAPIKeyRow(
                        provider: settings.provider,
                        apiKey: Binding(
                            get: { settings.apiKey(for: settings.provider) },
                            set: {
                                settings.setAPIKey($0, for: settings.provider)
                                connectionTestResult = nil
                            }
                        )
                    )
                    .id(settings.provider)
                    .settingsRowSeparator()

                    Button {
                        Task {
                            await testConnection()
                        }
                    } label: {
                        HStack {
                            Label(connectionTestTitle, systemImage: connectionTestSystemImage)
                            Spacer()

                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(
                        isTestingConnection
                            || !settings.allowsExternalAIDataSharing
                            || !settings.hasCredential(for: settings.provider)
                            || !hasUsableModelID
                    )
                    .listRowSeparator(.hidden, edges: .bottom)
                    .settingsRowSeparator()

                    if let connectionTestResult, !connectionTestResult.isSuccess {
                        Label(connectionTestResult.message, systemImage: "exclamationmark.circle")
                            .font(.overline(.caption))
                            .foregroundStyle(Color.overlineCoral)
                            .settingsRowSeparator()
                    }
                } header: {
                    Text("외부 AI 설정")
                }

                Section("텍스트 낭독") {
                    NavigationLink(value: OverlineSettingsDestination.textSpeech) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("음성 선택")
                                Text(quoteSpeechPlayer.selectedVoiceName(for: .korean))
                                    .font(.overline(.caption))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "speaker.wave.2")
                        }
                    }
                    .settingsRowSeparator()
                }

                Section {
                    Button {
                        prepareBackupExport()
                    } label: {
                        Label("백업 파일 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .disabled(library.books.isEmpty && library.savedInsights.isEmpty)
                    .settingsRowSeparator()

                    Button {
                        isBackupImporterPresented = true
                    } label: {
                        Label("백업 파일 가져오기", systemImage: "square.and.arrow.down")
                    }
                    .settingsRowSeparator()

                    Button {
                        showsRestoreResetConfirmation = true
                    } label: {
                        HStack {
                            Label("최근 초기화 복구", systemImage: "arrow.uturn.backward.circle")
                            Spacer()
                            if !library.resetBackupAvailable {
                                Text("복구 없음")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!library.resetBackupAvailable)
                    .settingsRowSeparator()

                    Button(role: .destructive) {
                        showsResetConfirmation = true
                    } label: {
                        Label("보관함 초기화", systemImage: "trash")
                    }
                    .settingsRowSeparator()
                } header: {
                    Text("보관함")
                } footer: {
                    Text("API 키와 앱 설정은 포함하지 않습니다.")
                        .font(.overline(.caption2))
                        .foregroundStyle(.secondary)
                }

                Section("개인 정보와 이용 조건") {
                    NavigationLink {
                        PrivacyTransmissionPolicyView(settings: settings)
                    } label: {
                        Label("개인정보 처리방침", systemImage: "lock.shield")
                    }
                    .settingsRowSeparator()

                    NavigationLink {
                        OverlineTermsView()
                    } label: {
                        Label("이용 조건", systemImage: "doc.text")
                    }
                    .settingsRowSeparator()

                    NavigationLink {
                        OpenSourceLicensesView()
                    } label: {
                        Label("오픈소스 라이선스", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .settingsRowSeparator()
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: OverlineSettingsDestination.self) { destination in
                switch destination {
                case .textSpeech:
                    QuoteSpeechSettingsView(
                        player: quoteSpeechPlayer,
                        onDone: presentsTextSpeechDirectly ? { dismiss() } : nil
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    OverlineDoneToolbarButton {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("보관함을 초기화할까요?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
                Button("모든 책, 글조각, 인사이트 삭제", role: .destructive) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        library.resetLibrary()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제 전 최근 상태를 이 기기에 복구 백업으로 남깁니다. 이후 설정의 최근 초기화 복구에서 되돌릴 수 있습니다.")
            }
            .confirmationDialog("최근 초기화를 복구할까요?", isPresented: $showsRestoreResetConfirmation, titleVisibility: .visible) {
                Button("복구") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        _ = library.restoreLastResetBackup()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("초기화 직전의 책, 글조각, 인사이트를 이 기기 안의 복구 백업에서 되돌립니다.")
            }
            .confirmationDialog(
                "이 백업으로 보관함을 바꿀까요?",
                isPresented: $showsBackupImportConfirmation,
                titleVisibility: .visible,
                presenting: pendingBackupImport
            ) { backup in
                Button("백업 가져오기") {
                    importBackup(backup)
                }
                Button("취소", role: .cancel) {
                    pendingBackupImport = nil
                }
            } message: { backup in
                Text(backupImportMessage(for: backup))
            }
            .fileExporter(
                isPresented: $isBackupExporterPresented,
                document: backupDocument,
                contentType: .bzogakBackup,
                defaultFilename: backupFilename
            ) { result in
                backupDocument = nil
                switch result {
                case .success:
                    backupNotice = LibraryBackupNotice(
                        title: "백업 파일을 내보냈습니다",
                        message: "선택한 위치에 독서 기록을 저장했습니다."
                    )
                case let .failure(error):
                    presentBackupError(error, title: "백업 파일을 내보내지 못했습니다")
                }
            }
            .fileImporter(
                isPresented: $isBackupImporterPresented,
                allowedContentTypes: [.bzogakBackup],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    loadBackup(from: url)
                case let .failure(error):
                    presentBackupError(error, title: "백업 파일을 열지 못했습니다")
                }
            }
            .alert(item: $backupNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("확인"))
                )
            }
            .overlineKeyboardDismissToolbar()
        }
    }

    private func prepareBackupExport() {
        let exportedAt = Date()
        do {
            backupDocument = LibraryBackupDocument(data: try library.makeBackupData(exportedAt: exportedAt))
            backupFilename = backupFilename(for: exportedAt)
            isBackupExporterPresented = true
        } catch {
            presentBackupError(error, title: "백업 파일을 만들지 못했습니다")
        }
    }

    private func loadBackup(from url: URL) {
        Task {
            do {
                let backup = try await Task.detached(priority: .userInitiated) {
                    try LibraryBackupCodec.decode(contentsOf: url)
                }.value
                pendingBackupImport = backup
                showsBackupImportConfirmation = true
            } catch is CancellationError {
                return
            } catch {
                presentBackupError(error, title: "백업 파일을 열지 못했습니다")
            }
        }
    }

    private func importBackup(_ backup: DecodedLibraryBackup) {
        let hadExistingLibrary = !library.books.isEmpty || !library.savedInsights.isEmpty
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            library.replaceLibrary(with: backup.snapshot)
        }
        pendingBackupImport = nil

        let recoveryMessage = hadExistingLibrary
            ? " 가져오기 전 상태는 ‘최근 초기화 복구’에서 되돌릴 수 있습니다."
            : ""
        backupNotice = LibraryBackupNotice(
            title: "보관함을 가져왔습니다",
            message: "\(backup.summary.description)\(recoveryMessage)"
        )
    }

    private func backupImportMessage(for backup: DecodedLibraryBackup) -> String {
        let recoveryMessage = library.books.isEmpty && library.savedInsights.isEmpty
            ? ""
            : "\n현재 보관함은 최근 초기화 복구에 보관됩니다."
        return "\(backup.summary.description)\(recoveryMessage)"
    }

    private func backupFilename(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "글조각서랍-%04d-%02d-%02d", year, month, day)
    }

    private func presentBackupError(_ error: Error, title: String) {
        let nsError = error as NSError
        guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else { return }

        backupNotice = LibraryBackupNotice(
            title: title,
            message: error.localizedDescription
        )
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { settings.provider },
            set: {
                settings.provider = $0
                connectionTestResult = nil
            }
        )
    }

    private var modelPickerBinding: Binding<LLMModelPickerSelection> {
        Binding(
            get: {
                if isEnteringCustomModelID {
                    return .custom
                }
                return .preset(settings.selectedModelID)
            },
            set: { selection in
                switch selection {
                case let .preset(modelID):
                    customModelProviders.remove(settings.provider)
                    settings.setSelectedModelID(modelID)
                case .custom:
                    let provider = settings.provider
                    customModelProviders.insert(provider)
                    if customModelDrafts[provider] == nil {
                        customModelDrafts[provider] = selectedModelIsPreset
                            ? ""
                            : settings.selectedModelID
                    }
                }
                connectionTestResult = nil
            }
        )
    }

    private var customModelIDBinding: Binding<String> {
        Binding(
            get: {
                let provider = settings.provider
                if let draft = customModelDrafts[provider] {
                    return draft
                }
                return selectedModelIsPreset ? "" : settings.selectedModelID
            },
            set: { modelID in
                let provider = settings.provider
                customModelDrafts[provider] = modelID
                if !modelID.trimmed.isEmpty {
                    settings.setSelectedModelID(modelID)
                }
                connectionTestResult = nil
            }
        )
    }

    private var aiDataSharingBinding: Binding<Bool> {
        Binding(
            get: { settings.allowsExternalAIDataSharing },
            set: {
                settings.setAllowsExternalAIDataSharing($0)
                connectionTestResult = nil
            }
        )
    }

    private var selectedModelIsPreset: Bool {
        settings.provider.modelOptions.contains { $0.id == settings.selectedModelID }
    }

    private var isEnteringCustomModelID: Bool {
        customModelProviders.contains(settings.provider) || !selectedModelIsPreset
    }

    private var hasUsableModelID: Bool {
        !isEnteringCustomModelID || !customModelIDBinding.wrappedValue.trimmed.isEmpty
    }

    private var connectionTestTitle: String {
        if isTestingConnection {
            return "AI 연결 테스트 중"
        }
        if connectionTestResult?.isSuccess == true {
            return "AI 연결 테스트 완료"
        }
        return "AI 연결 테스트"
    }

    private var connectionTestSystemImage: String {
        connectionTestResult?.isSuccess == true ? "checkmark.circle.fill" : "checkmark.circle"
    }

    @MainActor
    private func testConnection() async {
        guard !isTestingConnection else { return }
        guard settings.allowsExternalAIDataSharing else { return }
        guard settings.hasCredential(for: settings.provider) else { return }
        guard hasUsableModelID else { return }

        let provider = settings.provider
        let modelID = settings.selectedModelID
        let configuration = LLMTagProviderConfiguration(
            provider: provider,
            modelID: modelID,
            credential: settings.credential(for: provider)
        )
        let startedAt = Date()

        isTestingConnection = true
        connectionTestResult = nil
        insightMetricsLogger.info(
            "llm_connection_test_requested provider=\(provider.rawValue, privacy: .public)"
        )

        do {
            _ = try await LLMInsightClient().generateInsight(
                LLMInsightRequest(
                    provider: provider,
                    modelID: modelID,
                    credential: configuration.credential,
                    category: "연결 테스트",
                    instruction: "연결이 정상인지 확인하기 위해 한 문장으로만 답하세요.",
                    userPrompt: "BZOGAK AI 연결 테스트입니다. 정상이라면 짧게 확인했다고 답하세요.",
                    sources: [
                        LLMInsightSource(
                            bookTitle: "BZOGAK Test",
                            bookAuthor: "BZOGAK",
                            bookSummary: "독자가 책 속 글조각을 저장하고, 선택한 문장을 바탕으로 생각을 정리하는 테스트용 책입니다.",
                            text: "독서 메모를 안전하게 정리한다.",
                            memo: "연결 확인용 테스트 문장"
                        )
                    ]
                )
            )

            guard isCurrentConnectionTest(configuration) else {
                isTestingConnection = false
                return
            }

            settings.handleRequestSuccess(configuration: configuration)
            connectionTestResult = LLMConnectionTestResult(
                isSuccess: true,
                message: "AI 연결 테스트 완료"
            )
            MVPReadinessStore.markVerified(
                .llmInsight,
                detail: "\(provider.title) · \(modelID) 연결 테스트"
            )
            insightMetricsLogger.info(
                "llm_connection_test_completed provider=\(provider.rawValue, privacy: .public) duration_ms=\(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()), privacy: .public)"
            )
        } catch {
            guard isCurrentConnectionTest(configuration) else {
                isTestingConnection = false
                return
            }

            settings.handleRequestError(error, configuration: configuration)
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

    private func isCurrentConnectionTest(_ configuration: LLMTagProviderConfiguration) -> Bool {
        settings.provider == configuration.provider
            && settings.selectedModelID == configuration.modelID
            && settings.credential(for: configuration.provider) == configuration.credential
    }
}

private struct LibraryBackupNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct QuoteSpeechSettingsView: View {
    let player: QuoteSpeechPlayer
    let onDone: (() -> Void)?
    @State private var showsDownloadConfirmation = false
    @State private var showsRemovalConfirmation = false

    init(player: QuoteSpeechPlayer, onDone: (() -> Void)? = nil) {
        self.player = player
        self.onDone = onDone
    }

    var body: some View {
        Form {
            Section("한국어") {
                SpeechEnginePicker(selection: engineBinding)
                    .listRowSeparator(.hidden, edges: .bottom)

                if player.speechEngineChoice == .supertonic {
                    supertonicPrimarySettings
                } else {
                    systemVoiceSettings(for: .korean)
                }

                SpeechPlaybackControls(
                    rateMultiplier: speechRateBinding,
                    sentencePause: sentencePauseBinding
                )
                .listRowSeparator(.hidden)

                if player.speechEngineChoice == .supertonic {
                    supertonicInstalledSettings
                }
            }

            ForEach([CaptureLanguage.english, .japanese]) { language in
                Section(language.title) {
                    systemVoiceSettings(for: language)
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("고품질 음성은 iPhone 설정 → 손쉬운 사용 → 읽기 및 말하기 → 음성 → 한국어 → 음성에서 다운로드할 수 있습니다.")
            }
        }
        .navigationTitle("텍스트 낭독")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .topBarTrailing) {
                    OverlineDoneToolbarButton(action: onDone)
                }
            }
        }
        .confirmationDialog(
            "고품질 음성 팩을 받을까요?",
            isPresented: $showsDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("받기 · \(SupertonicAssetStore.downloadSizeDescription)") {
                player.setSpeechEngineChoice(.supertonic)
                Task {
                    await player.installSupertonicPack()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("한 번 받으면 인터넷 없이 사용할 수 있습니다.")
        }
        .confirmationDialog(
            "고품질 음성 팩을 삭제할까요?",
            isPresented: $showsRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("음성 팩 삭제", role: .destructive) {
                Task {
                    await player.removeSupertonicPack()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("필요할 때 다시 받을 수 있습니다.")
        }
        .alert(
            "음성 팩을 준비하지 못했습니다",
            isPresented: Binding(
                get: { player.speechErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { player.clearSpeechError() }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                player.clearSpeechError()
            }
        } message: {
            Text(player.speechErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
        .onAppear {
            player.logVoiceCatalog()
        }
        .onDisappear {
            player.stop()
        }
    }

    @ViewBuilder
    private var supertonicPrimarySettings: some View {
        switch player.supertonicAssetState {
        case .unavailable:
            Button {
                showsDownloadConfirmation = true
            } label: {
                LabeledContent {
                    Text(SupertonicAssetStore.downloadSizeDescription)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("고품질 음성 받기", systemImage: "arrow.down.circle")
                }
            }
            .listRowSeparator(.hidden)

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("고품질 음성 받는 중") {
                    Text("\(Int((progress * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .tint(Color.overlineAccent)
            }
            .listRowSeparator(.hidden)

        case .installed:
            NavigationLink {
                SupertonicVoiceSelectionView(player: player)
            } label: {
                LabeledContent("음성") {
                    Text(player.selectedSupertonicVoice.pickerTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowSeparator(.hidden)

        case .failed(let message):
            Text(message)
                .font(.overline(.footnote))
                .foregroundStyle(.red)
                .listRowSeparator(.hidden)

            Button {
                showsDownloadConfirmation = true
            } label: {
                Label("다시 받기", systemImage: "arrow.clockwise")
            }
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var supertonicInstalledSettings: some View {
        if player.supertonicAssetState.isInstalled {
            VStack(alignment: .leading, spacing: 12) {
                Text("음질")
                    .font(.overline(.body, weight: .medium))

                ForEach(SupertonicQuality.allCases) { quality in
                    Button {
                        player.setSupertonicQuality(quality)
                    } label: {
                        HStack {
                            Text(quality.title)
                                .foregroundStyle(Color.primary)

                            Spacer()

                            Image(systemName: player.supertonicQuality == quality ? "circle.inset.filled" : "circle")
                                .foregroundStyle(
                                    player.supertonicQuality == quality
                                        ? Color.overlineAccent
                                        : Color.overlineMutedInk
                                )
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .padding(.leading, 16)
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        player.supertonicQuality == quality ? .isSelected : []
                    )
                }
            }
            .listRowSeparator(.hidden)

            Button(role: .destructive) {
                showsRemovalConfirmation = true
            } label: {
                Label("고품질 음성 팩 삭제", systemImage: "trash")
            }
            .listRowSeparator(.visible, edges: .top)
            .settingsRowSeparator()
        }
    }

    @ViewBuilder
    private func systemVoiceSettings(for language: CaptureLanguage) -> some View {
        NavigationLink {
            SystemVoiceSelectionView(player: player, language: language)
        } label: {
            LabeledContent("음성") {
                Text(selectedSystemVoiceTitle(for: language))
                    .foregroundStyle(.secondary)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func selectedSystemVoiceTitle(for language: CaptureLanguage) -> String {
        let identifier = player.selectedVoiceIdentifier(for: language)
        return player.voiceOptions(for: language)
            .first(where: { $0.id == identifier })?
            .pickerTitle ?? player.selectedVoiceName(for: language)
    }

    private var engineBinding: Binding<SpeechEngineChoice> {
        Binding(
            get: { player.speechEngineChoice },
            set: { choice in
                if choice == .supertonic, !player.supertonicAssetState.isInstalled {
                    showsDownloadConfirmation = true
                } else {
                    player.setSpeechEngineChoice(choice)
                }
            }
        )
    }

    private var speechRateBinding: Binding<Double> {
        Binding(
            get: { player.speechRateMultiplier },
            set: { player.setSpeechRateMultiplier($0) }
        )
    }

    private var sentencePauseBinding: Binding<Double> {
        Binding(
            get: { player.sentencePause },
            set: { player.setSentencePause($0) }
        )
    }

}

private struct SpeechEnginePicker: View {
    @Binding var selection: SpeechEngineChoice

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpeechEngineChoice.allCases) { engine in
                Button {
                    selection = engine
                } label: {
                    Text(engine.title)
                        .font(.overline(.body, weight: .medium))
                        .foregroundStyle(
                            selection == engine ? Color.overlineInk : Color.overlineMutedInk
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if selection == engine {
                                Capsule(style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == engine ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemFill), in: Capsule(style: .continuous))
    }
}

private struct SupertonicVoiceSelectionView: View {
    let player: QuoteSpeechPlayer

    var body: some View {
        List(SupertonicVoicePreset.allCases) { voice in
            VoiceSelectionRow(
                title: voice.pickerTitle,
                isSelected: player.selectedSupertonicVoice == voice,
                isPreviewing: player.isPreviewing(voice),
                select: { player.setSelectedSupertonicVoice(voice) },
                togglePreview: { player.togglePreview(voice) }
            )
        }
        .navigationTitle("음성")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player.stop()
        }
    }
}

private struct SystemVoiceSelectionView: View {
    let player: QuoteSpeechPlayer
    let language: CaptureLanguage

    var body: some View {
        List(player.voiceOptions(for: language)) { option in
            VoiceSelectionRow(
                title: option.pickerTitle,
                isSelected: player.selectedVoiceIdentifier(for: language) == option.id,
                isPreviewing: player.isPreviewing(option, for: language),
                select: { player.setSelectedVoiceIdentifier(option.id, for: language) },
                togglePreview: { player.togglePreview(option, for: language) }
            )
        }
        .navigationTitle("음성")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player.stop()
        }
    }
}

private struct VoiceSelectionRow: View {
    let title: String
    let isSelected: Bool
    let isPreviewing: Bool
    let select: () -> Void
    let togglePreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Text(title)
                        .foregroundStyle(isSelected ? Color.overlineAccent : .primary)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.overline(.caption, weight: .semibold))
                            .foregroundStyle(Color.overlineAccent)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: togglePreview) {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.overline(.body, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPreviewing ? "미리 듣기 중지" : "\(title) 미리 듣기")
        }
        .accessibilityElement(children: .contain)
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
        case .unsafeCorrection:
            return "unsafe_correction"
        case .requestFailed(let statusCode, _):
            return "request_failed_\(statusCode)"
        }
    }
}

private struct PrivacyTransmissionPolicyView: View {
    let settings: LLMSettingsStore

    private let policies: [PrivacyTransmissionPolicy] = [
        PrivacyTransmissionPolicy(
            systemImage: "iphone",
            title: "기기 내 저장",
            body: "책, 글조각, 메모와 인사이트는 이 기기에 저장됩니다. 캡처 사진은 OCR이 끝나면 삭제됩니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "key",
            title: "인증 정보 보호",
            body: "API 키는 이 기기의 iOS Keychain에 저장됩니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "sparkles",
            title: "AI로 전송되는 정보",
            body: "인사이트, 감상문 초안, 자동 태그, OCR 교정 등 AI 기능에 필요한 글조각, 메모와 책 정보가 선택한 AI 제공자로 전송됩니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "nosign",
            title: "글조각 서랍의 처리",
            body: "AI 요청은 선택한 제공자에게 직접 전송됩니다. 글조각 서랍은 이 내용을 별도로 저장하거나 학습에 사용하지 않습니다. 제공자에서 처리되는 방식은 해당 서비스의 정책을 따릅니다."
        ),
        PrivacyTransmissionPolicy(
            systemImage: "location",
            title: "주변 장소와 검색",
            body: "주변 장소를 찾을 때 현재 위치를, 관련 글을 찾을 때 검색어를 커뮤니티 서버와 검색 제공자에게 보냅니다. 결과를 돌려준 뒤 커뮤니티 서버에는 내용을 저장하지 않습니다."
        )
    ]

    var body: some View {
        List {
            Section {
                Toggle("외부 AI 사용", isOn: aiDataSharingBinding)
                    .tint(Color.overlineAccent)
            } footer: {
                Text("켜면 AI 기능에 필요한 글조각, 메모와 책 정보가 \(settings.provider.title)에 전송됩니다. 끄면 AI 요청이 전송되지 않습니다.")
            }

            Section {
                ForEach(policies) { policy in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: policy.systemImage)
                            .font(.overline(.body, weight: .semibold))
                            .foregroundStyle(Color.overlineAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(policy.title)
                                .font(.overline(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.overlineInk)

                            Text(policy.body)
                                .font(.overline(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                    .settingsRowSeparator()
                }
            }

            if let privacyPolicyURL = OverlineAPIConfiguration.privacyPolicyURL {
                Section {
                    Link(destination: privacyPolicyURL) {
                        Label("웹에서 개인정보 처리방침 보기", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("개인정보 처리방침")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var aiDataSharingBinding: Binding<Bool> {
        Binding(
            get: { settings.allowsExternalAIDataSharing },
            set: { settings.setAllowsExternalAIDataSharing($0) }
        )
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
            title: "개인 독서 기록",
            body: "책, 글조각, 메모와 인사이트는 이 기기에 저장됩니다. 캡처 사진은 OCR이 끝나면 삭제됩니다."
        ),
        OverlineTerm(
            systemImage: "sparkles",
            title: "AI 기능 사용",
            body: "인사이트, 감상문 초안, 자동 태그, OCR 교정 등 AI 기능을 사용할 때 필요한 정보가 선택한 AI 제공자로 전송됩니다."
        ),
        OverlineTerm(
            systemImage: "square.and.arrow.up",
            title: "공유 전 확인",
            body: "책의 원문을 공유할 때에는 저작권과 인용 범위를 확인해 주세요."
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(terms) { term in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: term.systemImage)
                            .font(.overline(.body, weight: .semibold))
                            .foregroundStyle(Color.overlineAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(term.title)
                                .font(.overline(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.overlineInk)

                            Text(term.body)
                                .font(.overline(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                    .settingsRowSeparator()
                }
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

private struct OpenSourceLicensesView: View {
    private let notices: [OpenSourceLicenseNotice] = [
        OpenSourceLicenseNotice(
            name: "Pretendard Variable",
            detail: "SIL Open Font License 1.1",
            resourceName: "Pretendard-OFL"
        ),
        OpenSourceLicenseNotice(
            name: "Supertonic",
            detail: "MIT License",
            resourceName: "Supertonic-MIT"
        ),
        OpenSourceLicenseNotice(
            name: "ONNX Runtime",
            detail: "MIT License",
            resourceName: "ONNXRuntime-MIT"
        )
    ]

    var body: some View {
        List {
            Section {
                ForEach(notices) { notice in
                    NavigationLink {
                        OpenSourceLicenseTextView(notice: notice)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(notice.name)
                                .font(.overline(.subheadline, weight: .semibold))
                            Text(notice.detail)
                                .font(.overline(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsRowSeparator()
                }
            }

            Section {
                if let modelURL = URL(string: "https://huggingface.co/Supertone/supertonic-3") {
                    Link(destination: modelURL) {
                        Label("Supertonic 3 · OpenRAIL-M", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("다운로드 음성 모델")
            } footer: {
                Text("고품질 음성 모델과 라이선스는 사용자가 음성 팩을 받을 때 함께 저장됩니다.")
            }
        }
        .navigationTitle("오픈소스 라이선스")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OpenSourceLicenseTextView: View {
    let notice: OpenSourceLicenseNotice

    var body: some View {
        ScrollView {
            Text(notice.licenseText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(notice.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OpenSourceLicenseNotice: Identifiable {
    let name: String
    let detail: String
    let resourceName: String

    var id: String { resourceName }

    var licenseText: String {
        let candidateURLs = [
            Bundle.main.url(forResource: resourceName, withExtension: "txt"),
            Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Resources/Licenses"),
            Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Resources/Fonts")
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        return "라이선스 내용을 불러올 수 없습니다."
    }
}

private struct LLMAPIKeyRow: View {
    let provider: LLMProvider
    @Binding var apiKey: String

    var body: some View {
        HStack(spacing: 10) {
            LLMProviderIcon(provider: provider)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(provider.title) API 키")
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk)

                SecureField(provider.keyPlaceholder, text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.overline(.subheadline))
                    .privacySensitive()
            }
        }
    }
}

private struct LLMActiveModelSummary: View {
    let settings: LLMSettingsStore

    var body: some View {
        HStack(spacing: 10) {
            LLMProviderIcon(provider: settings.provider)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(settings.provider.title)
                        .font(.overline(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.overlineInk)

                    Text(settings.selectedModelTitle)
                        .font(.overline(.caption))
                        .foregroundStyle(Color.overlineMutedInk)
                        .lineLimit(1)
                }

                Text(settings.allowsExternalAIDataSharing ? "API 키 사용" : "AI 기능 꺼짐")
                    .font(.overline(.caption2, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.74))
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LLMProviderIcon: View {
    let provider: LLMProvider
    var size: CGFloat = 20

    var body: some View {
        Image(provider.assetName)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
                    .font(.overline(.body))
                    .lineLimit(7...10)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)

                HStack {
                    Button(action: openPicker) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            if selectedCount > 0 {
                                Text("\(selectedCount)")
                                    .font(.overline(.caption2, weight: .bold))
                                    .foregroundStyle(Color.overlineMutedInk)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minWidth: 17, minHeight: 17)
                            }
                        }
                        .font(.overline(.body, weight: .semibold))
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
                        .font(.overline(.caption, weight: .semibold))
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
                                        searchQuery: searchText,
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
        .overlineKeyboardDismissToolbar()
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
                        .font(.overline(.subheadline, weight: .semibold))
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
                .font(.overline(.subheadline, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.72))

            TextField(prompt, text: $text)
                .font(.overline(.subheadline))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.overline(.subheadline, weight: .semibold))
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
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.overlineInk.opacity(0.11), lineWidth: 1)
        }
    }
}

private struct BookPickerRow: View {
    let book: ReadingBook
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.overline(.title3, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.55))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.overline(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(2)

                if !book.author.trimmed.isEmpty {
                    Text(book.author)
                        .font(.overline(.caption, weight: .medium))
                        .foregroundStyle(Color.overlineMutedInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text("\(book.highlights.count)조각")
                .font(.overline(.caption, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct HighlightPickerRow: View {
    let highlight: Highlight
    let searchQuery: String
    let isSelected: Bool
    let isIncludedByBook: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.overline(.title3, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.55))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                SearchHighlightedText(
                    text: highlight.text,
                    query: searchQuery,
                    font: .overline(.subheadline, weight: .medium),
                    foregroundStyle: Color.overlineInk,
                    lineSpacing: 3,
                    lineLimit: 3
                )

                HStack(spacing: 8) {
                    Text(highlight.pageReference)
                    ForEach(highlight.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                    }
                    if isIncludedByBook {
                        Text("책으로 포함됨")
                    }
                }
                .font(.overline(.caption2, weight: .semibold))
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
                .font(.overline(.callout, weight: .semibold))
                .frame(width: 16)
            Text(prompt.title)
                .font(.overline(.caption, weight: .bold))
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
            .font(.overline(.subheadline, weight: .semibold))
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
                    .font(.overline(.caption, weight: .bold))
                Text(source.bookTitle)
                Text(source.highlight.pageReference)
            }
            .font(.overline(.caption2, weight: .semibold))
            .foregroundStyle(Color.overlineMutedInk.opacity(0.78))

            Text(source.highlight.text)
                .font(.overline(.subheadline, weight: .medium))
                .foregroundStyle(Color.overlineInk)
                .lineSpacing(4)
                .lineLimit(5)

            if !source.highlight.memo.isEmpty {
                Text(source.highlight.memo)
                    .font(.overline(.caption))
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
    var searchQuery = ""
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
            Text(highlighted(attributed))
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            SearchHighlightedText(
                text: value,
                query: searchQuery,
                font: font,
                foregroundStyle: foregroundStyle,
                lineSpacing: lineSpacing
            )
        }
    }

    private func highlighted(_ value: AttributedString) -> AttributedString {
        var result = value
        result.overlineApplySearchHighlight(query: searchQuery)
        return result
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
                                    .font(.overline(.title3, weight: .bold))
                                    .foregroundStyle(Color.overlineInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(insight.createdAt.overlineShortDate)
                                    .font(.overline(.caption, weight: .semibold))
                                    .foregroundStyle(Color.overlineMutedInk.opacity(0.78))
                            }
                        }

                        InsightMarkdownText(
                            text: insight.body,
                            font: .overline(.body),
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
    let searchQuery: String
    let canShowSources: Bool
    let openDetail: () -> Void
    let showSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                InsightCategoryIcon(prompt: InsightPrompt(rawValue: insight.categoryRaw) ?? .connect)

                VStack(alignment: .leading, spacing: 4) {
                    SearchHighlightedText(
                        text: insight.prompt,
                        query: searchQuery,
                        font: .overline(.headline, weight: .semibold),
                        foregroundStyle: Color.overlineInk,
                        lineLimit: 2
                    )

                    Text(insight.createdAt.overlineShortDate)
                        .font(.overline(.caption, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                InsightShareButton(item: insight.shareText)
            }

            InsightMarkdownText(
                text: insight.body,
                searchQuery: searchQuery,
                font: .overline(.subheadline),
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
            .font(.overline(.caption2, weight: .semibold))
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
    .environment(AppIntentRouter.shared)
    .environment(LLMSettingsStore())
}
