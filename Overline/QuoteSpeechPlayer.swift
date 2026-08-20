import AVFoundation
import Observation

@MainActor
@Observable
final class QuoteSpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var activeHighlightID: Highlight.ID?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
    }

    func toggle(_ highlight: Highlight) {
        if activeHighlightID == highlight.id {
            stop()
            return
        }

        let text = highlight.text.trimmed
        guard !text.isEmpty else { return }

        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice(for: highlight.language)
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.postUtteranceDelay = 0.12

        currentUtterance = utterance
        activeHighlightID = highlight.id
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
        activeHighlightID = nil
    }

    func isSpeaking(_ highlightID: Highlight.ID) -> Bool {
        activeHighlightID == highlightID
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finishIfCurrent(utterance)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finishIfCurrent(utterance)
        }
    }

    private func finishIfCurrent(_ utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        activeHighlightID = nil
    }

    private func preferredVoice(for language: CaptureLanguage) -> AVSpeechSynthesisVoice? {
        let localeIdentifier = language.speechLocaleIdentifier
        let languageCode = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier

        let installedVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.caseInsensitiveCompare(localeIdentifier) == .orderedSame
                || voice.language.lowercased().hasPrefix("\(languageCode.lowercased())-")
        }

        return installedVoices.max { lhs, rhs in
            lhs.quality.rawValue < rhs.quality.rawValue
        } ?? AVSpeechSynthesisVoice(language: localeIdentifier)
    }
}

private extension CaptureLanguage {
    var speechLocaleIdentifier: String {
        switch self {
        case .korean: "ko-KR"
        case .english: "en-US"
        case .japanese: "ja-JP"
        }
    }
}
