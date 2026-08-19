import SwiftUI
import UIKit

struct HighlightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library

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
    @State private var llmSettings = LLMSettingsStore()
    @State private var isCorrectingOCR = false
    @State private var correctionProposal: OCRCorrectionProposal?
    @State private var correctionMessage: String?

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
            .alert("AI 교정", isPresented: correctionMessageBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(correctionMessage ?? "")
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
                    .font(.title3.weight(.medium))
                    .lineSpacing(3)
                    .lineLimit(4...18)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)

                correctionButton
            }

            Divider().opacity(0.42)

            TextField("메모", text: $memo, axis: .vertical)
                .font(.body.weight(.regular))
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
                        .font(.body.weight(.semibold))
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
            OverlineEditorLabel(title: "태그")

            TextField("태그", text: $tagsText)
                .font(.title3.weight(.medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 18)
                .frame(minHeight: formControlHeight, alignment: .leading)
                .overlineGlassControl(cornerRadius: formControlCornerRadius)
        }
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.overlineAccent)
                    .frame(width: 24)

                Text("p.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.overlineInk.opacity(0.62))

                TextField("42", text: pageNumberBinding)
                    .font(.title3.weight(.medium))
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
                .font(.title2.weight(.semibold))
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

    private var correctionMessageBinding: Binding<Bool> {
        Binding(
            get: {
                correctionMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    correctionMessage = nil
                }
            }
        )
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

        guard let configuration = llmSettings.lightweightCorrectionConfiguration else {
            correctionMessage = "AI 설정에서 OpenAI, Claude 또는 Gemini를 먼저 연결해 주세요."
            return
        }

        let book = selectedBook
        isCorrectingOCR = true
        correctionMessage = nil

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
                    correctionMessage = "글조각이 바뀌어서 교정 제안을 적용하지 않았어요."
                    return
                }

                guard result.correctedText != trimmedText else {
                    correctionMessage = "교정할 부분을 찾지 못했어요."
                    return
                }

                correctionProposal = OCRCorrectionProposal(
                    sourceText: sourceText,
                    correctedText: result.correctedText,
                    changes: result.changes,
                    risk: result.risk
                )
            } catch {
                correctionMessage = error.localizedDescription
            }
        }
    }

    private func applyCorrection(_ proposal: OCRCorrectionProposal) {
        guard text == proposal.sourceText else {
            correctionMessage = "글조각이 바뀌어서 교정을 적용하지 않았어요."
            return
        }

        text = proposal.correctedText
        correctionProposal = nil
    }
}

private func editorPageNumber(from value: String) -> String {
    String(value.filter { $0.isNumber }.prefix(4))
}

private struct OCRCorrectionProposal: Identifiable, Equatable {
    let id = UUID()
    let sourceText: String
    let correctedText: String
    let changes: [String]
    let risk: String
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
                        .font(.subheadline.weight(.medium))
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
                .font(isPrimary ? .title3.weight(.medium) : .body.weight(.regular))
                .lineSpacing(isPrimary ? 5 : 4)
                .foregroundStyle(isPrimary ? Color.overlineInk : Color.overlineMutedInk.opacity(0.86))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .overlineGlassControl(cornerRadius: 22)
        }
    }
}

#Preview {
    HighlightEditorSheet(highlightID: SampleData.books[0].highlights[0].id)
        .environment(ReadingLibrary.preview)
}
