import CoreLocation
import Observation

@MainActor
@Observable
final class CommunityViewModel {
    var placeKind: CommunityPlaceKind = .all
    var placeRadius = 5_000
    var articleSource: CommunityArticleSource = .all
    var articleSort: CommunityArticleSort = .relevance
    var rankingKind: CommunityRankingKind = .bestseller
    var rankingCategory: CommunityRankingCategory = .all
    var articleSearchText = ""
    private(set) var selectedBookID: ReadingBook.ID?
    private(set) var articleQueryTitle = ""
    private(set) var articleQueryAuthor = ""

    private(set) var places: [CommunityPlace] = []
    private(set) var articles: [CommunityArticle] = []
    private(set) var rankings: [CommunityRankingItem] = []
    private(set) var articleWarnings: [String] = []
    private(set) var isLoadingPlaces = false
    private(set) var isLoadingArticles = false
    private(set) var isLoadingRankings = false
    private(set) var placeError: String?
    private(set) var articleError: String?
    private(set) var rankingError: String?

    private let client: OverlineAPIClient
    private var loadedPlaceKey: String?
    private var loadedArticleKey: String?
    private var loadedRankingKey: String?
    private var selectedBookTitle = ""
    private var selectedBookAuthor = ""

    init(client: OverlineAPIClient = OverlineAPIClient()) {
        self.client = client
    }

    func selectDefaultBook(from library: ReadingLibrary) {
        guard selectedBookID == nil, articleSearchText.trimmed.isEmpty else { return }
        guard let book = library.selectedBook ?? library.books.first else { return }
        selectArticleBook(book)
    }

    func reconcileBooks(from library: ReadingLibrary) {
        if let selectedBookID, library.book(with: selectedBookID) == nil {
            self.selectedBookID = nil
            selectedBookTitle = ""
            selectedBookAuthor = ""
            articleQueryAuthor = ""
        }
        selectDefaultBook(from: library)
    }

    func selectArticleBook(_ book: ReadingBook) {
        selectedBookID = book.id
        selectedBookTitle = book.title.trimmed
        selectedBookAuthor = book.author.trimmed
        articleSearchText = selectedBookTitle
        commitArticleQuery(title: selectedBookTitle, author: selectedBookAuthor)
    }

    func updateArticleSearchText(_ value: String) {
        articleSearchText = value
        if selectedBookID != nil, value.trimmed != selectedBookTitle {
            selectedBookID = nil
            selectedBookTitle = ""
            selectedBookAuthor = ""
        }
    }

    @discardableResult
    func commitArticleSearch() -> Bool {
        let title = articleSearchText.trimmed
        guard !title.isEmpty else { return false }
        let author = selectedBookID == nil ? "" : selectedBookAuthor
        return commitArticleQuery(title: title, author: author)
    }

    func clearArticleSearch() {
        articleSearchText = ""
        selectedBookID = nil
        selectedBookTitle = ""
        selectedBookAuthor = ""
        articleQueryTitle = ""
        articleQueryAuthor = ""
        articles = []
        articleWarnings = []
        articleError = nil
        loadedArticleKey = nil
    }

    func selectRankingKind(_ kind: CommunityRankingKind) {
        rankingKind = kind
        if !CommunityRankingCategory.options(for: kind).contains(rankingCategory) {
            rankingCategory = .all
        }
    }

    func loadPlaces(location: CLLocation, force: Bool = false) async {
        let latitude = roundedCoordinate(location.coordinate.latitude)
        let longitude = roundedCoordinate(location.coordinate.longitude)
        let key = "\(latitude)-\(longitude)-\(placeRadius)-\(placeKind.rawValue)"
        if !force, loadedPlaceKey == key {
            placeError = nil
            return
        }

        isLoadingPlaces = true
        placeError = nil
        defer { isLoadingPlaces = false }
        do {
            let response = try await client.nearbyPlaces(
                latitude: latitude,
                longitude: longitude,
                radius: placeRadius,
                kind: placeKind
            )
            guard !Task.isCancelled else { return }
            places = response.items
            loadedPlaceKey = key
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            placeError = error.localizedDescription
        }
    }

    func loadArticles(force: Bool = false) async {
        guard !articleQueryTitle.isEmpty else { return }
        let key = "\(articleQueryTitle)-\(articleQueryAuthor)-\(articleSource.rawValue)-\(articleSort.rawValue)"
        if !force, loadedArticleKey == key {
            articleError = nil
            return
        }

        isLoadingArticles = true
        articleError = nil
        defer { isLoadingArticles = false }
        do {
            let response = try await client.articles(
                title: articleQueryTitle,
                author: articleQueryAuthor,
                source: articleSource,
                sort: articleSort
            )
            guard !Task.isCancelled else { return }
            articles = response.items
            articleWarnings = response.warnings ?? []
            loadedArticleKey = key
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            articleError = error.localizedDescription
        }
    }

    func loadRankings(force: Bool = false) async {
        let key = "\(rankingKind.rawValue)-\(rankingCategory.rawValue)"
        if !force, loadedRankingKey == key {
            rankingError = nil
            return
        }

        isLoadingRankings = true
        rankingError = nil
        defer { isLoadingRankings = false }
        do {
            let response = try await client.rankings(kind: rankingKind, category: rankingCategory)
            guard !Task.isCancelled else { return }
            rankings = response.items
            loadedRankingKey = key
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            rankingError = error.localizedDescription
        }
    }

    private func roundedCoordinate(_ value: CLLocationDegrees) -> CLLocationDegrees {
        (value * 10_000).rounded() / 10_000
    }

    @discardableResult
    private func commitArticleQuery(title: String, author: String) -> Bool {
        let changed = articleQueryTitle != title || articleQueryAuthor != author
        articleQueryTitle = title
        articleQueryAuthor = author
        if changed {
            articles = []
            articleWarnings = []
            articleError = nil
        }
        return changed
    }
}
