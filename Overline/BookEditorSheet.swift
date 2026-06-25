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
    @State private var publisher = ""
    @State private var isbn = ""
    @State private var coverURLString = ""
    @State private var metadataSource: BookMetadataSource = .manual
    @State private var searchQuery = ""
    @State private var kakaoRESTAPIKey = BookMetadataAPIKeyStore.kakaoRESTAPIKey()
    @State private var searchResults: [BookMetadataCandidate] = []
    @State private var isSearching = false
    @State private var isTestingKakaoKey = false
    @State private var kakaoKeyTestResult: KakaoKeyTestResult?
    @State private var searchErrorMessage: String?
    @State private var searchInfoMessage: String?
    @State private var isISBNScannerPresented = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("도서 찾기") {
                    Button {
                        isISBNScannerPresented = true
                    } label: {
                        Label("ISBN 스캔", systemImage: "barcode.viewfinder")
                    }
                    .accessibilityLabel("ISBN 바코드 스캔")

                    HStack(spacing: 10) {
                        TextField("제목, 저자, ISBN", text: $searchQuery)
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
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .disabled(searchQuery.trimmed.isEmpty || isSearching)
                        .accessibilityLabel("도서 검색")
                    }

                    SecureField("Kakao REST API 키", text: $kakaoRESTAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()

                    Button {
                        Task {
                            await testKakaoKey()
                        }
                    } label: {
                        HStack {
                            Label("Kakao 연결 확인", systemImage: "network")
                            Spacer()
                            if isTestingKakaoKey {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(kakaoRESTAPIKey.trimmed.isEmpty || isTestingKakaoKey)

                    if kakaoRESTAPIKey.trimmed.isEmpty {
                        Text("Kakao 키가 없으면 Google Books만 fallback으로 검색합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let kakaoKeyTestResult {
                        Label(
                            kakaoKeyTestResult.message,
                            systemImage: kakaoKeyTestResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(kakaoKeyTestResult.isSuccess ? Color.overlineAccent : Color.overlineCoral)
                    }

                    if let searchErrorMessage {
                        Text(searchErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let searchInfoMessage {
                        Text(searchInfoMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(searchResults) { result in
                        Button {
                            apply(result)
                        } label: {
                            BookSearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    TextField("책 이름", text: $title)
                    TextField("저자", text: $author)
                    TextField("책 소개", text: $summary, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("세부 정보") {
                    TextField("출판사", text: $publisher)
                    TextField("ISBN", text: $isbn)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("표지 URL", text: $coverURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if case .edit = mode {
                    Section {
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmed.isEmpty)
                }
            }
            .confirmationDialog("책을 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    delete()
                }
                Button("취소", role: .cancel) {}
            }
            .onAppear {
                loadBook()
            }
            .onChange(of: kakaoRESTAPIKey) { _, key in
                BookMetadataAPIKeyStore.setKakaoRESTAPIKey(key)
                kakaoKeyTestResult = nil
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

    private func loadBook() {
        guard case .edit(let bookID) = mode, let book = library.book(with: bookID) else { return }
        title = book.title
        author = book.author
        summary = book.summary
        publisher = book.publisher ?? ""
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
                publisher: publisher,
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
                publisher: publisher,
                isbn: isbn,
                coverURLString: coverURLString,
                metadataSource: metadataSource
            )
        }

        dismiss()
    }

    @MainActor
    private func searchBooks() async {
        guard !searchQuery.trimmed.isEmpty else { return }

        isSearching = true
        searchErrorMessage = nil
        searchInfoMessage = nil
        defer {
            isSearching = false
        }

        do {
            let result = try await BookMetadataSearchClient().search(
                query: searchQuery,
                kakaoRESTAPIKey: kakaoRESTAPIKey
            )
            let results = result.candidates

            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                searchResults = results
            }

            if results.isEmpty {
                searchErrorMessage = "검색 결과가 없습니다."
                searchInfoMessage = result.infoMessage
            } else {
                searchInfoMessage = result.infoMessage
            }
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchInfoMessage = nil
            searchErrorMessage = error.localizedDescription
        }
    }

    private func apply(_ result: BookMetadataCandidate) {
        title = result.title
        author = result.author.isEmpty ? "Unknown" : result.author
        summary = result.summary.isEmpty ? summary : result.summary
        publisher = result.publisher
        isbn = result.isbn
        coverURLString = result.coverURLString
        metadataSource = result.source
    }

    @MainActor
    private func testKakaoKey() async {
        guard !isTestingKakaoKey else { return }

        isTestingKakaoKey = true
        kakaoKeyTestResult = nil

        do {
            try await BookMetadataSearchClient().testKakaoRESTAPIKey(kakaoRESTAPIKey)
            kakaoKeyTestResult = KakaoKeyTestResult(
                isSuccess: true,
                message: "Kakao 도서 API 연결 확인됨"
            )
            MVPReadinessStore.markVerified(.kakaoSearch, detail: "REST API 연결 테스트 성공")
        } catch {
            kakaoKeyTestResult = KakaoKeyTestResult(
                isSuccess: false,
                message: error.localizedDescription
            )
        }

        isTestingKakaoKey = false
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
            await searchBooks()
        }
    }

    private func delete() {
        guard case .edit(let bookID) = mode else { return }
        library.deleteBook(bookID)
        dismiss()
    }
}

private struct KakaoKeyTestResult {
    let isSuccess: Bool
    let message: String
}

private struct BookSearchResultRow: View {
    let result: BookMetadataCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.source == .kakao ? "k.circle" : "g.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.overlineAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(2)

                Text(result.author.isEmpty ? result.publisher : result.author)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
                    .lineLimit(1)

                Text(result.sourceTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.68))
            }

            Spacer(minLength: 0)

            Image(systemName: "plus.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
