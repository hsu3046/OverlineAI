import AppIntents
import SwiftUI
import WidgetKit
import OSLog
import ImageIO

struct WidgetBookChoice: AppEntity {
    let id: String
    let title: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "책"
    static let defaultQuery = WidgetBookQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WidgetBookQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetBookChoice] {
        choices().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetBookChoice] { choices() }
    private func choices() -> [WidgetBookChoice] {
        guard let snapshot = try? WidgetStore().readSnapshot() else { return [] }
        let ids = Set(snapshot.quotes.map(\.bookID))
        return snapshot.books.filter { ids.contains($0.id) }
            .map { WidgetBookChoice(id: $0.id.uuidString, title: $0.title) }
    }
}

struct QuoteConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "글조각"
    static let description = IntentDescription("최근 글조각을 5분 간격으로 다시 만납니다.")
    @Parameter(title: "책") var book: WidgetBookChoice?
}

struct QuoteEntry: TimelineEntry {
    let date: Date
    let quote: WidgetQuote?
    let books: [WidgetBook]
    var unavailable = false
    var coverData: Data? = nil
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry { WidgetSamples.quoteEntry }
    func snapshot(for configuration: QuoteConfiguration, in context: Context) async -> QuoteEntry {
        if context.isPreview { return WidgetSamples.quoteEntry }
        return await entries(configuration: configuration, now: .now, family: context.family, snapshotOnly: true).first!
    }
    func timeline(for configuration: QuoteConfiguration, in context: Context) async -> Timeline<QuoteEntry> {
        await Timeline(entries: entries(configuration: configuration, now: .now, family: context.family), policy: .atEnd)
    }
    private func entries(configuration: QuoteConfiguration, now: Date, family: WidgetFamily, snapshotOnly: Bool = false) async -> [QuoteEntry] {
        do {
            let snapshot = try WidgetStore().readSnapshot()
            let bookID = configuration.book.flatMap { UUID(uuidString: $0.id) }
            let candidates = snapshot.candidates(bookID: bookID)
            let dates = snapshotOnly ? [now] : QuoteSchedule.dates(from: now)
            var entries = dates.map {
                QuoteEntry(date: $0, quote: QuoteSchedule.quote(in: candidates, at: $0), books: Array(snapshot.readingBooks.prefix(2)))
            }
            if family == .systemLarge {
                let ids = Set(entries.compactMap { $0.quote?.bookID })
                let covers = await WidgetCoverLoader.images(for: snapshot.books.filter { ids.contains($0.id) })
                for index in entries.indices {
                    if let id = entries[index].quote?.bookID { entries[index].coverData = covers[id] }
                }
            }
            return entries
        } catch {
            return [QuoteEntry(date: now, quote: nil, books: [], unavailable: true),
                    QuoteEntry(date: now.addingTimeInterval(3600), quote: nil, books: [], unavailable: true)]
        }
    }
}

