import SwiftUI

enum SpeechPlaybackPreferences {
    static let rateDefaultsKey = "overline.speech.rateMultiplier"
    static let sentencePauseDefaultsKey = "overline.speech.sentencePause"
    static let legacyPageReaderRateDefaultsKey = "pageReader.speechRateMultiplier"

    static let rateRange = 0.8...1.6
    static let rateStep = 0.05
    static let defaultRate = 1.0

    static let sentencePauseRange = 0.0...0.6
    static let sentencePauseStep = 0.05
    static let defaultSentencePause = 0.15

    static func normalizedRate(_ value: Double) -> Double {
        normalized(value, range: rateRange, step: rateStep)
    }

    static func normalizedSentencePause(_ value: Double) -> Double {
        normalized(value, range: sentencePauseRange, step: sentencePauseStep)
    }

    private static func normalized(
        _ value: Double,
        range: ClosedRange<Double>,
        step: Double
    ) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped / step).rounded() * step
    }
}

struct SpeechPlaybackControls: View {
    @Binding var rateMultiplier: Double
    @Binding var sentencePause: Double

    var body: some View {
        VStack(spacing: 24) {
            SteppedSpeechSlider(
                title: "읽기 속도",
                value: $rateMultiplier,
                range: SpeechPlaybackPreferences.rateRange,
                step: SpeechPlaybackPreferences.rateStep,
                ticks: [0.8, 1.0, 1.2, 1.4, 1.6],
                valueText: { preciseValueText($0, suffix: "×") },
                tickText: { String(format: "%.1f", $0) }
            )

            SteppedSpeechSlider(
                title: "문장 간격",
                value: $sentencePause,
                range: SpeechPlaybackPreferences.sentencePauseRange,
                step: SpeechPlaybackPreferences.sentencePauseStep,
                ticks: [0.0, 0.2, 0.4, 0.6],
                valueText: { preciseValueText($0, suffix: "초") },
                tickText: { String(format: "%.1f", $0) }
            )
        }
        .padding(.vertical, 4)
    }

    private func preciseValueText(_ value: Double, suffix: String) -> String {
        let hundredths = Int((value * 100).rounded())
        let format = hundredths.isMultiple(of: 10) ? "%.1f" : "%.2f"
        return String(format: format, value) + suffix
    }
}

private struct SteppedSpeechSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let ticks: [Double]
    let valueText: (Double) -> String
    let tickText: (Double) -> String

    @State private var draftValue: Double
    @State private var isEditing = false

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        ticks: [Double],
        valueText: @escaping (Double) -> String,
        tickText: @escaping (Double) -> String
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.ticks = ticks
        self.valueText = valueText
        self.tickText = tickText
        _draftValue = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.overline(.body, weight: .medium))

                Spacer()

                Text(valueText(draftValue))
                    .font(.overline(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.overlineAccent)
                    .monospacedDigit()
            }

            Slider(
                value: $draftValue,
                in: range,
                step: step,
                onEditingChanged: { editing in
                    isEditing = editing
                    guard !editing else { return }
                    value = draftValue
                }
            )
            .tint(Color.overlineAccent)
            .accessibilityLabel(title)
            .accessibilityValue(valueText(draftValue))

            HStack(spacing: 0) {
                ForEach(ticks, id: \.self) { tick in
                    Text(tickText(tick))
                        .font(.overline(.caption2))
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: value) { _, newValue in
            guard !isEditing else { return }
            draftValue = newValue
        }
    }
}
