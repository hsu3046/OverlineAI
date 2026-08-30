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
    var selectedBookID: ReadingBook.ID?

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

    init(client: OverlineAPIClient = OverlineAPIClient()) {
        self.client = client
    }

    func selectDefaultBook(from library: ReadingLibrary) {
        guard selectedBookID == nil else { return }
        selectedBookID = library.selectedBookID ?? library.books.first?.id
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

    func loadArticles(book: ReadingBook, force: Bool = false) async {
        let key = "\(book.id)-\(articleSource.rawValue)-\(articleSort.rawValue)"
        if !force, loadedArticleKey == key {
            articleError = nil
            return
        }

        isLoadingArticles = true
        articleError = nil
        defer { isLoadingArticles = false }
        do {
            let response = try await client.articles(
                title: book.title,
                author: book.author,
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
        let key = rankingKind.rawValue
        if !force, loadedRankingKey == key {
            rankingError = nil
            return
        }

        isLoadingRankings = true
        rankingError = nil
        defer { isLoadingRankings = false }
        do {
            let response = try await client.rankings(kind: rankingKind)
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
}
