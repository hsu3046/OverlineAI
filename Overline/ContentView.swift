//
//  ContentView.swift
//  Overline
//
//  Created by Yu Hitomi on 6/24/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppIntentRouter.self) private var intentRouter
    @State private var selectedTab: AppTab = .capture
    @State private var isBottomMenuCompact = false
    @State private var isForwardTabTransition = true
    @State private var libraryRootResetToken = 0

    var body: some View {
        ZStack {
            selectedTabContent
                .id(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(selectedTabTransition)
        }
        .animation(OverlineMotion.tab, value: selectedTab)
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            recordAppOpen()
        }
        .onChange(of: selectedTab) { _, _ in
            setBottomMenuCompact(false)
        }
        .onChange(of: intentRouter.request) { _, request in
            apply(request)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .capture:
            NavigationStack {
                CaptureView()
            }
        case .library:
            NavigationStack {
                LibraryView(rootResetToken: libraryRootResetToken)
            }
        case .insights:
            NavigationStack {
                InsightsView()
            }
        }
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
        guard selectedTab != tab else {
            if tab == .library {
                libraryRootResetToken += 1
            }
            setBottomMenuCompact(false)
            return
        }

        isForwardTabTransition = tab.order > selectedTab.order
        withAnimation(OverlineMotion.tab) {
            selectedTab = tab
            isBottomMenuCompact = false
        }
    }

    private func recordAppOpen() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            AppUsageMetricsStore.recordOpen()
        }
    }

    private var selectedTabTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isForwardTabTransition ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isForwardTabTransition ? .leading : .trailing).combined(with: .opacity)
        )
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
        .animation(OverlineMotion.menu, value: isCompact)
        .animation(OverlineMotion.tab, value: isSelected)
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

    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    @ViewBuilder
    var rootView: some View {
        switch self {
        case .capture:
            CaptureView()
        case .library:
            LibraryView()
        case .insights:
            InsightsView()
        }
    }
}

#Preview {
    ContentView()
        .environment(ReadingLibrary.preview)
        .environment(AppIntentRouter())
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
        Canvas { context, size in
            var grain = Path()
            let spacing: CGFloat = 9
            for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
                for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
                    let column = Int((x / spacing).rounded(.down))
                    let row = Int((y / spacing).rounded(.down))
                    guard (column + row).isMultiple(of: 3) else { continue }
                    grain.addEllipse(in: CGRect(x: x, y: y, width: 0.65, height: 0.65))
                }
            }
            context.fill(grain, with: .color(Color.white.opacity(0.06)))

            var fibers = Path()
            for y in stride(from: CGFloat(6), through: size.height, by: 22) {
                fibers.move(to: CGPoint(x: 0, y: y))
                fibers.addLine(to: CGPoint(x: size.width, y: y + 1.2))
            }
            context.stroke(fibers, with: .color(Color.overlineMutedInk.opacity(0.018)), lineWidth: 0.45)
        }
        .allowsHitTesting(false)
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
