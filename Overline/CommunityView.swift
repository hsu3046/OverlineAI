import CoreLocation
import SwiftUI
import UIKit

struct CommunityView: View {
    @Environment(ReadingLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    var isActive = true

    @AppStorage("overline.community.selectedSection") private var selectedSectionRaw = CommunitySection.articles.rawValue
    @State private var model = CommunityViewModel()
    @State private var locationService = CommunityLocationService()

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
            SectionHeader(title: "커뮤니티", systemImage: "person.3")
                .communityListRow(top: 16, bottom: 10)

            Picker("커뮤니티 보기", selection: selectedSectionBinding) {
                ForEach(CommunitySection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .communityListRow(top: 0, bottom: 16)

            switch selectedSection {
            case .nearby:
                nearbyContent
            case .articles:
                articleContent
            case .rankings:
                rankingContent
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .overlineBottomMenuCompaction()
        .refreshable {
            await loadSelectedSection(force: true)
        }
        .task(id: loadTaskID) {
            model.selectDefaultBook(from: library)
            if library.books.isEmpty && selectedSection == .articles {
                selectedSectionRaw = CommunitySection.rankings.rawValue
                return
            }
            await loadSelectedSection()
        }
        .onChange(of: library.books.map(\.id)) { _, bookIDs in
            if let selectedBookID = model.selectedBookID, !bookIDs.contains(selectedBookID) {
                model.selectedBookID = library.selectedBookID ?? bookIDs.first
            } else {
                model.selectDefaultBook(from: library)
            }
        }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        VStack(spacing: 12) {
            Picker("장소 종류", selection: $model.placeKind) {
                ForEach(CommunityPlaceKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label("가까운 순", systemImage: "location")
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk)

                Spacer()

                Menu {
                    ForEach([1_000, 3_000, 5_000, 10_000], id: \.self) { radius in
                        Button {
                            model.placeRadius = radius
                        } label: {
                            if model.placeRadius == radius {
                                Label(radiusTitle(radius), systemImage: "checkmark")
                            } else {
                                Text(radiusTitle(radius))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(radiusTitle(model.placeRadius))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.overline(.caption2, weight: .semibold))
                    }
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)
                }
            }
        }
        .communityListRow(top: 0, bottom: 12)

        if let locationError = locationService.errorMessage {
            CommunityMessageRow(
                systemImage: "location.slash",
                title: "위치를 사용할 수 없습니다",
                message: locationError,
                actionTitle: locationService.authorizationStatus == .denied ? "설정 열기" : "다시 시도",
                action: recoverLocationAccess
            )
            .communityListRow(top: 0, bottom: 16)
        } else if locationService.location == nil || locationService.isRequesting {
            CommunityLoadingRow(message: "가까운 책 공간을 찾고 있습니다")
                .communityListRow(top: 12, bottom: 16)
        } else if let error = model.placeError {
            CommunityMessageRow(
                systemImage: "wifi.exclamationmark",
                title: "장소를 불러오지 못했습니다",
                message: error,
                actionTitle: "다시 시도",
                action: { Task { await loadSelectedSection(force: true) } }
            )
            .communityListRow(top: 0, bottom: 16)
        } else if model.isLoadingPlaces && model.places.isEmpty {
            CommunityLoadingRow(message: "가까운 책 공간을 찾고 있습니다")
                .communityListRow(top: 12, bottom: 16)
        } else if model.places.isEmpty {
            CommunityMessageRow(
                systemImage: "mappin.slash",
                title: "주변 장소를 찾지 못했습니다",
                message: "검색 범위를 넓혀 다시 확인해 보세요.",
                actionTitle: nil,
                action: nil
            )
            .communityListRow(top: 0, bottom: 16)
        } else {
            ForEach(model.places) { place in
                CommunityPlaceRow(place: place, openURL: openExternalURL)
                    .communityListRow(top: 0, bottom: 10)
            }
        }
    }

    @ViewBuilder
    private var articleContent: some View {
        if library.books.isEmpty {
            CommunityMessageRow(
                systemImage: "books.vertical",
                title: "먼저 책을 추가해 주세요",
                message: "책장에 담긴 책을 바탕으로 관련 글을 찾아드립니다.",
                actionTitle: nil,
                action: nil
            )
            .communityListRow(top: 8, bottom: 16)
        } else {
            VStack(spacing: 12) {
                Menu {
                    ForEach(library.books) { book in
                        Button {
                            model.selectedBookID = book.id
                        } label: {
                            if model.selectedBookID == book.id {
                                Label(book.title, systemImage: "checkmark")
                            } else {
                                Text(book.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.closed")
                            .foregroundStyle(Color.overlineAccent)
                        Text(selectedBook?.title ?? "책 선택")
                            .font(.overline(.body, weight: .semibold))
                            .foregroundStyle(Color.overlineInk)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.overline(.caption, weight: .semibold))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Picker("글 출처", selection: $model.articleSource) {
                    ForEach(CommunityArticleSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("책 제목과 저자로 검색")
                        .font(.overline(.caption))
                        .foregroundStyle(Color.overlineMutedInk)
                    Spacer()
                    Menu {
                        ForEach(CommunityArticleSort.allCases) { sort in
                            Button {
                                model.articleSort = sort
                            } label: {
                                if model.articleSort == sort {
                                    Label(sort.title, systemImage: "checkmark")
                                } else {
                                    Text(sort.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.articleSort.title)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.overline(.caption2, weight: .semibold))
                        }
                        .font(.overline(.caption, weight: .semibold))
                        .foregroundStyle(Color.overlineAccent)
                    }
                }
            }
            .communityListRow(top: 0, bottom: 12)

            if !model.articleWarnings.isEmpty && !model.articles.isEmpty {
                Label("일부 출처를 불러오지 못했습니다.", systemImage: "exclamationmark.circle")
                    .font(.overline(.caption))
                    .foregroundStyle(Color.overlineMutedInk)
                    .communityListRow(top: 0, bottom: 10)
            }

            if let error = model.articleError {
                CommunityMessageRow(
                    systemImage: "wifi.exclamationmark",
                    title: "관련 글을 불러오지 못했습니다",
                    message: error,
                    actionTitle: "다시 시도",
                    action: { Task { await loadSelectedSection(force: true) } }
                )
                .communityListRow(top: 0, bottom: 16)
            } else if model.isLoadingArticles && model.articles.isEmpty {
                CommunityLoadingRow(message: "책에 관한 글을 찾고 있습니다")
                    .communityListRow(top: 12, bottom: 16)
            } else if model.articles.isEmpty {
                CommunityMessageRow(
                    systemImage: "text.magnifyingglass",
                    title: "관련 글을 찾지 못했습니다",
                    message: "다른 책을 선택하거나 최신순으로 확인해 보세요.",
                    actionTitle: nil,
                    action: nil
                )
                .communityListRow(top: 0, bottom: 16)
            } else {
                ForEach(model.articles) { article in
                    CommunityArticleRow(article: article, openURL: openExternalURL)
                        .communityListRow(top: 0, bottom: 10)
                }
            }
        }
    }

    @ViewBuilder
    private var rankingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("순위 종류", selection: $model.rankingKind) {
                ForEach(CommunityRankingKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(model.rankingKind == .bestseller ? "알라딘 베스트셀러" : "최근 30일 전국 공공도서관 대출")
                .font(.overline(.caption))
                .foregroundStyle(Color.overlineMutedInk)
        }
        .communityListRow(top: 0, bottom: 12)

        if let error = model.rankingError {
            CommunityMessageRow(
                systemImage: "wifi.exclamationmark",
                title: "순위를 불러오지 못했습니다",
                message: error,
                actionTitle: "다시 시도",
                action: { Task { await loadSelectedSection(force: true) } }
            )
            .communityListRow(top: 0, bottom: 16)
        } else if model.isLoadingRankings && model.rankings.isEmpty {
            CommunityLoadingRow(message: "인기 도서를 불러오고 있습니다")
                .communityListRow(top: 12, bottom: 16)
        } else if model.rankings.isEmpty {
            CommunityMessageRow(
                systemImage: "chart.bar.xaxis",
                title: "순위 정보가 없습니다",
                message: "잠시 후 다시 확인해 주세요.",
                actionTitle: nil,
                action: nil
            )
            .communityListRow(top: 0, bottom: 16)
        } else {
            ForEach(model.rankings) { item in
                CommunityRankingRow(item: item, openURL: openExternalURL)
                    .communityListRow(top: 0, bottom: 10)
            }

            if model.rankingKind == .loans {
                Text("출처: 도서관 정보나루 · 국립중앙도서관")
                    .font(.overline(.caption2))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.74))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .communityListRow(top: 2, bottom: 18)
            }
        }
    }

    private var selectedSection: CommunitySection {
        CommunitySection(rawValue: selectedSectionRaw) ?? .articles
    }

    private var selectedSectionBinding: Binding<CommunitySection> {
        Binding(
            get: { selectedSection },
            set: { selectedSectionRaw = $0.rawValue }
        )
    }

    private var selectedBook: ReadingBook? {
        guard let selectedBookID = model.selectedBookID else { return nil }
        return library.book(with: selectedBookID)
    }

    private var loadTaskID: String {
        guard isActive else { return "inactive" }
        switch selectedSection {
        case .nearby:
            let coordinate = locationService.location?.coordinate
            return "nearby-\(coordinate?.latitude ?? 0)-\(coordinate?.longitude ?? 0)-\(model.placeKind.rawValue)-\(model.placeRadius)"
        case .articles:
            return "articles-\(model.selectedBookID?.uuidString ?? "none")-\(model.articleSource.rawValue)-\(model.articleSort.rawValue)"
        case .rankings:
            return "rankings-\(model.rankingKind.rawValue)"
        }
    }

    private func loadSelectedSection(force: Bool = false) async {
        guard isActive else { return }
        switch selectedSection {
        case .nearby:
            guard let location = locationService.location else {
                locationService.requestCurrentLocation()
                return
            }
            await model.loadPlaces(location: location, force: force)
        case .articles:
            guard let selectedBook else { return }
            await model.loadArticles(book: selectedBook, force: force)
        case .rankings:
            await model.loadRankings(force: force)
        }
    }

    private func openExternalURL(_ value: String?) {
        guard let value, let url = URL(string: value) else { return }
        openURL(url)
    }

    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func recoverLocationAccess() {
        if locationService.authorizationStatus == .denied {
            openApplicationSettings()
        } else {
            locationService.requestCurrentLocation()
        }
    }

    private func radiusTitle(_ radius: Int) -> String {
        radius < 1_000 ? "\(radius)m" : "\(radius / 1_000)km"
    }
}

private struct CommunityPlaceRow: View {
    let place: CommunityPlace
    let openURL: (String?) -> Void

    var body: some View {
        Button {
            openURL(place.detailURL)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: place.kind == .library ? "building.columns" : "books.vertical")
                    .font(.overline(.title3, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(place.name)
                            .font(.overline(.body, weight: .semibold))
                            .foregroundStyle(Color.overlineInk)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(distanceTitle(place.distanceMeters))
                            .font(.overline(.caption, weight: .bold))
                            .foregroundStyle(Color.overlineAccent)
                    }

                    Text(place.category)
                        .font(.overline(.caption))
                        .foregroundStyle(Color.overlineMutedInk)
                        .lineLimit(1)

                    Text(place.address)
                        .font(.overline(.subheadline))
                        .foregroundStyle(Color.overlineMutedInk)
                        .lineLimit(2)

                    if let phone = place.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.overline(.caption))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.84))
                    }
                }

                if place.detailURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.overline(.caption, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.52))
                        .padding(.top, 4)
                }
            }
            .communityRowChrome()
        }
        .buttonStyle(.plain)
        .disabled(place.detailURL == nil)
    }

    private func distanceTitle(_ meters: Int) -> String {
        if meters < 1_000 { return "\(meters)m" }
        return String(format: "%.1fkm", Double(meters) / 1_000)
    }
}

