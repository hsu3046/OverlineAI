import Foundation

nonisolated enum CommunitySection: String, CaseIterable, Identifiable {
    case rankings
    case articles
    case nearby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearby: String(localized: LocalizedStringResource("내 주변", locale: AppLocale.uiLocale))
        case .articles: String(localized: LocalizedStringResource("관련 글", locale: AppLocale.uiLocale))
        case .rankings: String(localized: LocalizedStringResource("인기 도서", locale: AppLocale.uiLocale))
        }
    }

    var systemImage: String {
        switch self {
        case .nearby: "location"
        case .articles: "newspaper"
        case .rankings: "book"
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
        case .all: String(localized: LocalizedStringResource("전체", locale: AppLocale.uiLocale))
        case .bookstore: String(localized: LocalizedStringResource("서점", locale: AppLocale.uiLocale))
        case .library: String(localized: LocalizedStringResource("도서관", locale: AppLocale.uiLocale))
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
        case .all: String(localized: LocalizedStringResource("전체", locale: AppLocale.uiLocale))
        case .naver: "NAVER"
        case .daum: "Daum"
        }
    }
}

nonisolated enum CommunityArticleSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case latest

    var id: String { rawValue }
    var title: String { self == .relevance ? String(localized: LocalizedStringResource("관련도순", locale: AppLocale.uiLocale)) : String(localized: LocalizedStringResource("최신순", locale: AppLocale.uiLocale)) }
}

nonisolated enum CommunityRankingKind: String, CaseIterable, Identifiable, Sendable {
    case bestseller
    case loans

    var id: String { rawValue }
    var title: String {
        if self == .bestseller && AppLocale.languageCode == "ja" { return "売れ筋" }
        return self == .bestseller
            ? String(localized: LocalizedStringResource("베스트셀러", locale: AppLocale.uiLocale))
            : String(localized: LocalizedStringResource("대출 순위", locale: AppLocale.uiLocale))
    }
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
        if AppLocale.languageCode == "ja" {
            switch self {
            case .all: return "全分野"
            case .fiction: return "小説・エッセイ"
            case .essay: return "エッセイ"
            case .humanities: return "人文・思想・社会"
            case .business: return "ビジネス・経済・就職"
            case .selfDevelopment: return "自己啓発"
            case .children: return "絵本・児童書・図鑑"
            default: break
            }
        }
        return switch self {
        case .all: String(localized: LocalizedStringResource("전체 분야", locale: AppLocale.uiLocale))
        case .fiction: String(localized: LocalizedStringResource("소설·시·희곡", locale: AppLocale.uiLocale))
        case .essay: String(localized: LocalizedStringResource("에세이", locale: AppLocale.uiLocale))
        case .humanities: String(localized: LocalizedStringResource("인문학", locale: AppLocale.uiLocale))
        case .business: String(localized: LocalizedStringResource("경제·경영", locale: AppLocale.uiLocale))
        case .selfDevelopment: String(localized: LocalizedStringResource("자기계발", locale: AppLocale.uiLocale))
        case .children: String(localized: LocalizedStringResource("어린이", locale: AppLocale.uiLocale))
        case .literature: String(localized: LocalizedStringResource("문학", locale: AppLocale.uiLocale))
        case .philosophy: String(localized: LocalizedStringResource("철학", locale: AppLocale.uiLocale))
        case .socialScience: String(localized: LocalizedStringResource("사회과학", locale: AppLocale.uiLocale))
        case .naturalScience: String(localized: LocalizedStringResource("자연과학", locale: AppLocale.uiLocale))
        case .technology: String(localized: LocalizedStringResource("기술과학", locale: AppLocale.uiLocale))
        case .arts: String(localized: LocalizedStringResource("예술", locale: AppLocale.uiLocale))
        case .history: String(localized: LocalizedStringResource("역사", locale: AppLocale.uiLocale))
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
