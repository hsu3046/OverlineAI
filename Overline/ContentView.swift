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

    var body: some View {
        persistentTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    OverlineBottomMenu(
                        selectedTab: selectedTab,
                        isCompact: isBottomMenuCompact,
                        selectTab: selectTab
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .tint(Color.overlineAccent)
            .background(OverlineCanvasBackground().ignoresSafeArea())
            .environment(\.setBottomMenuCompact, setBottomMenuCompact)
            .onAppear {
                recordAppOpen()
                apply(intentRouter.request)
            }
            .task {
                guard cameraScanner == nil else { return }
                cameraScanner = await CameraTextScanner.makePrepared()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    quoteSpeechPlayer.stop()
                    Task {
                        await library.flushPendingPersistence()
                    }
                    return
                }
                quoteSpeechPlayer.invalidateVoiceCatalog()
                recordAppOpen()
            }
            .onChange(of: selectedTab) { _, _ in
                setBottomMenuCompact(false)
                if selectedTab != .library {
                    quoteSpeechPlayer.stop()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlineHighlightsRemoved)) { notification in
                guard
                    let activeHighlightID = quoteSpeechPlayer.activeHighlightID,
                    let removedHighlightIDs = notification.userInfo?[OverlineNotificationUserInfoKey.highlightIDs]
                        as? [Highlight.ID],
                    removedHighlightIDs.contains(activeHighlightID)
                else {
                    return
                }
                quoteSpeechPlayer.stop()
            }
            .onChange(of: intentRouter.request) { _, request in
                apply(request)
            }
    }

    @ViewBuilder
    private var persistentTabContent: some View {
        ZStack {
            if loadedTabs.contains(.capture) {
                persistentTabLayer(.capture) {
                    NavigationStack {
                        if let cameraScanner {
                            CaptureView(cameraScanner: cameraScanner, isActive: selectedTab == .capture)
                        } else {
                            CameraStartupPlaceholder()
                        }
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
                    }
                }
            }

            if loadedTabs.contains(.insights) {
                persistentTabLayer(.insights) {
                    NavigationStack {
                        InsightsView(isActive: selectedTab == .insights)
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
        selectTab(request.tab)
    }

    private func setBottomMenuCompact(_ isCompact: Bool) {
        guard isBottomMenuCompact != isCompact else { return }
        withAnimation(OverlineMotion.menu) {
            isBottomMenuCompact = isCompact
        }
    }

    private func selectTab(_ tab: AppTab) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

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

    private func recordAppOpen() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            AppUsageMetricsStore.recordOpen()
        }
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

private struct OverlineBottomMenu: View {
    let selectedTab: AppTab
    let isCompact: Bool
    let selectTab: (AppTab) -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: isCompact ? 8 : 12) {
                    menuItems
                        .menuShellPadding(isCompact: isCompact)
                        .glassEffect(
                            .regular.tint(Color.white.opacity(0.18)),
                            in: Capsule(style: .continuous)
                        )
                        .menuShellOverlay()
                }
            } else {
                menuItems
                    .menuShellPadding(isCompact: isCompact)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .menuShellOverlay()
            }
        }
        .animation(OverlineMotion.menu, value: isCompact)
        .animation(OverlineMotion.tab, value: selectedTab)
    }

    private var menuItems: some View {
        HStack(spacing: isCompact ? 4 : 6) {
            ForEach(AppTab.allCases) { tab in
                OverlineBottomMenuItem(
                    tab: tab,
                    selectedTab: selectedTab,
                    isCompact: isCompact,
                    selectTab: selectTab
                )
            }
        }
    }
}

private struct OverlineBottomMenuItem: View {
    let tab: AppTab
    let selectedTab: AppTab
    let isCompact: Bool
    let selectTab: (AppTab) -> Void

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
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
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tabLabel: some View {
        VStack(spacing: isCompact ? 0 : 5) {
            Image(systemName: tab.systemImage)
                .font(.system(size: isCompact ? 21 : 24, weight: .semibold))
                .frame(height: isCompact ? 24 : 26)

            Text(tab.title)
                .font(.caption.weight(.bold))
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
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.overlineAccent.opacity(0.08))
                .glassEffect(
                    .regular.tint(Color.overlineAccent.opacity(0.16)),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                }
        } else {
            Capsule(style: .continuous)
                .fill(Color.overlineAccent.opacity(0.16))
        }
    }
}

private extension View {
    func menuShellPadding(isCompact: Bool) -> some View {
        self
            .padding(isCompact ? 5 : 6)
            .frame(maxWidth: isCompact ? nil : .infinity)
    }

    func menuShellOverlay() -> some View {
        self
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.62), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.28))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.top, 1)
            }
    }

    func metricCardChrome(color: Color, cornerRadius: CGFloat) -> some View {
        self
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.48), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.72))
                    .frame(width: 28, height: 3)
                    .padding(.leading, 14)
                    .padding(.top, 10)
            }
    }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case capture
    case library
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "캡처"
        case .library: "책장"
        case .insights: "인사이트"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: "text.viewfinder"
        case .library: "books.vertical"
        case .insights: "sparkles"
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
    static let overlineCanvas = Color(red: 0.94, green: 0.92, blue: 0.84)
    static let overlinePaper = Color(red: 0.98, green: 0.95, blue: 0.87)
    static let overlineInk = Color(red: 0.12, green: 0.12, blue: 0.10)
    static let overlineMutedInk = Color(red: 0.39, green: 0.37, blue: 0.31)
    static let overlineAccent = Color(red: 0.16, green: 0.43, blue: 0.45)
    static let overlineCoral = Color(red: 0.84, green: 0.31, blue: 0.25)
    static let overlinePlum = Color(red: 0.34, green: 0.20, blue: 0.40)
    static let overlineHighlight = Color(red: 1.00, green: 0.83, blue: 0.22)
}

struct OverlineCanvasBackground: View {
    var body: some View {
        Color.overlineCanvas
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear,
                        Color.overlineMutedInk.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                OverlineCanvasTexture()
            }
    }
}

private struct OverlineCanvasTexture: View {
    var body: some View {
        Image("CanvasTexture")
            .resizable(resizingMode: .tile)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.overlineAccent)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.overlineInk)
            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.semibold))
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
        if #available(iOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: metricCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
                .glassEffect(
                    .regular.tint(color.opacity(0.10)),
                    in: .rect(cornerRadius: metricCornerRadius)
                )
                .metricCardChrome(color: color, cornerRadius: metricCornerRadius)
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: metricCornerRadius, style: .continuous))
                .metricCardChrome(color: color, cornerRadius: metricCornerRadius)
        }
    }

    private var metricCornerRadius: CGFloat {
        18
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineMutedInk)
            Text(value)
                .font(.title3.weight(.bold))
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

extension EnvironmentValues {
    var setBottomMenuCompact: (Bool) -> Void {
        get { self[BottomMenuCompactActionKey.self] }
        set { self[BottomMenuCompactActionKey.self] = newValue }
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
