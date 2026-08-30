import SwiftUI
import UIKit

struct ReadingRecordSection: View {
    let book: ReadingBook
    let addRecord: () -> Void
    let editRecord: (ReadingRecord.ID) -> Void
    let showHistory: () -> Void

    private var records: [ReadingRecord] {
        book.readingRecords.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "book.pages")
                    .font(.overline(.headline, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)

                Text("독서 기록")
                    .font(.overline(.headline, weight: .bold))
                    .foregroundStyle(Color.overlineInk)

                if !records.isEmpty {
                    Text("\(records.count)")
                        .font(.overline(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                }

                Spacer(minLength: 0)

                if records.count > 1 {
                    Button("전체 보기", action: showHistory)
                        .font(.overline(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.overlineAccent)
                        .buttonStyle(.plain)
                }

                if !records.isEmpty {
                    Button(action: addRecord) {
                        Image(systemName: "plus")
                            .font(.overline(.body, weight: .semibold))
                            .foregroundStyle(Color.overlineAccent)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("독서 기록 추가")
                }
            }

            if let latestRecord = records.first {
                Button {
                    editRecord(latestRecord.id)
                } label: {
                    ReadingRecordSummary(record: latestRecord)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("최근 독서 기록 편집")
            } else {
                Button(action: addRecord) {
                    HStack(spacing: 8) {
                        Text("첫 독서 기록 남기기")
                            .font(.overline(.subheadline, weight: .medium))
                            .foregroundStyle(Color.overlineMutedInk)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.overline(.caption, weight: .bold))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.52))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineInk.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ReadingRecordSummary: View {
    let record: ReadingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: record.status.systemImage)
                    Text(record.status.title)
                }
                    .foregroundStyle(Color.overlineAccent)

                Text(readingDateRangeText(for: record))
                    .foregroundStyle(Color.overlineMutedInk)

                Spacer(minLength: 0)

                if let rating = record.rating {
                    ReadingRatingStars(rating: rating, size: 12)
                }
            }
            .font(.overline(.caption, weight: .semibold))

            if !record.review.trimmed.isEmpty {
                Text(record.review)
                    .font(.overline(.subheadline, weight: .medium))
                    .foregroundStyle(Color.overlineInk.opacity(0.82))
                    .lineLimit(4)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ReadingRecordHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library

    let bookID: ReadingBook.ID
    @State private var editorTarget: ReadingRecordEditorTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: "독서 기록") {
                    OverlineSheetIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "닫기",
                        tint: Color.overlineMutedInk.opacity(0.72),
                        font: .title3.weight(.semibold)
                    ) {
                        dismiss()
                    }
                } trailing: {
                    OverlineSheetIconButton(systemImage: "plus", accessibilityLabel: "독서 기록 추가") {
                        editorTarget = ReadingRecordEditorTarget(recordID: nil)
                    }
                }

                if records.isEmpty {
                    ContentUnavailableView(
                        "독서 기록 없음",
                        systemImage: "book.pages",
                        description: Text("이 책을 읽은 시간을 남겨보세요.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(records) { record in
                                Button {
                                    editorTarget = ReadingRecordEditorTarget(recordID: record.id)
                                } label: {
                                    ReadingRecordHistoryRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .sheet(item: $editorTarget) { target in
                ReadingRecordEditorSheet(bookID: bookID, recordID: target.recordID)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var records: [ReadingRecord] {
        (library.book(with: bookID)?.readingRecords ?? []).sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private struct ReadingRecordHistoryRow: View {
    let record: ReadingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(record.status.title, systemImage: record.status.systemImage)
                    .foregroundStyle(Color.overlineAccent)
                Spacer(minLength: 0)
                Text(readingDateRangeText(for: record))
                    .foregroundStyle(Color.overlineMutedInk)
            }
            .font(.overline(.subheadline, weight: .semibold))

            if let rating = record.rating {
                ReadingRatingStars(rating: rating, size: 15)
            }

            if !record.review.trimmed.isEmpty {
                Text(record.review)
                    .font(.overline(.body, weight: .medium))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(4)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .overlineGlassControl(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ReadingRecordEditorSheet: View {
    private static let reviewLimit = 3_000

    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library

    let bookID: ReadingBook.ID
    let recordID: ReadingRecord.ID?

    @State private var startedAt = Calendar.current.startOfDay(for: .now)
    @State private var endedAt = Calendar.current.startOfDay(for: .now)
    @State private var hasEndDate = false
    @State private var status: ReadingStatus = .reading
    @State private var rating = 0.0
    @State private var review = ""
    @State private var showsReviewEditor = false
    @State private var showsDeleteConfirmation = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: recordID == nil ? "독서 기록 추가" : "독서 기록 편집") {
                    OverlineSheetIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "취소",
                        tint: Color.overlineMutedInk.opacity(0.72),
                        font: .title3.weight(.semibold)
                    ) {
                        dismiss()
                    }
                } trailing: {
                    OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "완료") {
                        save()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        statusEditor
                        dateEditor
                        ratingEditor
                        reviewEditor

                        if recordID != nil {
                            deleteButton
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear(perform: loadRecord)
            .onChange(of: startedAt) { _, newStartDate in
                if endedAt < newStartDate {
                    endedAt = newStartDate
                }
            }
            .onChange(of: review) { _, newValue in
                if newValue.count > Self.reviewLimit {
                    review = String(newValue.prefix(Self.reviewLimit))
                }
            }
            .fullScreenCover(isPresented: $showsReviewEditor) {
                ReadingReviewFullScreenEditor(
                    bookID: bookID,
                    status: status,
                    initialText: review
                ) { updatedReview in
                    review = String(updatedReview.prefix(Self.reviewLimit))
                }
            }
            .confirmationDialog("독서 기록을 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("삭제", role: .destructive, action: deleteRecord)
                Button("취소", role: .cancel) {}
            }
        }
    }

    private var statusEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "독서 상태")

            Menu {
                ForEach(ReadingStatus.allCases) { option in
                    Button {
                        selectStatus(option)
                    } label: {
                        Label(option.title, systemImage: option.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: status.systemImage)
                        .font(.overline(.title3, weight: .semibold))
                        .foregroundStyle(Color.overlineAccent)
                        .frame(width: 24)
                    Text(status.title)
                        .font(.overline(.title3, weight: .medium))
                        .foregroundStyle(Color.overlineInk)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.overline(.caption, weight: .bold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.58))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlineGlassControl(cornerRadius: 22)
        }
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "독서 날짜")

            VStack(spacing: 0) {
                DatePicker("시작", selection: $startedAt, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 58)

                Divider().opacity(0.42).padding(.leading, 18)

                Toggle("종료일", isOn: $hasEndDate)
                    .tint(Color.overlineAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 58)

                if hasEndDate {
                    Divider().opacity(0.42).padding(.leading, 18)
                    DatePicker("종료", selection: $endedAt, in: startedAt..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 58)
                }
            }
            .font(.overline(.body, weight: .medium))
            .overlineGlassControl(cornerRadius: 22)
        }
    }

    private var ratingEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "별점")
            ReadingRatingPicker(rating: $rating)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .overlineGlassControl(cornerRadius: 22)
        }
    }

    private var reviewEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "감상문")

            Button {
                showsReviewEditor = true
            } label: {
                Text(review.trimmed.isEmpty ? "이 책을 읽고 남은 생각" : review)
                    .font(.overline(.body, weight: review.trimmed.isEmpty ? .regular : .medium))
                    .foregroundStyle(
                        review.trimmed.isEmpty
                            ? Color.overlineMutedInk.opacity(0.46)
                            : Color.overlineInk
                    )
                    .lineLimit(4)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlineGlassControl(cornerRadius: 22)
            .accessibilityLabel(review.trimmed.isEmpty ? "감상문 작성" : "감상문 편집")

            Text("\(review.count.formatted()) / \(Self.reviewLimit.formatted())")
                .font(.overline(.caption))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showsDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.overline(.title2, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.overlineCoral)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("독서 기록 삭제")
    }

    private var book: ReadingBook? {
        library.book(with: bookID)
    }

    private func selectStatus(_ newStatus: ReadingStatus) {
        status = newStatus
        if [.completed, .abandoned].contains(newStatus), !hasEndDate {
            hasEndDate = true
            endedAt = max(startedAt, Calendar.current.startOfDay(for: .now))
        }
    }

    private func loadRecord() {
        guard !didLoad else { return }
        didLoad = true
        guard
            let recordID,
            let record = book?.readingRecords.first(where: { $0.id == recordID })
        else {
            return
        }

        startedAt = record.startedAt
        endedAt = record.endedAt ?? max(record.startedAt, Calendar.current.startOfDay(for: .now))
        hasEndDate = record.endedAt != nil
        status = record.status
        rating = record.rating ?? 0
        review = record.review
    }

    private func save() {
        let selectedEndDate = hasEndDate ? endedAt : nil
        let selectedRating = rating > 0 ? rating : nil

        if let recordID {
            library.updateReadingRecord(
                recordID,
                in: bookID,
                startedAt: startedAt,
                endedAt: selectedEndDate,
                status: status,
                rating: selectedRating,
                review: review
            )
        } else {
            library.addReadingRecord(
                to: bookID,
                startedAt: startedAt,
                endedAt: selectedEndDate,
                status: status,
                rating: selectedRating,
                review: review
            )
        }
        dismiss()
    }

    private func deleteRecord() {
        guard let recordID else { return }
        library.deleteReadingRecord(recordID, in: bookID)
        dismiss()
    }
}

private struct ReadingReviewFullScreenEditor: View {
    private static let reviewLimit = 3_000

    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library
    @Environment(LLMSettingsStore.self) private var llmSettings

    let bookID: ReadingBook.ID
    let status: ReadingStatus
    let save: (String) -> Void

    @State private var draftText: String
    @State private var isGeneratingDraft = false
    @State private var draftProposal: ReadingReviewDraftProposal?
    @State private var aiAlert: ReadingRecordAlert?
    @State private var generationTask: Task<Void, Never>?
    @FocusState private var isEditorFocused: Bool

    init(
        bookID: ReadingBook.ID,
        status: ReadingStatus,
        initialText: String,
        save: @escaping (String) -> Void
    ) {
        self.bookID = bookID
        self.status = status
        self.save = save
        _draftText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: "감상문") {
                    OverlineSheetIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "취소",
                        tint: Color.overlineMutedInk.opacity(0.72),
                        font: .title3.weight(.semibold)
                    ) {
                        dismiss()
                    }
                } trailing: {
                    HStack(spacing: 2) {
                        if !(book?.highlights.isEmpty ?? true) {
                            aiDraftButton
                        }

                        OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "완료") {
                            save(String(draftText.prefix(Self.reviewLimit)))
                            dismiss()
                        }
                    }
                }

