import AVFoundation
import Speech
import SwiftUI
import UIKit

struct LibraryView: View {
    @Environment(ReadingLibrary.self) private var library
    var rootResetToken = 0
    @State private var presentedSheet: LibrarySheet?
    @State private var showsResetConfirmation = false
    @State private var showsRestoreResetConfirmation = false
    @State private var activeBookID: ReadingBook.ID?
    @State private var pendingDeletedHighlight: PendingHighlightUndo?
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
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

                    Menu {
                        Button {
                            presentedSheet = .mvpReadiness
                        } label: {
                            Label("MVP 점검", systemImage: "checkmark.shield")
                        }

                        Button {
                            presentedSheet = .ocrValidation
                        } label: {
                            Label("OCR 검증 기록", systemImage: "checklist.checked")
                        }

                        if library.resetBackupAvailable {
                            Button {
                                showsRestoreResetConfirmation = true
                            } label: {
                                Label("최근 초기화 복구", systemImage: "arrow.uturn.backward.circle")
                            }
                        }

                        Button(role: .destructive) {
                            showsResetConfirmation = true
                        } label: {
                            Label("보관함 초기화", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 19, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("책장 메뉴")
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

                if library.highlightCount > displayedHighlights.count {
                    Button {
                        presentedSheet = .highlightBrowser
                    } label: {
                        Text("모두 보기")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.overlineAccent.opacity(0.86))
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

                ScrapbookCard(
                    highlight: highlight,
                    bookTitle: bookTitle(for: highlight),
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
        .confirmationDialog("보관함을 초기화할까요?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("모든 책과 글조각 삭제", role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    library.resetLibrary()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제 전 최근 상태를 이 기기에 복구 백업으로 남깁니다. 이후 책장 메뉴의 최근 초기화 복구에서 되돌릴 수 있습니다.")
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
        .scrollIndicators(.hidden)
        .overlineBottomMenuCompaction()
        .background(OverlineCanvasBackground().ignoresSafeArea())
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
            case .ocrValidation:
                OCRValidationSheet(
                    capturedHighlightCount: library.recentHighlights.filter { $0.source == .capture }.count,
                    reviewedHighlightCount: library.recentHighlights.filter { $0.source == .capture && $0.reviewedAt != nil }.count
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .mvpReadiness:
                MVPReadinessSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var displayedHighlights: [Highlight] {
        return Array(library.recentHighlights.prefix(10))
    }

    private func bookTitle(for highlight: Highlight) -> String? {
        guard
            let bookID = library.bookID(containing: highlight.id),
            let book = library.book(with: bookID)
        else {
            return nil
        }
        return book.title.trimmed.isEmpty ? nil : book.title
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
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.overlineAccent)

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.overlineInk)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.overlineMutedInk)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
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
    case ocrValidation
    case mvpReadiness

    var id: String {
        switch self {
        case .addBook: "addBook"
        case .editBook(let id): "editBook-\(id.uuidString)"
        case .editHighlight(let id): "editHighlight-\(id.uuidString)"
        case .highlightBrowser: "highlightBrowser"
        case .ocrValidation: "ocrValidation"
        case .mvpReadiness: "mvpReadiness"
        }
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
        NavigationStack {
            VStack(spacing: 0) {
                if !library.recentHighlights.isEmpty {
                    VStack(spacing: 10) {
                        if !library.books.isEmpty {
                            OverlineBookSelectorButton(
                                title: selectedBookFilterTitle,
                                subtitle: "\(filteredHighlights.count)조각",
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
                    ForEach(Array(filteredHighlights.enumerated()), id: \.element.id) { index, highlight in
                        if pendingDeletedHighlight?.visibleIndex == index {
                            OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                                .listRowChrome(top: 0, bottom: 12)
                        }

                        ScrapbookCard(
                            highlight: highlight,
                            bookTitle: bookTitle(for: highlight),
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

                    if let pendingDeletedHighlight, pendingDeletedHighlight.visibleIndex >= filteredHighlights.count {
                        OverlineInlineUndoRow(message: "글조각 삭제됨", undo: restoreDeletedHighlight)
                            .listRowChrome(top: 0, bottom: 12)
                    }

                    if filteredHighlights.isEmpty && pendingDeletedHighlight == nil {
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

    private func bookTitle(for highlight: Highlight) -> String? {
        guard
            let bookID = library.bookID(containing: highlight.id),
            let book = library.book(with: bookID)
        else {
            return nil
        }
        return book.title.trimmed.isEmpty ? nil : book.title
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

private struct MVPReadinessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingLibrary.self) private var library
    @State private var checklist: MVPReadinessChecklist
    @State private var savedChecklist: MVPReadinessChecklist
    @State private var deviceTestSessions: [MVPDeviceTestSession]
    @State private var didCopyEvidencePackage = false

    init() {
        let loadedChecklist = MVPReadinessStore.load()
        _checklist = State(initialValue: loadedChecklist)
        _savedChecklist = State(initialValue: loadedChecklist)
        _deviceTestSessions = State(initialValue: MVPDeviceTestSessionStore.load())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MVPReadinessProgressCard(checklist: checklist, canClaimMVP: canClaimMVP)
                }

                Section("프리플라이트") {
                    MVPPreflightSummaryCard(status: preflightStatus)
                }

                Section {
                    NavigationLink {
                        MVPReadinessTestPlanView()
                    } label: {
                        Label("실제 기기 테스트 절차", systemImage: "list.clipboard")
                    }

                    NavigationLink {
                        MVPDeviceTestSessionLogView(
                            checklist: checklist,
                            onSave: {
                                deviceTestSessions = MVPDeviceTestSessionStore.load()
                            }
                        )
                    } label: {
                        HStack {
                            Label("테스트 세션 기록", systemImage: "iphone.gen3.radiowaves.left.and.right")
                            Spacer()
                            Text(latestDeviceTestSessionLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                        }
                    }

                    NavigationLink {
                        MVPReadinessReportView(checklist: checklist, library: library)
                    } label: {
                        Label("검증 리포트", systemImage: "doc.plaintext")
                    }

                    Button {
                        copyEvidencePackage()
                    } label: {
                        HStack {
                            Label(
                                "검증 패키지 복사",
                                systemImage: didCopyEvidencePackage ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                            Spacer()
                            Text(didCopyEvidencePackage ? "복사됨" : "현장 보관용")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("실제 기기 검증") {
                    MVPReadinessToggle(
                        title: "10초 안에 캡처 저장",
                        detail: "실제 카메라 경로에서 앱 열기부터 저장까지",
                        systemImage: "timer",
                        verifiedAt: checklist.captureSpeedVerifiedAt,
                        isOn: $checklist.captureSpeedVerified
                    )

                    MVPReadinessToggle(
                        title: "캡처 경로 3탭 이하",
                        detail: "열기, 선 긋기, 저장까지 흐름을 끊지 않음",
                        systemImage: "hand.tap",
                        verifiedAt: checklist.capturePathVerifiedAt,
                        isOn: $checklist.capturePathVerified
                    )

                    MVPReadinessToggle(
                        title: "한국어 OCR 90% 이상",
                        detail: "실제 한국어 책으로 M0 기준을 기록",
                        systemImage: "text.viewfinder",
                        verifiedAt: checklist.ocrAccuracyVerifiedAt,
                        isOn: $checklist.ocrAccuracyVerified
                    )

                    MVPReadinessToggle(
                        title: "페이지 경계 감지",
                        detail: "책 페이지 윤곽이 카메라 위에 맞게 표시됨",
                        systemImage: "doc.viewfinder",
                        verifiedAt: checklist.pageBoundaryVerifiedAt,
                        isOn: $checklist.pageBoundaryVerified
                    )

                    MVPReadinessToggle(
                        title: "원문 사진 미저장",
                        detail: "OCR 완료 후 사진은 폐기하고 글조각만 저장",
                        systemImage: "photo.badge.minus",
                        verifiedAt: checklist.snapshotCropVerifiedAt,
                        isOn: $checklist.snapshotCropVerified
                    )

                    MVPReadinessToggle(
                        title: "저조도 캡처",
                        detail: "어두운 환경 안내와 플래시 토글 후 캡처 확인",
                        systemImage: "flashlight.on.fill",
                        verifiedAt: checklist.lowLightVerifiedAt,
                        isOn: $checklist.lowLightVerified
                    )

                    MVPReadinessToggle(
                        title: "ISBN 스캔",
                        detail: "실제 책 바코드로 책 정보 검색",
                        systemImage: "barcode.viewfinder",
                        verifiedAt: checklist.isbnScanVerifiedAt,
                        isOn: $checklist.isbnScanVerified
                    )

                    MVPReadinessToggle(
                        title: "음성 메모",
                        detail: "온디바이스 STT로 메모 저장",
                        systemImage: "mic",
                        verifiedAt: checklist.speechMemoVerifiedAt,
                        isOn: $checklist.speechMemoVerified
                    )
                }

                Section {
                    MVPReadinessToggle(
                        title: "도서 API",
                        detail: "Kakao 또는 Aladin 도서 검색 성공",
                        systemImage: "book.closed",
                        verifiedAt: checklist.kakaoSearchVerifiedAt,
                        isOn: $checklist.kakaoSearchVerified
                    )

                    MVPReadinessToggle(
                        title: "LLM 인사이트",
                        detail: "현재 모델 테스트 또는 실제 인사이트 생성 성공",
                        systemImage: "sparkles",
                        verifiedAt: checklist.llmInsightVerifiedAt,
                        isOn: $checklist.llmInsightVerified
                    )
                } header: {
                    Text("API 검증")
                } footer: {
                    Text("키 입력은 프리플라이트 준비 항목이고, 실제 연결 성공은 MVP 검증 항목입니다. 연결 테스트가 성공하면 자동으로 체크됩니다.")
                }

                Section("메모") {
                    TextField("남은 이슈나 테스트 조건", text: $checklist.note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("MVP 점검")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let loadedChecklist = MVPReadinessStore.load()
                checklist = loadedChecklist
                savedChecklist = loadedChecklist
                deviceTestSessions = MVPDeviceTestSessionStore.load()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let previousChecklist = savedChecklist
                        MVPReadinessStore.save(checklist)
                        let updatedChecklist = MVPReadinessStore.load()
                        recordManualVerificationEvents(from: previousChecklist, to: updatedChecklist)
                        checklist = updatedChecklist
                        savedChecklist = updatedChecklist
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var latestDeviceTestSessionLabel: String {
        guard let latest = deviceTestSessions.first else { return "대기" }
        return latest.isPhysicalDeviceEvidence ? latest.summary : "\(latest.summary) · 시뮬레이터"
    }

    private var preflightStatus: MVPPreflightStatus {
        MVPPreflightStatus.current(library: library)
    }

    private var canClaimMVP: Bool {
        guard checklist.isReady, let latestDeviceTestSession = deviceTestSessions.first else { return false }
        return latestDeviceTestSession.isPassingEvidence
    }

    private var evidencePackageText: String {
        let checklistRows = MVPReadinessItem.allCases.map { item in
            let state = item.isVerified(in: checklist) ? "통과" : "대기"
            let verifiedAt = item.verifiedAt(in: checklist).map { " · \($0.overlineShortDate)" } ?? ""
            return "- \(item.title): \(state)\(verifiedAt)"
        }
        .joined(separator: "\n")

        let latestSessionText: String
        if let latest = deviceTestSessions.first {
            let failedItems = latest.failedItems.map(\.title).joined(separator: ", ")
            let openItems = latest.openItems.map(\.title).joined(separator: ", ")
            latestSessionText = """
            최근 세션: \(latest.summary)
            기기: \(latest.runtime) · \(latest.deviceName)
            증거: \(latest.evidenceLabel)
            OS: \(latest.osVersion)
            앱: \(latest.appVersion)
            기록: \(latest.createdAt.overlineShortDate)
            실패: \(failedItems.isEmpty ? "없음" : failedItems)
            미확인: \(openItems.isEmpty ? "없음" : openItems)
            메모: \(latest.note.trimmed.isEmpty ? "-" : latest.note.trimmed)
            """
        } else {
            latestSessionText = "최근 세션: 없음"
        }

        return """
        Overline MVP 검증 패키지
        생성: \(Date().overlineShortDate)

        판정: \(canClaimMVP ? "MVP 통과 가능" : "대기")
        기능 점검: \(checklist.completedCount)/\(checklist.totalCount)
        프리플라이트: \(preflightStatus.summary)

        프리플라이트 상세
        \(preflightStatus.reportText)

        기능 점검 상세
        \(checklistRows)

        실제 테스트 세션
        \(latestSessionText)

        보관함
        책: \(library.books.count)
        글조각: \(library.highlightCount)
        저장된 인사이트: \(library.savedInsights.count)
        주 저장소: \(library.storageStatus.primaryLabel)
        백업 저장: \(library.storageStatus.fallbackLabel)

        현장 절차
        1. 실제 iPhone에서 책 한 줄을 swipe해 10초 안에 저장
        2. OCR 정확도, 페이지 경계, 원문 사진 미저장, 저조도, ISBN, 음성 메모 확인
        3. 도서 API와 LLM 연결 테스트 성공 날짜 확인
        4. 테스트 세션 기록에서 실제 iPhone 10/10 세션 저장
        5. 검증 리포트의 MVP 판정이 통과 가능인지 확인
        """
    }

    private func copyEvidencePackage() {
        UIPasteboard.general.string = evidencePackageText
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            didCopyEvidencePackage = true
        }
    }

    private func recordManualVerificationEvents(
        from previousChecklist: MVPReadinessChecklist,
        to updatedChecklist: MVPReadinessChecklist
    ) {
        let transitions: [(wasVerified: Bool, isVerified: Bool, item: MVPReadinessItem)] = [
            (previousChecklist.captureSpeedVerified, updatedChecklist.captureSpeedVerified, .captureSpeed),
            (previousChecklist.capturePathVerified, updatedChecklist.capturePathVerified, .capturePath),
            (previousChecklist.ocrAccuracyVerified, updatedChecklist.ocrAccuracyVerified, .ocrAccuracy),
            (previousChecklist.pageBoundaryVerified, updatedChecklist.pageBoundaryVerified, .pageBoundary),
            (previousChecklist.snapshotCropVerified, updatedChecklist.snapshotCropVerified, .snapshotCrop),
            (previousChecklist.lowLightVerified, updatedChecklist.lowLightVerified, .lowLight),
            (previousChecklist.isbnScanVerified, updatedChecklist.isbnScanVerified, .isbnScan),
            (previousChecklist.speechMemoVerified, updatedChecklist.speechMemoVerified, .speechMemo),
            (previousChecklist.kakaoSearchVerified, updatedChecklist.kakaoSearchVerified, .kakaoSearch),
            (previousChecklist.llmInsightVerified, updatedChecklist.llmInsightVerified, .llmInsight)
        ]

        for transition in transitions where !transition.wasVerified && transition.isVerified {
            MVPVerificationEventStore.add(
                MVPVerificationEvent(
                    item: transition.item,
                    detail: "MVP 점검 화면에서 수동 체크"
                )
            )
        }
    }
}

private struct MVPReadinessProgressCard: View {
    let checklist: MVPReadinessChecklist
    let canClaimMVP: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    statusTitle,
                    systemImage: statusSystemImage
                )
                .font(.headline.weight(.semibold))
                .foregroundStyle(statusColor)

                Spacer()

                Text("\(checklist.completedCount)/\(checklist.totalCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk)
            }

            ProgressView(value: Double(checklist.completedCount), total: Double(checklist.totalCount))
                .tint(Color.overlineAccent)

            Text(footerText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.68))
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        if canClaimMVP {
            return "MVP 통과 가능"
        }

        if checklist.isReady {
            return "기능 점검 10/10"
        }

        return "기능 점검 진행 중"
    }

    private var statusSystemImage: String {
        if canClaimMVP {
            return "checkmark.seal.fill"
        }

        return checklist.isReady ? "checkmark.shield.fill" : "checkmark.shield"
    }

    private var statusColor: Color {
        canClaimMVP ? Color.overlineAccent : Color.overlineInk
    }

    private var footerText: String {
        if canClaimMVP {
            return "실제 iPhone 세션 통과 · \(checklist.updatedAt.overlineShortDate)"
        }

        if checklist.isReady {
            return "실제 iPhone 10/10 세션 필요 · \(checklist.updatedAt.overlineShortDate)"
        }

        return "최근 업데이트 \(checklist.updatedAt.overlineShortDate)"
    }
}

private struct MVPPreflightSummaryCard: View {
    let status: MVPPreflightStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(status.isReady ? "테스트 준비 완료" : "테스트 준비 확인 필요", systemImage: status.isReady ? "checkmark.circle.fill" : "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.isReady ? Color.overlineAccent : Color.overlineInk)

                Spacer()

                Text(status.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk)
            }

            if status.isReady {
                Text("실제 iPhone 테스트를 시작할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
            } else {
                ForEach(status.notReadyRows.prefix(4)) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.overlineMutedInk)
                            .frame(width: 18)

                        Text(row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.overlineInk)
                            .lineLimit(1)

                        Spacer()

                        Text(row.value)
                            .font(.caption)
                            .foregroundStyle(Color.overlineMutedInk)
                            .lineLimit(1)
                    }
                }

                if status.notReadyRows.count > 4 {
                    Text("외 \(status.notReadyRows.count - 4)개는 검증 리포트에서 확인")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MVPReadinessToggle: View {
    let title: String
    let detail: String
    let systemImage: String
    let verifiedAt: Date?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? Color.overlineAccent : Color.overlineMutedInk)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.overlineInk)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.overlineMutedInk)
                    if isOn, let verifiedAt {
                        Text("검증 \(verifiedAt.overlineShortDate)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                    }
                }
            }
        }
    }
}

private struct MVPDeviceTestSessionLogView: View {
    let checklist: MVPReadinessChecklist
    var onSave: () -> Void = {}
    @State private var note = ""
    @State private var failedItemRawValues: Set<String> = []
    @State private var sessions = MVPDeviceTestSessionStore.load()
    @State private var lastSavedSession: MVPDeviceTestSession?
    private let environment = MVPReportEnvironment.current

    var body: some View {
        List {
            Section {
                Label(
                    "현재 MVP 점검 상태를 테스트 세션으로 저장합니다.",
                    systemImage: "checkmark.shield"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineInk)

                MVPReportMetricRow(systemImage: "iphone", title: "실행 환경", value: environment.runtime)
                MVPReportMetricRow(
                    systemImage: environment.isPhysicalDevice ? "checkmark.seal" : "exclamationmark.triangle",
                    title: "증거",
                    value: environment.isPhysicalDevice ? "실기기 가능" : "빌드 확인용"
                )
                MVPReportMetricRow(systemImage: "gear", title: "OS", value: environment.systemVersion)
                MVPReportMetricRow(systemImage: "app.badge", title: "앱", value: environment.appVersion)
                MVPReportMetricRow(systemImage: "number", title: "번들 ID", value: MVPBundleIdentifierStatus.value)
                MVPReportMetricRow(systemImage: "app", title: "앱 아이콘", value: MVPAppIconStatus.label)
            }

            Section("이번 세션 판정") {
                Label(currentSessionVerdict, systemImage: currentSessionSystemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(currentSessionColor)

                MVPReportMetricRow(
                    systemImage: "checklist.checked",
                    title: "상태",
                    value: "\(currentPassedItems.count) 통과 · \(currentFailedItems.count) 실패 · \(currentOpenItems.count) 미확인"
                )

                Text(currentSessionReason)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
            }

            Section("현재 상태") {
                ForEach(MVPReadinessItem.allCases) { item in
                    MVPDeviceTestItemRow(item: item, checklist: checklist)
                }
            }

            if !unverifiedItems.isEmpty {
                Section("실패/재검증 필요") {
                    ForEach(unverifiedItems) { item in
                        Toggle(isOn: failedBinding(for: item)) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.overlineMutedInk)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.overlineInk)
                                    Text("이번 세션에서 실패했거나 재검증이 필요하면 켭니다.")
                                        .font(.caption)
                                        .foregroundStyle(Color.overlineMutedInk)
                                }
                            }
                        }
                    }
                }
            }

            Section("메모") {
                TextField("기기, 조명, 책, 네트워크 조건 등", text: $note, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section {
                Button {
                    saveSession()
                } label: {
                    Label("현재 상태 기록", systemImage: "plus.circle")
                }
                .font(.subheadline.weight(.semibold))
            } footer: {
                Text("원문 사진과 API 키는 이 기록에 포함하지 않습니다.")
            }

            if let lastSavedSession {
                Section {
                    Label(lastSavedSessionConfirmationTitle(for: lastSavedSession), systemImage: lastSavedSessionConfirmationIcon(for: lastSavedSession))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(lastSavedSession.isPassingEvidence ? Color.overlineAccent : Color.overlineMutedInk)

                    Text(lastSavedSessionConfirmationDetail(for: lastSavedSession))
                        .font(.caption)
                        .foregroundStyle(Color.overlineMutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !sessions.isEmpty {
                Section("최근 세션") {
                    ForEach(sessions.prefix(10)) { session in
                        MVPDeviceTestSessionRow(session: session)
                    }
                }
            }
        }
        .navigationTitle("테스트 세션")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveSession() {
        let session = MVPDeviceTestSession(
            runtime: environment.runtime,
            deviceName: currentDeviceName,
            osVersion: environment.systemVersion,
            appVersion: environment.appVersion,
            passedItems: currentPassedItems,
            failedItems: currentFailedItems,
            openItems: currentOpenItems,
            note: note.trimmed
        )
        MVPDeviceTestSessionStore.add(session)
        sessions = MVPDeviceTestSessionStore.load()
        failedItemRawValues.removeAll()
        note = ""
        lastSavedSession = session
        onSave()
    }

    private func lastSavedSessionConfirmationTitle(for session: MVPDeviceTestSession) -> String {
        if session.isPassingEvidence {
            return "MVP 통과 근거로 저장됨"
        }

        if session.isPhysicalDeviceEvidence {
            return "실기기 세션 저장됨"
        }

        return "빌드 확인용 세션 저장됨"
    }

    private func lastSavedSessionConfirmationIcon(for session: MVPDeviceTestSession) -> String {
        session.isPassingEvidence ? "checkmark.seal.fill" : "checkmark.circle.fill"
    }

    private func lastSavedSessionConfirmationDetail(for session: MVPDeviceTestSession) -> String {
        if session.isPassingEvidence {
            return "검증 리포트에서 MVP 판정이 통과 가능으로 표시됩니다."
        }

        if session.isPhysicalDeviceEvidence {
            return "검증 리포트에 \(session.failedCount)개 실패, \(session.openCount)개 미확인이 반영됩니다."
        }

        return "시뮬레이터 세션은 MVP 통과 근거가 아니며, 실제 iPhone 세션이 별도로 필요합니다."
    }

    private var currentPassedItems: [MVPReadinessItem] {
        MVPReadinessItem.allCases.filter { $0.isVerified(in: checklist) }
    }

    private var currentFailedItems: [MVPReadinessItem] {
        unverifiedItems.filter { failedItemRawValues.contains($0.rawValue) }
    }

    private var currentOpenItems: [MVPReadinessItem] {
        unverifiedItems.filter { !failedItemRawValues.contains($0.rawValue) }
    }

    private var currentSessionVerdict: String {
        guard environment.isPhysicalDevice else {
            return "실기기 필요"
        }

        if currentFailedItems.isEmpty && currentOpenItems.isEmpty {
            return "통과 가능"
        }

        if !currentFailedItems.isEmpty {
            return "실패 포함"
        }

        return "미확인 남음"
    }

    private var currentSessionReason: String {
        guard environment.isPhysicalDevice else {
            return "시뮬레이터 세션은 UI 빌드 확인용이며 MVP 통과 근거가 아닙니다."
        }

        if currentFailedItems.isEmpty && currentOpenItems.isEmpty {
            return "이 상태로 저장하면 MVP 통과 근거로 사용할 수 있습니다."
        }

        if !currentFailedItems.isEmpty {
            return "실패로 표시한 항목은 검증 리포트에 실패 항목으로 남습니다."
        }

        return "남은 항목을 실제 기기에서 확인하거나 실패/재검증 필요로 표시하세요."
    }

    private var currentSessionSystemImage: String {
        guard environment.isPhysicalDevice else {
            return "exclamationmark.triangle"
        }

        if currentFailedItems.isEmpty && currentOpenItems.isEmpty {
            return "checkmark.seal.fill"
        }

        if !currentFailedItems.isEmpty {
            return "xmark.seal"
        }

        return "hourglass"
    }

    private var currentSessionColor: Color {
        guard environment.isPhysicalDevice else {
            return Color.overlineCoral
        }

        if currentFailedItems.isEmpty && currentOpenItems.isEmpty {
            return Color.overlineAccent
        }

        if !currentFailedItems.isEmpty {
            return Color.overlineCoral
        }

        return Color.overlineMutedInk
    }

    private var unverifiedItems: [MVPReadinessItem] {
        MVPReadinessItem.allCases.filter { !$0.isVerified(in: checklist) }
    }

    private func failedBinding(for item: MVPReadinessItem) -> Binding<Bool> {
        Binding(
            get: { failedItemRawValues.contains(item.rawValue) },
            set: { isOn in
                if isOn {
                    failedItemRawValues.insert(item.rawValue)
                } else {
                    failedItemRawValues.remove(item.rawValue)
                }
            }
        )
    }

    private var currentDeviceName: String {
        #if targetEnvironment(simulator)
        "Simulator · \(UIDevice.current.model)"
        #else
        UIDevice.current.name
        #endif
    }
}

private struct MVPDeviceTestItemRow: View {
    let item: MVPReadinessItem
    let checklist: MVPReadinessChecklist

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isVerified(in: checklist) ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(item.isVerified(in: checklist) ? Color.overlineAccent : Color.overlineMutedInk)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)

                Text(item.verifiedAt(in: checklist)?.overlineShortDate ?? "미확인")
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MVPDeviceTestSessionRow: View {
    let session: MVPDeviceTestSession

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(session.summary, systemImage: session.isPassingEvidence ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.isPassingEvidence ? Color.overlineAccent : Color.overlineInk)

                Spacer()

                Text(session.createdAt.overlineShortDate)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
            }

            Text("\(session.runtime) · \(session.deviceName)")
                .font(.caption)
                .foregroundStyle(Color.overlineMutedInk)

            if !session.failedItems.isEmpty {
                Text("실패: \(session.failedItems.map(\.title).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color.overlineCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.openItems.isEmpty {
                Text("미확인: \(session.openItems.map(\.title).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.note.trimmed.isEmpty {
                Text(session.note)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.82))
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct MVPReadinessTestPlanView: View {
    @State private var didCopyPlan = false

    private let sections: [MVPTestPlanSection] = [
        MVPTestPlanSection(
            title: "준비",
            systemImage: "checklist",
            steps: [
                "실제 iPhone에서 실행하고 카메라, 마이크, 음성 인식 권한을 허용",
                "MVP 점검의 검증 리포트에서 프리플라이트 준비 상태를 확인",
                "도서 API 키 준비, LLM API 키 준비, 주 저장소, 백업 저장, 원문 사진 미저장 정책이 준비 상태인지 확인",
                "한국어 종이책 1권과 ISBN 바코드가 보이는 뒷표지 준비",
                "실제 검색과 연결 테스트로 도서 API와 LLM 연결 날짜를 남기기"
            ]
        ),
        MVPTestPlanSection(
            title: "캡처",
            systemImage: "text.viewfinder",
            steps: [
                "캡처 탭을 열고 페이지를 2초 정도 비춘 뒤 문장 위를 가로로 긋기",
                "페이지 윤곽선이 실제 종이 페이지에 맞게 따라오는지 확인",
                "글조각 저장 상태에 10초 이하 시간이 표시되는지 확인",
                "책장 상세에서 OCR 텍스트만 저장되고 원문 사진이 남지 않는지 확인",
                "조명이 어두울 때 저조도 안내와 플래시 토글이 실제로 동작하는지 확인"
            ]
        ),
        MVPTestPlanSection(
            title: "OCR 정확도",
            systemImage: "checkmark.seal",
            steps: [
                "한국어 문장 여러 줄을 캡처하고 글조각 편집에서 원문과 대조",
                "책장 메뉴의 OCR 검증 기록에 검증 줄 수와 수정 필요 줄 수 입력",
                "정확도 90% 이상이면 M0 통과로 기록되는지 확인"
            ]
        ),
        MVPTestPlanSection(
            title: "책 정보",
            systemImage: "barcode.viewfinder",
            steps: [
                "책 추가에서 ISBN 스캔으로 바코드를 읽기",
                "국내 도서 검색 결과로 제목, 저자, 책소개, 표지 URL이 적용되는지 확인",
                "Kakao 결과가 없을 때 Aladin fallback 또는 수동 입력이 가능한지 확인"
            ]
        ),
        MVPTestPlanSection(
            title: "메모와 인사이트",
            systemImage: "sparkles",
            steps: [
                "메모장에서 마이크 버튼으로 온디바이스 음성 메모를 텍스트로 저장",
                "인사이트 탭의 AI 설정에서 API 키와 모델을 선택하고 현재 모델 테스트 실행",
                "검증 리포트에 LLM 연결 날짜가 남는지 확인",
                "글조각을 선택해 질문, 연결, 확장, 요약 중 하나를 생성하고 저장"
            ]
        )
    ]

    var body: some View {
        List {
            Section {
                Label("실제 iPhone에서 10/10 세션을 저장해야 MVP 통과 근거가 됩니다.", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)

                Text("시뮬레이터 세션은 UI 빌드 확인용으로만 기록됩니다.")
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
            }

            if didCopyPlan {
                Section {
                    Label("현장 체크리스트를 복사했습니다.", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.overlineAccent)
                }
            }

            ForEach(sections) { section in
                Section {
                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.overlineAccent)
                                .frame(width: 22, height: 22)
                                .background(Color.overlineAccent.opacity(0.10), in: Circle())

                            Text(step)
                                .font(.caption)
                                .foregroundStyle(Color.overlineInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
        }
        .navigationTitle("테스트 절차")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    copyPlan()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("현장 체크리스트 복사")
            }
        }
    }

    private var planText: String {
        let sectionText = sections.map { section in
            let steps = section.steps.enumerated().map { index, step in
                "\(index + 1). \(step)"
            }
            .joined(separator: "\n")

            return """
            [\(section.title)]
            \(steps)
            """
        }
        .joined(separator: "\n\n")

        return """
        Overline MVP 실제 iPhone 테스트 체크리스트

        목표
        - 실제 iPhone에서 10/10 세션을 저장해야 MVP 통과 근거가 됩니다.
        - 시뮬레이터 세션은 UI 빌드 확인용입니다.
        - 기능 점검 10/10은 체크리스트 완료이고, MVP 통과 가능은 실제 iPhone 세션까지 통과한 상태입니다.
        - 도서 API 키 준비와 LLM API 키 준비는 프리플라이트이고, 도서 API와 LLM 연결은 실제 검증 증거입니다.
        - 원문 사진과 API 키는 이 체크리스트에 포함하지 않습니다.

        \(sectionText)

        마무리
        1. MVP 점검 > 테스트 세션 기록에서 현재 상태를 저장
        2. 저장 완료 안내가 MVP 통과 근거인지, 실기기 세션인지, 빌드 확인용인지 확인
        3. MVP 점검 > 검증 리포트에서 MVP 판정, 다음 조치, 도서 API, LLM 연결 확인
        4. 검증 리포트를 복사해 증거 메모로 보관
        """
    }

    private func copyPlan() {
        UIPasteboard.general.string = planText
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            didCopyPlan = true
        }
    }
}

private struct MVPTestPlanSection: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let steps: [String]
}

private struct MVPReportEnvironment {
    let runtime: String
    let isPhysicalDevice: Bool
    let systemVersion: String
    let appVersion: String

    static var current: MVPReportEnvironment {
        #if targetEnvironment(simulator)
        let runtime = "Simulator"
        let isPhysicalDevice = false
        #else
        let runtime = "Device"
        let isPhysicalDevice = true
        #endif

        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildNumber = info?["CFBundleVersion"] as? String
        let versionParts = [shortVersion, buildNumber.map { "build \($0)" }]
            .compactMap { $0 }
        let appVersion = versionParts.isEmpty ? "-" : versionParts.joined(separator: " · ")

        return MVPReportEnvironment(
            runtime: runtime,
            isPhysicalDevice: isPhysicalDevice,
            systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: appVersion
        )
    }
}

private enum MVPPrivacyManifestStatus {
    static var isIncluded: Bool {
        Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil
    }

    static var label: String {
        isIncluded ? "번들 포함" : "확인 필요"
    }
}

private enum MVPPermissionPurposeStatus {
    private static let requiredKeys = [
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription"
    ]

    static var includedCount: Int {
        requiredKeys.filter { key in
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return false }
            return !value.trimmed.isEmpty
        }
        .count
    }

    static var isReady: Bool {
        includedCount == requiredKeys.count
    }

    static var label: String {
        "\(includedCount)/\(requiredKeys.count)"
    }
}

private enum MVPAppIntentsMetadataStatus {
    static var isIncluded: Bool {
        FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL
                .appendingPathComponent("Metadata.appintents")
                .path
        )
    }

    static var label: String {
        isIncluded ? "번들 포함" : "확인 필요"
    }
}

private enum MVPBundleIdentifierStatus {
    static var value: String {
        Bundle.main.bundleIdentifier ?? "-"
    }

    static var isReady: Bool {
        value.contains(".") && value != "-"
    }
}

private enum MVPAppVersionStatus {
    static var label: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildNumber = info?["CFBundleVersion"] as? String
        let trimmedBuildNumber = buildNumber?.trimmed ?? ""
        let buildLabel = trimmedBuildNumber.isEmpty ? nil : "build \(trimmedBuildNumber)"
        let parts = [
            shortVersion?.trimmed,
            buildLabel
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    static var isReady: Bool {
        label != "-"
    }
}

private enum MVPAppIconStatus {
    static var isIncluded: Bool {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any]
        else {
            return false
        }

        let iconName = (primaryIcon["CFBundleIconName"] as? String)?.trimmed ?? ""
        let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] ?? []
        return !iconName.isEmpty || !iconFiles.isEmpty
    }

    static var label: String {
        isIncluded ? "번들 포함" : "확인 필요"
    }
}

private struct MVPPreflightStatus {
    let rows: [MVPPreflightRow]

    static func current(library: ReadingLibrary) -> MVPPreflightStatus {
        let llmKeyStore = KeychainStringStore(service: "aib.Overline.llm")
        let configuredLLMProviders = LLMProvider.allCases.filter { provider in
            let apiKey = llmKeyStore.string(account: provider.rawValue) ?? ""
            return !apiKey.trimmed.isEmpty
        }
        let configuredLLMTitle = configuredLLMProviders.isEmpty
            ? "대기"
            : configuredLLMProviders.map { $0.shortTitle }.joined(separator: ", ")

        return MVPPreflightStatus(
            rows: [
                MVPPreflightRow(
                    systemImage: "camera",
                    title: "카메라 권한",
                    value: cameraAuthorizationLabel,
                    isReady: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                ),
                MVPPreflightRow(
                    systemImage: "mic",
                    title: "마이크 권한",
                    value: microphoneAuthorizationLabel,
                    isReady: AVAudioApplication.shared.recordPermission == .granted
                ),
                MVPPreflightRow(
                    systemImage: "waveform",
                    title: "음성 인식 권한",
                    value: speechAuthorizationLabel,
                    isReady: SFSpeechRecognizer.authorizationStatus() == .authorized
                ),
                MVPPreflightRow(
                    systemImage: "book.closed",
                    title: "도서 API 키 준비",
                    value: (
                        BookMetadataAPIKeyStore.kakaoRESTAPIKey().trimmed.isEmpty
                            && BookMetadataAPIKeyStore.aladinTTBKey().trimmed.isEmpty
                    ) ? "대기" : "입력됨",
                    isReady: !BookMetadataAPIKeyStore.kakaoRESTAPIKey().trimmed.isEmpty
                        || !BookMetadataAPIKeyStore.aladinTTBKey().trimmed.isEmpty
                ),
                MVPPreflightRow(
                    systemImage: "sparkles",
                    title: "LLM API 키 준비",
                    value: configuredLLMTitle,
                    isReady: !configuredLLMProviders.isEmpty
                ),
                MVPPreflightRow(
                    systemImage: "key",
                    title: "API 키 보관",
                    value: KeychainStringStore.storagePolicyLabel,
                    isReady: true
                ),
                MVPPreflightRow(
                    systemImage: "externaldrive",
                    title: "주 저장소",
                    value: library.storageStatus.primaryLabel,
                    isReady: library.storageStatus.primarySaveSucceeded
                ),
                MVPPreflightRow(
                    systemImage: "archivebox",
                    title: "백업 저장",
                    value: library.storageStatus.fallbackLabel,
                    isReady: library.storageStatus.fallbackSaveSucceeded
                ),
                MVPPreflightRow(
                    systemImage: "photo.badge.minus",
                    title: "원문 사진",
                    value: "OCR 후 폐기",
                    isReady: true
                ),
                MVPPreflightRow(
                    systemImage: "hand.raised",
                    title: "개인정보 매니페스트",
                    value: MVPPrivacyManifestStatus.label,
                    isReady: MVPPrivacyManifestStatus.isIncluded
                ),
                MVPPreflightRow(
                    systemImage: "text.badge.checkmark",
                    title: "권한 문구",
                    value: MVPPermissionPurposeStatus.label,
                    isReady: MVPPermissionPurposeStatus.isReady
                ),
                MVPPreflightRow(
                    systemImage: "app.badge",
                    title: "App Intents",
                    value: MVPAppIntentsMetadataStatus.label,
                    isReady: MVPAppIntentsMetadataStatus.isIncluded
                ),
                MVPPreflightRow(
                    systemImage: "number",
                    title: "번들 ID",
                    value: MVPBundleIdentifierStatus.value,
                    isReady: MVPBundleIdentifierStatus.isReady
                ),
                MVPPreflightRow(
                    systemImage: "tag",
                    title: "앱 버전",
                    value: MVPAppVersionStatus.label,
                    isReady: MVPAppVersionStatus.isReady
                ),
                MVPPreflightRow(
                    systemImage: "app",
                    title: "앱 아이콘",
                    value: MVPAppIconStatus.label,
                    isReady: MVPAppIconStatus.isIncluded
                )
            ]
        )
    }

    var readyCount: Int {
        rows.filter(\.isReady).count
    }

    var notReadyRows: [MVPPreflightRow] {
        rows.filter { !$0.isReady }
    }

    var isReady: Bool {
        readyCount == rows.count
    }

    var summary: String {
        "\(readyCount)/\(rows.count)"
    }

    var reportText: String {
        rows.map { row in
            "- \(row.title): \(row.value)"
        }
        .joined(separator: "\n")
    }

    private static var cameraAuthorizationLabel: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            "허용"
        case .notDetermined:
            "미요청"
        case .denied:
            "거부"
        case .restricted:
            "제한"
        @unknown default:
            "알 수 없음"
        }
    }

    private static var microphoneAuthorizationLabel: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            "허용"
        case .denied:
            "거부"
        case .undetermined:
            "미요청"
        @unknown default:
            "알 수 없음"
        }
    }

    private static var speechAuthorizationLabel: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            "허용"
        case .denied:
            "거부"
        case .restricted:
            "제한"
        case .notDetermined:
            "미요청"
        @unknown default:
            "알 수 없음"
        }
    }
}

private struct MVPPreflightRow: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let value: String
    let isReady: Bool
}

private struct MVPReadinessReportView: View {
    let checklist: MVPReadinessChecklist
    let library: ReadingLibrary
    @State private var didCopyReport = false
    private let ocrRecords = OCRValidationStore.load()
    private let captureRecords = CapturePerformanceStore.load()
    private let usageMetrics = AppUsageMetricsStore.load()
    private let llmMetrics = LLMUsageMetricsStore.load()
    private let verificationEvents = MVPVerificationEventStore.load()
    private let deviceTestSessions = MVPDeviceTestSessionStore.load()
    private let environment = MVPReportEnvironment.current
    private var preflightStatus: MVPPreflightStatus {
        MVPPreflightStatus.current(library: library)
    }

    var body: some View {
        List {
            Section {
                MVPReadinessProgressCard(checklist: checklist, canClaimMVP: canClaimMVP)
            }

            Section("MVP 판정") {
                MVPReportMetricRow(
                    systemImage: canClaimMVP ? "checkmark.seal.fill" : "hourglass",
                    title: "상태",
                    value: canClaimMVP ? "통과 가능" : "대기"
                )
                MVPReportMetricRow(
                    systemImage: canClaimMVP ? "iphone.gen3.radiowaves.left.and.right" : "exclamationmark.triangle",
                    title: "근거",
                    value: mvpDecisionReason
                )
            }

            if !nextActionItems.isEmpty {
                Section("다음 조치") {
                    ForEach(nextActionItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.overlineAccent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.overlineInk)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.overlineMutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if didCopyReport {
                Section {
                    Label("검증 리포트를 복사했습니다.", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.overlineAccent)
                }
            }

            Section("보관함") {
                MVPReportMetricRow(systemImage: "books.vertical", title: "책", value: "\(library.books.count)")
                MVPReportMetricRow(systemImage: "quote.opening", title: "글조각", value: "\(library.highlightCount)")
                MVPReportMetricRow(systemImage: "sparkles", title: "저장된 인사이트", value: "\(library.savedInsights.count)")
                MVPReportMetricRow(
                    systemImage: "externaldrive",
                    title: "주 저장소",
                    value: library.storageStatus.primaryLabel
                )
                MVPReportMetricRow(
                    systemImage: "archivebox",
                    title: "백업 저장",
                    value: library.storageStatus.fallbackLabel
                )
                MVPReportMetricRow(
                    systemImage: "clock",
                    title: "마지막 저장",
                    value: library.storageStatus.lastSavedLabel
                )
                MVPReportMetricRow(
                    systemImage: "arrow.uturn.backward.circle",
                    title: "초기화 복구",
                    value: library.resetBackupAvailable ? "가능" : "없음"
                )
            }

            Section("저작권/로컬 원칙") {
                MVPReportMetricRow(
                    systemImage: "photo.on.rectangle",
                    title: "표지 이미지",
                    value: "\(coverURLReferenceCount)권 URL 참조"
                )
                MVPReportMetricRow(systemImage: "externaldrive.badge.xmark", title: "표지 저장", value: "앱 저장 없음")
                MVPReportMetricRow(systemImage: "building.columns", title: "도서 DB 출처", value: metadataSourceSummary)
                MVPReportMetricRow(systemImage: "text.badge.checkmark", title: "출처 표기", value: "책 상세 하단")
                MVPReportMetricRow(
                    systemImage: "photo.badge.minus",
                    title: "원문 사진",
                    value: "저장 안 함"
                )
                MVPReportMetricRow(
                    systemImage: "lock.shield",
                    title: "사진 정책",
                    value: "OCR 후 폐기"
                )
                MVPReportMetricRow(
                    systemImage: "key",
                    title: "API 키 보관",
                    value: KeychainStringStore.storagePolicyLabel
                )
                MVPReportMetricRow(
                    systemImage: "hand.raised",
                    title: "개인정보 매니페스트",
                    value: MVPPrivacyManifestStatus.label
                )
                MVPReportMetricRow(
                    systemImage: "text.badge.checkmark",
                    title: "권한 문구",
                    value: MVPPermissionPurposeStatus.label
                )
                MVPReportMetricRow(
                    systemImage: "app.badge",
                    title: "App Intents",
                    value: MVPAppIntentsMetadataStatus.label
                )
                MVPReportMetricRow(systemImage: "icloud.slash", title: "클라우드 동기화", value: "v1 없음")
                MVPReportMetricRow(systemImage: "sparkles", title: "AI 전송", value: "요청형")
                MVPReportMetricRow(systemImage: "square.and.arrow.up", title: "공유", value: "매번 확인")
            }

            Section("환경") {
                MVPReportMetricRow(systemImage: "iphone", title: "실행 환경", value: environment.runtime)
                MVPReportMetricRow(
                    systemImage: environment.isPhysicalDevice ? "checkmark.seal" : "exclamationmark.triangle",
                    title: "증거",
                    value: environment.isPhysicalDevice ? "실기기 가능" : "빌드 확인용"
                )
                MVPReportMetricRow(systemImage: "gear", title: "OS", value: environment.systemVersion)
                MVPReportMetricRow(systemImage: "app.badge", title: "앱", value: environment.appVersion)
            }

            Section("프리플라이트") {
                MVPReportMetricRow(systemImage: "checklist", title: "준비 상태", value: preflightStatus.summary)
                ForEach(preflightStatus.rows) { row in
                    MVPReportMetricRow(
                        systemImage: row.isReady ? "checkmark.circle.fill" : row.systemImage,
                        title: row.title,
                        value: row.value
                    )
                }
            }

            Section("검증") {
                MVPReportMetricRow(
                    systemImage: checklist.isReady ? "checkmark.shield.fill" : "checkmark.shield",
                    title: "MVP 점검",
                    value: "\(checklist.completedCount)/\(checklist.totalCount)"
                )
                MVPReportMetricRow(
                    systemImage: latestOCRRecord?.passesM0 == true ? "checkmark.seal.fill" : "checkmark.seal",
                    title: "최근 OCR 정확도",
                    value: latestOCRRecord.map { $0.accuracy.formatted(.percent.precision(.fractionLength(1))) } ?? "-"
                )
                MVPReportMetricRow(
                    systemImage: latestOCRRecord?.passesM0 == true ? "book.closed.fill" : "book.closed",
                    title: "OCR 검증 근거",
                    value: ocrEvidenceLabel
                )
                MVPReportMetricRow(
                    systemImage: "calendar",
                    title: "최근 업데이트",
                    value: checklist.updatedAt.overlineShortDate
                )
                MVPReportMetricRow(
                    systemImage: checklist.kakaoSearchVerified ? "checkmark.circle.fill" : "book.closed",
                    title: "도서 API",
                    value: checklist.kakaoSearchVerifiedAt?.overlineShortDate ?? "대기"
                )
                MVPReportMetricRow(
                    systemImage: checklist.llmInsightVerified ? "checkmark.circle.fill" : "sparkles",
                    title: "LLM 연결",
                    value: checklist.llmInsightVerifiedAt?.overlineShortDate ?? "대기"
                )
            }

            Section("실제 테스트 세션") {
                if let latestDeviceTestSession {
                    MVPReportMetricRow(
                        systemImage: latestDeviceTestSession.isPassingEvidence ? "checkmark.seal.fill" : "checkmark.seal",
                        title: "최근 세션",
                        value: latestDeviceTestSession.summary
                    )
                    MVPReportMetricRow(
                        systemImage: "iphone",
                        title: "기기",
                        value: "\(latestDeviceTestSession.runtime) · \(latestDeviceTestSession.deviceName)"
                    )
                    MVPReportMetricRow(
                        systemImage: latestDeviceTestSession.isPhysicalDeviceEvidence ? "checkmark.seal" : "exclamationmark.triangle",
                        title: "증거",
                        value: latestDeviceTestSession.evidenceLabel
                    )
                    MVPReportMetricRow(
                        systemImage: "gear",
                        title: "OS",
                        value: latestDeviceTestSession.osVersion
                    )
                    MVPReportMetricRow(
                        systemImage: "clock",
                        title: "기록",
                        value: latestDeviceTestSession.createdAt.overlineShortDate
                    )
                } else {
                    Label("아직 저장된 테스트 세션이 없습니다.", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                }
            }

            Section("캡처 성능") {
                MVPReportMetricRow(
                    systemImage: "timer",
                    title: "최근 캡처",
                    value: latestCaptureRecord?.durationLabel ?? "-"
                )
                MVPReportMetricRow(
                    systemImage: "camera",
                    title: "최근 카메라",
                    value: latestCameraCaptureRecord.map { "\($0.durationLabel) · \($0.pathStepLabel) · \($0.lineCount)줄" } ?? "-"
                )
                MVPReportMetricRow(
                    systemImage: latestCameraCaptureRecord?.meetsSpeedTarget == true ? "checkmark.circle" : "exclamationmark.circle",
                    title: "10초 기준",
                    value: captureSpeedLabel
                )
                MVPReportMetricRow(
                    systemImage: latestCameraCaptureRecord?.meetsPathTarget == true ? "checkmark.circle" : "exclamationmark.circle",
                    title: "3단계 기준",
                    value: capturePathLabel
                )
                MVPReportMetricRow(
                    systemImage: "chart.bar",
                    title: "최근 카메라 통과",
                    value: recentCameraSpeedSummary
                )
                MVPReportMetricRow(
                    systemImage: "hand.tap",
                    title: "최근 경로 통과",
                    value: recentCameraPathSummary
                )
                MVPReportMetricRow(
                    systemImage: "waveform.path.ecg",
                    title: "신뢰도",
                    value: latestCameraCaptureRecord?.confidenceLabel ?? "-"
                )
                MVPReportMetricRow(
                    systemImage: "sun.max",
                    title: "밝기",
                    value: latestCameraCaptureRecord?.brightnessLabel ?? "-"
                )
            }

            Section("사용 지표") {
                MVPReportMetricRow(systemImage: "apps.iphone", title: "실행 횟수", value: "\(usageMetrics.totalOpenCount)")
                MVPReportMetricRow(
                    systemImage: "calendar.badge.clock",
                    title: "최근 실행",
                    value: usageMetrics.lastOpenAt?.overlineShortDate ?? "-"
                )
                MVPReportMetricRow(
                    systemImage: "calendar",
                    title: "최근 7일 활성",
                    value: "\(usageMetrics.activeDayCount())/7"
                )
                MVPReportMetricRow(systemImage: "chart.line.uptrend.xyaxis", title: "D7 상태", value: usageMetrics.d7StatusLabel())
            }

            Section("LLM 사용") {
                MVPReportMetricRow(systemImage: "paperplane", title: "생성 시도", value: "\(llmMetrics.requestedCount)")
                MVPReportMetricRow(systemImage: "checkmark.circle", title: "성공", value: "\(llmMetrics.completedCount)")
                MVPReportMetricRow(systemImage: "exclamationmark.circle", title: "실패", value: "\(llmMetrics.failedCount)")
                MVPReportMetricRow(
                    systemImage: "person.crop.circle.badge.checkmark",
                    title: "로컬 사용",
                    value: llmMetrics.requestedCount > 0 ? "사용됨" : "대기"
                )
                MVPReportMetricRow(
                    systemImage: "clock",
                    title: "최근 사용",
                    value: llmMetrics.lastUsedAt?.overlineShortDate ?? "-"
                )
            }

            Section("MVP 성공 지표") {
                MVPReportMetricRow(systemImage: "timer", title: "캡처 10초 이하", value: mvpCaptureSpeedMetric)
                MVPReportMetricRow(systemImage: "checkmark.seal", title: "OCR 90% 이상", value: mvpOCRMetric)
                MVPReportMetricRow(systemImage: "person.2", title: "D7 Retention 40% 이상", value: mvpD7Metric)
                MVPReportMetricRow(systemImage: "sparkles", title: "LLM 사용률 30% 이상", value: mvpLLMUsageMetric)
            }

            if !remainingItems.isEmpty {
                Section("남은 항목") {
                    ForEach(remainingItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.overlineMutedInk)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.overlineInk)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.overlineMutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if !verificationEvents.isEmpty {
                Section("최근 검증 이벤트") {
                    ForEach(verificationEvents.prefix(8)) { event in
                        MVPVerificationEventRow(event: event)
                    }
                }
            }

            if let latestOCRRecord {
                Section("최근 OCR 기록") {
                    OCRValidationRecordRow(record: latestOCRRecord)
                }
            }

            if !checklist.note.trimmed.isEmpty {
                Section("메모") {
                    Text(checklist.note)
                        .font(.caption)
                        .foregroundStyle(Color.overlineInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("검증 리포트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    copyReport()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("검증 리포트 복사")
            }
        }
    }

    private var latestOCRRecord: OCRValidationRecord? {
        ocrRecords.first
    }

    private var latestCaptureRecord: CapturePerformanceRecord? {
        captureRecords.first
    }

    private var latestCameraCaptureRecord: CapturePerformanceRecord? {
        captureRecords.first(where: \.isCameraCapture)
    }

    private var latestDeviceTestSession: MVPDeviceTestSession? {
        deviceTestSessions.first
    }

    private var recentCameraCaptureRecords: [CapturePerformanceRecord] {
        Array(captureRecords.filter(\.isCameraCapture).prefix(10))
    }

    private var captureSpeedLabel: String {
        guard let latestCameraCaptureRecord else { return "-" }
        return latestCameraCaptureRecord.meetsSpeedTarget ? "통과" : "초과"
    }

    private var capturePathLabel: String {
        guard let latestCameraCaptureRecord, latestCameraCaptureRecord.pathStepCount != nil else { return "-" }
        return latestCameraCaptureRecord.meetsPathTarget ? "통과" : "초과"
    }

    private var recentCameraSpeedSummary: String {
        let records = recentCameraCaptureRecords
        guard !records.isEmpty else { return "-" }

        let passedCount = records.filter(\.meetsSpeedTarget).count
        let averageMilliseconds = records.map(\.durationMilliseconds).reduce(0, +) / records.count
        let averageSeconds = Double(averageMilliseconds) / 1000
        return "\(passedCount)/\(records.count) · 평균 \(averageSeconds.formatted(.number.precision(.fractionLength(1))))초"
    }

    private var recentCameraPathSummary: String {
        let records = recentCameraCaptureRecords.filter { $0.pathStepCount != nil }
        guard !records.isEmpty else { return "-" }

        let passedCount = records.filter(\.meetsPathTarget).count
        let averageSteps = Double(records.compactMap(\.pathStepCount).reduce(0, +)) / Double(records.count)
        return "\(passedCount)/\(records.count) · 평균 \(averageSteps.formatted(.number.precision(.fractionLength(1))))단계"
    }

    private var coverURLReferenceCount: Int {
        library.books.filter { book in
            !(book.coverURLString ?? "").trimmed.isEmpty
        }
        .count
    }

    private var metadataSourceSummary: String {
        let grouped = Dictionary(grouping: library.books) { book in
            book.metadataSource ?? .manual
        }

        let orderedSources: [BookMetadataSource] = [.kakao, .aladin, .google, .manual]
        let summary = orderedSources.compactMap { source -> String? in
            guard let count = grouped[source]?.count, count > 0 else { return nil }
            return "\(metadataSourceTitle(source)) \(count)"
        }

        return summary.isEmpty ? "-" : summary.joined(separator: ", ")
    }

    private func metadataSourceTitle(_ source: BookMetadataSource) -> String {
        switch source {
        case .manual:
            "Manual"
        case .kakao:
            "Kakao"
        case .aladin:
            "Aladin"
        case .google:
            "Google"
        }
    }

    private var reportText: String {
        let latestOCRAccuracy = latestOCRRecord.map {
            $0.accuracy.formatted(.percent.precision(.fractionLength(1)))
        } ?? "-"
        let latestCapture = latestCaptureRecord?.durationLabel ?? "-"
        let latestCameraCapture = latestCameraCaptureRecord.map {
            "\($0.durationLabel), \($0.pathStepLabel), \($0.lineCount)줄, 신뢰도 \($0.confidenceLabel), 밝기 \($0.brightnessLabel)"
        } ?? "-"
        let remaining = remainingItems.map(\.title).joined(separator: ", ")
        let bookAPIConnection = checklist.kakaoSearchVerifiedAt?.overlineShortDate ?? "대기"
        let llmConnection = checklist.llmInsightVerifiedAt?.overlineShortDate ?? "대기"
        let nextActions = nextActionItems.map { item in
            "- \(item.title): \(item.detail)"
        }
        .joined(separator: "\n")
        let recentEvents = verificationEvents.prefix(8).map { event in
            let detail = event.detail.trimmed.isEmpty ? "" : " · \(event.detail)"
            return "- \(event.displayTitle): \(event.createdAt.overlineShortDate)\(detail)"
        }
        .joined(separator: "\n")
        let latestDeviceSessionText: String
        if let latestDeviceTestSession {
            let failedItems = latestDeviceTestSession.failedItems.map(\.title).joined(separator: ", ")
            let openItems = latestDeviceTestSession.openItems.map(\.title).joined(separator: ", ")
            latestDeviceSessionText = """
            최근 세션: \(latestDeviceTestSession.summary)
            기기: \(latestDeviceTestSession.runtime) · \(latestDeviceTestSession.deviceName)
            증거: \(latestDeviceTestSession.evidenceLabel)
            OS: \(latestDeviceTestSession.osVersion)
            앱: \(latestDeviceTestSession.appVersion)
            기록: \(latestDeviceTestSession.createdAt.overlineShortDate)
            실패: \(failedItems.isEmpty ? "없음" : failedItems)
            미확인: \(openItems.isEmpty ? "없음" : openItems)
            메모: \(latestDeviceTestSession.note.trimmed.isEmpty ? "-" : latestDeviceTestSession.note.trimmed)
            """
        } else {
            latestDeviceSessionText = "최근 세션: -"
        }

        return """
        Overline MVP 검증 리포트
        생성: \(Date().overlineShortDate)

        MVP 판정: \(canClaimMVP ? "통과 가능" : "대기")
        판정 근거: \(mvpDecisionReason)

        다음 조치
        \(nextActions.isEmpty ? "- 없음" : nextActions)

        점검: \(checklist.completedCount)/\(checklist.totalCount)
        최근 업데이트: \(checklist.updatedAt.overlineShortDate)

        환경
        실행 환경: \(environment.runtime)
        증거: \(environment.isPhysicalDevice ? "실기기 가능" : "빌드 확인용")
        OS: \(environment.systemVersion)
        앱: \(environment.appVersion)
        번들 ID: \(MVPBundleIdentifierStatus.value)
        앱 아이콘: \(MVPAppIconStatus.label)

        프리플라이트
        준비 상태: \(preflightStatus.summary)
        \(preflightStatus.reportText)

        책: \(library.books.count)
        글조각: \(library.highlightCount)
        저장된 인사이트: \(library.savedInsights.count)
        주 저장소: \(library.storageStatus.primaryLabel)
        백업 저장: \(library.storageStatus.fallbackLabel)
        마지막 저장: \(library.storageStatus.lastSavedLabel)
        초기화 복구: \(library.resetBackupAvailable ? "가능" : "없음")

        저작권/로컬 원칙
        표지 이미지: \(coverURLReferenceCount)권 URL 참조
        표지 저장: 앱 저장 없음
        도서 DB 출처: \(metadataSourceSummary)
        원문 사진: 저장 안 함
        사진 정책: OCR 후 폐기
        API 키 보관: \(KeychainStringStore.storagePolicyLabel)
        개인정보 매니페스트: \(MVPPrivacyManifestStatus.label)
        권한 문구: \(MVPPermissionPurposeStatus.label)
        App Intents: \(MVPAppIntentsMetadataStatus.label)
        클라우드 동기화: v1 없음
        AI 전송: 요청형
        공유: 매번 확인

        OCR
        최근 정확도: \(latestOCRAccuracy)
        검증 근거: \(ocrEvidenceLabel)

        API 연결 검증
        도서 API: \(bookAPIConnection)
        LLM 연결: \(llmConnection)

        실제 테스트 세션
        \(latestDeviceSessionText)

        캡처 성능
        최근 캡처: \(latestCapture)
        최근 카메라: \(latestCameraCapture)
        10초 기준: \(captureSpeedLabel)
        3단계 기준: \(capturePathLabel)
        최근 카메라 통과: \(recentCameraSpeedSummary)
        최근 경로 통과: \(recentCameraPathSummary)

        사용 지표
        실행 횟수: \(usageMetrics.totalOpenCount)
        최근 실행: \(usageMetrics.lastOpenAt?.overlineShortDate ?? "-")
        최근 7일 활성: \(usageMetrics.activeDayCount())/7
        D7 상태: \(usageMetrics.d7StatusLabel())

        LLM
        생성 시도: \(llmMetrics.requestedCount)
        성공: \(llmMetrics.completedCount)
        실패: \(llmMetrics.failedCount)
        최근 사용: \(llmMetrics.lastUsedAt?.overlineShortDate ?? "-")

        MVP 성공 지표
        캡처 10초 이하: \(mvpCaptureSpeedMetric)
        OCR 90% 이상: \(mvpOCRMetric)
        D7 Retention 40% 이상: \(mvpD7Metric)
        LLM 사용률 30% 이상: \(mvpLLMUsageMetric)

        남은 항목: \(remaining.isEmpty ? "없음" : remaining)
        최근 검증 이벤트:
        \(recentEvents.isEmpty ? "-" : recentEvents)
        메모: \(checklist.note.trimmed.isEmpty ? "-" : checklist.note.trimmed)
        """
    }

    private var canClaimMVP: Bool {
        guard checklist.isReady, let latestDeviceTestSession else { return false }
        return latestDeviceTestSession.isPassingEvidence
    }

    private var mvpDecisionReason: String {
        guard checklist.isReady else {
            return "MVP 점검 \(checklist.completedCount)/\(checklist.totalCount)"
        }

        guard let latestDeviceTestSession else {
            return "실제 테스트 세션 없음"
        }

        guard latestDeviceTestSession.isPhysicalDeviceEvidence else {
            return "실제 iPhone 세션 필요"
        }

        if latestDeviceTestSession.failedCount > 0 {
            return "\(latestDeviceTestSession.failedCount)개 실패"
        }

        if latestDeviceTestSession.openCount > 0 {
            return "\(latestDeviceTestSession.openCount)개 미확인"
        }

        guard latestDeviceTestSession.passedCount == checklist.totalCount else {
            return "최근 세션 \(latestDeviceTestSession.passedCount)/\(checklist.totalCount)"
        }

        return "10/10 실기기 세션 통과"
    }

    private var mvpCaptureSpeedMetric: String {
        guard let latestCameraCaptureRecord else { return "실기기 측정 대기" }
        return latestCameraCaptureRecord.meetsSpeedTarget
            ? "최근 \(latestCameraCaptureRecord.durationLabel) 통과"
            : "최근 \(latestCameraCaptureRecord.durationLabel) 초과"
    }

    private var mvpOCRMetric: String {
        guard let latestOCRRecord else { return "M0 검증 대기" }

        let accuracy = latestOCRRecord.accuracy.formatted(.percent.precision(.fractionLength(1)))
        if latestOCRRecord.passesM0 {
            return "\(accuracy) 통과"
        }

        if latestOCRRecord.accuracyPassesThreshold && !latestOCRRecord.isKoreanBookSample {
            return "\(accuracy) · 실제 책 필요"
        }

        return "\(accuracy) 미달"
    }

    private var ocrEvidenceLabel: String {
        guard let latestOCRRecord else { return "대기" }
        return "\(latestOCRRecord.sampleLabel) · \(latestOCRRecord.isKoreanBookSample ? "실제 한국어 책" : "샘플")"
    }

    private var mvpD7Metric: String {
        let localState = usageMetrics.d7StatusLabel()
        guard localState != "-" else { return "TestFlight 코호트 필요" }
        return "\(localState) · TestFlight 코호트 필요"
    }

    private var mvpLLMUsageMetric: String {
        guard llmMetrics.requestedCount > 0 else {
            return "TestFlight 코호트 필요"
        }

        return "로컬 \(llmMetrics.requestedCount)회 · TestFlight 코호트 필요"
    }

    private var nextActionItems: [MVPReportNextActionItem] {
        guard !canClaimMVP else { return [] }

        var items: [MVPReportNextActionItem] = []
        let notReadyPreflightRows = preflightStatus.rows.filter { !$0.isReady }
        if !notReadyPreflightRows.isEmpty {
            items.append(
                MVPReportNextActionItem(
                    systemImage: "checklist",
                    title: "프리플라이트 준비",
                    detail: "\(compactTitleList(notReadyPreflightRows.map(\.title), limit: 4)) 확인"
                )
            )
        }

        if let latestDeviceTestSession {
            if !latestDeviceTestSession.isPhysicalDeviceEvidence {
                items.append(
                    MVPReportNextActionItem(
                        systemImage: "iphone.gen3.radiowaves.left.and.right",
                        title: "실제 iPhone 세션 저장",
                        detail: "시뮬레이터 기록은 빌드 확인용입니다. 실제 기기에서 테스트 세션을 다시 저장하세요."
                    )
                )
            } else if !latestDeviceTestSession.failedItems.isEmpty {
                items.append(
                    MVPReportNextActionItem(
                        systemImage: "xmark.seal",
                        title: "실패 항목 재검증",
                        detail: compactTitleList(latestDeviceTestSession.failedItems.map(\.title), limit: 4)
                    )
                )
            } else if !latestDeviceTestSession.openItems.isEmpty {
                items.append(
                    MVPReportNextActionItem(
                        systemImage: "hourglass",
                        title: "미확인 항목 확인",
                        detail: compactTitleList(latestDeviceTestSession.openItems.map(\.title), limit: 4)
                    )
                )
            } else if latestDeviceTestSession.passedCount != checklist.totalCount {
                items.append(
                    MVPReportNextActionItem(
                        systemImage: "checklist.checked",
                        title: "세션 범위 보강",
                        detail: "최근 실기기 세션이 \(latestDeviceTestSession.passedCount)/\(checklist.totalCount)개만 통과했습니다."
                    )
                )
            }
        } else {
            items.append(
                MVPReportNextActionItem(
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    title: "실제 iPhone 세션 저장",
                    detail: "테스트 절차를 따라 10개 항목 결과를 기록하세요."
                )
            )
        }

        if !remainingItems.isEmpty {
            items.append(
                MVPReportNextActionItem(
                    systemImage: "checkmark.shield",
                    title: "MVP 미완료 항목",
                    detail: compactTitleList(remainingItems.map(\.title), limit: 4)
                )
            )
        }

        return Array(items.prefix(4))
    }

    private func compactTitleList(_ titles: [String], limit: Int) -> String {
        let compactTitles = titles.filter { !$0.trimmed.isEmpty }
        guard compactTitles.count > limit else {
            return compactTitles.joined(separator: ", ")
        }

        let visibleTitles = compactTitles.prefix(limit).joined(separator: ", ")
        return "\(visibleTitles) 외 \(compactTitles.count - limit)개"
    }

    private func copyReport() {
        UIPasteboard.general.string = reportText
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            didCopyReport = true
        }
    }

    private var remainingItems: [MVPReportRemainingItem] {
        [
            MVPReportRemainingItem(
                isDone: checklist.captureSpeedVerified,
                systemImage: "timer",
                title: "10초 안에 캡처 저장",
                detail: "실제 카메라 경로에서 캡처 저장 시간을 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.capturePathVerified,
                systemImage: "hand.tap",
                title: "캡처 경로 3탭 이하",
                detail: "열기, 선 긋기, 저장 흐름이 끊기지 않는지 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.ocrAccuracyVerified,
                systemImage: "text.viewfinder",
                title: "한국어 OCR 90% 이상",
                detail: "OCR 검증 기록에서 M0 통과 결과 입력"
            ),
            MVPReportRemainingItem(
                isDone: checklist.pageBoundaryVerified,
                systemImage: "doc.viewfinder",
                title: "페이지 경계 감지",
                detail: "실제 책 페이지 윤곽이 카메라 화면에 맞게 표시되는지 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.snapshotCropVerified,
                systemImage: "photo.badge.minus",
                title: "원문 사진 미저장",
                detail: "캡처 후 글조각만 저장되고 원문 사진은 남지 않는지 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.lowLightVerified,
                systemImage: "flashlight.on.fill",
                title: "저조도 캡처",
                detail: "어두운 환경에서 안내와 플래시 토글 후 캡처 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.isbnScanVerified,
                systemImage: "barcode.viewfinder",
                title: "ISBN 스캔",
                detail: "실제 책 바코드를 카메라로 읽어 책 검색 실행"
            ),
            MVPReportRemainingItem(
                isDone: checklist.speechMemoVerified,
                systemImage: "mic",
                title: "음성 메모",
                detail: "온디바이스 STT로 메모가 저장되는지 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.kakaoSearchVerified,
                systemImage: "book.closed",
                title: "도서 API",
                detail: "Kakao 또는 Aladin 도서 검색 연결 확인"
            ),
            MVPReportRemainingItem(
                isDone: checklist.llmInsightVerified,
                systemImage: "sparkles",
                title: "LLM 인사이트",
                detail: "API 키와 모델로 연결 테스트 또는 인사이트 생성"
            )
        ]
        .filter { !$0.isDone }
    }
}

private struct MVPReportMetricRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.overlineAccent)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineInk)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk)
        }
    }
}

private struct MVPReportRemainingItem: Identifiable {
    let id = UUID()
    let isDone: Bool
    let systemImage: String
    let title: String
    let detail: String
}

private struct MVPReportNextActionItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let detail: String
}

private extension MVPReadinessItem {
    func isVerified(in checklist: MVPReadinessChecklist) -> Bool {
        switch self {
        case .captureSpeed:
            checklist.captureSpeedVerified
        case .capturePath:
            checklist.capturePathVerified
        case .ocrAccuracy:
            checklist.ocrAccuracyVerified
        case .pageBoundary:
            checklist.pageBoundaryVerified
        case .snapshotCrop:
            checklist.snapshotCropVerified
        case .lowLight:
            checklist.lowLightVerified
        case .isbnScan:
            checklist.isbnScanVerified
        case .speechMemo:
            checklist.speechMemoVerified
        case .kakaoSearch:
            checklist.kakaoSearchVerified
        case .llmInsight:
            checklist.llmInsightVerified
        }
    }

    func verifiedAt(in checklist: MVPReadinessChecklist) -> Date? {
        switch self {
        case .captureSpeed:
            checklist.captureSpeedVerifiedAt
        case .capturePath:
            checklist.capturePathVerifiedAt
        case .ocrAccuracy:
            checklist.ocrAccuracyVerifiedAt
        case .pageBoundary:
            checklist.pageBoundaryVerifiedAt
        case .snapshotCrop:
            checklist.snapshotCropVerifiedAt
        case .lowLight:
            checklist.lowLightVerifiedAt
        case .isbnScan:
            checklist.isbnScanVerifiedAt
        case .speechMemo:
            checklist.speechMemoVerifiedAt
        case .kakaoSearch:
            checklist.kakaoSearchVerifiedAt
        case .llmInsight:
            checklist.llmInsightVerifiedAt
        }
    }
}

private struct MVPVerificationEventRow: View {
    let event: MVPVerificationEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.overlineAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.overlineInk)
                    Text(event.createdAt.overlineShortDate)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                }

                if !event.detail.trimmed.isEmpty {
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(Color.overlineMutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct OCRValidationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let capturedHighlightCount: Int
    let reviewedHighlightCount: Int

    @State private var testedLineCountText = ""
    @State private var correctionCountText = ""
    @State private var sampleTitle = ""
    @State private var isKoreanBookSample = true
    @State private var note = ""
    @State private var records = OCRValidationStore.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("캡처", systemImage: "text.viewfinder")
                        Spacer()
                        Text("\(capturedHighlightCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("검수", systemImage: "checkmark.seal")
                        Spacer()
                        Text("\(reviewedHighlightCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("이번 OCR 테스트") {
                    TextField("검증 책 또는 샘플", text: $sampleTitle)
                    Toggle(isOn: $isKoreanBookSample) {
                        Label("실제 한국어 책", systemImage: "book.closed")
                    }
                    TextField("검증한 줄 수", text: $testedLineCountText)
                        .keyboardType(.numberPad)
                    TextField("수정 필요 줄 수", text: $correctionCountText)
                        .keyboardType(.numberPad)
                    TextField("메모", text: $note, axis: .vertical)
                        .lineLimit(2...4)

                    OCRValidationResultRow(
                        accuracy: currentAccuracy,
                        passesM0: currentPassesM0,
                        accuracyPassesThreshold: currentAccuracyPassesThreshold,
                        isKoreanBookSample: isKoreanBookSample,
                        isReady: currentTestedLineCount > 0
                    )
                }

                if !records.isEmpty {
                    Section("최근 기록") {
                        ForEach(records.prefix(5)) { record in
                            OCRValidationRecordRow(record: record)
                        }
                    }
                }
            }
            .navigationTitle("OCR 검증")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("기록") {
                        saveRecord()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var currentTestedLineCount: Int {
        Int(testedLineCountText.filter(\.isNumber)) ?? 0
    }

    private var currentCorrectionCount: Int {
        Int(correctionCountText.filter(\.isNumber)) ?? 0
    }

    private var currentAccuracy: Double {
        guard currentTestedLineCount > 0 else { return 0 }
        return Double(max(currentTestedLineCount - currentCorrectionCount, 0)) / Double(currentTestedLineCount)
    }

    private var currentPassesM0: Bool {
        isKoreanBookSample && currentAccuracyPassesThreshold
    }

    private var currentAccuracyPassesThreshold: Bool {
        currentTestedLineCount > 0 && currentCorrectionCount <= currentTestedLineCount && currentAccuracy >= 0.90
    }

    private var canSave: Bool {
        currentTestedLineCount > 0 && currentCorrectionCount <= currentTestedLineCount
    }

    private func saveRecord() {
        let record = OCRValidationRecord(
            testedLineCount: currentTestedLineCount,
            correctionCount: currentCorrectionCount,
            sampleTitle: sampleTitle.trimmed,
            isKoreanBookSample: isKoreanBookSample,
            note: note.trimmed
        )
        OCRValidationStore.add(record)
        if record.passesM0 {
            MVPReadinessStore.markVerified(
                .ocrAccuracy,
                detail: "\(record.accuracy.formatted(.percent.precision(.fractionLength(1)))) · \(record.testedLineCount)줄 중 \(record.correctionCount)줄 수정"
            )
        }
        records = OCRValidationStore.load()
        testedLineCountText = ""
        correctionCountText = ""
        sampleTitle = ""
        isKoreanBookSample = true
        note = ""
    }
}

private struct OCRValidationResultRow: View {
    let accuracy: Double
    let passesM0: Bool
    let accuracyPassesThreshold: Bool
    let isKoreanBookSample: Bool
    let isReady: Bool

    var body: some View {
        HStack {
            Label(statusTitle, systemImage: statusSystemImage)
                .foregroundStyle(statusColor)

            Spacer()

            Text(isReady ? accuracy.formatted(.percent.precision(.fractionLength(1))) : "-")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.overlineInk)
        }
    }

    private var statusTitle: String {
        guard isReady else { return "대기" }
        if passesM0 { return "M0 통과" }
        if accuracyPassesThreshold && !isKoreanBookSample { return "실제 책 확인 필요" }
        return "검증 필요"
    }

    private var statusSystemImage: String {
        guard isReady else { return "circle.dashed" }
        return passesM0 ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var statusColor: Color {
        guard isReady else { return Color.overlineMutedInk }
        return passesM0 ? Color.overlineAccent : Color.overlineCoral
    }
}

private struct OCRValidationRecordRow: View {
    let record: OCRValidationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(recordStatusTitle, systemImage: recordStatusSystemImage)
                .foregroundStyle(record.passesM0 ? Color.overlineAccent : Color.overlineCoral)

                Spacer()

                Text(record.accuracy.formatted(.percent.precision(.fractionLength(1))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)
            }

            Text("\(record.testedLineCount)줄 중 \(record.correctionCount)줄 수정")
                .font(.caption)
                .foregroundStyle(Color.overlineMutedInk)

            Text("\(record.sampleLabel) · \(record.isKoreanBookSample ? "실제 한국어 책" : "샘플")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.82))

            if !record.note.trimmed.isEmpty {
                Text(record.note)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.82))
                    .lineLimit(2)
            }

            Text(record.createdAt.overlineShortDate)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.68))
        }
        .padding(.vertical, 3)
    }

    private var recordStatusTitle: String {
        if record.passesM0 { return "M0 통과" }
        if record.accuracyPassesThreshold && !record.isKoreanBookSample { return "실제 책 확인 필요" }
        return "검증 필요"
    }

    private var recordStatusSystemImage: String {
        record.passesM0 ? "checkmark.circle.fill" : "exclamationmark.circle"
    }
}

