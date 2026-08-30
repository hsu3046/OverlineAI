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
    private(set) var speechEngineChoice: SpeechEngineChoice = .system
    private(set) var selectedSupertonicVoice: SupertonicVoicePreset = .f1
    private(set) var supertonicQuality: SupertonicQuality = .balanced
    private(set) var supertonicAssetState: SupertonicAssetState = .unavailable
    private(set) var speechErrorMessage: String?

    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var cachedVoices: [AVSpeechSynthesisVoice]?
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var supertonicPlaybackTask: Task<Void, Never>?
    @ObservationIgnored private var supertonicPlaybackToken: UUID?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let supertonicAssetStore: SupertonicAssetStore
    @ObservationIgnored private let supertonicEngine = SupertonicSpeechEngine()
    @ObservationIgnored private let supertonicAudioPlayer = SupertonicAudioPlayer()

    override init() {
        supertonicAssetStore = SupertonicAssetStore()
        super.init()
        loadVoiceSelections()
        supertonicAssetState = supertonicAssetStore.state
        loadSupertonicSelections()
    }

    func toggle(_ highlight: Highlight) {
        if activeHighlightID == highlight.id {
            stop()
            return
        }

        let text = highlight.text.trimmed
        guard !text.isEmpty else { return }

        stop()

        if usesSupertonic(for: highlight.language) {
            activeHighlightID = highlight.id
            startSupertonicPlayback(
                text: text,
                language: highlight.language
            )
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        configure(utterance, for: highlight.language)

        currentUtterance = utterance
        activeHighlightID = highlight.id
        activeSynthesizer().speak(utterance)
    }

    func togglePreview(for language: CaptureLanguage) {
        if previewLanguage == language {
            stop()
            return
        }

        stop()

        if usesSupertonic(for: language) {
            previewLanguage = language
            startSupertonicPlayback(
                text: language.speechPreviewText,
                language: language
            )
            return
        }

        let utterance = AVSpeechUtterance(string: language.speechPreviewText)
        configure(utterance, for: language)

        currentUtterance = utterance
        previewLanguage = language
        activeSynthesizer().speak(utterance)
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
        var selectableVoices = highQualityVoices.isEmpty ? rankedVoices : highQualityVoices
        let savedIdentifier = selectedVoiceIdentifiers[language.rawValue]
            ?? defaults.string(forKey: voiceDefaultsKey(for: language))
        if
            let savedIdentifier,
            savedIdentifier != QuoteSpeechVoiceIdentifier.systemAutomatic,
            !selectableVoices.contains(where: { $0.identifier == savedIdentifier }),
            let savedVoice = rankedVoices.first(where: { $0.identifier == savedIdentifier })
        {
            selectableVoices.append(savedVoice)
        }

        let options = selectableVoices
            .map {
                QuoteSpeechVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: $0.quality
                )
            }

        return [automatic] + options
    }

    func selectedVoiceIdentifier(for language: CaptureLanguage) -> String {
        let savedIdentifier = selectedVoiceIdentifiers[language.rawValue]
        if let savedIdentifier,
           isVoiceAvailable(savedIdentifier, for: language) {
            return savedIdentifier
        }
        return QuoteSpeechVoiceIdentifier.systemAutomatic
    }

    func selectedVoiceName(for language: CaptureLanguage) -> String {
        if language == .korean, speechEngineChoice == .supertonic {
            if supertonicAssetState.isInstalled {
                return "고품질 온디바이스 · \(selectedSupertonicVoice.title)"
            }
            return "고품질 온디바이스 · 받기 필요"
        }
        let identifier = selectedVoiceIdentifier(for: language)
        return voiceOptions(for: language).first(where: { $0.id == identifier })?.name ?? "기본 음성"
    }

    func usesSupertonic(for language: CaptureLanguage) -> Bool {
        language == .korean
            && speechEngineChoice == .supertonic
            && supertonicAssetState.isInstalled
    }

    func setSpeechEngineChoice(_ choice: SpeechEngineChoice) {
        stop()
        speechEngineChoice = choice
        defaults.set(choice.rawValue, forKey: Self.supertonicEngineDefaultsKey)
    }

    func setSelectedSupertonicVoice(_ voice: SupertonicVoicePreset) {
        stop()
        selectedSupertonicVoice = voice
        defaults.set(voice.rawValue, forKey: Self.supertonicVoiceDefaultsKey)
    }

    func setSupertonicQuality(_ quality: SupertonicQuality) {
        stop()
        supertonicQuality = quality
        defaults.set(quality.rawValue, forKey: Self.supertonicQualityDefaultsKey)
    }

    func installSupertonicPack() async {
        speechErrorMessage = nil
        await supertonicAssetStore.install { [weak self] state in
            self?.supertonicAssetState = state
        }
        supertonicAssetState = supertonicAssetStore.state
        if supertonicAssetState.isInstalled {
            setSpeechEngineChoice(.supertonic)
        } else if case .failed(let message) = supertonicAssetState {
            speechErrorMessage = message
        }
    }

    func removeSupertonicPack() async {
        stop()
        await supertonicEngine.unload()
        do {
            try supertonicAssetStore.remove()
            supertonicAssetState = supertonicAssetStore.state
            setSpeechEngineChoice(.system)
        } catch {
            speechErrorMessage = error.localizedDescription
        }
    }

    func clearSpeechError() {
        speechErrorMessage = nil
    }

    func synthesizeSupertonic(
        text: String,
        speedMultiplier: Float
    ) async throws -> SupertonicAudio {
        guard let paths = supertonicAssetStore.modelPaths else {
            throw SupertonicError.packNotInstalled
        }
        let voice = selectedSupertonicVoice
        let quality = supertonicQuality
        return try await supertonicEngine.synthesize(
            text: text,
            voice: voice,
            quality: quality,
            speed: min(max(speedMultiplier, 0.8), 1.4),
            paths: paths
        )
    }

    func releaseSupertonicRuntime() {
        Task { [supertonicEngine] in
            await supertonicEngine.unload()
        }
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

    func invalidateVoiceCatalog() {
        cachedVoices = nil
    }

    func stop() {
        let wasUsingSupertonic = supertonicPlaybackToken != nil
        supertonicPlaybackTask?.cancel()
        supertonicPlaybackTask = nil
        supertonicPlaybackToken = nil
        supertonicAudioPlayer.stop()
        if let synthesizer,
           synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
        activeHighlightID = nil
        previewLanguage = nil
        if wasUsingSupertonic {
            releaseSupertonicRuntime()
        }
    }

    func isSpeaking(_ highlightID: Highlight.ID) -> Bool {
        activeHighlightID == highlightID
    }

    func configuredUtterance(
        for text: String,
        language: CaptureLanguage,
        rateMultiplier: Float = 1
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        configure(utterance, for: language)
        utterance.rate = min(
            max(utterance.rate * rateMultiplier, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        return utterance
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

    private func startSupertonicPlayback(
        text: String,
        language: CaptureLanguage
    ) {
        let token = UUID()
        supertonicPlaybackToken = token
        speechErrorMessage = nil
        supertonicPlaybackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await synthesizeSupertonic(text: text, speedMultiplier: 1)
                try Task.checkCancellation()
                guard supertonicPlaybackToken == token else { return }
                try supertonicAudioPlayer.play(audio) { [weak self] in
                    self?.finishSupertonicPlayback(token: token)
                }
            } catch is CancellationError {
                return
            } catch {
                guard supertonicPlaybackToken == token else { return }
                quoteSpeechLogger.error(
                    "supertonic_playback_failed language=\(language.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                speechErrorMessage = error.localizedDescription
                finishSupertonicPlayback(token: token)
            }
        }
    }

    private func finishSupertonicPlayback(token: UUID) {
        guard supertonicPlaybackToken == token else { return }
        supertonicPlaybackTask = nil
        supertonicPlaybackToken = nil
        activeHighlightID = nil
        previewLanguage = nil
        releaseSupertonicRuntime()
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

        return availableVoices().filter { voice in
            voice.language.caseInsensitiveCompare(localeIdentifier) == .orderedSame
                || voice.language.lowercased().hasPrefix("\(languageCode.lowercased())-")
        }
    }

    private func rankedVoices(for language: CaptureLanguage) -> [AVSpeechSynthesisVoice] {
        matchingVoices(for: language).sorted { lhs, rhs in
            let lhsIsNovelty = lhs.voiceTraits.contains(.isNoveltyVoice)
            let rhsIsNovelty = rhs.voiceTraits.contains(.isNoveltyVoice)
            if lhsIsNovelty != rhsIsNovelty {
                return !lhsIsNovelty
            }

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
            selectedVoiceIdentifiers[language.rawValue] =
                defaults.string(forKey: voiceDefaultsKey(for: language))
                ?? QuoteSpeechVoiceIdentifier.systemAutomatic
        }
    }

    private func loadSupertonicSelections() {
        if
            let rawEngine = defaults.string(forKey: Self.supertonicEngineDefaultsKey),
            let engine = SpeechEngineChoice(rawValue: rawEngine)
        {
            speechEngineChoice = engine
        }
        if
            let rawVoice = defaults.string(forKey: Self.supertonicVoiceDefaultsKey),
            let voice = SupertonicVoicePreset(rawValue: rawVoice)
        {
            selectedSupertonicVoice = voice
        }
        if
            defaults.object(forKey: Self.supertonicQualityDefaultsKey) != nil,
            let quality = SupertonicQuality(rawValue: defaults.integer(forKey: Self.supertonicQualityDefaultsKey))
        {
            supertonicQuality = quality
        }

        if speechEngineChoice == .supertonic, !supertonicAssetState.isInstalled {
            speechEngineChoice = .system
        }
    }

    private func activeSynthesizer() -> AVSpeechSynthesizer {
        if let synthesizer {
            return synthesizer
        }

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
        self.synthesizer = synthesizer
        return synthesizer
    }

    private func availableVoices() -> [AVSpeechSynthesisVoice] {
        if let cachedVoices {
            return cachedVoices
        }

        let voices = AVSpeechSynthesisVoice.speechVoices()
        cachedVoices = voices
        return voices
    }

    private func isVoiceAvailable(_ identifier: String, for language: CaptureLanguage) -> Bool {
        identifier == QuoteSpeechVoiceIdentifier.systemAutomatic
            || matchingVoices(for: language).contains(where: { $0.identifier == identifier })
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

    private static let supertonicEngineDefaultsKey = "overline.quoteSpeech.supertonic.engine"
    private static let supertonicVoiceDefaultsKey = "overline.quoteSpeech.supertonic.voice"
    private static let supertonicQualityDefaultsKey = "overline.quoteSpeech.supertonic.quality"
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