                VStack(spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        if draftText.isEmpty {
                            Text("이 책을 읽고 남은 생각")
                                .font(.overline(.body))
                                .foregroundStyle(Color.overlineMutedInk.opacity(0.46))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 22)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $draftText)
                            .font(.overline(.body, weight: .medium))
                            .lineSpacing(5)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .focused($isEditorFocused)
                            .accessibilityLabel("감상문")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlineGlassControl(cornerRadius: 22)

                    Text("\(draftText.count.formatted()) / \(Self.reviewLimit.formatted())")
                        .font(.overline(.caption))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                isEditorFocused = true
            }
            .onChange(of: draftText) { _, newValue in
                if newValue.count > Self.reviewLimit {
                    draftText = String(newValue.prefix(Self.reviewLimit))
                }
            }
            .onDisappear {
                generationTask?.cancel()
            }
            .sheet(item: $draftProposal) { proposal in
                ReadingReviewDraftPreviewSheet(proposal: proposal) { draft in
                    applyDraft(draft, proposal: proposal)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thinMaterial)
            }
            .alert(item: $aiAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .cancel(Text("확인"))
                )
            }
        }
    }

    private var aiDraftButton: some View {
        Button(action: requestAIDraft) {
            ZStack {
                if isGeneratingDraft {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.overlineAccent)
                } else {
                    Image(systemName: "sparkles")
                        .font(.overline(.body, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.overlineAccent)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isGeneratingDraft)
        .accessibilityLabel("AI 감상문 초안 만들기")
    }

    private var book: ReadingBook? {
        library.book(with: bookID)
    }

    private func requestAIDraft() {
        guard let book, !book.highlights.isEmpty else { return }
        guard let configuration = llmSettings.activeConfiguration else {
            aiAlert = ReadingRecordAlert(title: "AI 초안", message: selectedAISetupMessage)
            return
        }

        let snapshot = ReadingReviewGenerationSnapshot(
            review: draftText,
            status: status,
            highlights: book.highlights
        )
        let sources = readingReviewSources(for: book)
        guard !sources.isEmpty else { return }

        generationTask?.cancel()
        isGeneratingDraft = true
        aiAlert = nil
        LLMUsageMetricsStore.recordRequested()

        generationTask = Task { @MainActor in
            defer {
                isGeneratingDraft = false
                generationTask = nil
            }

            do {
                let generatedDraft = try await LLMInsightClient().generateInsight(
                    LLMInsightRequest(
                        provider: configuration.provider,
                        modelID: configuration.modelID,
                        credential: configuration.credential,
                        category: "독서 감상문",
                        instruction: "",
                        userPrompt: "현재 독서 상태: \(snapshot.status.title)",
                        sources: sources
                    )
                )

                guard !Task.isCancelled else { return }
                llmSettings.handleRequestSuccess(configuration: configuration)
                LLMUsageMetricsStore.recordCompleted()

                guard
                    draftText == snapshot.review,
                    library.book(with: bookID)?.highlights == snapshot.highlights
                else {
                    aiAlert = ReadingRecordAlert(
                        title: "AI 초안",
                        message: "감상문이나 글조각이 바뀌어서 이번 초안을 적용하지 않았어요."
                    )
                    return
                }

                draftProposal = ReadingReviewDraftProposal(
                    sourceReview: snapshot.review,
                    generatedText: String(generatedDraft.trimmed.prefix(Self.reviewLimit)),
                    sourceCount: sources.count
                )
            } catch {
                guard !Task.isCancelled else { return }
                llmSettings.handleRequestError(error, configuration: configuration)
                LLMUsageMetricsStore.recordFailed()
                aiAlert = ReadingRecordAlert(title: "AI 초안", message: error.localizedDescription)
            }
        }
    }

    private func applyDraft(_ draft: String, proposal: ReadingReviewDraftProposal) {
        guard draftText == proposal.sourceReview else {
            draftProposal = nil
            aiAlert = ReadingRecordAlert(
                title: "AI 초안",
                message: "감상문이 바뀌어서 초안을 적용하지 않았어요."
            )
            return
        }

        draftText = String(draft.trimmed.prefix(Self.reviewLimit))
        draftProposal = nil
    }

    private var selectedAISetupMessage: String {
        let provider = llmSettings.provider
        if llmSettings.isCredentialRejected(for: provider) {
            return "\(provider.title) 인증 또는 현재 모델 접근이 거부되었습니다. AI 설정에서 다시 연결하거나 모델을 확인해 주세요."
        }

        switch llmSettings.authMode(for: provider) {
        case .apiKey:
            return "AI 설정에서 선택한 \(provider.title) API 키를 입력해 주세요."
        case .subscription:
            return "AI 설정에서 선택한 \(provider.title) 구독 토큰을 연결해 주세요."
        }
    }
}

private struct ReadingRatingPicker: View {
    @Binding var rating: Double

    var body: some View {
        HStack(spacing: 10) {
            InteractiveReadingRatingStars(rating: $rating)
                .frame(maxWidth: .infinity)

            Text(rating > 0 ? "\(rating.formatted(.number.precision(.fractionLength(1))))점" : "평가 안 함")
                .font(.overline(.subheadline, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk)
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)

            Button {
                rating = 0
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.overline(.body, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.56))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(rating > 0 ? 1 : 0)
            .allowsHitTesting(rating > 0)
            .accessibilityHidden(rating <= 0)
            .accessibilityLabel("별점 지우기")
        }
    }
}

private struct InteractiveReadingRatingStars: View {
    @Binding var rating: Double

    private static let feedbackGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    let symbol = symbolName(for: index)
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: symbol == "star" ? .regular : .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.overlineHighlight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateRating(at: value.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("별점")
        .accessibilityValue(rating > 0 ? "5점 만점에 \(rating)점" : "평가 안 함")
        .accessibilityHint("별을 탭하거나 쓸어 별점을 선택합니다")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setRating(min(5, max(0.5, rating + 0.5)))
            case .decrement:
                setRating(rating <= 0.5 ? 0 : rating - 0.5)
            @unknown default:
                break
            }
        }
        .onAppear {
            Self.feedbackGenerator.prepare()
        }
    }

    private func updateRating(at locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let clampedX = min(max(locationX, 0), width)
        let halfStarStep = min(10, max(1, Int(ceil((clampedX / width) * 10))))
        setRating(Double(halfStarStep) / 2)
    }

    private func setRating(_ newRating: Double) {
        guard rating != newRating else { return }
        rating = newRating
        Self.feedbackGenerator.selectionChanged()
        Self.feedbackGenerator.prepare()
    }

    private func symbolName(for index: Int) -> String {
        let threshold = Double(index)
        if rating >= threshold { return "star.fill" }
        if rating >= threshold - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

private struct ReadingRatingStars: View {
    let rating: Double
    let size: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                let symbol = symbolName(for: index)
                Image(systemName: symbol)
                    .font(.system(size: size, weight: symbol == "star" ? .regular : .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.overlineHighlight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating > 0 ? "별점 \(rating)점" : "별점 없음")
    }

    private func symbolName(for index: Int) -> String {
        let threshold = Double(index)
        if rating >= threshold { return "star.fill" }
        if rating >= threshold - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

private struct ReadingReviewDraftPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let proposal: ReadingReviewDraftProposal
    let apply: (String) -> Void
    @State private var draftText: String

    init(proposal: ReadingReviewDraftProposal, apply: @escaping (String) -> Void) {
        self.proposal = proposal
        self.apply = apply
        _draftText = State(initialValue: proposal.generatedText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: "AI 감상문 초안") {
                    OverlineSheetIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "취소",
                        tint: Color.overlineMutedInk.opacity(0.72),
                        font: .title3.weight(.semibold)
                    ) {
                        dismiss()
                    }
                } trailing: {
                    OverlineSheetIconButton(
                        systemImage: "checkmark",
                        accessibilityLabel: proposal.sourceReview.trimmed.isEmpty ? "초안 사용" : "초안으로 바꾸기",
                        isDisabled: draftText.trimmed.isEmpty
                    ) {
                        apply(draftText)
                        dismiss()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("글조각 \(proposal.sourceCount)개 참고", systemImage: "quote.bubble")
                        .font(.overline(.caption, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk)

                    TextEditor(text: $draftText)
                        .font(.overline(.body, weight: .medium))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlineGlassControl(cornerRadius: 20)
                        .accessibilityLabel("AI 감상문 초안")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onChange(of: draftText) { _, newValue in
                if newValue.count > 3_000 {
                    draftText = String(newValue.prefix(3_000))
                }
            }
        }
    }
}

private struct ReadingRecordEditorTarget: Identifiable {
    let id = UUID()
    let recordID: ReadingRecord.ID?
}

private struct ReadingReviewDraftProposal: Identifiable {
    let id = UUID()
    let sourceReview: String
    let generatedText: String
    let sourceCount: Int
}

private struct ReadingReviewGenerationSnapshot: Equatable {
    let review: String
    let status: ReadingStatus
    let highlights: [Highlight]
}

private struct ReadingRecordAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private func readingReviewSources(for book: ReadingBook) -> [LLMInsightSource] {
    let orderedHighlights = book.highlights
        .filter { !$0.text.trimmed.isEmpty }
        .sorted { $0.createdAt < $1.createdAt }
    let selectedHighlights = evenlySampled(orderedHighlights, maximumCount: 24)
    guard !selectedHighlights.isEmpty else { return [] }

    let perSourceBudget = max(320, 12_000 / selectedHighlights.count)
    let textBudget = Int(Double(perSourceBudget) * 0.78)
    let memoBudget = perSourceBudget - textBudget

    return selectedHighlights.map { highlight in
        LLMInsightSource(
            bookTitle: book.title,
            bookAuthor: book.author,
            bookSummary: book.summary,
            text: String(highlight.text.trimmed.prefix(textBudget)),
            memo: String(highlight.memo.trimmed.prefix(memoBudget))
        )
    }
}

private func evenlySampled<T>(_ values: [T], maximumCount: Int) -> [T] {
    guard values.count > maximumCount, maximumCount > 1 else { return values }

    return (0..<maximumCount).map { position in
        let ratio = Double(position) / Double(maximumCount - 1)
        let index = Int((ratio * Double(values.count - 1)).rounded())
        return values[index]
    }
}

private func readingDateRangeText(for record: ReadingRecord) -> String {
    let start = readingRecordDateFormatter.string(from: record.startedAt)
    guard let endedAt = record.endedAt else { return start }
    let end = readingRecordDateFormatter.string(from: endedAt)
    return start == end ? start : "\(start) - \(end)"
}

private let readingRecordDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy. M. d."
    return formatter
}()
