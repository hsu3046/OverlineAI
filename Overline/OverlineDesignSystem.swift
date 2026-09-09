import SwiftUI

enum OverlineDesign {
    static let pageInset: CGFloat = 20
    static let controlHeight: CGFloat = 48
    static let touchTarget: CGFloat = 44
    static let controlRadius: CGFloat = 24
    static let contentRadius: CGFloat = 8
    static let fieldInset: CGFloat = 16

    static let pageTitle = Font.overline(.title2, weight: .bold)
    static let sectionTitle = Font.overline(.headline)
    static let body = Font.overline(.body)
    static let button = Font.overline(.subheadline, weight: .semibold)
    static let detail = Font.overline(.footnote)
    static let icon = Font.system(.body, weight: .semibold)
}

extension View {
    @ViewBuilder
    func overlineControlSurface(selected: Bool = false, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.interactive(interactive),
                in: .capsule
            )
            .background(selected ? Color.primary.opacity(0.08) : Color.clear, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
                .background(selected ? Color.primary.opacity(0.08) : Color.clear, in: Capsule())
        }
    }

    func overlineContentSurface(selected: Bool = false, emphasized: Bool = false) -> some View {
        background(
            selected ? Color(uiColor: .tertiarySystemFill)
                : emphasized ? Color(uiColor: .tertiarySystemFill).opacity(0.55)
                : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: OverlineDesign.contentRadius)
        )
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: OverlineDesign.contentRadius)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    func overlineSearchSurface() -> some View {
        padding(.horizontal, OverlineDesign.fieldInset)
            .frame(minHeight: OverlineDesign.controlHeight)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

struct OverlineActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OverlineDesign.button)
            .padding(.horizontal, OverlineDesign.fieldInset)
            .frame(minHeight: OverlineDesign.touchTarget)
            .foregroundStyle(prominent ? Color(uiColor: .systemBackground) : Color.overlineInk)
            .background(prominent ? Color.overlineInk : Color(uiColor: .tertiarySystemFill), in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

struct OverlinePillSearchField: View {
    static let height: CGFloat = OverlineDesign.controlHeight

    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(OverlineDesign.icon)
                .foregroundStyle(Color.overlineMutedInk)

            TextField(prompt, text: $text)
                .font(OverlineDesign.body)
                .foregroundStyle(Color.overlineInk)
                .accessibilityLabel(prompt)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(OverlineDesign.icon)
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(width: OverlineDesign.touchTarget, height: OverlineDesign.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .overlineSearchSurface()
    }
}
