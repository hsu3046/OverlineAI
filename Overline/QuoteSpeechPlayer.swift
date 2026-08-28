import AVFoundation
import Observation
import OSLog

private let quoteSpeechLogger = Logger(subsystem: "aib.Overline", category: "SpeechVoice")

private enum QuoteSpeechVoiceIdentifier {
    static let systemAutomatic = "overline.system-automatic"
}

struct QuoteSpeechVoiceOption: Identifiable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality?

    var qualityTitle: String {
        switch quality {
        case .some(.premium):
            "최고 음질"
        case .some(.enhanced):
            "고음질"
        case .some:
            "기본"
        case .none:
            ""
        }
    }

    var pickerTitle: String {
        qualityTitle.isEmpty ? name : "\(name) · \(qualityTitle)"
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
        let automatic = QuoteSpeechVoiceOption(
            id: QuoteSpeechVoiceIdentifier.systemAutomatic,
            name: "최고 음질 자동 선택",
            language: language.speechLocaleIdentifier,
            quality: nil
        )
        let rankedVoices = rankedVoices(for: language)
        let highQualityVoices = rankedVoices.filter { $0.quality != .default }
        let selectableVoices = (highQualityVoices.isEmpty ? rankedVoices : highQualityVoices)
            .map {
                QuoteSpeechVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: $0.quality
                )
            }

        return [automatic] + selectableVoices
    }

    func selectedVoiceIdentifier(for language: CaptureLanguage) -> String {
        let savedIdentifier = selectedVoiceIdentifiers[language.rawValue]
        if let savedIdentifier,
           voiceOptions(for: language).contains(where: { $0.id == savedIdentifier }) {
            return savedIdentifier
        }
        return QuoteSpeechVoiceIdentifier.systemAutomatic
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

    func logVoiceCatalog() {
        for language in CaptureLanguage.allCases {
            let automaticVoice = rankedVoices(for: language).first
            if let automaticVoice {
                logVoice(automaticVoice, selection: "automatic", requestedLanguage: language)
            } else {
                quoteSpeechLogger.info(
                    "tts_voice_automatic_unavailable requested_language=\(language.speechLocaleIdentifier, privacy: .public)"
                )
            }

            let voices = matchingVoices(for: language)
            quoteSpeechLogger.info(
                "tts_voice_catalog requested_language=\(language.speechLocaleIdentifier, privacy: .public) count=\(voices.count, privacy: .public)"
            )
            for voice in voices {
                logVoice(voice, selection: "catalog", requestedLanguage: language)
            }
        }
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
        if identifier != QuoteSpeechVoiceIdentifier.systemAutomatic,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return rankedVoices(for: language).first
    }

    private func matchingVoices(for language: CaptureLanguage) -> [AVSpeechSynthesisVoice] {
        let localeIdentifier = language.speechLocaleIdentifier
        let languageCode = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier

        return AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.caseInsensitiveCompare(localeIdentifier) == .orderedSame
                || voice.language.lowercased().hasPrefix("\(languageCode.lowercased())-")
        }
    }

    private func rankedVoices(for language: CaptureLanguage) -> [AVSpeechSynthesisVoice] {
        matchingVoices(for: language).sorted { lhs, rhs in
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
    }

    private func loadVoiceSelections() {
        for language in CaptureLanguage.allCases {
            let options = voiceOptions(for: language)
            let savedIdentifier = defaults.string(forKey: voiceDefaultsKey(for: language))
            let resolvedIdentifier = savedIdentifier.flatMap { saved in
                options.contains(where: { $0.id == saved }) ? saved : nil
            } ?? QuoteSpeechVoiceIdentifier.systemAutomatic

            selectedVoiceIdentifiers[language.rawValue] = resolvedIdentifier
            defaults.set(resolvedIdentifier, forKey: voiceDefaultsKey(for: language))
        }
    }

    private func logVoice(
        _ voice: AVSpeechSynthesisVoice,
        selection: String,
        requestedLanguage: CaptureLanguage
    ) {
        let quality: String
        switch voice.quality {
        case .premium:
            quality = "premium"
        case .enhanced:
            quality = "enhanced"
        default:
            quality = "default"
        }

        let traits: String
        if voice.voiceTraits.contains(.isPersonalVoice) {
            traits = "personal"
        } else if voice.voiceTraits.contains(.isNoveltyVoice) {
            traits = "novelty"
        } else {
            traits = "regular"
        }

        quoteSpeechLogger.info(
            "tts_voice selection=\(selection, privacy: .public) requested_language=\(requestedLanguage.speechLocaleIdentifier, privacy: .public) name=\(voice.name, privacy: .public) language=\(voice.language, privacy: .public) quality=\(quality, privacy: .public) traits=\(traits, privacy: .public) identifier=\(voice.identifier, privacy: .public)"
        )
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
