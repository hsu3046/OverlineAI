//
//  ContentView.swift
//  Overline
//
//  Created by Yu Hitomi on 6/24/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppIntentRouter.self) private var intentRouter
    @Environment(ReadingLibrary.self) private var library
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer
    @State private var selectedTab: AppTab = .capture
    @State private var isBottomMenuCompact = false
    @State private var libraryRootResetToken = 0
    @State private var cameraScanner: CameraTextScanner?
    @State private var loadedTabs: Set<AppTab> = [.capture]
    @State private var tutorial = CaptureTutorial()
    @State private var didCheckTutorial = false

    var body: some View {
        persistentTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OverlineBottomMenuBar(
                    selectedTab: selectedTab,
                    isCompact: isBottomMenuCompact,
                    selectTab: selectTab
                )
            }
            .tint(Color.overlineAccent)
            .background(OverlineCanvasBackground().ignoresSafeArea())
            .alert("음성을 재생하지 못했습니다", isPresented: quoteSpeechErrorIsPresented) {
                Button("확인", role: .cancel) {
                    quoteSpeechPlayer.clearSpeechError()
                }
            } message: {
                Text(quoteSpeechPlayer.speechErrorMessage ?? "잠시 후 다시 시도해 주세요.")
            }
            .environment(\.setBottomMenuCompact, setBottomMenuCompact)
            .environment(\.selectAppTab, selectTab)
            .environment(\.captureTutorial, tutorial)
            .onAppear {
                WidgetSnapshotPublisher.publish(books: library.books)
                if !didCheckTutorial {
                    didCheckTutorial = true
                    if !UserDefaults.standard.bool(forKey: CaptureTutorial.completedKey), intentRouter.request == nil {
                        tutorial.start()
                        selectTab(.library)
                    }
                }
                recordAppOpen()
                apply(intentRouter.request)
            }
            .onChange(of: tutorial.step) { _, step in
                guard let step else { return }
                let destination: AppTab = step == .addBook || step == .bookForm ? .library : .capture
                if selectedTab != destination { selectTab(destination) }
            }
            .onChange(of: tutorial.replayRequested) { _, requested in
                guard requested else { return }
                tutorial.replayRequested = false
                tutorial.start()
                selectTab(.library)
            }
            .task {
                Task {
                    await PageReadingDraftStore.shared.removeIfExpired()
                }
                guard cameraScanner == nil else { return }
                cameraScanner = await CameraTextScanner.makePrepared()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    Task {
                        await library.flushPendingPersistence()
                    }
                    return
                }
                quoteSpeechPlayer.invalidateVoiceCatalog()
                Task {
                    await PageReadingDraftStore.shared.removeIfExpired()
                }
                recordAppOpen()
            }
            .onChange(of: selectedTab) { _, _ in
                setBottomMenuCompact(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlineHighlightsRemoved)) { notification in
                guard
                    let removedHighlightIDs = notification.userInfo?[OverlineNotificationUserInfoKey.highlightIDs]
                        as? [Highlight.ID]
                else {
                    return
                }
                quoteSpeechPlayer.removeHighlights(Set(removedHighlightIDs))
            }
            .onChange(of: intentRouter.request) { _, request in
                apply(request)
            }
            .onOpenURL { url in
                guard let link = WidgetLink(url: url) else { return }
                switch link {
                case .capture: intentRouter.open(.capture)
                case .book(let id): intentRouter.open(.library, bookID: id)
                case .quote(let id): intentRouter.open(.library, highlightID: id)
                case .rankings(let kind): intentRouter.open(.community, rankingKind: kind)
                }
            }
    }

    @ViewBuilder
    private var persistentTabContent: some View {
        ZStack {
            if loadedTabs.contains(.capture) {
                persistentTabLayer(.capture) {
                    NavigationStack {
                        Group {
                            if let cameraScanner {
                                CaptureView(cameraScanner: cameraScanner, isActive: selectedTab == .capture)
                            } else {
                                CameraStartupPlaceholder()
                            }
                        }
                        .overlineKeyboardDismissToolbar(isEnabled: selectedTab == .capture)
                    }
                }
            }

            if loadedTabs.contains(.library) {
                persistentTabLayer(.library) {
                    NavigationStack {
                        LibraryView(
                            rootResetToken: libraryRootResetToken,
                            isActive: selectedTab == .library
                        )
                        .overlineKeyboardDismissToolbar(isEnabled: selectedTab == .library)
                    }
                }
            }

            if loadedTabs.contains(.insights) {
                persistentTabLayer(.insights) {
                    NavigationStack {
                        InsightsView(isActive: selectedTab == .insights)
                            .overlineKeyboardDismissToolbar(isEnabled: selectedTab == .insights)
                    }
                }
            }

            if loadedTabs.contains(.community) {
                persistentTabLayer(.community) {
                    NavigationStack {
                        CommunityView(isActive: selectedTab == .community)
                            .overlineKeyboardDismissToolbar(isEnabled: selectedTab == .community)
                    }
                }
            }
        }
    }

    private func persistentTabLayer<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = selectedTab == tab

        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }

    private func apply(_ request: AppIntentRequest?) {
        guard let request else { return }
        tutorial.step = nil
        if selectedTab != request.tab || (request.bookID == nil && request.highlightID == nil) {
            selectTab(request.tab)
        }
    }

    private func setBottomMenuCompact(_ isCompact: Bool) {
        guard isBottomMenuCompact != isCompact else { return }
        withAnimation(OverlineMotion.menu) {
            isBottomMenuCompact = isCompact
        }
    }

    private func selectTab(_ tab: AppTab) {
        dismissKeyboard()

        guard selectedTab != tab else {
            if tab == .library {
                libraryRootResetToken += 1
            }
            setBottomMenuCompact(false)
            return
        }

        loadedTabs.insert(tab)
        selectedTab = tab
        isBottomMenuCompact = false
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func recordAppOpen() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            AppUsageMetricsStore.recordOpen()
        }
    }

    private var quoteSpeechErrorIsPresented: Binding<Bool> {
        Binding(
            get: {
                quoteSpeechPlayer.speechErrorHighlightID != nil
                    && quoteSpeechPlayer.speechErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    quoteSpeechPlayer.clearSpeechError()
                }
            }
        )
    }

}

