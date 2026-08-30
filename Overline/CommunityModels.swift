import Foundation

nonisolated enum CommunitySection: String, CaseIterable, Identifiable {
    case nearby
    case articles
    case rankings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearby: "내 주변"
        case .articles: "관련 글"
        case .rankings: "인기 도서"
        }
    }

    var systemImage: String {
        switch self {
        case .nearby: "location"
        case .articles: "newspaper"
        case .rankings: "chart.bar"
        }
    }
}

nonisolated enum CommunityPlaceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case bookstore
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .bookstore: "서점"
        case .library: "도서관"
        }
    }
}

nonisolated enum CommunityArticleSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case naver
    case daum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .naver: "NAVER"
        case .daum: "Daum"
        }
    }
}

nonisolated enum CommunityArticleSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case latest

    var id: String { rawValue }
    var title: String { self == .relevance ? "관련도순" : "최신순" }
}

nonisolated enum CommunityRankingKind: String, CaseIterable, Identifiable, Sendable {
    case bestseller
    case loans

    var id: String { rawValue }
    var title: String { self == .bestseller ? "베스트셀러" : "대출 순위" }
}

nonisolated enum CommunityRankingCategory: String, Identifiable, Sendable {
    case all
    case fiction
    case essay
    case humanities
    case business
    case selfDevelopment
    case children
    case literature
    case philosophy
    case socialScience
    case naturalScience
    case technology
    case arts
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체 분야"
        case .fiction: "소설·시·희곡"
        case .essay: "에세이"
        case .humanities: "인문학"
        case .business: "경제·경영"
        case .selfDevelopment: "자기계발"
        case .children: "어린이"
        case .literature: "문학"
        case .philosophy: "철학"
        case .socialScience: "사회과학"
        case .naturalScience: "자연과학"
        case .technology: "기술과학"
        case .arts: "예술"
        case .history: "역사"
        }
    }

    static func options(for kind: CommunityRankingKind) -> [CommunityRankingCategory] {
        switch kind {
        case .bestseller:
            [.all, .fiction, .essay, .humanities, .business, .selfDevelopment, .children]
        case .loans:
            [.all, .literature, .philosophy, .socialScience, .naturalScience, .technology, .arts, .history]
        }
    }
}

nonisolated struct CommunityPlace: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let name: String
    let kind: CommunityPlaceKind
    let category: String
    let address: String
    let distanceMeters: Int
    let source: String
    let phone: String?
    let detailURL: String?
}

nonisolated struct CommunityArticle: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let title: String
    let snippet: String
    let url: String
    let source: CommunityArticleSource
    let sourceName: String
    let publishedAt: String?
    let thumbnailURL: String?
}

nonisolated struct CommunityRankingItem: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let rank: Int
    let title: String
    let author: String
    let source: String
    let publisher: String?
    let publishedDate: String?
    let isbn13: String?
    let coverURL: String?
    let detailURL: String?
    let loanCount: Int?
}

nonisolated struct CommunityListResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let fetchedAt: String
    let warnings: [String]?
}