struct QuoteWidgetView: View {
    let entry: QuoteEntry
    #if WIDGET_RENDER
    var family: WidgetFamily = .systemMedium
    #else
    @Environment(\.widgetFamily) private var family
    #endif
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .footnote) private var smallTextSize = 13
    @ScaledMetric(relativeTo: .subheadline) private var textSize = 15

    var body: some View {
        quoteContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.primary)
        .containerBackground(for: .widget) { widgetBackground }
        .widgetURL(entry.quote.map { WidgetLink.quote($0.id).url } ?? WidgetLink.capture.url)
    }

    private var quoteContent: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 3 : 8) {
            if let quote = entry.quote {
                highlightedText(quote.text)
                    .font(.system(size: family == .systemSmall ? smallTextSize : textSize))
                    .lineSpacing(family == .systemLarge ? 3 : 2)
                    .lineLimit(family == .systemLarge ? (entry.books.isEmpty ? 10 : 7) : family == .systemSmall ? 8 : 5)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .privacySensitive()

                if family != .systemSmall {
                    Spacer(minLength: 0)
                    Group {
                        if family == .systemMedium {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(quote.bookTitle).font(.caption).lineLimit(1)
                                if !quote.page.isEmpty {
                                    Text("· \(quote.page)").font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        } else {
                            HStack(spacing: 10) {
                                coverThumbnail
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(quote.bookTitle).font(.caption).lineLimit(2)
                                        if !quote.page.isEmpty {
                                            Text("· \(quote.page)").font(.caption2).foregroundStyle(.secondary)
                                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                        }
                                    }
                                    if !quote.author.isEmpty {
                                        Text(quote.author).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .privacySensitive()
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.unavailable ? "앱을 열어 글조각을 불러오세요" : "마음에 남은 문장을 담아보세요")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if family == .systemLarge && !entry.books.isEmpty {
                Divider().padding(.vertical, 2)
                Text("읽는 중").font(.caption).foregroundStyle(.secondary)
                ForEach(entry.books) { book in
                    Link(destination: WidgetLink.book(book.id).url) {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed").foregroundStyle(.secondary)
                            Text(book.title).lineLimit(1)
                            Spacer(minLength: 0)
                            if let page = book.bookmark {
                                Label("\(page)", systemImage: "bookmark").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .privacySensitive()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
    }

    var widgetBackground: some View {
        WidgetPaperBackground()
            .overlay {
                QuoteCornerMarks().stroke(accent.opacity(0.65), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
    }

    private var coverThumbnail: some View {
        Group {
            if let data = entry.coverData, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: image, scale: 2).resizable().scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 38, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func highlightedText(_ text: String) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            Text(text).textRenderer(QuoteMarkerRenderer(color: accent))
        } else {
            Text(text).italic().background(accent.opacity(0.16))
        }
    }

    private var accent: Color {
        guard renderingMode == .fullColor else { return .primary }
        return switch entry.quote?.tone {
        case "rose": Color(red: 0.95, green: 0.58, blue: 0.67)
        case "blue": Color(red: 0.56, green: 0.79, blue: 0.92)
        case "mint": Color(red: 0.58, green: 0.82, blue: 0.68)
        case "purple": Color(red: 0.74, green: 0.64, blue: 0.91)
        default: Color(red: 0.98, green: 0.86, blue: 0.31)
        }
    }
}

private struct WidgetPaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .light {
            Color(red: 252.0 / 255, green: 254.0 / 255, blue: 1)
        } else {
            Rectangle().fill(.background)
        }
    }
}

private struct QuoteCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 5
        let radius: CGFloat = min(25, min(rect.width, rect.height) / 5)
        let length = radius + 6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset + length, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset + radius, y: rect.minY + inset))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset + radius),
                          control: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset + length))
        path.move(to: CGPoint(x: rect.maxX - inset - length, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset - radius, y: rect.maxY - inset))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - radius),
                          control: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - length))
        return path
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct QuoteMarkerRenderer: TextRenderer {
    let color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for (lineIndex, line) in layout.enumerated() {
            let bounds = line.typographicBounds.rect
            // Follow each rendered line, including a shorter last line, without coloring the gaps.
            let stripe = CGRect(x: bounds.minX, y: bounds.minY + bounds.height * 0.25,
                                width: bounds.width, height: bounds.height * 0.68)
            context.fill(Path(roundedRect: stripe, cornerRadius: 1), with: .color(color.opacity(0.22)))
            for (runIndex, run) in line.enumerated() {
                for sliceIndex in run.indices {
                    var glyphContext = context
                    // Korean fallback fonts often have no italic face; slant the ink around its baseline.
                    glyphContext.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.14, d: 1,
                                                               tx: 0.14 * line.typographicBounds.origin.y, ty: 0))
                    if layout.isTruncated && lineIndex == layout.count - 1
                        && runIndex == line.count - 1 && sliceIndex == run.endIndex - 1 {
                        glyphContext.opacity *= 0.35
                    }
                    glyphContext.draw(run[sliceIndex])
                }
            }
        }
    }
}

struct QuotesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.quoteKind, intent: QuoteConfiguration.self, provider: QuoteProvider()) {
            QuoteWidgetView(entry: $0)
        }
        .configurationDisplayName("다시 만난 글조각")
        .description("저장한 문장과 읽는 중인 책을 홈 화면에서 만나세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

enum RankingChoice: String, AppEnum {
    case bestseller, loans
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "순위"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.bestseller: "베스트셀러", .loans: "도서관 대출 순위"]
    var title: String { self == .loans ? "도서관 대출 순위" : "베스트셀러" }
    var source: String { self == .loans ? "도서관 정보나루" : "알라딘" }
}

struct RankingConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "인기 도서"
    @Parameter(title: "순위", default: .bestseller) var kind: RankingChoice
}

struct RankingEntry: TimelineEntry {
    let date: Date
    let kind: RankingChoice
    let data: WidgetRankings?
    var failed = false
}

