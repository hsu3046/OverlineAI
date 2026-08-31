import SwiftUI

struct LibraryView: View {
    @Environment(ReadingLibrary.self) private var library
    @Environment(LLMSettingsStore.self) private var llmSettings
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer
    var rootResetToken = 0
    var isActive = true
    @State private var presentedSheet: LibrarySheet?
    @State private var activeBookID: ReadingBook.ID?
    @State private var pendingDeletedHighlight: PendingHighlightUndo?
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
        List {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SectionHeader(
                        title: "책",
                        systemImage: "books.vertical",
                        trailingText: "\(library.books.count)"
                    )

                    Button {
                        presentedSheet = .addBook
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.78))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("책 추가")

                    OverlineSettingsButton(settings: llmSettings) {
                        presentedSheet = .settings
                    }
                }

                if !library.books.isEmpty {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(library.books) { book in
                                Button {
                                    activeBookID = book.id
                                } label: {
                                    BookCoverCard(book: book)
                                        .containerRelativeFrame(.horizontal, count: 3, spacing: 14)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(book.title) 열기")
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .scrollIndicators(.hidden)
                }

                if library.books.isEmpty {
                    LibraryEmptyStateCard(
                        systemImage: "book.closed",
                        title: "첫 책을 추가하세요",
                        message: "ISBN을 스캔하거나 직접 입력해 캡처할 책을 준비할 수 있습니다.",
                        actionTitle: "책 추가",
                        action: {
                            presentedSheet = .addBook
                        }
                    )
                }
            }
            .listRowChrome(top: 16, bottom: 18)

            HStack(spacing: 10) {
                SectionHeader(
                    title: "최근 글조각",
                    systemImage: "quote.opening"
                )

                if !library.recentHighlights.isEmpty {
                    Button {
                        presentedSheet = .highlightSpeech
                    } label: {
                        Image(systemName: quoteSpeechPlayer.isActive ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                quoteSpeechPlayer.isActive
                                    ? Color.overlineAccent
                                    : Color.overlineMutedInk.opacity(0.72)
                            )
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("글조각 이어듣기")
                }

                if library.highlightCount > displayedHighlights.count {
                    Button {
                        presentedSheet = .highlightBrowser
                    } label: {
                        Image(systemName: "tray.full")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("최근 글조각 모두 보기")
                }
            }
            .listRowChrome(top: 10, bottom: 8)

            ForEach(Array(displayedHighlights.enumerated()), id: \.element.id) { index, highlight in
                if pendingDeletedHighlight?.visibleIndex == index {
                    OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                        .listRowChrome(top: 0, bottom: 12)
                }

                let book = book(for: highlight)
                ScrapbookCard(
                    highlight: highlight,
                    book: book,
                    edit: {
                        presentedSheet = .editHighlight(highlight.id)
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteHighlight(highlight)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .listRowChrome(top: 0, bottom: 12)
            }

            if let pendingDeletedHighlight, pendingDeletedHighlight.visibleIndex >= displayedHighlights.count {
                OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                    .listRowChrome(top: 0, bottom: 12)
            }

            if library.recentHighlights.isEmpty && pendingDeletedHighlight == nil {
                LibraryEmptyStateCard(
                    systemImage: "text.viewfinder",
                    title: "아직 글조각이 없습니다",
                    message: "캡처 탭에서 문장 위를 쓸어 저장하면 이곳에 모입니다.",
                    actionTitle: nil,
                    action: nil
                )
                .listRowChrome(top: 0, bottom: 16)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .overlineBottomMenuCompaction()
        .navigationDestination(isPresented: isBookNavigationPresented) {
            if let activeBookID {
                ScrapbookView(bookID: activeBookID)
            } else {
                EmptyView()
            }
        }
        .onChange(of: rootResetToken) { _, _ in
            clearPendingUndo(animated: false)
            activeBookID = nil
        }
        .onDisappear {
            clearPendingUndo(animated: false)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addBook:
                BookEditorSheet(mode: .add)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .editBook(let bookID):
                BookEditorSheet(mode: .edit(bookID))
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .editHighlight(let highlightID):
                HighlightEditorSheet(highlightID: highlightID) { highlightID in
                    deleteHighlight(highlightID)
                }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .highlightBrowser:
                HighlightBrowserSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .highlightSpeech:
                HighlightSpeechSelectionSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .settings:
                OverlineSettingsSheet(settings: llmSettings)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var displayedHighlights: [Highlight] {
        return Array(library.recentHighlights.prefix(10))
    }

    private func book(for highlight: Highlight) -> ReadingBook? {
        guard
            let bookID = library.bookID(containing: highlight.id),
            let book = library.book(with: bookID)
        else {
            return nil
        }
        return book
    }

    private var isBookNavigationPresented: Binding<Bool> {
        Binding(
            get: { activeBookID != nil },
            set: { isActive in
                if !isActive {
                    activeBookID = nil
                }
            }
        )
    }

    private func deleteHighlight(_ highlight: Highlight) {
        deleteHighlight(highlight.id)
    }

    private func deleteHighlight(_ highlightID: Highlight.ID) {
        let visibleIndex = displayedHighlights.firstIndex { $0.id == highlightID } ?? 0

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            if let deletion = library.deleteHighlightForUndo(highlightID) {
                let pendingUndo = PendingHighlightUndo(deletion: deletion, visibleIndex: visibleIndex)
                pendingDeletedHighlight = pendingUndo
                scheduleUndoDismiss(for: pendingUndo.id)
            }
        }
    }

    private func restoreDeletedHighlight() {
        guard let pendingDeletedHighlight else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            library.restoreDeletedHighlight(pendingDeletedHighlight.deletion)
            clearPendingUndo(animated: false)
        }
    }

    private func scheduleUndoDismiss(for undoID: UUID) {
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard pendingDeletedHighlight?.id == undoID else { return }
                clearPendingUndo(animated: true)
            }
        }
    }

    private func clearPendingUndo(animated: Bool) {
        undoDismissTask?.cancel()
        undoDismissTask = nil

        guard pendingDeletedHighlight != nil else { return }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                pendingDeletedHighlight = nil
            }
        } else {
            pendingDeletedHighlight = nil
        }
    }
}

