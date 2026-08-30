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
    private(set) var placeWarnings: [String] = []
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
    private var latestPlaceRequestKey: String?
    private var latestArticleRequestKey: String?
    private var latestRankingRequestKey: String?
    private var placeRequestID: UUID?
    private var articleRequestID: UUID?
    private var rankingRequestID: UUID?
    private var selectedBookTitle = ""
    private var selectedBookAuthor = ""
    private var hasInitializedArticleSearch = false

    init(client: OverlineAPIClient = OverlineAPIClient()) {
        self.client = client
    }

    func selectDefaultBook(from library: ReadingLibrary) {
        guard
            !hasInitializedArticleSearch,
            selectedBookID == nil,
            articleSearchText.trimmed.isEmpty
        else { return }
        guard let book = library.selectedBook ?? library.books.first else { return }
        selectArticleBook(book)
    }

    func reconcileBooks(from library: ReadingLibrary) {
        if let selectedBookID, let book = library.book(with: selectedBookID) {
            let title = book.title.trimmed
            let author = book.author.trimmed
            if title != selectedBookTitle || author != selectedBookAuthor {
                selectedBookTitle = title
                selectedBookAuthor = author
                articleSearchText = title
                commitArticleQuery(title: title, author: author)
            }
        } else if selectedBookID != nil {
            self.selectedBookID = nil
            selectedBookTitle = ""
            selectedBookAuthor = ""
            articleQueryAuthor = ""
        }
        selectDefaultBook(from: library)
    }

    func selectArticleBook(_ book: ReadingBook) {
        hasInitializedArticleSearch = true
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
        hasInitializedArticleSearch = true
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
        latestArticleRequestKey = nil
        articleRequestID = nil
        isLoadingArticles = false
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
        let radius = placeRadius
        let kind = placeKind
        let key = placeKey(latitude: latitude, longitude: longitude, radius: radius, kind: kind)
        latestPlaceRequestKey = key
        if !force, loadedPlaceKey == key {
            placeError = nil
            return
        }

        let requestID = UUID()
        placeRequestID = requestID
        isLoadingPlaces = true
        placeError = nil
        placeWarnings = []
        defer {
            if placeRequestID == requestID {
                isLoadingPlaces = false
            }
        }
        do {
            let response = try await client.nearbyPlaces(
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                kind: kind
            )
            guard
                !Task.isCancelled,
                placeRequestID == requestID,
                latestPlaceRequestKey == key,
                key == placeKey(latitude: latitude, longitude: longitude)
            else { return }
            places = response.items
            placeWarnings = response.warnings ?? []
            loadedPlaceKey = placeWarnings.isEmpty ? key : nil
        } catch is CancellationError {
            return
        } catch {
            guard
                !Task.isCancelled,
                placeRequestID == requestID,
                latestPlaceRequestKey == key,
                key == placeKey(latitude: latitude, longitude: longitude)
            else { return }
            placeError = error.localizedDescription
        }
    }

    func loadArticles(force: Bool = false) async {
        guard !articleQueryTitle.isEmpty else { return }
        let title = articleQueryTitle
        let author = articleQueryAuthor
        let source = articleSource
        let sort = articleSort
        let key = articleKey(title: title, author: author, source: source, sort: sort)
        latestArticleRequestKey = key
        if !force, loadedArticleKey == key {
            articleError = nil
            return
        }

        let requestID = UUID()
        articleRequestID = requestID
        isLoadingArticles = true
        articleError = nil
        defer {
            if articleRequestID == requestID {
                isLoadingArticles = false
            }
        }
        do {
            let response = try await client.articles(
                title: title,
                author: author,
                source: source,
                sort: sort
            )
            guard
                !Task.isCancelled,
                articleRequestID == requestID,
                latestArticleRequestKey == key,
                key == articleKey()
            else { return }
            articles = response.items
            articleWarnings = response.warnings ?? []
            loadedArticleKey = articleWarnings.isEmpty ? key : nil
        } catch is CancellationError {
            return
        } catch {
            guard
                !Task.isCancelled,
                articleRequestID == requestID,
                latestArticleRequestKey == key,
                key == articleKey()
            else { return }
            articleError = error.localizedDescription
        }
    }

    func loadRankings(force: Bool = false) async {
        let kind = rankingKind
        let category = rankingCategory
        let key = rankingKey(kind: kind, category: category)
        latestRankingRequestKey = key
        if !force, loadedRankingKey == key {
            rankingError = nil
            return
        }

        let requestID = UUID()
        rankingRequestID = requestID
        isLoadingRankings = true
        rankingError = nil
        defer {
            if rankingRequestID == requestID {
                isLoadingRankings = false
            }
        }
        do {
            let response = try await client.rankings(kind: kind, category: category)
            guard
                !Task.isCancelled,
                rankingRequestID == requestID,
                latestRankingRequestKey == key,
                key == rankingKey()
            else { return }
            rankings = response.items
            loadedRankingKey = key
        } catch is CancellationError {
            return
        } catch {
            guard
                !Task.isCancelled,
                rankingRequestID == requestID,
                latestRankingRequestKey == key,
                key == rankingKey()
            else { return }
            rankingError = error.localizedDescription
        }
    }

    private func roundedCoordinate(_ value: CLLocationDegrees) -> CLLocationDegrees {
        (value * 10_000).rounded() / 10_000
    }

    private func placeKey(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        radius: Int? = nil,
        kind: CommunityPlaceKind? = nil
    ) -> String {
        "\(latitude)-\(longitude)-\(radius ?? placeRadius)-\((kind ?? placeKind).rawValue)"
    }

    private func articleKey(
        title: String? = nil,
        author: String? = nil,
        source: CommunityArticleSource? = nil,
        sort: CommunityArticleSort? = nil
    ) -> String {
        "\(title ?? articleQueryTitle)-\(author ?? articleQueryAuthor)-\((source ?? articleSource).rawValue)-\((sort ?? articleSort).rawValue)"
    }

    private func rankingKey(
        kind: CommunityRankingKind? = nil,
        category: CommunityRankingCategory? = nil
    ) -> String {
        "\((kind ?? rankingKind).rawValue)-\((category ?? rankingCategory).rawValue)"
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
            loadedArticleKey = nil
            latestArticleRequestKey = nil
            articleRequestID = nil
            isLoadingArticles = false
        }
        return changed
    }
}