private struct CameraStartupPlaceholder: View {
    var body: some View {
        ProgressView()
            .tint(Color.overlineAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("카메라 준비 중")
    }
}

private enum OverlineMotion {
    static let tab = Animation.smooth(duration: 0.28, extraBounce: 0.03)
    static let menu = Animation.smooth(duration: 0.24, extraBounce: 0.02)
}

struct OverlineBottomMenuBar: View {
    let selectedTab: AppTab
    let isCompact: Bool
    let selectTab: (AppTab) -> Void
    var selectCaptureMode: ((CaptureExperienceMode) -> Void)? = nil

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            OverlineBottomMenu(
                selectedTab: selectedTab,
                isCompact: isCompact,
                selectTab: selectTab,
                selectCaptureMode: selectCaptureMode
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

private struct OverlineBottomMenu: View {
    @Environment(\.captureTutorial) private var tutorial
    let selectedTab: AppTab
    let isCompact: Bool
    let selectTab: (AppTab) -> Void
    var selectCaptureMode: ((CaptureExperienceMode) -> Void)? = nil

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: isCompact ? 8 : 12) {
                    menuItems
                        .menuShellPadding(isCompact: isCompact)
                        .glassEffect(
                            .regular,
                            in: Capsule(style: .continuous)
                        )
                }
            } else {
                menuItems
                    .menuShellPadding(isCompact: isCompact)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            }
        }
        .animation(OverlineMotion.menu, value: isCompact)
        .animation(OverlineMotion.tab, value: selectedTab)
        .tutorialHighlight(tutorial?.step == .saved, cornerRadius: 40)
    }

    private var menuItems: some View {
        HStack(spacing: isCompact ? 4 : 6) {
            ForEach(AppTab.allCases) { tab in
                OverlineBottomMenuItem(
                    tab: tab,
                    selectedTab: selectedTab,
                    isCompact: isCompact,
                    selectTab: selectTab,
                    selectCaptureMode: selectCaptureMode
                )
            }
        }
    }
}

private struct OverlineBottomMenuItem: View {
    @AppStorage("capture.lastExperienceMode") private var lastMode = CaptureExperienceMode.highlight.rawValue
    @State private var showsModes = false
    @State private var pendingMode: CaptureExperienceMode?
    @State private var longPressFeedback = 0
    let tab: AppTab
    let selectedTab: AppTab
    let isCompact: Bool
    let selectTab: (AppTab) -> Void
    var selectCaptureMode: ((CaptureExperienceMode) -> Void)? = nil

    private var captureMode: CaptureExperienceMode {
        CaptureExperienceMode(rawValue: lastMode) ?? .highlight
    }

    private var title: String { tab == .capture ? captureMode.title : tab.title }

    private var isSelected: Bool {
        selectedTab == tab
    }

