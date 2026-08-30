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
    @State private var forcePlaceReloadAfterLocation = false
    @FocusState private var isArticleSearchFocused: Bool
    @Namespace private var sectionTabNamespace

    @ViewBuilder
    var body: some View {
        Group {
            if isActive {
                activeContent
            } else {
                Color.clear
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                model.reconcileBooks(from: library)
                if selectedSection == .nearby {
                    locationService.requestCurrentLocation()
                }
            }
        }
    }

    private var activeContent: some View {
        List {
            CommunitySectionTabBar(
                selection: selectedSectionBinding,
                namespace: sectionTabNamespace
            )
            .communityListRow(top: 20, bottom: 16)

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
            await loadSelectedSection()
        }
        .onChange(of: libraryBookSearchFingerprint) { _, _ in
            model.reconcileBooks(from: library)
        }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        HStack(spacing: 8) {
            ForEach(CommunityPlaceKind.allCases) { kind in
                CommunityFilterChip(
                    title: kind.title,
                    isSelected: model.placeKind == kind
                ) {
                    model.placeKind = kind
                }
            }

            Spacer(minLength: 4)

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
                CommunityFilterMenuLabel(
                    title: radiusTitle(model.placeRadius),
                    systemImage: "scope"
                )
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
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.overline(.body, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.72))

                TextField("책 제목 또는 저자", text: articleSearchBinding)
                    .font(.overline(.body))
                    .foregroundStyle(Color.overlineInk)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isArticleSearchFocused)
                    .onSubmit(performArticleSearch)

                if !model.articleSearchText.isEmpty {
                    Button {
                        model.clearArticleSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.overline(.body))
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.46))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                }

                if !library.books.isEmpty {
                    Menu {
                        ForEach(library.books) { book in
                            Button {
                                isArticleSearchFocused = false
                                model.selectArticleBook(book)
                            } label: {
                                if model.selectedBookID == book.id {
                                    Label(book.title, systemImage: "checkmark")
                                } else {
                                    Text(book.title)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "books.vertical")
                            .font(.overline(.body, weight: .semibold))
                            .foregroundStyle(Color.overlineAccent)
                            .frame(width: 36, height: 36)
                            .background(Color.overlineAccent.opacity(0.09), in: Circle())
                    }
                    .accessibilityLabel("책장에서 선택")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(minHeight: 52)
            .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.overlineInk.opacity(0.07), lineWidth: 1)
            }

            HStack(spacing: 8) {
                ForEach(CommunityArticleSource.allCases) { source in
                    CommunityFilterChip(
                        title: source.title,
                        isSelected: model.articleSource == source
                    ) {
                        model.articleSource = source
                    }
                }

                Spacer(minLength: 4)

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
                    CommunityFilterMenuLabel(
                        title: model.articleSort.title,
                        systemImage: "arrow.up.arrow.down"
                    )
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

        if model.articleQueryTitle.isEmpty {
            CommunityMessageRow(
                systemImage: "text.magnifyingglass",
                title: "찾고 싶은 책을 입력해 주세요",
                message: library.books.isEmpty
                    ? "책 제목이나 저자로 관련 글을 찾을 수 있습니다."
                    : "직접 검색하거나 책장에서 골라보세요.",
                actionTitle: nil,
                action: nil
            )
            .communityListRow(top: 0, bottom: 16)
        } else if let error = model.articleError {
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
                message: "검색어를 바꾸거나 최신순으로 확인해 보세요.",
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

    @ViewBuilder
    private var rankingContent: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(CommunityRankingKind.allCases) { kind in
                    Button {
                        model.selectRankingKind(kind)
                    } label: {
                        if model.rankingKind == kind {
                            Label(kind.title, systemImage: "checkmark")
                        } else {
                            Text(kind.title)
                        }
                    }
                }
            } label: {
                CommunityFilterMenuLabel(
                    title: model.rankingKind.title,
                    systemImage: "chart.bar"
                )
            }

            Menu {
                ForEach(CommunityRankingCategory.options(for: model.rankingKind)) { category in
                    Button {
                        model.rankingCategory = category
                    } label: {
                        if model.rankingCategory == category {
                            Label(category.title, systemImage: "checkmark")
                        } else {
                            Text(category.title)
                        }
                    }
                }
            } label: {
                CommunityFilterMenuLabel(
                    title: model.rankingCategory.title,
                    systemImage: "line.3.horizontal.decrease"
                )
            }

            Spacer(minLength: 0)
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
            set: { section in
                isArticleSearchFocused = false
                withAnimation(.easeInOut(duration: 0.22)) {
                    selectedSectionRaw = section.rawValue
                }
                if section == .nearby {
                    locationService.requestCurrentLocation()
                }
            }
        )
    }

    private var articleSearchBinding: Binding<String> {
        Binding(
            get: { model.articleSearchText },
            set: model.updateArticleSearchText
        )
    }

    private var loadTaskID: String {
        guard isActive else { return "inactive" }
        switch selectedSection {
        case .nearby:
            let coordinate = locationService.location?.coordinate
            return "nearby-\(locationService.locationRevision)-\(coordinate?.latitude ?? 0)-\(coordinate?.longitude ?? 0)-\(model.placeKind.rawValue)-\(model.placeRadius)"
        case .articles:
            return "articles-\(model.articleQueryTitle)-\(model.articleQueryAuthor)-\(model.articleSource.rawValue)-\(model.articleSort.rawValue)"
        case .rankings:
            return "rankings-\(model.rankingKind.rawValue)-\(model.rankingCategory.rawValue)"
        }
    }

    private func loadSelectedSection(force: Bool = false) async {
        guard isActive else { return }
        switch selectedSection {
        case .nearby:
            if force {
                forcePlaceReloadAfterLocation = true
                locationService.requestCurrentLocation()
                return
            }
            guard !locationService.isRequesting else { return }
            guard let location = locationService.location else {
                locationService.requestCurrentLocation()
                return
            }
            let shouldForce = forcePlaceReloadAfterLocation
            forcePlaceReloadAfterLocation = false
            await model.loadPlaces(location: location, force: shouldForce)
        case .articles:
            await model.loadArticles(force: force)
        case .rankings:
            await model.loadRankings(force: force)
        }
    }

    private func performArticleSearch() {
        isArticleSearchFocused = false
        let queryChanged = model.commitArticleSearch()
        guard !model.articleQueryTitle.isEmpty, !queryChanged else { return }
        Task { await model.loadArticles(force: true) }
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

    private var libraryBookSearchFingerprint: [String] {
        library.books.map { book in
            "\(book.id)|\(book.title)|\(book.author)"
        }
    }

    private func radiusTitle(_ radius: Int) -> String {
        radius < 1_000 ? "\(radius)m" : "\(radius / 1_000)km"
    }
}

private struct CommunitySectionTabBar: View {
    @Binding var selection: CommunitySection
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CommunitySection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: section.systemImage)
                                .font(.overline(.subheadline, weight: .semibold))
                            Text(section.title)
                                .font(.overline(.subheadline, weight: .semibold))
                        }
                        .foregroundStyle(selection == section ? Color.overlineAccent : Color.overlineMutedInk)
                        .frame(maxWidth: .infinity, minHeight: 34)

                        ZStack {
                            Color.clear.frame(height: 2)
                            if selection == section {
                                Capsule(style: .continuous)
                                    .fill(Color.overlineAccent)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "community-section", in: namespace)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? [.isSelected] : [])
            }
        }
    }
}

private struct CommunityFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.overline(.caption, weight: .semibold))
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(
                    isSelected ? Color.overlineAccent.opacity(0.12) : Color.white.opacity(0.38),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? Color.overlineAccent.opacity(0.25) : Color.overlineInk.opacity(0.06),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct CommunityFilterMenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.overline(.caption, weight: .semibold))
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.overline(.caption2, weight: .bold))
        }
        .font(.overline(.caption, weight: .semibold))
        .foregroundStyle(Color.overlineAccent)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineInk.opacity(0.06), lineWidth: 1)
        }
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