private struct CommunityArticleRow: View {
    let article: CommunityArticle
    let openURL: (String?) -> Void

    var body: some View {
        Button {
            openURL(article.url)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.overline(.body, weight: .semibold))
                        .foregroundStyle(Color.overlineInk)
                        .lineLimit(2)

                    if !article.snippet.isEmpty {
                        Text(article.snippet)
                            .font(.overline(.subheadline))
                            .foregroundStyle(Color.overlineMutedInk)
                            .lineLimit(3)
                    }

                    HStack(spacing: 6) {
                        Text(article.source == .naver ? "NAVER" : "Daum")
                            .font(.overline(.caption2, weight: .bold))
                            .foregroundStyle(Color.overlineAccent)
                        Text(article.sourceName)
                            .lineLimit(1)
                        if let publishedAt = article.publishedAt {
                            Text("·")
                            Text(shortDate(publishedAt))
                        }
                    }
                    .font(.overline(.caption))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.82))
                }

                if let thumbnailURL = article.thumbnailURL, let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.overlineInk.opacity(0.06)
                                .overlay {
                                    Image(systemName: "doc.text.image")
                                        .foregroundStyle(Color.overlineMutedInk.opacity(0.4))
                                }
                        }
                    }
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Image(systemName: "arrow.up.right")
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.52))
                    .padding(.top, 4)
            }
            .communityRowChrome()
        }
        .buttonStyle(.plain)
    }

    private func shortDate(_ date: String) -> String {
        date.replacingOccurrences(of: "-", with: ".")
    }
}