    @ViewBuilder
    var body: some View {
        if tab == .capture {
            tabButton
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .exclusively(before: TapGesture(count: 2).exclusively(before: TapGesture()))
                        .onEnded { gesture in
                            switch gesture {
                            case .first:
                                longPressFeedback += 1
                                showsModes = true
                            case .second(.first): showsModes = true
                            case .second(.second): selectTab(tab)
                            }
                        }
                )
                .accessibilityAction(named: "캡처 방식 선택") { showsModes = true }
                .sensoryFeedback(.selection, trigger: longPressFeedback)
                .popover(isPresented: $showsModes, attachmentAnchor: .point(UnitPoint(x: 0.5, y: -0.15)), arrowEdge: .bottom) {
                    VStack(spacing: 4) {
                        ForEach(CaptureExperienceMode.allCases) { mode in
                            Button {
                                pendingMode = mode
                                showsModes = false
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: mode.systemImage).frame(width: 24)
                                    Text(mode.title)
                                    Spacer()
                                    if mode == captureMode { Image(systemName: "checkmark") }
                                }
                                .font(.overline(.subheadline, weight: .semibold))
                                .foregroundStyle(Color.overlineInk)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(mode == captureMode ? [.isSelected] : [])
                        }
                    }
                    .padding(8)
                    .frame(width: 200)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.regularMaterial)
                    .onDisappear {
                        guard let mode = pendingMode else { return }
                        pendingMode = nil
                        if let selectCaptureMode {
                            selectCaptureMode(mode)
                        } else {
                            lastMode = mode.rawValue
                            selectTab(.capture)
                        }
                    }
                }
        } else {
            tabButton
        }
    }

    private var tabButton: some View {
        Button {
            selectTab(tab)
        } label: {
            tabLabel
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineInk)
                .frame(width: isCompact ? 44 : nil, height: isCompact ? 42 : nil)
                .frame(maxWidth: isCompact ? nil : .infinity, minHeight: isCompact ? nil : 62)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        SelectedTabGlass()
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tabLabel: some View {
        VStack(spacing: isCompact ? 0 : 5) {
            Image(systemName: tab == .capture ? captureMode.systemImage : tab.systemImage)
                .font(.system(size: isCompact ? 21 : 24, weight: .semibold))
                .frame(height: isCompact ? 24 : 26)
                .scaleEffect(tab == .community ? 0.9 : 1)

            Text(title)
                .font(.overline(.caption, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .opacity(isCompact ? 0 : 1)
                .scaleEffect(isCompact ? 0.92 : 1)
                .frame(height: isCompact ? 0 : 16)
                .clipped()
        }
        .frame(height: isCompact ? 24 : 47)
        .clipped()
    }
}

private struct SelectedTabGlass: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.overlineInk.opacity(0.08))
    }
}

private extension View {
    func menuShellPadding(isCompact: Bool) -> some View {
        self
            .padding(isCompact ? 5 : 6)
            .frame(maxWidth: isCompact ? nil : .infinity)
    }


}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case capture
    case library
    case insights
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: String(localized: LocalizedStringResource("캡처", locale: AppLocale.uiLocale))
        case .library: String(localized: LocalizedStringResource("책장", locale: AppLocale.uiLocale))
        case .insights: String(localized: LocalizedStringResource("인사이트", locale: AppLocale.uiLocale))
        case .community: String(localized: LocalizedStringResource("커뮤니티", locale: AppLocale.uiLocale))
        }
    }

    var systemImage: String {
        switch self {
        case .capture: "text.viewfinder"
        case .library: "books.vertical"
        case .insights: "sparkles"
        case .community: "person.2"
        }
    }

}

#Preview {
    ContentView()
        .environment(ReadingLibrary.preview)
        .environment(AppIntentRouter())
        .environment(QuoteSpeechPlayer())
        .environment(LLMSettingsStore())
}

extension Color {
    static let overlineCanvas = Color(uiColor: .systemGroupedBackground)
    static let overlinePaper = Color(uiColor: .secondarySystemGroupedBackground)
    static let overlineInk = Color(uiColor: .label)
    static let overlineMutedInk = Color(uiColor: .secondaryLabel)
    static let overlineAccent = Color(uiColor: .label)
    static let overlineCoral = Color(red: 0.84, green: 0.31, blue: 0.25)
    static let overlinePlum = Color(white: 0.28)
    static let overlineHighlight = Color(red: 1.00, green: 0.83, blue: 0.22)
}

struct OverlineCanvasBackground: View {
    var body: some View {
        Color.overlineCanvas
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.overline(.headline))
                .foregroundStyle(Color.overlineAccent)
            Text(title)
                .font(.overline(.headline))
                .foregroundStyle(Color.overlineInk)
            if let trailingText {
                Text(trailingText)
                    .font(.overline(.caption, weight: .semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct CapsuleMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        content.overlineContentSurface()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.overline(.caption, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk)
            Text(value)
                .font(.overline(.title3, weight: .bold))
                .foregroundStyle(Color.overlineInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}

private struct BottomMenuCompactActionKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

private struct AppTabSelectionActionKey: EnvironmentKey {
    static let defaultValue: (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    var setBottomMenuCompact: (Bool) -> Void {
        get { self[BottomMenuCompactActionKey.self] }
        set { self[BottomMenuCompactActionKey.self] = newValue }
    }

    var selectAppTab: (AppTab) -> Void {
        get { self[AppTabSelectionActionKey.self] }
        set { self[AppTabSelectionActionKey.self] = newValue }
    }
}

private struct BottomMenuCompactionModifier: ViewModifier {
    @Environment(\.setBottomMenuCompact) private var setBottomMenuCompact

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 24
                } action: { _, isCompact in
                    setBottomMenuCompact(isCompact)
                }
        } else {
            content
        }
    }
}

extension View {
    func overlineBottomMenuCompaction() -> some View {
        modifier(BottomMenuCompactionModifier())
    }
}
