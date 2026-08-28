import AVFoundation
import Observation

struct QuoteSpeechVoiceOption: Identifiable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    var qualityTitle: String {
        switch quality {
        case .premium:
            "최고 음질"
        case .enhanced:
            "고음질"
        default:
            "기본"
        }
    }

    var pickerTitle: String {
        "\(name) · \(qualityTitle)"
    }
}

@MainActor
@Observable
final class QuoteSpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var activeHighlightID: Highlight.ID?
    private(set) var previewLanguage: CaptureLanguage?
    private(set) var selectedVoiceIdentifiers: [String: String] = [:]

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private let defaults = UserDefaults.standard

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
        loadVoiceSelections()
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
        configure(utterance, for: highlight.language)

        currentUtterance = utterance
        activeHighlightID = highlight.id
        synthesizer.speak(utterance)
    }

    func togglePreview(for language: CaptureLanguage) {
        if previewLanguage == language {
            stop()
            return
        }

        stop()

        let utterance = AVSpeechUtterance(string: language.speechPreviewText)
        configure(utterance, for: language)

        currentUtterance = utterance
        previewLanguage = language
        synthesizer.speak(utterance)
    }

    func voiceOptions(for language: CaptureLanguage) -> [QuoteSpeechVoiceOption] {
        matchingVoices(for: language)
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }

                let lhsIsExactLocale = lhs.language.caseInsensitiveCompare(language.speechLocaleIdentifier) == .orderedSame
                let rhsIsExactLocale = rhs.language.caseInsensitiveCompare(language.speechLocaleIdentifier) == .orderedSame
                if lhsIsExactLocale != rhsIsExactLocale {
                    return lhsIsExactLocale
                }

                let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.identifier < rhs.identifier
            }
            .map {
                QuoteSpeechVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: $0.quality
                )
            }
    }

    func selectedVoiceIdentifier(for language: CaptureLanguage) -> String {
        let savedIdentifier = selectedVoiceIdentifiers[language.rawValue]
        if let savedIdentifier,
           voiceOptions(for: language).contains(where: { $0.id == savedIdentifier }) {
            return savedIdentifier
        }
        return voiceOptions(for: language).first?.id ?? ""
    }

    func selectedVoiceName(for language: CaptureLanguage) -> String {
        let identifier = selectedVoiceIdentifier(for: language)
        return voiceOptions(for: language).first(where: { $0.id == identifier })?.name ?? "기본 음성"
    }

    func setSelectedVoiceIdentifier(_ identifier: String, for language: CaptureLanguage) {
        guard voiceOptions(for: language).contains(where: { $0.id == identifier }) else { return }

        stop()
        selectedVoiceIdentifiers[language.rawValue] = identifier
        defaults.set(identifier, forKey: voiceDefaultsKey(for: language))
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
        activeHighlightID = nil
        previewLanguage = nil
    }

    func isSpeaking(_ highlightID: Highlight.ID) -> Bool {
        activeHighlightID == highlightID
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishIfCurrent(utteranceID)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishIfCurrent(utteranceID)
        }
    }

    private func finishIfCurrent(_ utteranceID: ObjectIdentifier) {
        guard let activeUtterance = currentUtterance,
              ObjectIdentifier(activeUtterance) == utteranceID else { return }
        currentUtterance = nil
        activeHighlightID = nil
        previewLanguage = nil
    }

    private func configure(_ utterance: AVSpeechUtterance, for language: CaptureLanguage) {
        utterance.voice = selectedVoice(for: language)
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.postUtteranceDelay = 0.12
    }

    private func selectedVoice(for language: CaptureLanguage) -> AVSpeechSynthesisVoice? {
        let identifier = selectedVoiceIdentifier(for: language)
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: language.speechLocaleIdentifier)
    }

    private func matchingVoices(for language: CaptureLanguage) -> [AVSpeechSynthesisVoice] {
        let localeIdentifier = language.speechLocaleIdentifier
        let languageCode = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier

        return AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.caseInsensitiveCompare(localeIdentifier) == .orderedSame
                || voice.language.lowercased().hasPrefix("\(languageCode.lowercased())-")
        }
    }

    private func loadVoiceSelections() {
        for language in CaptureLanguage.allCases {
            let options = voiceOptions(for: language)
            let savedIdentifier = defaults.string(forKey: voiceDefaultsKey(for: language))
            let resolvedIdentifier = savedIdentifier.flatMap { saved in
                options.contains(where: { $0.id == saved }) ? saved : nil
            } ?? options.first?.id

            guard let resolvedIdentifier else { continue }
            selectedVoiceIdentifiers[language.rawValue] = resolvedIdentifier
            defaults.set(resolvedIdentifier, forKey: voiceDefaultsKey(for: language))
        }
    }

    private func voiceDefaultsKey(for language: CaptureLanguage) -> String {
        "overline.quoteSpeech.voice.\(language.rawValue)"
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

    var speechPreviewText: String {
        switch self {
        case .korean:
            "책 속 문장이 오늘의 생각으로 이어집니다."
        case .english:
            "A line from a book can become a thought of your own."
        case .japanese:
            "本の中の言葉が、今日の思考につながります。"
        }
    }
}
