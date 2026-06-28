import SwiftUI
import UIKit

struct HighlightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library

    let highlightID: Highlight.ID

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
                    library.deleteHighlight(highlightID)
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
            .onAppear {
                loadHighlight()
            }
        }
    }

    private var textEditorCard: some View {
        VStack(spacing: 16) {
            TextField("글조각", text: $text, axis: .vertical)
                .font(.title3.weight(.medium))
                .lineSpacing(3)
                .lineLimit(4...18)
                .padding(.vertical, 2)
                .frame(minHeight: 132, alignment: .topLeading)

            Divider().opacity(0.42)

            TextField("메모", text: $memo, axis: .vertical)
                .font(.body.weight(.regular))
                .lineLimit(1...6)
                .padding(.vertical, 2)
        }
        .padding(18)
        .overlineGlassControl(cornerRadius: 24)
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
}

private func editorPageNumber(from value: String) -> String {
    String(value.filter { $0.isNumber }.prefix(4))
}

#Preview {
    HighlightEditorSheet(highlightID: SampleData.books[0].highlights[0].id)
        .environment(ReadingLibrary.preview)
}
