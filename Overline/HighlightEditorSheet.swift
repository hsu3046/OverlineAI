import SwiftUI
import UIKit

struct HighlightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library
    @Environment(LLMSettingsStore.self) private var llmSettings

    let highlightID: Highlight.ID
    var deleteHighlight: ((Highlight.ID) -> Void)? = nil

    @State private var text = ""
    @State private var memo = ""
    @State private var pageReference = ""
    @State private var tagsText = ""
    @State private var loadedTagsText = ""
    @State private var selectedBookID: ReadingBook.ID?
    @State private var selectedTone: StickyTone = .yellow
    @State private var isReviewed = false
    @State private var showsDeleteConfirmation = false
    @State private var isBookSelectionPresented = false
    @State private var isCorrectingOCR = false
    @State private var correctionProposal: OCRCorrectionProposal?
    @State private var isRegeneratingTags = false
    @State private var tagRegenerationProposal: TagRegenerationProposal?
    @State private var aiAlert: EditorAIAlert?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: "글조각 편집") {
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
                        accessibilityLabel: "완료",
                        isDisabled: text.trimmed.isEmpty
                    ) {
                        save()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        textEditorCard

                        if !library.books.isEmpty {
                            bookSelector
                        }

                        pageEditor

                        tagsEditor

                        toneEditor

                        deleteButton
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .confirmationDialog("글조각을 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let deleteHighlight {
                        deleteHighlight(highlightID)
                    } else {
                        library.deleteHighlight(highlightID)
                    }
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            }
            .sheet(isPresented: $isBookSelectionPresented) {
                OverlineBookPickerSheet(
                    title: "책 선택",
                    books: library.books,
                    selectedBookID: selectedBookID,
                    onSelect: { bookID in
                        selectedBookID = bookID
                    }
                )
                .presentationDetents([.height(bookSelectionSheetHeight), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thinMaterial)
            }
            .sheet(item: $correctionProposal) { proposal in
                OCRCorrectionPreviewSheet(proposal: proposal) {
                    applyCorrection(proposal)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thinMaterial)
            }
            .sheet(item: $tagRegenerationProposal) { proposal in
                TagRegenerationPreviewSheet(proposal: proposal) {
                    applyTagRegeneration(proposal)
                }
                .presentationDetents([.medium])
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
            .onAppear {
                loadHighlight()
            }
        }
    }

    private var textEditorCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                TextField("글조각", text: $text, axis: .vertical)
                    .font(.overline(.title3, weight: .medium))
                    .lineSpacing(3)
                    .lineLimit(4...18)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)

                correctionButton
            }

            Divider().opacity(0.42)

            TextField("메모", text: $memo, axis: .vertical)
                .font(.overline(.body, weight: .regular))
                .lineLimit(1...6)
                .padding(.vertical, 2)
        }
        .padding(18)
        .overlineGlassControl(cornerRadius: 24)
    }

    private var correctionButton: some View {
        Button {
            requestOCRCorrection()
        } label: {
            ZStack {
                if isCorrectingOCR {
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
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.trimmed.isEmpty || isCorrectingOCR)
        .opacity(text.trimmed.isEmpty ? 0.32 : 1)
        .accessibilityLabel("AI OCR 교정")
    }

    private var bookSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "책 이름")

            OverlineBookSelectorButton(
                title: selectedBook?.title ?? "Inbox",
                height: formControlHeight,
                cornerRadius: formControlCornerRadius,
                titleFont: .title3.weight(.medium)
            ) {
                isBookSelectionPresented = true
            }
        }
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                OverlineEditorLabel(title: "태그")

                Spacer(minLength: 0)

                tagRegenerationButton
                    .padding(.trailing, 14)
            }

            TextField("태그", text: $tagsText)
                .font(.overline(.title3, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 18)
                .frame(minHeight: formControlHeight, alignment: .leading)
                .overlineGlassControl(cornerRadius: formControlCornerRadius)
        }
    }

    private var tagRegenerationButton: some View {
        Button {
            requestTagRegeneration()
        } label: {
            ZStack {
                if isRegeneratingTags {
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
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.trimmed.isEmpty || isRegeneratingTags)
        .opacity(text.trimmed.isEmpty ? 0.32 : 1)
        .accessibilityLabel("AI 태그 재생성")
    }

    private var toneEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "색상")

            HStack {
                HighlightTonePicker(selectedTone: $selectedTone)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: formControlHeight, alignment: .leading)
            .overlineGlassControl(cornerRadius: formControlCornerRadius)
        }
    }

    private var pageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "책 페이지")

            HStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                    .font(.overline(.title3, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)
                    .frame(width: 24)

                Text("p.")
                    .font(.overline(.title3, weight: .medium))
                    .foregroundStyle(Color.overlineInk.opacity(0.62))

                TextField("42", text: pageNumberBinding)
                    .font(.overline(.title3, weight: .medium))
                    .keyboardType(.numberPad)
                    .tint(Color.overlineAccent)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: formControlHeight, alignment: .leading)
            .overlineGlassControl(cornerRadius: formControlCornerRadius)
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
        .accessibilityLabel("글조각 삭제")
    }

    private var selectedBook: ReadingBook? {
        guard let selectedBookID else { return library.books.first }
        return library.book(with: selectedBookID) ?? library.books.first
    }

    private var formControlHeight: CGFloat {
        64
    }

    private var formControlCornerRadius: CGFloat {
        22
    }

    private var bookSelectionSheetHeight: CGFloat {
        OverlineBookPickerMetrics.sheetHeight(bookCount: library.books.count)
    }

    private var pageNumberBinding: Binding<String> {
        Binding(
            get: {
                editorPageNumber(from: pageReference)
            },
            set: { newValue in
                let pageNumber = editorPageNumber(from: newValue)
                pageReference = pageNumber.isEmpty ? "" : "p.\(pageNumber)"
            }
        )
    }

    private func loadHighlight() {
        guard let highlight = library.highlight(with: highlightID) else { return }
        text = highlight.text
        memo = highlight.memo
        pageReference = highlight.pageReference
        tagsText = highlight.tags.joined(separator: " ")
        loadedTagsText = tagsText
        selectedTone = highlight.stickyTone
        selectedBookID = library.bookID(containing: highlightID) ?? library.selectedBookID ?? library.books.first?.id
        isReviewed = highlight.reviewedAt != nil
    }

    private func save() {
        let tagsTextForSave: String
        if tagsText.trimmed == loadedTagsText.trimmed, let currentHighlight = library.highlight(with: highlightID) {
            tagsTextForSave = currentHighlight.tags.joined(separator: " ")
        } else {
            tagsTextForSave = tagsText
        }

        library.updateHighlight(
            highlightID,
            text: text,
            memo: memo,
            pageReference: pageReference,
            tagsText: tagsTextForSave,
            bookID: selectedBookID,
            stickyTone: selectedTone,
            isReviewed: isReviewed
        )
        dismiss()
    }

    private func requestOCRCorrection() {
        let sourceText = text
        let trimmedText = sourceText.trimmed
        guard !trimmedText.isEmpty else { return }

        guard let configuration = llmSettings.activeConfiguration else {
            showAIAlert(title: "AI 교정", message: selectedAISetupMessage)
            return
        }

        let book = selectedBook
        isCorrectingOCR = true
        aiAlert = nil

        Task { @MainActor in
            defer { isCorrectingOCR = false }

            do {
                let result = try await LLMInsightClient().generateOCRCorrection(
                    LLMOCRCorrectionRequest(
                        provider: configuration.provider,
                        modelID: configuration.modelID,
                        credential: configuration.credential,
                        bookTitle: book?.title ?? "",
                        bookAuthor: book?.author ?? "",
                        text: trimmedText
                    )
                )

                guard text == sourceText else {
                    showAIAlert(title: "AI 교정", message: "글조각이 바뀌어서 교정 제안을 적용하지 않았어요.")
                    return
                }

                guard result.correctedText != trimmedText else {
                    showAIAlert(title: "AI 교정", message: "교정할 부분을 찾지 못했어요.")
                    return
                }

                correctionProposal = OCRCorrectionProposal(
                    sourceText: sourceText,
                    correctedText: result.correctedText,
                    changes: result.changes,
                    risk: result.risk
                )
            } catch {
                llmSettings.handleRequestError(error, configuration: configuration)
                showAIAlert(title: "AI 교정", message: error.localizedDescription)
            }
        }
    }

    private func applyCorrection(_ proposal: OCRCorrectionProposal) {
        guard text == proposal.sourceText else {
            showAIAlert(title: "AI 교정", message: "글조각이 바뀌어서 교정을 적용하지 않았어요.")
            return
        }

        text = proposal.correctedText
        correctionProposal = nil
    }

    private func requestTagRegeneration() {
        let snapshot = TagRegenerationSnapshot(
            text: text,
            memo: memo,
            tagsText: tagsText,
            selectedBookID: selectedBookID
        )
        let trimmedText = snapshot.text.trimmed
        guard !trimmedText.isEmpty else { return }

        guard let configuration = llmSettings.activeConfiguration else {
            showAIAlert(title: "AI 태그", message: selectedAISetupMessage)
            return
        }

        let book = selectedBook
        let currentTags = editorTags(from: snapshot.tagsText)
        isRegeneratingTags = true
        aiAlert = nil

        Task { @MainActor in
            defer { isRegeneratingTags = false }

            do {
                let suggestedTags = try await LLMInsightClient().generateTags(
                    LLMTagRequest(
                        provider: configuration.provider,
                        modelID: configuration.modelID,
                        credential: configuration.credential,
                        bookTitle: book?.title ?? "",
                        bookAuthor: book?.author ?? "",
                        bookSummary: book?.summary ?? "",
                        text: trimmedText,
                        memo: snapshot.memo.trimmed,
                        existingTags: currentTags,
                        mode: .manualRegeneration
                    )
                )

                guard currentTagRegenerationSnapshot == snapshot else {
                    showAIAlert(title: "AI 태그", message: "편집 내용이 바뀌어서 태그 제안을 적용하지 않았어요.")
                    return
                }

                guard !suggestedTags.isEmpty else {
                    showAIAlert(title: "AI 태그", message: "추천할 태그를 찾지 못했어요.")
                    return
                }

                guard canonicalTags(currentTags) != canonicalTags(suggestedTags) else {
                    showAIAlert(title: "AI 태그", message: "현재 태그가 이 글조각에 잘 맞아요.")
                    return
                }

                tagRegenerationProposal = TagRegenerationProposal(
                    snapshot: snapshot,
                    currentTags: currentTags,
                    suggestedTags: suggestedTags
                )
            } catch {
                llmSettings.handleRequestError(error, configuration: configuration)
                showAIAlert(title: "AI 태그", message: error.localizedDescription)
            }
        }
    }

    private func applyTagRegeneration(_ proposal: TagRegenerationProposal) {
        guard currentTagRegenerationSnapshot == proposal.snapshot else {
            showAIAlert(title: "AI 태그", message: "편집 내용이 바뀌어서 태그 제안을 적용하지 않았어요.")
            return
        }

        tagsText = proposal.suggestedTags.joined(separator: " ")
        tagRegenerationProposal = nil
    }

    private var currentTagRegenerationSnapshot: TagRegenerationSnapshot {
        TagRegenerationSnapshot(
            text: text,
            memo: memo,
            tagsText: tagsText,
            selectedBookID: selectedBookID
        )
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

    private func showAIAlert(title: String, message: String) {
        aiAlert = EditorAIAlert(title: title, message: message)
    }
}

