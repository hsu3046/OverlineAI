import SwiftUI

enum OverlineTextStyle: Equatable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2

    var pointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        }
    }

    var relativeStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }

    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

extension Font {
    static func overline(
        _ style: OverlineTextStyle,
        weight: Font.Weight? = nil
    ) -> Font {
        custom(
            "PretendardVariable-Regular",
            size: style.pointSize,
            relativeTo: style.relativeStyle
        )
        .weight(weight ?? style.defaultWeight)
    }

    static func overline(
        size: CGFloat,
        relativeTo style: Font.TextStyle = .body,
        weight: Font.Weight = .regular
    ) -> Font {
        custom(
            "PretendardVariable-Regular",
            size: size,
            relativeTo: style
        )
        .weight(weight)
    }
}