private struct CommunityRankingRow: View {
    let item: CommunityRankingItem
    let openURL: (String?) -> Void

    var body: some View {
        Button {
            openURL(item.detailURL)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(item.rank)")
                    .font(.overline(.title3, weight: .bold))
                    .foregroundStyle(item.rank <= 3 ? Color.overlineAccent : Color.overlineMutedInk)
                    .frame(width: 30, alignment: .trailing)

                CommunityBookCover(urlString: item.coverURL)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.overline(.body, weight: .semibold))
                        .foregroundStyle(Color.overlineInk)
                        .lineLimit(2)
                    if !item.author.isEmpty {
                        Text(item.author)
                            .font(.overline(.subheadline))
                            .foregroundStyle(Color.overlineMutedInk)
                            .lineLimit(1)
                    }
                    if let publisher = item.publisher, !publisher.isEmpty {
                        Text(publisher)
                            .font(.overline(.caption))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.76))
                            .lineLimit(1)
                    }
                    if let loanCount = item.loanCount {
                        Label("\(loanCount.formatted())회 대출", systemImage: "arrow.left.arrow.right")
                            .font(.overline(.caption, weight: .semibold))
                            .foregroundStyle(Color.overlineAccent)
                    }
                }

                Spacer(minLength: 4)
                if item.detailURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.overline(.caption, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.52))
                        .padding(.top, 4)
                }
            }
            .communityRowChrome()
        }
        .buttonStyle(.plain)
        .disabled(item.detailURL == nil)
    }
}

private struct CommunityBookCover: View {
    let urlString: String?

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.overlineInk.opacity(0.07)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.46))
                    }
            }
        }
        .frame(width: 50, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct CommunityLoadingRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color.overlineAccent)
            Text(message)
                .font(.overline(.subheadline, weight: .medium))
                .foregroundStyle(Color.overlineMutedInk)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .center)
    }
}

private struct CommunityMessageRow: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.overline(.title2, weight: .semibold))
                .foregroundStyle(Color.overlineAccent)
            Text(title)
                .font(.overline(.headline, weight: .semibold))
                .foregroundStyle(Color.overlineInk)
            Text(message)
                .font(.overline(.subheadline))
                .foregroundStyle(Color.overlineMutedInk)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.overline(.subheadline, weight: .semibold))
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(18)
    }
}

private extension View {
    func communityRowChrome() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.overlineInk.opacity(0.07), lineWidth: 1)
            }
    }

    func communityListRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