actor RankingLoader {
    static let shared = RankingLoader()
    private var inFlight: [String: Task<WidgetRankings, Error>] = [:]
    private let logger = Logger(subsystem: "vote.aib.bzogak", category: "WidgetRankings")

    func load(kind: RankingChoice) async -> RankingEntry {
        let now = Date.now
        let store = try? WidgetStore()
        let cached = try? store?.readRankings(kind: kind.rawValue)
        if let cached, cached.isFresh(at: now) {
            return RankingEntry(date: now, kind: kind, data: cached)
        }
        do {
            let task: Task<WidgetRankings, Error>
            if let existing = inFlight[kind.rawValue] {
                task = existing
            } else {
                task = Task { try await Self.fetch(kind: kind.rawValue) }
                inFlight[kind.rawValue] = task
            }
            defer { inFlight[kind.rawValue] = nil }
            let result = try await task.value
            if let store {
                do { try store.writeRankings(result, kind: kind.rawValue) }
                catch { logger.error("Unable to cache widget rankings") }
            }
            return RankingEntry(date: now, kind: kind, data: result)
        } catch {
            logger.error("Widget ranking refresh failed")
            return RankingEntry(date: now, kind: kind, data: cached, failed: true)
        }
    }

    private static func fetch(kind: String) async throws -> WidgetRankings {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OverlineAPIBaseURL") as? String,
              let base = URL(string: value), base.scheme == "https",
              var url = URLComponents(url: base.appendingPathComponent("api/v1/rankings"), resolvingAgainstBaseURL: false)
        else { throw URLError(.badURL) }
        url.queryItems = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "category", value: "all")]
        guard let endpoint = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 1_000_000 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(WidgetRankings.self, from: data)
        return WidgetRankings(items: Array(decoded.items.prefix(10)), fetchedAt: decoded.fetchedAt, cachedAt: .now)
    }
}

struct RankingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RankingEntry { WidgetSamples.rankingEntry }
    func snapshot(for configuration: RankingConfiguration, in context: Context) async -> RankingEntry {
        if context.isPreview { return WidgetSamples.rankingEntry }
        return await RankingLoader.shared.load(kind: configuration.kind)
    }
    func timeline(for configuration: RankingConfiguration, in context: Context) async -> Timeline<RankingEntry> {
        let entry = await RankingLoader.shared.load(kind: configuration.kind)
        let next = entry.failed ? Date.now.addingTimeInterval(3600)
            : max(Date.now.addingTimeInterval(300), (entry.data?.cachedAt ?? .now).addingTimeInterval(86400))
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct RankingWidgetView: View {
    let entry: RankingEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.kind.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.secondary)
            }
            if let data = entry.data, !data.items.isEmpty {
                ForEach(Array(data.items.prefix(family == .systemLarge ? 5 : 3))) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(item.rank)").monospacedDigit().foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1)
                            if family == .systemLarge {
                                Text(item.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }.font(.subheadline)
                }
            } else {
                Text(entry.failed ? "순위를 불러오지 못했어요" : "표시할 순위가 없어요")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Text(entry.kind.source)
                Spacer(minLength: 0)
                if let date = entry.data?.sourceDate {
                    Text(date, format: .dateTime.month().day())
                }
                if entry.failed { Image(systemName: "arrow.clockwise") }
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { WidgetPaperBackground() }
        .widgetURL(WidgetLink.rankings(entry.kind.rawValue).url)
    }
}

struct RankingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.rankingKind, intent: RankingConfiguration.self, provider: RankingProvider()) {
            RankingWidgetView(entry: $0)
        }
        .configurationDisplayName("인기 도서")
        .description("베스트셀러와 도서관 대출 순위를 살펴보세요.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#if !WIDGET_RENDER
@main struct BZOGAKWidgetBundle: WidgetBundle {
    var body: some Widget { QuotesWidget(); RankingsWidget() }
}
#endif

enum WidgetSamples {
    static let book = WidgetBook(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "나의 독서 노트", author: "", bookmark: 128, readingUpdatedAt: .now)
    static let quoteEntry = QuoteEntry(date: .now, quote: WidgetQuote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, bookID: book.id,
        text: "한 조각씩 쌓인 문장들이 나만의 생각으로 성장합니다.", bookTitle: book.title,
        author: "글조각 서랍", page: "p.128", tone: "yellow", createdAt: .now
    ), books: [book])
    static let rankingEntry = RankingEntry(date: .now, kind: .bestseller, data: WidgetRankings(
        items: (1...3).map { WidgetRankingItem(id: "preview-\($0)", rank: $0, title: "새롭게 만날 책 \($0)", author: "작가") },
        fetchedAt: "2026-09-09T00:00:00Z", cachedAt: .now
    ))
}

#if !WIDGET_RENDER
#Preview(as: .systemSmall) { QuotesWidget() } timeline: { WidgetSamples.quoteEntry }
#Preview(as: .systemMedium) { QuotesWidget() } timeline: { WidgetSamples.quoteEntry }
#Preview(as: .systemLarge) { QuotesWidget() } timeline: { WidgetSamples.quoteEntry }
#Preview(as: .systemMedium) { RankingsWidget() } timeline: { WidgetSamples.rankingEntry }
#endif
