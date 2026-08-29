import SwiftUI

struct OverlineInlineUndoRow: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.overline(.caption, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.56))
                .frame(width: 18)

            Text(message)
                .font(.overline(.subheadline, weight: .semibold))
                .foregroundStyle(Color.overlineMutedInk.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("복구", action: undo)
                .font(.overline(.subheadline, weight: .bold))
                .foregroundStyle(Color.overlineAccent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.48), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.overlineInk.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message), 복구")
    }
}
