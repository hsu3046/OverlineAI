import SwiftUI

struct HighlightTonePicker: View {
    @Binding var selectedTone: StickyTone

    private let tones: [StickyTone] = [.yellow, .rose, .blue, .mint]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tones, id: \.self) { tone in
                Button {
                    withAnimation(.smooth(duration: 0.18, extraBounce: 0.04)) {
                        selectedTone = tone
                    }
                } label: {
                    Circle()
                        .fill(tone.paper)
                        .frame(width: selectedTone == tone ? 15 : 12, height: selectedTone == tone ? 15 : 12)
                        .overlay {
                            if selectedTone == tone {
                                Circle()
                                    .stroke(Color.overlineInk.opacity(0.42), lineWidth: 1.4)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tone.accessibilityName) 형광펜")
                .accessibilityAddTraits(selectedTone == tone ? [.isSelected] : [])
            }
        }
        .fixedSize()
    }
}
