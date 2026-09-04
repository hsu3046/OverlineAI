import AppIntents

struct ReadingBookEntity: AppEntity, Identifiable {
    let id: String
    let title: String
    let author: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "책"
    static let defaultQuery = ReadingBookEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(author)"
        )
    }
}

struct ReadingBookEntityQuery: EntityQuery {
    func entities(for identifiers: [ReadingBookEntity.ID]) async throws -> [ReadingBookEntity] {
        await MainActor.run {
            ReadingLibrary.shared.books
                .filter { identifiers.contains($0.id.uuidString) }
                .map { ReadingBookEntity(book: $0) }
        }
    }

    func suggestedEntities() async throws -> [ReadingBookEntity] {
        await MainActor.run {
            ReadingLibrary.shared.books.map { ReadingBookEntity(book: $0) }
        }
    }

    func defaultResult() async -> ReadingBookEntity? {
        await MainActor.run {
            ReadingLibrary.shared.selectedBook.map { ReadingBookEntity(book: $0) }
        }
    }
}

private extension ReadingBookEntity {
    init(book: ReadingBook) {
        id = book.id.uuidString
        title = book.title
        author = book.author
    }

    var bookID: ReadingBook.ID? {
        UUID(uuidString: id)
    }
}

enum OverlineIntentDestination: String, AppEnum {
    case capture
    case library
    case insights
    case community

    static var typeDisplayName: LocalizedStringResource { "화면" }
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "화면"

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .capture: "캡처",
            .library: "책장",
            .insights: "인사이트",
            .community: "커뮤니티"
        ]
    }

    var appTab: AppTab {
        switch self {
        case .capture: .capture
        case .library: .library
        case .insights: .insights
        case .community: .community
        }
    }
}

struct OpenOverlineIntent: AppIntent {
    static let title: LocalizedStringResource = "글조각 서랍 열기"
    static let description = IntentDescription("글조각 서랍의 캡처, 책장, 인사이트, 커뮤니티 화면을 바로 엽니다.")
    static let openAppWhenRun = true

    @Parameter(title: "화면")
    var destination: OverlineIntentDestination

    init() {
        destination = .capture
    }

    init(destination: OverlineIntentDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppIntentRouter.shared.open(destination.appTab)
        }
        return .result()
    }
}

struct AddReadingThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "읽다가 든 생각 저장"
    static let description = IntentDescription("책을 읽다가 떠오른 짧은 생각을 글조각 서랍에 저장합니다.")
    static let openAppWhenRun = false

    @Parameter(
        title: "생각",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var thought: String

    @Parameter(title: "책")
    var book: ReadingBookEntity?

    init() {
        thought = ""
        book = nil
    }

    init(thought: String, book: ReadingBookEntity? = nil) {
        self.thought = thought
        self.book = book
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = thought.trimmed
        guard !trimmed.isEmpty else {
            return .result(dialog: "저장할 생각을 입력해 주세요.")
        }

        await MainActor.run {
            _ = ReadingLibrary.shared.addQuickThought(trimmed, bookID: book?.bookID)
        }
        await ReadingLibrary.shared.flushPendingPersistence()

        if let book {
            return .result(dialog: "\(book.title)에 저장했어요.")
        }

        return .result(dialog: "글조각 서랍에 저장했어요.")
    }
}

extension InsightPrompt: AppEnum {
    nonisolated static var typeDisplayName: LocalizedStringResource { "인사이트 방식" }
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation { "인사이트 방식" }

    nonisolated static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .questions: "질문",
            .connect: "연결",
            .expand: "확장",
            .digest: "요약"
        ]
    }
}

struct OpenInsightWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "생각 정리하기"
    static let description = IntentDescription("최근 글조각을 선택한 상태로 글조각 서랍의 인사이트 작업 공간을 엽니다.")
    static let openAppWhenRun = true

    @Parameter(title: "방식")
    var prompt: InsightPrompt

    @Parameter(title: "질문")
    var question: String?

    init() {
        prompt = .expand
        question = nil
    }

    init(prompt: InsightPrompt, question: String? = nil) {
        self.prompt = prompt
        self.question = question
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let sourceLimit = prompt == .digest ? 8 : 3
            let highlightIDs = Set(ReadingLibrary.shared.recentHighlights.prefix(sourceLimit).map(\.id))
            AppIntentRouter.shared.open(
                .insights,
                insightSeed: InsightSeedRequest(
                    highlightIDs: highlightIDs,
                    prompt: prompt,
                    question: question
                )
            )
        }

        return .result()
    }
}

struct OverlineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenOverlineIntent(destination: .capture),
            phrases: [
                "\(.applicationName)에서 캡처",
                "\(.applicationName)으로 책 캡처",
                "Capture with \(.applicationName)",
                "Open capture in \(.applicationName)"
            ],
            shortTitle: "캡처",
            systemImageName: "text.viewfinder"
        )

        AppShortcut(
            intent: OpenOverlineIntent(destination: .library),
            phrases: [
                "\(.applicationName)에서 책장 열기",
                "\(.applicationName) 책장",
                "Open library in \(.applicationName)",
                "Show books in \(.applicationName)"
            ],
            shortTitle: "책장",
            systemImageName: "books.vertical"
        )

        AppShortcut(
            intent: OpenOverlineIntent(destination: .insights),
            phrases: [
                "\(.applicationName)에서 인사이트 열기",
                "\(.applicationName) 생각 정리",
                "Open insights in \(.applicationName)"
            ],
            shortTitle: "인사이트",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: OpenOverlineIntent(destination: .community),
            phrases: [
                "\(.applicationName)에서 커뮤니티 열기",
                "\(.applicationName) 책 커뮤니티",
                "Open community in \(.applicationName)"
            ],
            shortTitle: "커뮤니티",
            systemImageName: "person.3"
        )

        AppShortcut(
            intent: AddReadingThoughtIntent(),
            phrases: [
                "\(.applicationName)에 생각 저장",
                "\(.applicationName)에 독서 메모",
                "Save a reading thought with \(.applicationName)",
                "Add a note to \(.applicationName)"
            ],
            shortTitle: "생각 저장",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: OpenInsightWorkspaceIntent(),
            phrases: [
                "\(.applicationName)에서 생각 정리",
                "\(.applicationName)에서 인사이트 만들기",
                "\(.applicationName) 글조각 요약",
                "Organize thoughts in \(.applicationName)"
            ],
            shortTitle: "생각 정리",
            systemImageName: "sparkles"
        )
    }
}