private func editorPageNumber(from value: String) -> String {
    String(value.filter { $0.isNumber }.prefix(4))
}

private func editorTags(from value: String) -> [String] {
    var seen = Set<String>()

    return value
        .split { character in
            character.isWhitespace || character == ","
        }
        .compactMap { rawTag in
            let content = String(rawTag)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmed
            guard !content.isEmpty else { return nil }

            let tag = "#\(content.replacingOccurrences(of: " ", with: ""))"
            let key = tag.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return tag
        }
}

private func canonicalTags(_ tags: [String]) -> Set<String> {
    Set(tags.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() })
}

private struct OCRCorrectionProposal: Identifiable, Equatable {
    let id = UUID()
    let sourceText: String
    let correctedText: String
    let changes: [String]
    let risk: String
}

private struct EditorAIAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TagRegenerationSnapshot: Equatable {
    let text: String
    let memo: String
    let tagsText: String
    let selectedBookID: ReadingBook.ID?
}

private struct TagRegenerationProposal: Identifiable, Equatable {
    let id = UUID()
    let snapshot: TagRegenerationSnapshot
    let currentTags: [String]
    let suggestedTags: [String]
}

private struct OCRCorrectionPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let proposal: OCRCorrectionProposal
    let apply: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: "AI 교정") {
                    OverlineSheetIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "취소",
                        tint: Color.overlineMutedInk.opacity(0.72),
                        font: .title3.weight(.semibold)
                    ) {
                        dismiss()
                    }
                } trailing: {
                    OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "적용") {
                        apply()
                        dismiss()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        correctionTextCard(
                            title: "교정 제안",
                            text: proposal.correctedText,
                            isPrimary: true
                        )

                        if !proposal.changes.isEmpty {
                            changesCard
                        }

                        correctionTextCard(
                            title: "원문",
                            text: proposal.sourceText,
                            isPrimary: false
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "변경점")
                .padding(.leading, 0)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(proposal.changes, id: \.self) { change in
                    Text("· \(change)")
                        .font(.overline(.subheadline, weight: .medium))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.78))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .overlineGlassControl(cornerRadius: 22)
        }
    }

    private func correctionTextCard(title: String, text: String, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: title)
                .padding(.leading, 0)

            Text(text)
                .font(
                    isPrimary
                        ? .overline(.title3, weight: .medium)
                        : .overline(.body, weight: .regular)
                )
                .lineSpacing(isPrimary ? 5 : 4)
                .foregroundStyle(isPrimary ? Color.overlineInk : Color.overlineMutedInk.opacity(0.86))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .overlineGlassControl(cornerRadius: 22)
        }
    }
}

private struct TagRegenerationPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let proposal: TagRegenerationProposal
    let apply: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: "AI 태그") {
                    OverlineSheetIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "취소",
                        tint: Color.overlineMutedInk.opacity(0.72),
                        font: .title3.weight(.semibold)
                    ) {
                        dismiss()
                    }
                } trailing: {
                    OverlineSheetIconButton(systemImage: "checkmark", accessibilityLabel: "적용") {
                        apply()
                        dismiss()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        tagCard(title: "새 태그", tags: proposal.suggestedTags, isPrimary: true)
                        tagCard(title: "현재 태그", tags: proposal.currentTags, isPrimary: false)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    private func tagCard(title: String, tags: [String], isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: title)
                .padding(.leading, 0)

            Text(tags.isEmpty ? "없음" : tags.joined(separator: "  "))
                .font(.overline(.title3, weight: isPrimary ? .semibold : .medium))
                .foregroundStyle(isPrimary ? Color.overlineInk : Color.overlineMutedInk.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .overlineGlassControl(cornerRadius: 22)
        }
    }
}

#Preview {
    HighlightEditorSheet(highlightID: SampleData.books[0].highlights[0].id)
        .environment(ReadingLibrary.preview)
        .environment(LLMSettingsStore())
}