private struct BookCoverCard: View {
    let book: ReadingBook

    var body: some View {
        BookCoverArtwork(book: book, cornerRadius: 8)
            .aspectRatio(0.72, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Text("\(book.highlights.count)")
                    .font(.caption.weight(.bold))
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
                        .font(.body.weight(.medium))
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
                    .font(.caption)
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

                    if !book.highlights.isEmpty {
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
                        ContentUnavailableView(
                            "검색 결과 없음",
                            systemImage: "magnifyingglass",
                            description: Text("다른 글조각, 태그, 메모로 찾아보세요.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowChrome(top: 0, bottom: 16)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .overlineBottomMenuCompaction()
                .background(OverlineCanvasBackground().ignoresSafeArea())
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

    var id: String {
        switch self {
        case .editBook(let id): "editBook-\(id.uuidString)"
        case .editHighlight(let id): "editHighlight-\(id.uuidString)"
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
                        OverlineShareButton(item: book.shareText, accessibilityLabel: "전체 메모 공유")
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !book.summary.trimmed.isEmpty {
                Text(book.summary)
                    .font(.system(size: 15, weight: .medium))
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
            font: .subheadline,
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
                .font(.system(size: 15, weight: .semibold))
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
    var bookTitle: String? = nil
    var searchQuery = ""
    var edit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(highlight.stickyTone.paper.opacity(0.94))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 10) {
                    if let bookTitle = visibleBookTitle {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "book.closed")
                                .font(.caption.weight(.bold))
                                .symbolRenderingMode(.hierarchical)

                            SearchHighlightedText(
                                text: bookTitle,
                                query: searchQuery,
                                font: .caption.weight(.semibold),
                                foregroundStyle: Color.overlineMutedInk.opacity(0.76),
                                lineSpacing: 0
                            )
                            .lineLimit(1)
                        }
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.76))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SearchHighlightedText(
                        text: highlight.text,
                        query: searchQuery,
                        font: .body.weight(.semibold),
                        foregroundStyle: Color.overlineInk,
                        lineSpacing: 5
                    )

                    if !highlight.memo.isEmpty {
                        ScrapbookMemoNote(
                            memo: highlight.memo,
                            tone: highlight.stickyTone,
                            searchQuery: searchQuery
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            HStack(alignment: .center, spacing: 10) {
                HighlightMetaBar(highlight: highlight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                OverlineShareButton(
                    item: highlight.shareText,
                    accessibilityLabel: "공유",
                    iconYOffset: -2
                )
            }
            .frame(minHeight: 26, alignment: .center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .libraryGlassSurface(
            cornerRadius: 18,
            tint: Color.white.opacity(0.13),
            fillOpacity: 0.08,
            strokeOpacity: 0.34,
            shadowOpacity: 0.05,
            shadowRadius: 16
        )
    }

    private var visibleBookTitle: String? {
        guard let title = bookTitle?.trimmed, !title.isEmpty else {
            return nil
        }
        return title
    }
}

private extension View {
    @ViewBuilder
    func libraryGlassSurface(
        cornerRadius: CGFloat,
        tint: Color = Color.white.opacity(0.12),
        fillOpacity: Double = 0.07,
        strokeOpacity: Double = 0.30,
        shadowOpacity: Double = 0.05,
        shadowRadius: CGFloat = 14
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(fillOpacity))
                }
                .glassEffect(
                    .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .libraryGlassChrome(
                    cornerRadius: cornerRadius,
                    strokeOpacity: strokeOpacity,
                    shadowOpacity: shadowOpacity,
                    shadowRadius: shadowRadius
                )
        } else {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .libraryGlassChrome(
                    cornerRadius: cornerRadius,
                    strokeOpacity: strokeOpacity,
                    shadowOpacity: shadowOpacity,
                    shadowRadius: shadowRadius
                )
        }
    }

    func libraryGlassChrome(
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
                    .stroke(Color.white.opacity(strokeOpacity * 0.62), lineWidth: 0.6)
                    .blur(radius: 0.2)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: 24)
                    }
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowRadius * 0.42)
    }
}

private struct OverlineShareButton: View {
    let item: String
    let accessibilityLabel: String
    var iconYOffset: CGFloat = 0

    var body: some View {
        ShareLink(item: item) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.overlineMutedInk.opacity(0.46))
                .offset(y: iconYOffset)
                .frame(width: 30, height: 26)
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

    var shareText: String {
        [
            text,
            visiblePageReference,
            tags.joined(separator: " ")
        ]
        .compactMap { $0 }
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
            highlightText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}

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
                .font(.caption2.weight(.bold))
                .frame(width: 12)
            Text(text)
                .font(.caption2.weight(.semibold))
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
}
