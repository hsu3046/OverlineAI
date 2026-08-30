import SwiftUI

struct BookEditorSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(ReadingBook.ID)

        var id: String {
            switch self {
            case .add:
                "add"
            case .edit(let bookID):
                "edit-\(bookID.uuidString)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library

    let mode: Mode

    @State private var title = ""
    @State private var author = ""
    @State private var summary = ""
    @State private var tagsText = ""
    @State private var publisher = ""
    @State private var publishedDate = ""
    @State private var isbn = ""
    @State private var coverURLString = ""
    @State private var metadataSource: BookMetadataSource = .manual
    @State private var searchQuery = ""
    @State private var searchResults: [BookMetadataCandidate] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?
    @State private var isISBNScannerPresented = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OverlineSheetHeader(title: navigationTitle) {
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
                        isDisabled: title.trimmed.isEmpty
                    ) {
                        save()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if isAddingBook {
                            searchSection
                        }

                        editorField("책 이름", prompt: "책 이름", text: $title, axis: .vertical, lineLimit: 1...3)
                        editorField("저자", prompt: "저자", text: $author, axis: .vertical, lineLimit: 1...3)
                        editorField("책 소개", prompt: "책 소개", text: $summary, axis: .vertical, lineLimit: 3...8)
                        editorField("태그", prompt: "태그", text: $tagsText, axis: .vertical, lineLimit: 1...3, autocorrectionDisabled: true)

                        VStack(alignment: .leading, spacing: 14) {
                            OverlineEditorLabel(title: "세부 정보")
                            editorFieldContent(prompt: "출판사", text: $publisher, axis: .vertical, lineLimit: 1...2)
                            editorFieldContent(prompt: "발행일", text: $publishedDate, autocorrectionDisabled: true)
                            editorFieldContent(prompt: "ISBN", text: $isbn, autocorrectionDisabled: true)
                            editorFieldContent(prompt: "표지 URL", text: $coverURLString, axis: .vertical, lineLimit: 1...3, autocorrectionDisabled: true)
                        }

                        if case .edit = mode {
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
            .confirmationDialog("책을 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    delete()
                }
                Button("취소", role: .cancel) {}
            }
            .onAppear {
                loadBook()
            }
            .fullScreenCover(isPresented: $isISBNScannerPresented) {
                ISBNScannerSheet { isbn, didScanBarcode in
                    applyScannedISBN(isbn, didScanBarcode: didScanBarcode)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add:
            "책 추가"
        case .edit:
            "책 편집"
        }
    }

    private var isAddingBook: Bool {
        if case .add = mode {
            return true
        }
        return false
    }

    private var formControlHeight: CGFloat {
        64
    }

    private var formControlCornerRadius: CGFloat {
        22
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: "도서 찾기")

            VStack(spacing: 14) {
                Button {
                    isISBNScannerPresented = true
                } label: {
                    Label("ISBN 스캔", systemImage: "barcode.viewfinder")
                        .font(.overline(.title3, weight: .medium))
                        .foregroundStyle(Color.overlineAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ISBN 바코드 스캔")

                Divider()
                    .opacity(0.46)

                HStack(spacing: 10) {
                    TextField("제목, 저자, ISBN", text: $searchQuery)
                        .font(.overline(.title3, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            Task {
                                await searchBooks()
                            }
                        }

                    Button {
                        Task {
                            await searchBooks()
                        }
                    } label: {
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.overline(.title3, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(searchQuery.trimmed.isEmpty || isSearching)
                    .foregroundStyle(searchQuery.trimmed.isEmpty ? Color.overlineMutedInk.opacity(0.38) : Color.overlineAccent)
                    .accessibilityLabel("도서 검색")
                }

                if let searchErrorMessage {
                    Text(searchErrorMessage)
                        .font(.overline(.caption))
                        .foregroundStyle(Color.overlineCoral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(searchResults) { result in
                    Button {
                        apply(result)
                    } label: {
                        BookSearchResultRow(result: result)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .overlineGlassControl(cornerRadius: 24)
        }
    }

    private func editorField(
        _ label: String,
        prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 1...1,
        autocorrectionDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineEditorLabel(title: label)
            editorFieldContent(
                prompt: prompt,
                text: text,
                axis: axis,
                lineLimit: lineLimit,
                autocorrectionDisabled: autocorrectionDisabled
            )
        }
    }

    private func editorFieldContent(
        prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 1...1,
        autocorrectionDisabled: Bool = false
    ) -> some View {
        TextField(prompt, text: text, axis: axis)
            .font(.overline(.title3, weight: .medium))
            .lineLimit(lineLimit)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(autocorrectionDisabled)
            .padding(.horizontal, 18)
            .padding(.vertical, axis == .vertical ? 14 : 0)
            .frame(
                minHeight: axis == .vertical ? verticalControlHeight(for: lineLimit) : formControlHeight,
                alignment: axis == .vertical ? .topLeading : .leading
            )
            .overlineGlassControl(cornerRadius: formControlCornerRadius)
    }

    private func verticalControlHeight(for lineLimit: ClosedRange<Int>) -> CGFloat {
        lineLimit.lowerBound >= 3 ? 132 : formControlHeight
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
        .accessibilityLabel("책 삭제")
    }

    private func loadBook() {
        guard case .edit(let bookID) = mode, let book = library.book(with: bookID) else { return }
        title = book.title
        author = book.author
        summary = book.summary
        tagsText = book.tags.joined(separator: " ")
        publisher = book.publisher ?? ""
        publishedDate = book.publishedDate ?? ""
        isbn = book.isbn ?? ""
        coverURLString = book.coverURLString ?? ""
        metadataSource = book.metadataSource ?? .manual
        searchQuery = [book.title, book.author]
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: " ")
    }

    private func save() {
        switch mode {
        case .add:
            library.addBook(
                title: title,
                author: author,
                summary: summary,
                tagsText: tagsText,
                publisher: publisher,
                publishedDate: publishedDate,
                isbn: isbn,
                coverURLString: coverURLString,
                metadataSource: metadataSource
            )
        case .edit(let bookID):
            library.updateBook(
                bookID,
                title: title,
                author: author,
                summary: summary,
                tagsText: tagsText,
                publisher: publisher,
                publishedDate: publishedDate,
                isbn: isbn,
                coverURLString: coverURLString,
                metadataSource: metadataSource
            )
        }

        dismiss()
    }

    @MainActor
    private func searchBooks(autoApplyFirstResult: Bool = false) async {
        guard !searchQuery.trimmed.isEmpty else { return }

        isSearching = true
        searchErrorMessage = nil
        defer {
            isSearching = false
        }

        do {
            let result = try await BookMetadataSearchClient().search(query: searchQuery)
            let results = result.candidates

            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                searchResults = results
            }

            if results.isEmpty {
                searchErrorMessage = "검색 결과가 없습니다."
            } else {
                if autoApplyFirstResult, let firstResult = results.first {
                    apply(firstResult)
                }

                if let sourceTitle = results.first?.sourceTitle {
                    MVPReadinessStore.markVerified(.kakaoSearch, detail: "\(sourceTitle) 도서 검색 성공")
                }
            }
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchErrorMessage = error.localizedDescription
        }
    }

    private func apply(_ result: BookMetadataCandidate) {
        title = result.title
        author = result.author.isEmpty ? "Unknown" : result.author
        summary = result.summary.isEmpty ? summary : result.summary
        publisher = result.publisher
        publishedDate = result.publishedDate
        isbn = result.isbn
        coverURLString = result.coverURLString
        metadataSource = result.source
    }

    private func applyScannedISBN(_ scannedISBN: String, didScanBarcode: Bool) {
        let cleanISBN = scannedISBN.filter(\.isNumber)
        guard cleanISBN.count >= 10 else { return }

        searchQuery = cleanISBN
        isbn = cleanISBN
        if didScanBarcode {
            MVPReadinessStore.markVerified(
                .isbnScan,
                detail: "\(cleanISBN.count)자리 ISBN 바코드 인식"
            )
        }

        Task {
            await searchBooks(autoApplyFirstResult: true)
        }
    }

    private func delete() {
        guard case .edit(let bookID) = mode else { return }
        library.deleteBook(bookID)
        dismiss()
    }
}

private struct BookSearchResultRow: View {
    let result: BookMetadataCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sourceSystemImage)
                .font(.overline(.title3, weight: .semibold))
                .foregroundStyle(Color.overlineAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.overline(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(2)

                Text(result.author.isEmpty ? result.publisher : result.author)
                    .font(.overline(.caption))
                    .foregroundStyle(Color.overlineMutedInk)
                    .lineLimit(1)

                Text([result.publishedDate, result.sourceTitle].filter { !$0.trimmed.isEmpty }.joined(separator: " · "))
                    .font(.overline(.caption2, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.68))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var sourceSystemImage: String {
        switch result.source {
        case .manual:
            "book.closed"
        case .kakao:
            "k.circle"
        case .aladin:
            "a.circle"
        case .google:
            "g.circle"
        }
    }
}

struct AddBookSheet: View {
    var body: some View {
        BookEditorSheet(mode: .add)
    }
}

#Preview {
    AddBookSheet()
        .environment(ReadingLibrary.preview)
}
