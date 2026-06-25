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

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CaptureView()
            }
            .tag(AppTab.capture)

            NavigationStack {
                LibraryView()
            }
            .tag(AppTab.library)

            NavigationStack {
                InsightsView()
            }
            .tag(AppTab.insights)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                OverlineBottomMenu(
                    selectedTab: $selectedTab,
                    isCompact: isBottomMenuCompact
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .tint(Color.overlineAccent)
        .background(Color.overlineCanvas.ignoresSafeArea())
        .environment(\.setBottomMenuCompact, setBottomMenuCompact)
        .onAppear {
            AppUsageMetricsStore.recordOpen()
            apply(intentRouter.request)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            AppUsageMetricsStore.recordOpen()
        }
        .onChange(of: selectedTab) { _, _ in
            setBottomMenuCompact(false)
        }
        .onChange(of: intentRouter.request) { _, request in
            apply(request)
        }
    }

    private func apply(_ request: AppIntentRequest?) {
        guard let request else { return }
        selectedTab = request.tab
    }

    private func setBottomMenuCompact(_ isCompact: Bool) {
        guard isBottomMenuCompact != isCompact else { return }
        isBottomMenuCompact = isCompact
    }
}

private struct OverlineBottomMenu: View {
    @Binding var selectedTab: AppTab
    let isCompact: Bool

    var body: some View {
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

    private var menuItems: some View {
        HStack(spacing: isCompact ? 4 : 6) {
            ForEach(AppTab.allCases) { tab in
                OverlineBottomMenuItem(
                    tab: tab,
                    selectedTab: $selectedTab,
                    isCompact: isCompact
                )
            }
        }
    }
}

private struct OverlineBottomMenuItem: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab
    let isCompact: Bool

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button {
            guard selectedTab != tab else { return }
            selectedTab = tab
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

    @ViewBuilder
    private var tabLabel: some View {
        if isCompact {
            Image(systemName: tab.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .frame(height: 24)
        } else {
            VStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(height: 26)
                Text(tab.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
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
            .shadow(color: Color.black.opacity(0.15), radius: 24, y: 10)
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
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
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
