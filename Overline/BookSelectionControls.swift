import SwiftUI

struct OverlineDoneToolbarButton: View {
    var isDisabled = false
    var accessibilityLabel = "완료"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isDisabled ? Color.overlineMutedInk.opacity(0.38) : Color.overlineAccent)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct OverlineSettingsButton: View {
    let settings: LLMSettingsStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.84))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("설정")
        .accessibilityValue("\(settings.provider.title), \(settings.selectedModelTitle)")
    }
}

struct OverlineSheetHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            leading
                .frame(width: 44, height: 44)

            Spacer(minLength: 0)

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.overlineInk)

            Spacer(minLength: 0)

            trailing
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct OverlineSheetIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = Color.overlineAccent
    var font: Font = .title2.weight(.semibold)
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(font)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isDisabled ? Color.overlineMutedInk.opacity(0.36) : tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct OverlineEditorLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
            .padding(.leading, 18)
    }
}

struct OverlineBookSelectorButton: View {
    let title: String
    var subtitle: String?
    var systemImage = "book.closed"
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 26
    var titleFont: Font = .subheadline.weight(.semibold)
    var subtitleFont: Font = .caption.weight(.semibold)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.overlineAccent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(Color.overlineInk)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle, !subtitle.trimmed.isEmpty {
                        Text(subtitle)
                            .font(subtitleFont)
                            .foregroundStyle(Color.overlineMutedInk.opacity(0.70))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.58))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .overlineGlassControl(cornerRadius: cornerRadius, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("책 선택")
    }
}

struct OverlineBookPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let books: [ReadingBook]
    let selectedBookID: ReadingBook.ID?
    var includesAllOption = false
    var allTitle = "전체"
    var allCount: Int?
    var addBook: (() -> Void)?
    let onSelect: (ReadingBook.ID?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if includesAllOption {
                        Button {
                            onSelect(nil)
                            dismiss()
                        } label: {
                            OverlineBookPickerRow(
                                systemImage: "tray.full",
                                title: allTitle,
                                subtitle: nil,
                                trailingText: countText(allCount),
                                isSelected: selectedBookID == nil
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(books) { book in
                        Button {
                            onSelect(book.id)
                            dismiss()
                        } label: {
                            OverlineBookPickerRow(
                                systemImage: "book.closed",
                                title: book.title,
                                subtitle: book.author,
                                trailingText: countText(book.highlights.count),
                                isSelected: selectedBookID == book.id
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let addBook {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                addBook()
                            }
                        } label: {
                            OverlineBookPickerRow(
                                systemImage: "plus",
                                title: "책 추가",
                                subtitle: nil,
                                trailingText: nil,
                                isSelected: false,
                                isAddAction: true
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func countText(_ count: Int?) -> String? {
        guard let count else { return nil }
        return "\(count)조각"
    }
}

struct OverlineBookPickerMetrics {
    static func sheetHeight(bookCount: Int, includesAllOption: Bool = false, includesAddBook: Bool = false) -> CGFloat {
        let rowCount = bookCount
            + (includesAllOption ? 1 : 0)
            + (includesAddBook ? 1 : 0)
        return min(max(CGFloat(rowCount) * 88 + 124, 292), 560)
    }
}

private struct OverlineBookPickerRow: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let trailingText: String?
    let isSelected: Bool
    var isAddAction = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isAddAction ? Color.overlineAccent : Color.overlineInk)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let subtitle, !subtitle.trimmed.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 78)
        .overlineGlassControl(cornerRadius: 24, selected: isSelected, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var iconColor: Color {
        if isAddAction { return Color.overlineAccent }
        return isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.62)
    }
}

extension View {
    @ViewBuilder
    func overlineGlassControl(cornerRadius: CGFloat, selected: Bool = false, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.16 : 0.045))
                }
                .glassEffect(
                    .regular.tint(Color.white.opacity(selected ? 0.18 : 0.07)),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(selected ? 0.54 : 0.26), lineWidth: 1)
                }
        } else {
            self
                .background(Color.white.opacity(selected ? 0.26 : 0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(selected ? 0.54 : 0.26), lineWidth: 1)
                }
        }
    }
}