private struct LibraryEmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.overline(.title3, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.overlineAccent)

            Text(title)
                .font(.overline(.headline, weight: .semibold))
                .foregroundStyle(Color.overlineInk)

            Text(message)
                .font(.overline(.subheadline))
                .foregroundStyle(Color.overlineMutedInk)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.overline(.subheadline, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineInk.opacity(0.08), lineWidth: 1)
        }
    }
}

private extension View {
    func listRowChrome(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private enum LibrarySheet: Identifiable {
    case addBook
    case editBook(ReadingBook.ID)
    case editHighlight(Highlight.ID)
    case highlightBrowser
    case highlightSpeech
    case settings

    var id: String {
        switch self {
        case .addBook: "addBook"
        case .editBook(let id): "editBook-\(id.uuidString)"
        case .editHighlight(let id): "editHighlight-\(id.uuidString)"
        case .highlightBrowser: "highlightBrowser"
        case .highlightSpeech: "highlightSpeech"
        case .settings: "settings"
        }
    }
}

private enum HighlightSpeechScope: String, CaseIterable, Identifiable {
    case recent
    case book

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "최근"
        case .book: "책별"
        }
    }
}

private struct HighlightSpeechSelectionSheet: View {
    private static let maximumSelectionCount = 30

    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer
    @State private var scope: HighlightSpeechScope = .recent
    @State private var selectedBookID: ReadingBook.ID?
    @State private var selectedHighlightIDs: Set<Highlight.ID> = []
    @State private var isBookPickerPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if quoteSpeechPlayer.isActive {
                    activePlaybackBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Picker("선택 범위", selection: $scope) {
                    ForEach(HighlightSpeechScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, quoteSpeechPlayer.isActive ? 10 : 14)

                if scope == .book, !library.books.isEmpty {
                    OverlineBookSelectorButton(
                        title: selectedBookTitle,
                        subtitle: "최근 \(candidateHighlights.count)조각",
                        systemImage: "book.closed",
                        height: 50,
                        cornerRadius: 25,
                        titleFont: .subheadline.weight(.semibold),
                        subtitleFont: .caption2.weight(.semibold)
                    ) {
                        isBookPickerPresented = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                HStack(spacing: 12) {
                    Text("최대 \(Self.maximumSelectionCount)개")
                        .font(.overline(.caption, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))

                    Spacer()

                    Button(allCandidatesAreSelected ? "선택 해제" : "모두 선택") {
                        toggleAllCandidates()
                    }
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)
                    .disabled(candidateHighlights.isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 6)

                List {
                    ForEach(candidateHighlights) { highlight in
                        HighlightSpeechSelectionRow(
                            highlight: highlight,
                            bookTitle: bookTitle(for: highlight),
                            isSelected: selectedHighlightIDs.contains(highlight.id)
                        ) {
                            toggleSelection(of: highlight)
                        }
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                    }

                    if candidateHighlights.isEmpty {
                        ContentUnavailableView(
                            "읽을 글조각이 없습니다",
                            systemImage: "speaker.slash",
                            description: Text("다른 책을 선택해 보세요.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: beginPlayback) {
                    Label("\(selectedHighlightIDs.count)개 이어듣기", systemImage: "play.fill")
                        .font(.overline(.headline, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(selectedHighlightIDs.isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("글조각 이어듣기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    OverlineDoneToolbarButton {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isBookPickerPresented) {
                OverlineBookPickerSheet(
                    title: "책 선택",
                    books: library.books,
                    selectedBookID: selectedBookID,
                    onSelect: { bookID in
                        selectedBookID = bookID
                    }
                )
                .presentationDetents([.height(bookPickerSheetHeight), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thinMaterial)
            }
            .onAppear {
                prepareInitialSelection()
            }
            .onChange(of: scope) { _, _ in
                selectedHighlightIDs.removeAll()
                if scope == .book, selectedBookID == nil {
                    selectedBookID = mostRecentBookID ?? library.books.first?.id
                }
            }
            .onChange(of: selectedBookID) { _, _ in
                guard scope == .book else { return }
                selectedHighlightIDs.removeAll()
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private var activePlaybackBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.overlineAccent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(quoteSpeechPlayer.currentPlaylistItem?.bookTitle ?? "글조각 이어듣기")
                    .font(.overline(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(1)
                Text("\(quoteSpeechPlayer.playlistIndex + 1)/\(max(quoteSpeechPlayer.playlist.count, 1))")
                    .font(.overline(.caption2, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk)
            }

            Spacer()

            Button {
                quoteSpeechPlayer.togglePause()
            } label: {
                Image(systemName: quoteSpeechPlayer.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(quoteSpeechPlayer.isPaused ? "이어듣기 재생" : "이어듣기 일시정지")

            Button {
                quoteSpeechPlayer.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이어듣기 중지")
        }
        .foregroundStyle(Color.overlineAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color.overlineAccent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var candidateHighlights: [Highlight] {
        switch scope {
        case .recent:
            return Array(library.recentHighlights.prefix(Self.maximumSelectionCount))
        case .book:
            guard let selectedBookID else { return [] }
            return Array(
                library.recentHighlights
                    .filter { library.bookID(containing: $0.id) == selectedBookID }
                    .prefix(Self.maximumSelectionCount)
            )
        }
    }

    private var allCandidatesAreSelected: Bool {
        !candidateHighlights.isEmpty
            && candidateHighlights.allSatisfy { selectedHighlightIDs.contains($0.id) }
    }

    private var selectedBookTitle: String {
        guard let selectedBookID else { return "책 선택" }
        return library.book(with: selectedBookID)?.title ?? "책 선택"
    }

    private var mostRecentBookID: ReadingBook.ID? {
        library.recentHighlights.first.flatMap { library.bookID(containing: $0.id) }
    }

    private var bookPickerSheetHeight: CGFloat {
        OverlineBookPickerMetrics.sheetHeight(bookCount: library.books.count)
    }

    private func prepareInitialSelection() {
        selectedBookID = mostRecentBookID ?? library.books.first?.id
        let candidateIDs = Set(candidateHighlights.map(\.id))
        selectedHighlightIDs = Set(quoteSpeechPlayer.playlist.map(\.id))
            .intersection(candidateIDs)
    }

    private func toggleSelection(of highlight: Highlight) {
        if selectedHighlightIDs.contains(highlight.id) {
            selectedHighlightIDs.remove(highlight.id)
        } else if selectedHighlightIDs.count < Self.maximumSelectionCount {
            selectedHighlightIDs.insert(highlight.id)
        }
    }

    private func toggleAllCandidates() {
        if allCandidatesAreSelected {
            selectedHighlightIDs.removeAll()
        } else {
            selectedHighlightIDs = Set(candidateHighlights.map(\.id))
        }
    }

    private func beginPlayback() {
        let items = playbackHighlights.map { highlight in
            QuoteSpeechPlaylistItem(
                highlight: highlight,
                bookTitle: bookTitle(for: highlight)
            )
        }
        quoteSpeechPlayer.play(items)
        dismiss()
    }

    private var playbackHighlights: [Highlight] {
        let selected = candidateHighlights.filter { selectedHighlightIDs.contains($0.id) }
        switch scope {
        case .recent:
            return Array(selected.reversed())
        case .book:
            return selected.sorted(by: bookPlaybackOrder)
        }
    }

    private func bookPlaybackOrder(_ lhs: Highlight, _ rhs: Highlight) -> Bool {
        let lhsPage = pageNumber(in: lhs.pageReference)
        let rhsPage = pageNumber(in: rhs.pageReference)

        switch (lhsPage, rhsPage) {
        case let (.some(lhsPage), .some(rhsPage)) where lhsPage != rhsPage:
            return lhsPage < rhsPage
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func pageNumber(in pageReference: String) -> Int? {
        pageReference
            .split(whereSeparator: { !$0.isNumber })
            .first
            .flatMap { Int($0) }
    }

    private func bookTitle(for highlight: Highlight) -> String? {
        guard let bookID = library.bookID(containing: highlight.id) else { return nil }
        return library.book(with: bookID)?.title
    }
}

private struct HighlightSpeechSelectionRow: View {
    let highlight: Highlight
    let bookTitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.54))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(highlight.text)
                        .font(.overline(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.overlineInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !metadataText.isEmpty {
                        Text(metadataText)
                            .font(.overline(.caption2, weight: .semibold))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.76))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isSelected ? "선택됨" : "선택 안 됨"), \(highlight.text)")
    }

    private var metadataText: String {
        [bookTitle, highlight.pageReference]
            .compactMap { $0?.trimmed.nilIfEmpty }
            .joined(separator: " · ")
    }
}

private struct HighlightBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library
    @State private var searchText = ""
    @State private var selectedBookID: ReadingBook.ID?
    @State private var isBookFilterPresented = false
    @State private var presentedHighlight: HighlightEditorPresentation?
    @State private var pendingDeletedHighlight: PendingHighlightUndo?
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
        let visibleHighlights = filteredHighlights

        NavigationStack {
            VStack(spacing: 0) {
                if !library.recentHighlights.isEmpty {
                    VStack(spacing: 10) {
                        if !library.books.isEmpty {
                            OverlineBookSelectorButton(
                                title: selectedBookFilterTitle,
                                subtitle: "\(visibleHighlights.count)조각",
                                systemImage: selectedBookID == nil ? "tray.full" : "book.closed",
                                height: 52,
                                cornerRadius: 26,
                                titleFont: .subheadline.weight(.semibold),
                                subtitleFont: .caption2.weight(.semibold)
                            ) {
                                isBookFilterPresented = true
                            }
                        }

                        OverlinePillSearchField(text: $searchText, prompt: "글조각, 태그, 책 검색")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }

                List {
                    ForEach(Array(visibleHighlights.enumerated()), id: \.element.id) { index, highlight in
                        if pendingDeletedHighlight?.visibleIndex == index {
                            OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                                .listRowChrome(top: 0, bottom: 12)
                        }

                        let book = book(for: highlight)
                        ScrapbookCard(
                            highlight: highlight,
                            book: book,
                            searchQuery: searchText,
                            edit: {
                                presentedHighlight = HighlightEditorPresentation(id: highlight.id)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteHighlight(highlight)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .listRowChrome(top: 0, bottom: 12)
                    }

                    if let pendingDeletedHighlight, pendingDeletedHighlight.visibleIndex >= visibleHighlights.count {
                        OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                            .listRowChrome(top: 0, bottom: 12)
                    }

                    if visibleHighlights.isEmpty && pendingDeletedHighlight == nil {
                        ContentUnavailableView(
                            searchText.trimmed.isEmpty ? "글조각 없음" : "검색 결과 없음",
                            systemImage: "text.viewfinder",
                            description: Text(searchText.trimmed.isEmpty ? "캡처한 글조각이 여기에 모입니다." : "다른 단어, 태그, 책 이름으로 찾아보세요.")
                        )
                        .listRowChrome(top: 24, bottom: 24)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("글조각")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    OverlineDoneToolbarButton {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isBookFilterPresented) {
                OverlineBookPickerSheet(
                    title: "책 선택",
                    books: library.books,
                    selectedBookID: selectedBookID,
                    includesAllOption: true,
                    allTitle: "전체",
                    allCount: library.highlightCount,
                    onSelect: { bookID in
                        selectedBookID = bookID
                    }
                )
                .presentationDetents([.height(bookFilterSheetHeight), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thinMaterial)
            }
            .sheet(item: $presentedHighlight) { presentation in
                HighlightEditorSheet(highlightID: presentation.id) { highlightID in
                    deleteHighlight(highlightID)
                }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .overlineKeyboardDismissToolbar()
        }
        .presentationBackground(.thinMaterial)
        .onDisappear {
            clearPendingUndo(animated: false)
        }
    }

    private var selectedBookFilterTitle: String {
        guard let selectedBookID else { return "전체" }
        return library.book(with: selectedBookID)?.title ?? "전체"
    }

    private func book(for highlight: Highlight) -> ReadingBook? {
        guard
            let bookID = library.bookID(containing: highlight.id),
            let book = library.book(with: bookID)
        else {
            return nil
        }
        return book
    }

    private var bookFilterSheetHeight: CGFloat {
        OverlineBookPickerMetrics.sheetHeight(bookCount: library.books.count, includesAllOption: true)
    }

    private var filteredHighlights: [Highlight] {
        library.recentHighlights.filter { highlight in
            let matchesBook = selectedBookID.map { library.bookID(containing: highlight.id) == $0 } ?? true
            guard matchesBook else { return false }

            let query = searchText.trimmed
            guard !query.isEmpty else { return true }

            let book = library.bookID(containing: highlight.id).flatMap { library.book(with: $0) }
            let searchableText = [
                highlight.text,
                highlight.memo,
                highlight.pageReference,
                highlight.tags.joined(separator: " "),
                book?.title ?? "",
                book?.author ?? ""
            ]
            .joined(separator: " ")

            return searchableText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func deleteHighlight(_ highlight: Highlight) {
        deleteHighlight(highlight.id)
    }

    private func deleteHighlight(_ highlightID: Highlight.ID) {
        let visibleIndex = filteredHighlights.firstIndex { $0.id == highlightID } ?? 0

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            if let deletion = library.deleteHighlightForUndo(highlightID) {
                let pendingUndo = PendingHighlightUndo(deletion: deletion, visibleIndex: visibleIndex)
                pendingDeletedHighlight = pendingUndo
                scheduleUndoDismiss(for: pendingUndo.id)
            }
        }
    }

    private func restoreDeletedHighlight() {
        guard let pendingDeletedHighlight else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            library.restoreDeletedHighlight(pendingDeletedHighlight.deletion)
            clearPendingUndo(animated: false)
        }
    }

    private func scheduleUndoDismiss(for undoID: UUID) {
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard pendingDeletedHighlight?.id == undoID else { return }
                clearPendingUndo(animated: true)
            }
        }
    }

    private func clearPendingUndo(animated: Bool) {
        undoDismissTask?.cancel()
        undoDismissTask = nil

        guard pendingDeletedHighlight != nil else { return }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                pendingDeletedHighlight = nil
            }
        } else {
            pendingDeletedHighlight = nil
        }
    }
}

private struct PendingHighlightUndo: Identifiable {
    let deletion: DeletedHighlightSnapshot
    let visibleIndex: Int

    var id: UUID {
        deletion.id
    }
}

private struct HighlightEditorPresentation: Identifiable {
    let id: Highlight.ID
}

private struct BookCoverCard: View {
    let book: ReadingBook

    var body: some View {
        BookCoverArtwork(book: book, cornerRadius: 8)
            .aspectRatio(0.72, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Text("\(book.highlights.count)")
                    .font(.overline(.caption, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.28), in: Capsule())
                    .padding(10)
            }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct HighlightRow: View {
    let highlight: Highlight
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(highlight.stickyTone.paper)
                    .frame(width: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(highlight.text)
                        .font(.overline(.body, weight: .medium))
                        .foregroundStyle(Color.overlineInk)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if let pageReference = highlight.visiblePageReference {
                            Text(pageReference)
                        }
                        ForEach(highlight.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                        }
                        Text(highlight.createdAt.overlineShortDate)
                    }
                    .font(.overline(.caption))
                    .foregroundStyle(Color.overlineMutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("글조각 상세")
        .padding(14)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineInk.opacity(0.08), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScrapbookView: View {
    @Environment(ReadingLibrary.self) private var library
    let bookID: ReadingBook.ID
    @State private var presentedSheet: ScrapbookSheet?
    @State private var searchText = ""
    @State private var pendingDeletedHighlight: PendingHighlightUndo?
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let book = library.book(with: bookID) {
                List {
                    ScrapbookHeader(book: book) {
                        presentedSheet = .editBook(book.id)
                    }
                    .listRowChrome(top: 16, bottom: 18)

                    ReadingRecordSection(
                        book: book,
                        addRecord: {
                            presentedSheet = .editReadingRecord(book.id, nil)
                        },
                        editRecord: { recordID in
                            presentedSheet = .editReadingRecord(book.id, recordID)
                        },
                        showHistory: {
                            presentedSheet = .readingRecordHistory(book.id)
                        }
                    )
                    .listRowChrome(top: 0, bottom: 16)

                    if !book.highlights.isEmpty {
                        Rectangle()
                            .fill(Color.overlineInk.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                            .listRowChrome(top: 0, bottom: 18)

                        OverlinePillSearchField(text: $searchText, prompt: "글조각, 태그, 메모 검색")
                            .listRowChrome(top: 0, bottom: 12)
                    }

                    let highlights = filteredHighlights(in: book)
                    ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                        if pendingDeletedHighlight?.visibleIndex == index {
                            OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                                .listRowChrome(top: 0, bottom: 12)
                        }

                        ScrapbookCard(
                            highlight: highlight,
                            shareBookTitle: book.title,
                            searchQuery: searchText,
                            edit: {
                                presentedSheet = .editHighlight(highlight.id)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteHighlight(highlight)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .listRowChrome(top: 0, bottom: 12)
                    }

                    if let pendingDeletedHighlight, pendingDeletedHighlight.visibleIndex >= highlights.count {
                        OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                            .listRowChrome(top: 0, bottom: 12)
                    }

                    if highlights.isEmpty && pendingDeletedHighlight == nil {
                        Group {
                            if book.highlights.isEmpty {
                                ContentUnavailableView(
                                    "아직 글조각이 없습니다",
                                    systemImage: "text.quote",
                                    description: Text("캡처 탭에서 간직하고 싶은 문장을 저장해 보세요.")
                                )
                            } else {
                                ContentUnavailableView(
                                    "검색 결과 없음",
                                    systemImage: "magnifyingglass",
                                    description: Text("다른 글조각, 태그, 메모로 찾아보세요.")
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowChrome(top: 0, bottom: 16)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .overlineBottomMenuCompaction()
                .navigationTitle(book.title)
                .sheet(item: $presentedSheet) { sheet in
                    switch sheet {
                    case .editBook(let bookID):
                        BookEditorSheet(mode: .edit(bookID))
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    case .editHighlight(let highlightID):
                        HighlightEditorSheet(highlightID: highlightID) { highlightID in
                            deleteHighlight(highlightID)
                        }
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    case .readingRecordHistory(let bookID):
                        ReadingRecordHistorySheet(bookID: bookID)
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    case .editReadingRecord(let bookID, let recordID):
                        ReadingRecordEditorSheet(bookID: bookID, recordID: recordID)
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    }
                }
            } else {
                ContentUnavailableView("책을 찾을 수 없음", systemImage: "books.vertical")
            }
        }
        .onDisappear {
            clearPendingUndo(animated: false)
        }
    }

    private func filteredHighlights(in book: ReadingBook) -> [Highlight] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return book.highlights }

        return book.highlights.filter { highlight in
            [
                highlight.text,
                highlight.memo,
                highlight.pageReference,
                highlight.tags.joined(separator: " ")
            ]
            .joined(separator: " ")
            .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func deleteHighlight(_ highlight: Highlight) {
        deleteHighlight(highlight.id)
    }

    private func deleteHighlight(_ highlightID: Highlight.ID) {
        let visibleIndex = library.book(with: bookID).map { book in
            filteredHighlights(in: book).firstIndex { $0.id == highlightID } ?? 0
        } ?? 0

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            if let deletion = library.deleteHighlightForUndo(highlightID) {
                let pendingUndo = PendingHighlightUndo(deletion: deletion, visibleIndex: visibleIndex)
                pendingDeletedHighlight = pendingUndo
                scheduleUndoDismiss(for: pendingUndo.id)
            }
        }
    }

    private func restoreDeletedHighlight() {
        guard let pendingDeletedHighlight else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            library.restoreDeletedHighlight(pendingDeletedHighlight.deletion)
            clearPendingUndo(animated: false)
        }
    }

    private func scheduleUndoDismiss(for undoID: UUID) {
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard pendingDeletedHighlight?.id == undoID else { return }
                clearPendingUndo(animated: true)
            }
        }
    }

    private func clearPendingUndo(animated: Bool) {
        undoDismissTask?.cancel()
        undoDismissTask = nil

        guard pendingDeletedHighlight != nil else { return }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                pendingDeletedHighlight = nil
            }
        } else {
            pendingDeletedHighlight = nil
        }
    }
}

private enum ScrapbookSheet: Identifiable {
    case editBook(ReadingBook.ID)
    case editHighlight(Highlight.ID)
    case readingRecordHistory(ReadingBook.ID)
    case editReadingRecord(ReadingBook.ID, ReadingRecord.ID?)

    var id: String {
        switch self {
        case .editBook(let id): "editBook-\(id.uuidString)"
        case .editHighlight(let id): "editHighlight-\(id.uuidString)"
        case .readingRecordHistory(let id): "readingRecordHistory-\(id.uuidString)"
        case .editReadingRecord(let bookID, let recordID):
            "editReadingRecord-\(bookID.uuidString)-\(recordID?.uuidString ?? "new")"
        }
    }
}

private struct ScrapbookHeader: View {
    let book: ReadingBook
    var edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                bookCover
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture(perform: edit)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("책 편집")

                VStack(alignment: .leading, spacing: 5) {
                    bookInfo
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: edit)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("책 편집")

                    HStack(alignment: .center, spacing: 10) {
                        if !bookTagText.isEmpty {
                            BookMetaLine(systemImage: "tag", text: bookTagText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                        OverlineShareButton(item: book.shareText, accessibilityLabel: "책 공유")
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !book.summary.trimmed.isEmpty {
                Text(book.summary)
                    .font(.overline(size: 15, relativeTo: .subheadline, weight: .medium))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private var bookCover: some View {
        BookCoverArtwork(book: book, cornerRadius: 10)
            .frame(width: 88, height: 124)
    }

    private var bookTagText: String {
        book.tags
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var bookInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookMetaLine(systemImage: "book.closed", text: book.title, lineLimit: 2)
            BookMetaLine(systemImage: "person.crop.circle", text: book.author)
            if let publishedDate = book.publishedDate, !publishedDate.trimmed.isEmpty {
                BookMetaLine(systemImage: "calendar", text: publishedDate)
            }
        }
        .padding(.top, 6)
    }
}

private struct BookCoverArtwork: View {
    let book: ReadingBook
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(book.coverTheme.gradient)
            .overlay {
                if let coverURL = book.coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFill()
                        case .failure:
                            book.coverTheme.gradient
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                        @unknown default:
                            book.coverTheme.gradient
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct ScrapbookMemoNote: View {
    let memo: String
    let tone: StickyTone
    var searchQuery = ""

    var body: some View {
        SearchHighlightedText(
            text: memo,
            query: searchQuery,
            font: .overline(.subheadline),
            foregroundStyle: Color.overlineInk.opacity(0.82),
            lineSpacing: 4
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.paper.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tone.paper.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct BookMetaLine: View {
    let systemImage: String
    let text: String
    var lineLimit = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 18)
                .foregroundStyle(Color.overlineAccent)

            Text(text)
                .font(.overline(size: 15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScrapbookCard: View {
    let highlight: Highlight
    var book: ReadingBook? = nil
    var shareBookTitle: String? = nil
    var searchQuery = ""
    var edit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                if let bookTitle = visibleBookTitle {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.overline(.caption, weight: .bold))
                            .symbolRenderingMode(.hierarchical)

                        SearchHighlightedText(
                            text: bookTitle,
                            query: searchQuery,
                            font: .overline(.caption, weight: .semibold),
                            foregroundStyle: Color.overlineMutedInk.opacity(0.76),
                            lineSpacing: 0
                        )
                        .lineLimit(1)
                    }
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(highlight.stickyTone.paper.opacity(0.94))
                        .frame(width: 6)

                    SearchHighlightedText(
                        text: highlight.text,
                        query: searchQuery,
                        font: .overline(.body, weight: .semibold),
                        foregroundStyle: Color.overlineInk,
                        lineSpacing: 5
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !highlight.memo.isEmpty {
                    ScrapbookMemoNote(
                        memo: highlight.memo,
                        tone: highlight.stickyTone,
                        searchQuery: searchQuery
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            HStack(alignment: .center, spacing: 10) {
                HighlightMetaBar(highlight: highlight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    QuoteSpeechButton(highlight: highlight, bookTitle: book?.title)
                    OverlineShareButton(
                        item: highlight.shareText(bookTitle: shareBookTitle ?? book?.title),
                        accessibilityLabel: "공유",
                        iconYOffset: -2,
                        controlSize: CGSize(width: 36, height: 32)
                    )
                }
            }
            .frame(minHeight: 32, alignment: .center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let book {
                ScrapbookCoverBackdrop(book: book, cornerRadius: 18)
            }
        }
        .libraryCardSurface(
            cornerRadius: 18,
            fillOpacity: book == nil ? 0.54 : 0.08,
            strokeOpacity: 0.34
        )
    }

    private var visibleBookTitle: String? {
        guard let title = book?.title.trimmed, !title.isEmpty else {
            return nil
        }
        return title
    }
}

private struct ScrapbookCoverBackdrop: View {
    let book: ReadingBook
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                book.coverTheme.gradient
                    .opacity(0.22)

                if let coverURL = book.coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        case .failure, .empty:
                            Color.clear
                        @unknown default:
                            Color.clear
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(0.26)
                }

                Color.white.opacity(0.78)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct QuoteSpeechButton: View {
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer
    let highlight: Highlight
    let bookTitle: String?

    private var isSpeaking: Bool {
        quoteSpeechPlayer.isSpeaking(highlight.id)
    }

    var body: some View {
        Button {
            quoteSpeechPlayer.toggle(highlight, bookTitle: bookTitle)
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    isSpeaking
                        ? Color.overlineAccent
                        : Color.overlineMutedInk.opacity(0.46)
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeaking ? "글조각 낭독 중지" : "글조각 듣기")
    }
}

private extension View {
    func libraryCardSurface(
        cornerRadius: CGFloat,
        fillOpacity: Double,
        strokeOpacity: Double
    ) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            }
    }
}

private struct OverlineShareButton: View {
    let item: String
    let accessibilityLabel: String
    var iconYOffset: CGFloat = 0
    var controlSize = CGSize(width: 30, height: 26)

    var body: some View {
        ShareLink(item: item) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.overlineMutedInk.opacity(0.46))
                .offset(y: iconYOffset)
                .frame(width: controlSize.width, height: controlSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private extension Highlight {
    var visiblePageReference: String? {
        let value = pageReference.trimmed
        guard !value.isEmpty else { return nil }

        switch value.lowercased() {
        case "camera", "photo", "gallery", "mock":
            return nil
        default:
            return value
        }
    }

    var visibleTagText: String {
        tags
            .prefix(3)
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: " ")
    }

    func shareText(bookTitle: String?) -> String {
        let title = bookTitle?.trimmed ?? ""
        let page = visiblePageReference ?? ""
        let sourceLine: String

        if !title.isEmpty && !page.isEmpty {
            sourceLine = "\(title) \(page)"
        } else if !title.isEmpty {
            sourceLine = title
        } else {
            sourceLine = page
        }

        return [
            text,
            sourceLine,
            tags.joined(separator: " ")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}

private extension ReadingBook {
    var coverURL: URL? {
        guard
            let coverURLString,
            let url = URL(string: coverURLString)
        else {
            return nil
        }

        return url
    }

    var shareText: String {
        let sortedReadingRecords = readingRecords.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt < rhs.startedAt
            }
            return lhs.createdAt < rhs.createdAt
        }
        let readingRecordText = sortedReadingRecords.enumerated().map { index, record in
            let heading = sortedReadingRecords.count > 1 ? "독서 기록 \(index + 1)" : "독서 기록"
            var lines = [
                heading,
                "독서 날짜: \(readingRecordShareDateRange(for: record))"
            ]

            if let rating = record.rating {
                lines.append("별점: \(rating.formatted(.number.precision(.fractionLength(1))))점")
            }

            let review = record.review.trimmed
            if !review.isEmpty {
                lines.append("감상문: \(review)")
            }

            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")

        let highlightText = highlights.enumerated().map { index, highlight in
            var lines = [
                "\(index + 1). \(highlight.text)",
                highlight.visiblePageReference,
                highlight.tags.joined(separator: " ")
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

            if !highlight.memo.isEmpty {
                lines.append("메모: \(highlight.memo)")
            }

            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")

        return [
            title,
            author,
            readingRecordText,
            highlightText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}

private func readingRecordShareDateRange(for record: ReadingRecord) -> String {
    let start = readingRecordShareDateFormatter.string(from: record.startedAt)
    guard let endedAt = record.endedAt else { return start }
    let end = readingRecordShareDateFormatter.string(from: endedAt)
    return start == end ? start : "\(start) - \(end)"
}

private let readingRecordShareDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy. M. d."
    return formatter
}()

private struct HighlighterStroke: View {
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.overlineHighlight.opacity(0.42))
                .frame(height: 11)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(height: 3)
                .padding(.horizontal, 8)
                .offset(y: -3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blur(radius: 0.15)
    }
}

private struct HighlightMetaBar: View {
    let highlight: Highlight

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                if let pageReference = highlight.visiblePageReference {
                    HighlightMetaItem(systemImage: "book.pages", text: pageReference)
                }
                if !highlight.visibleTagText.isEmpty {
                    HighlightMetaItem(systemImage: "tag", text: highlight.visibleTagText)
                }
                HighlightMetaItem(systemImage: "calendar", text: highlight.createdAt.overlineShortDate)
                if highlight.reviewedAt != nil {
                    HighlightMetaItem(systemImage: "checkmark.seal", text: "검수")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    if let pageReference = highlight.visiblePageReference {
                        HighlightMetaItem(systemImage: "book.pages", text: pageReference)
                    }
                    if !highlight.visibleTagText.isEmpty {
                        HighlightMetaItem(systemImage: "tag", text: highlight.visibleTagText)
                    }
                }
                HStack(spacing: 10) {
                    HighlightMetaItem(systemImage: "calendar", text: highlight.createdAt.overlineShortDate)
                    if highlight.reviewedAt != nil {
                        HighlightMetaItem(systemImage: "checkmark.seal", text: "검수")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
    }
}

private struct HighlightMetaItem: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.overline(.caption2, weight: .bold))
                .frame(width: 12)
            Text(text)
                .font(.overline(.caption2, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(height: 18, alignment: .center)
        .foregroundStyle(Color.overlineMutedInk)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .navigationTitle("책장")
    }
    .environment(ReadingLibrary.preview)
    .environment(QuoteSpeechPlayer())
    .environment(LLMSettingsStore())
}
