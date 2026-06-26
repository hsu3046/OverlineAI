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
    @State private var selectedBookID: ReadingBook.ID?
    @State private var snapshotURL: URL?
    @State private var isReviewed = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                if snapshotURL != nil {
                    Section {
                        HighlightReviewSnapshotPreview(snapshotURL: snapshotURL)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }

                Section {
                    TextField("글조각", text: $text, axis: .vertical)
                        .lineLimit(1...8)
                    TextField("메모", text: $memo, axis: .vertical)
                        .lineLimit(1...6)
                }

                if !library.books.isEmpty {
                    Section("책 이름") {
                        Picker("책 이름", selection: selectedBookBinding) {
                            ForEach(library.books) { book in
                                Text(book.title)
                                    .tag(book.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.inline)
                    }
                }

                Section {
                    TextField("태그", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("글조각 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        library.updateHighlight(
                            highlightID,
                            text: text,
                            memo: memo,
                            pageReference: pageReference,
                            tagsText: tagsText,
                            bookID: selectedBookID,
                            isReviewed: isReviewed
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmed.isEmpty)
                }
            }
            .confirmationDialog("글조각을 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    library.deleteHighlight(highlightID)
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            }
            .onAppear {
                loadHighlight()
            }
        }
    }

    private var selectedBookBinding: Binding<ReadingBook.ID> {
        Binding(
            get: { selectedBookID ?? library.bookID(containing: highlightID) ?? library.books.first?.id ?? UUID() },
            set: { selectedBookID = $0 }
        )
    }

    private func loadHighlight() {
        guard let highlight = library.highlight(with: highlightID) else { return }
        text = highlight.text
        memo = highlight.memo
        pageReference = highlight.pageReference
        tagsText = highlight.tags.joined(separator: " ")
        selectedBookID = library.bookID(containing: highlightID) ?? library.selectedBookID ?? library.books.first?.id
        snapshotURL = HighlightSnapshotStore.url(for: highlight.snapshotFileName)
        isReviewed = highlight.reviewedAt != nil
    }
}

private struct HighlightReviewSnapshotPreview: View {
    var snapshotURL: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.overlinePaper)
            .frame(minHeight: 146)
            .overlay {
                if let snapshotImage {
                    snapshotImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<5, id: \.self) { _ in
                            Capsule()
                                .fill(Color.overlineInk.opacity(0.10))
                                .frame(height: 2)
                        }
                    }
                    .padding(18)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.overlineInk.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var snapshotImage: Image? {
        guard
            let snapshotURL,
            let uiImage = UIImage(contentsOfFile: snapshotURL.path)
        else {
            return nil
        }

        return Image(uiImage: uiImage)
    }
}

#Preview {
    HighlightEditorSheet(highlightID: SampleData.books[0].highlights[0].id)
        .environment(ReadingLibrary.preview)
}
