import AVFoundation
import NaturalLanguage
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

struct QuoteSpeechPlaylistItem: Identifiable, Hashable {
    let id: Highlight.ID
    let text: String
    let language: CaptureLanguage
    let bookTitle: String?

    init(highlight: Highlight, bookTitle: String?) {
        id = highlight.id
        text = highlight.text
        language = highlight.language
        self.bookTitle = bookTitle
    }
}

@MainActor
@Observable
final class QuoteSpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var activeHighlightID: Highlight.ID?
    private(set) var playlist: [QuoteSpeechPlaylistItem] = []
    private(set) var playlistIndex = 0
    private(set) var isPaused = false
    private(set) var previewVoiceKey: String?
    private(set) var selectedVoiceIdentifiers: [String: String] = [:]
    private(set) var speechEngineChoice: SpeechEngineChoice = .system
    private(set) var selectedSupertonicVoice: SupertonicVoicePreset = .f1
    private(set) var supertonicQuality: SupertonicQuality = .balanced
    private(set) var supertonicAssetState: SupertonicAssetState = .unavailable
    private(set) var speechRateMultiplier = SpeechPlaybackPreferences.defaultRate
    private(set) var sentencePause = SpeechPlaybackPreferences.defaultSentencePause
    private(set) var playbackConfigurationRevision = 0
    private(set) var speechErrorMessage: String?
    private(set) var speechErrorHighlightID: Highlight.ID?

    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var cachedVoices: [AVSpeechSynthesisVoice]?
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var queuedSystemUtterances: [ObjectIdentifier: AVSpeechUtterance] = [:]
    @ObservationIgnored private var managesSystemAudioSession = false
    @ObservationIgnored private var activeUsesSupertonic = false
    @ObservationIgnored private var shouldResumeAfterInterruption = false
    @ObservationIgnored private var supertonicPlaybackTask: Task<Void, Never>?
    @ObservationIgnored private var supertonicSynthesisTasks: [Int: Task<SupertonicAudio, Error>] = [:]
    @ObservationIgnored private var supertonicPlaybackToken: UUID?
    @ObservationIgnored private var supertonicCues: [String] = []
    @ObservationIgnored private var supertonicCueIndex = 0
    @ObservationIgnored private var supertonicPlaybackLanguage: CaptureLanguage?
    @ObservationIgnored private var supertonicPlaybackVoice: SupertonicVoicePreset?
    @ObservationIgnored private var prefetchedPlaylistItemID: Highlight.ID?
    @ObservationIgnored private var prefetchedPlaylistSynthesisTask: Task<SupertonicAudio, Error>?
    @ObservationIgnored private var supertonicIdleReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var pageReadingRuntimeOwnerID: ObjectIdentifier?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let supertonicAssetStore: SupertonicAssetStore
    @ObservationIgnored private let supertonicEngine = SupertonicSpeechEngine()
    @ObservationIgnored private let supertonicAudioPlayer = SupertonicAudioPlayer()
    @ObservationIgnored private let remoteControls = QuoteSpeechRemoteControls()
    @ObservationIgnored private var audioInterruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var audioRouteChangeObserver: NSObjectProtocol?

    override init() {
        supertonicAssetStore = SupertonicAssetStore()
        super.init()
        loadVoiceSelections()
        loadPlaybackPreferences()
        supertonicAssetState = supertonicAssetStore.state
        loadSupertonicSelections()
        registerAudioNotifications()
    }

    deinit {
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
        }
        if let audioRouteChangeObserver {
            NotificationCenter.default.removeObserver(audioRouteChangeObserver)
        }
    }

    var currentPlaylistItem: QuoteSpeechPlaylistItem? {
        guard playlist.indices.contains(playlistIndex) else { return nil }
        return playlist[playlistIndex]
    }

    var isActive: Bool {
        activeHighlightID != nil
    }

    func toggle(_ highlight: Highlight, bookTitle: String? = nil) {
        if activeHighlightID == highlight.id {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }

        play([QuoteSpeechPlaylistItem(highlight: highlight, bookTitle: bookTitle)])
    }

    func play(_ items: [QuoteSpeechPlaylistItem]) {
        var seenIDs: Set<Highlight.ID> = []
        let playableItems = items.prefix(30).filter { item in
            let isNew = seenIDs.insert(item.id).inserted
            return isNew && !item.text.trimmed.isEmpty
        }
        guard !playableItems.isEmpty else { return }

        NotificationCenter.default.post(name: .overlineQuoteSpeechWillStart, object: nil)
        stopPlayback(releaseSupertonicRuntime: false)
        clearSpeechError()
        playlist = playableItems
        playlistIndex = 0
        isPaused = false
        activateRemoteControlsIfNeeded()
        startCurrentPlaylistItem()
    }

    func isPreviewing(_ option: QuoteSpeechVoiceOption, for language: CaptureLanguage) -> Bool {
        previewVoiceKey == systemPreviewKey(for: option.id, language: language)
    }

    func togglePreview(_ option: QuoteSpeechVoiceOption, for language: CaptureLanguage) {
        let previewKey = systemPreviewKey(for: option.id, language: language)
        if previewVoiceKey == previewKey {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }

        stopPlayback(releaseSupertonicRuntime: false)
        NotificationCenter.default.post(name: .overlineQuoteSpeechWillStart, object: nil)

        previewVoiceKey = previewKey
        speakSystemText(
            language.speechPreviewText,
            language: language,
            voiceIdentifier: option.id
        )
    }

    func isPreviewing(_ voice: SupertonicVoicePreset) -> Bool {
        previewVoiceKey == supertonicPreviewKey(for: voice)
    }

    func togglePreview(_ voice: SupertonicVoicePreset) {
        let previewKey = supertonicPreviewKey(for: voice)
        if previewVoiceKey == previewKey {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }

        stopPlayback(releaseSupertonicRuntime: false)
        NotificationCenter.default.post(name: .overlineQuoteSpeechWillStart, object: nil)
        previewVoiceKey = previewKey
        startSupertonicPlayback(
            text: CaptureLanguage.korean.speechPreviewText,
            language: .korean,
            voice: voice
        )
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
        guard speechEngineChoice != choice else { return }
        stop()
        speechEngineChoice = choice
        defaults.set(choice.rawValue, forKey: Self.supertonicEngineDefaultsKey)
        playbackConfigurationRevision += 1
    }

    func setSelectedSupertonicVoice(_ voice: SupertonicVoicePreset) {
        guard selectedSupertonicVoice != voice else { return }
        stop()
        selectedSupertonicVoice = voice
        defaults.set(voice.rawValue, forKey: Self.supertonicVoiceDefaultsKey)
        playbackConfigurationRevision += 1
    }

    func setSupertonicQuality(_ quality: SupertonicQuality) {
        guard supertonicQuality != quality else { return }
        stop()
        supertonicQuality = quality
        defaults.set(quality.rawValue, forKey: Self.supertonicQualityDefaultsKey)
        playbackConfigurationRevision += 1
    }

    func setSpeechRateMultiplier(_ multiplier: Double) {
        let normalized = SpeechPlaybackPreferences.normalizedRate(multiplier)
        guard abs(speechRateMultiplier - normalized) > 0.001 else { return }
        speechRateMultiplier = normalized
        defaults.set(normalized, forKey: SpeechPlaybackPreferences.rateDefaultsKey)
        playbackConfigurationRevision += 1
    }

    func setSentencePause(_ pause: Double) {
        let normalized = SpeechPlaybackPreferences.normalizedSentencePause(pause)
        guard abs(sentencePause - normalized) > 0.001 else { return }
        sentencePause = normalized
        defaults.set(normalized, forKey: SpeechPlaybackPreferences.sentencePauseDefaultsKey)
        playbackConfigurationRevision += 1
    }

    func installSupertonicPack() async {
        clearSpeechError()
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
        clearSpeechError()
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
        speechErrorHighlightID = nil
    }

    func synthesizeSupertonic(
        text: String,
        speedMultiplier: Float,
        sentencePause: Double? = nil,
        voice: SupertonicVoicePreset? = nil
    ) async throws -> SupertonicAudio {
        guard let paths = supertonicAssetStore.modelPaths else {
            throw SupertonicError.packNotInstalled
        }
        let voice = voice ?? selectedSupertonicVoice
        let quality = supertonicQuality
        let normalizedPause = SpeechPlaybackPreferences.normalizedSentencePause(
            sentencePause ?? self.sentencePause
        )
        let audio = try await supertonicEngine.synthesize(
            text: text,
            voice: voice,
            quality: quality,
            speed: min(max(speedMultiplier, 0.8), 1.6),
            silenceDuration: Float(normalizedPause),
            paths: paths
        )
        return audio.appendingSilence(duration: normalizedPause)
    }

    func releaseSupertonicRuntime() {
        pageReadingRuntimeOwnerID = nil
        cancelScheduledSupertonicRelease()
        Task { [supertonicEngine] in
            await supertonicEngine.unload()
        }
    }

    func claimSupertonicRuntime(for owner: AnyObject) {
        pageReadingRuntimeOwnerID = ObjectIdentifier(owner)
        cancelScheduledSupertonicRelease()
    }

    func releaseSupertonicRuntime(for owner: AnyObject) {
        guard pageReadingRuntimeOwnerID == ObjectIdentifier(owner) else { return }
        pageReadingRuntimeOwnerID = nil
        scheduleSupertonicRelease()
    }

    func setSelectedVoiceIdentifier(_ identifier: String, for language: CaptureLanguage) {
        guard voiceOptions(for: language).contains(where: { $0.id == identifier }) else { return }
        guard selectedVoiceIdentifier(for: language) != identifier else { return }

        stop()
        selectedVoiceIdentifiers[language.rawValue] = identifier
        defaults.set(identifier, forKey: voiceDefaultsKey(for: language))
        playbackConfigurationRevision += 1
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
        stopPlayback(releaseSupertonicRuntime: true)
    }

    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true

        if activeUsesSupertonic {
            supertonicAudioPlayer.pause()
        } else if let synthesizer, synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        updateRemotePlaybackState()
    }

    func resume() {
        guard isActive, isPaused else { return }

        do {
            if activeUsesSupertonic {
                if supertonicSynthesisTasks[supertonicCueIndex] != nil,
                   !supertonicAudioPlayer.isPlaying {
                    isPaused = false
                    updateRemotePlaybackState()
                    return
                }
                if supertonicAudioPlayer.isPlaying {
                    isPaused = false
                    updateRemotePlaybackState()
                    return
                }
                try supertonicAudioPlayer.resume()
            } else {
                try activateSystemSpeechAudioSession()
                _ = synthesizer?.continueSpeaking()
            }
            isPaused = false
            updateRemotePlaybackState()
        } catch {
            speechErrorHighlightID = activeHighlightID
            speechErrorMessage = error.localizedDescription
            stopPlayback(releaseSupertonicRuntime: false)
        }
    }

    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func skipForward() {
        guard playlist.indices.contains(playlistIndex + 1) else { return }
        let wasPaused = isPaused
        stopCurrentAudio()
        playlistIndex += 1
        isPaused = wasPaused
        startCurrentPlaylistItem()
    }

    func skipBackward() {
        guard playlistIndex > 0 else { return }
        let wasPaused = isPaused
        stopCurrentAudio()
        playlistIndex -= 1
        isPaused = wasPaused
        startCurrentPlaylistItem()
    }

    func removeHighlights(_ highlightIDs: Set<Highlight.ID>) {
        guard !highlightIDs.isEmpty, !playlist.isEmpty else { return }

        let previousActiveID = activeHighlightID
        let previousIndex = playlistIndex
        playlist.removeAll { highlightIDs.contains($0.id) }

        guard !playlist.isEmpty else {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }

        if let previousActiveID, highlightIDs.contains(previousActiveID) {
            let wasPaused = isPaused
            stopCurrentAudio()
            playlistIndex = min(previousIndex, playlist.count - 1)
            isPaused = wasPaused
            startCurrentPlaylistItem()
        } else if let previousActiveID,
                  let retainedIndex = playlist.firstIndex(where: { $0.id == previousActiveID }) {
            playlistIndex = retainedIndex
            updateRemotePlaybackState()
        }
    }

    private func registerAudioNotifications() {
        let callbackTarget = QuoteSpeechPlayerWeakReference(self)
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                callbackTarget.value?.handleAudioInterruption(
                    rawType: rawType,
                    rawOptions: rawOptions
                )
            }
        }
        audioRouteChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                callbackTarget.value?.handleAudioRouteChange(rawReason: rawReason)
            }
        }
    }

    private func handleAudioInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard
            isActive || previewVoiceKey != nil,
            let rawType,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            if previewVoiceKey != nil, !isActive {
                shouldResumeAfterInterruption = false
                supertonicAudioPlayer.markAudioSessionInterrupted()
                stopPlayback(releaseSupertonicRuntime: false)
                return
            }
            shouldResumeAfterInterruption = !isPaused
            supertonicAudioPlayer.markAudioSessionInterrupted()
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            let shouldResume = shouldResumeAfterInterruption && options.contains(.shouldResume)
            shouldResumeAfterInterruption = false
            if shouldResume {
                resume()
            }
        @unknown default:
            shouldResumeAfterInterruption = false
        }
    }

    private func handleAudioRouteChange(rawReason: UInt?) {
        guard
            isActive || previewVoiceKey != nil,
            let rawReason,
            AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
        else {
            return
        }
        if previewVoiceKey != nil, !isActive {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }
        pause()
    }

    private func stopPlayback(releaseSupertonicRuntime shouldReleaseRuntime: Bool) {
        let managesSupertonicRuntime = supertonicPlaybackToken != nil
            || !supertonicSynthesisTasks.isEmpty
            || prefetchedPlaylistSynthesisTask != nil
            || supertonicIdleReleaseTask != nil

        stopCurrentAudio()
        playlist.removeAll()
        playlistIndex = 0
        isPaused = false
        shouldResumeAfterInterruption = false
        activeHighlightID = nil
        previewVoiceKey = nil
        activeUsesSupertonic = false
        remoteControls.deactivate()

        guard managesSupertonicRuntime else { return }
        if shouldReleaseRuntime {
            releaseSupertonicRuntime()
        } else {
            scheduleSupertonicRelease()
        }
    }

    func isSpeaking(_ highlightID: Highlight.ID) -> Bool {
        activeHighlightID == highlightID
    }

    func configuredUtterance(
        for text: String,
        language: CaptureLanguage,
        rateMultiplier: Float? = nil,
        sentencePause: Double? = nil
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        configure(
            utterance,
            for: language,
            rateMultiplier: rateMultiplier,
            sentencePause: sentencePause
        )
        return utterance
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.markSystemUtteranceStarted(utteranceID)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishSystemUtterance(utteranceID)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishSystemUtterance(utteranceID)
        }
    }

    private func markSystemUtteranceStarted(_ utteranceID: ObjectIdentifier) {
        guard let utterance = queuedSystemUtterances[utteranceID] else { return }
        currentUtterance = utterance
        if isPaused {
            synthesizer?.pauseSpeaking(at: .immediate)
        }
    }

    private func finishSystemUtterance(_ utteranceID: ObjectIdentifier) {
        guard queuedSystemUtterances.removeValue(forKey: utteranceID) != nil else { return }
        if let currentUtterance,
           ObjectIdentifier(currentUtterance) == utteranceID {
            self.currentUtterance = nil
        }
        guard queuedSystemUtterances.isEmpty else { return }
        finishCurrentPlaybackUnit()
    }

    private func speakSystemText(
        _ text: String,
        language: CaptureLanguage,
        voiceIdentifier: String? = nil
    ) {
        let cues = makeSpeechCues(from: text, language: language)
        guard !cues.isEmpty else { return }

        do {
            try activateSystemSpeechAudioSession()
        } catch {
            speechErrorHighlightID = activeHighlightID
            speechErrorMessage = error.localizedDescription
            if isActive {
                stopPlayback(releaseSupertonicRuntime: false)
            } else {
                previewVoiceKey = nil
            }
            return
        }

        let utterances = cues.map { cue in
            let utterance = AVSpeechUtterance(string: cue)
            configure(
                utterance,
                for: language,
                voiceIdentifier: voiceIdentifier
            )
            return utterance
        }
        queuedSystemUtterances = Dictionary(
            uniqueKeysWithValues: utterances.map { (ObjectIdentifier($0), $0) }
        )
        currentUtterance = utterances.first

        let synthesizer = activeSynthesizer()
        for utterance in utterances {
            synthesizer.speak(utterance)
        }
    }

    private func startSupertonicPlayback(
        text: String,
        language: CaptureLanguage,
        voice: SupertonicVoicePreset? = nil,
        preparedFirstCueTask: Task<SupertonicAudio, Error>? = nil
    ) {
        let cues = makeSpeechCues(from: text, language: language)
        guard !cues.isEmpty else { return }

        cancelScheduledSupertonicRelease()
        let token = UUID()
        supertonicPlaybackToken = token
        supertonicCues = cues
        supertonicCueIndex = 0
        supertonicPlaybackLanguage = language
        supertonicPlaybackVoice = voice
        if let preparedFirstCueTask {
            supertonicSynthesisTasks[0] = preparedFirstCueTask
        }
        clearSpeechError()

        startSupertonicCue(at: 0, token: token)
    }

    private func startSupertonicCue(at cueIndex: Int, token: UUID) {
        guard
            supertonicPlaybackToken == token,
            supertonicCues.indices.contains(cueIndex),
            let language = supertonicPlaybackLanguage
        else {
            return
        }

        supertonicCueIndex = cueIndex
        let synthesisTask = supertonicSynthesisTasks[cueIndex]
            ?? makeSupertonicSynthesisTask(
                text: supertonicCues[cueIndex],
                voice: supertonicPlaybackVoice
            )
        supertonicSynthesisTasks[cueIndex] = synthesisTask
        supertonicPlaybackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await synthesisTask.value
                try Task.checkCancellation()
                guard supertonicPlaybackToken == token else { return }
                supertonicSynthesisTasks[cueIndex] = nil
                try supertonicAudioPlayer.play(audio) { [weak self] in
                    self?.finishSupertonicCue(at: cueIndex, token: token)
                }
                if isPaused {
                    supertonicAudioPlayer.pause()
                }
                prefetchNextSupertonicCue(after: cueIndex, token: token)
            } catch is CancellationError {
                return
            } catch {
                guard supertonicPlaybackToken == token else { return }
                quoteSpeechLogger.error(
                    "supertonic_playback_failed language=\(language.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                speechErrorHighlightID = activeHighlightID
                speechErrorMessage = error.localizedDescription
                stopPlayback(releaseSupertonicRuntime: false)
            }
        }
    }

    private func makeSupertonicSynthesisTask(
        text: String,
        voice: SupertonicVoicePreset?
    ) -> Task<SupertonicAudio, Error> {
        Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await synthesizeSupertonic(
                text: text,
                speedMultiplier: Float(speechRateMultiplier),
                sentencePause: sentencePause,
                voice: voice
            )
        }
    }

    private func prefetchNextSupertonicCue(after cueIndex: Int, token: UUID) {
        let nextCueIndex = cueIndex + 1
        guard supertonicPlaybackToken == token else {
            return
        }

        guard supertonicCues.indices.contains(nextCueIndex) else {
            prefetchNextPlaylistItem()
            return
        }
        guard supertonicSynthesisTasks[nextCueIndex] == nil else { return }

        supertonicSynthesisTasks[nextCueIndex] = makeSupertonicSynthesisTask(
            text: supertonicCues[nextCueIndex],
            voice: supertonicPlaybackVoice
        )
    }

    private func finishSupertonicCue(at cueIndex: Int, token: UUID) {
        guard
            supertonicPlaybackToken == token,
            supertonicCueIndex == cueIndex
        else {
            return
        }

        let nextCueIndex = cueIndex + 1
        if supertonicCues.indices.contains(nextCueIndex) {
            startSupertonicCue(at: nextCueIndex, token: token)
        } else {
            finishSupertonicPlayback(token: token)
        }
    }

    private func finishSupertonicPlayback(token: UUID) {
        guard supertonicPlaybackToken == token else { return }
        supertonicPlaybackTask = nil
        supertonicSynthesisTasks.values.forEach { $0.cancel() }
        supertonicSynthesisTasks.removeAll()
        supertonicPlaybackToken = nil
        supertonicCues.removeAll()
        supertonicCueIndex = 0
        supertonicPlaybackLanguage = nil
        supertonicPlaybackVoice = nil
        supertonicAudioPlayer.stop()
        scheduleSupertonicRelease()
        finishCurrentPlaybackUnit()
    }

    private func startCurrentPlaylistItem() {
        guard let item = currentPlaylistItem else {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }

        let text = item.text.trimmed
        guard !text.isEmpty else {
            advanceAfterCurrentItem()
            return
        }

        activeHighlightID = item.id
        previewVoiceKey = nil
        activeUsesSupertonic = usesSupertonic(for: item.language)
        updateRemotePlaybackState()

        if activeUsesSupertonic {
            deactivateSystemSpeechAudioSession()
            startSupertonicPlayback(
                text: text,
                language: item.language,
                preparedFirstCueTask: takePrefetchedPlaylistTask(for: item.id)
            )
        } else {
            speakSystemText(text, language: item.language)
            prefetchNextPlaylistItem()
        }
    }

    private func finishCurrentPlaybackUnit() {
        if !playlist.isEmpty, activeHighlightID != nil {
            advanceAfterCurrentItem()
            return
        }

        currentUtterance = nil
        previewVoiceKey = nil
        activeUsesSupertonic = false
        deactivateSystemSpeechAudioSession()
    }

    private func advanceAfterCurrentItem() {
        let nextIndex = playlistIndex + 1
        guard playlist.indices.contains(nextIndex) else {
            stopPlayback(releaseSupertonicRuntime: false)
            return
        }

        playlistIndex = nextIndex
        isPaused = false
        startCurrentPlaylistItem()
    }

    private func stopCurrentAudio() {
        cancelScheduledSupertonicRelease()
        supertonicPlaybackTask?.cancel()
        supertonicPlaybackTask = nil
        supertonicSynthesisTasks.values.forEach { $0.cancel() }
        supertonicSynthesisTasks.removeAll()
        supertonicPlaybackToken = nil
        supertonicCues.removeAll()
        supertonicCueIndex = 0
        supertonicPlaybackLanguage = nil
        supertonicPlaybackVoice = nil
        supertonicAudioPlayer.stop()
        prefetchedPlaylistSynthesisTask?.cancel()
        prefetchedPlaylistSynthesisTask = nil
        prefetchedPlaylistItemID = nil

        queuedSystemUtterances.removeAll()
        if let synthesizer,
           synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
        deactivateSystemSpeechAudioSession()
    }

    private func prefetchNextPlaylistItem() {
        guard prefetchedPlaylistSynthesisTask == nil else { return }
        let nextIndex = playlistIndex + 1
        guard
            playlist.indices.contains(nextIndex),
            usesSupertonic(for: playlist[nextIndex].language)
        else {
            return
        }

        let nextItem = playlist[nextIndex]
        guard let firstCue = makeSpeechCues(
            from: nextItem.text.trimmed,
            language: nextItem.language
        ).first else {
            return
        }

        prefetchedPlaylistItemID = nextItem.id
        prefetchedPlaylistSynthesisTask = makeSupertonicSynthesisTask(
            text: firstCue,
            voice: selectedSupertonicVoice
        )
    }

    private func takePrefetchedPlaylistTask(
        for itemID: Highlight.ID
    ) -> Task<SupertonicAudio, Error>? {
        guard prefetchedPlaylistItemID == itemID else {
            prefetchedPlaylistSynthesisTask?.cancel()
            prefetchedPlaylistSynthesisTask = nil
            prefetchedPlaylistItemID = nil
            return nil
        }

        let task = prefetchedPlaylistSynthesisTask
        prefetchedPlaylistSynthesisTask = nil
        prefetchedPlaylistItemID = nil
        return task
    }

    private func activateRemoteControlsIfNeeded() {
        remoteControls.activate(
            onPlay: { [weak self] in
                self?.resume()
            },
            onPause: { [weak self] in
                self?.pause()
            },
            onToggle: { [weak self] in
                self?.togglePause()
            },
            onNext: { [weak self] in
                self?.skipForward()
            },
            onPrevious: { [weak self] in
                self?.skipBackward()
            }
        )
    }

    private func updateRemotePlaybackState() {
        remoteControls.update(
            bookTitle: currentPlaylistItem?.bookTitle,
            itemIndex: playlistIndex,
            itemCount: playlist.count,
            isPlaying: isActive,
            isPaused: isPaused
        )
    }

    private func scheduleSupertonicRelease() {
        cancelScheduledSupertonicRelease()
        supertonicIdleReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await supertonicEngine.unload()
            guard !Task.isCancelled else { return }
            supertonicIdleReleaseTask = nil
        }
    }

    private func cancelScheduledSupertonicRelease() {
        supertonicIdleReleaseTask?.cancel()
        supertonicIdleReleaseTask = nil
    }

    private func makeSpeechCues(
        from text: String,
        language: CaptureLanguage
    ) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(naturalLanguage(for: language))

        let cues = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]).trimmed }
            .filter { !$0.isEmpty }
        return cues.isEmpty ? [text] : cues
    }

    private func naturalLanguage(for language: CaptureLanguage) -> NLLanguage {
        switch language {
        case .korean: .korean
        case .english: .english
        case .japanese: .japanese
        }
    }

    private func configure(
        _ utterance: AVSpeechUtterance,
        for language: CaptureLanguage,
        voiceIdentifier: String? = nil,
        rateMultiplier: Float? = nil,
        sentencePause: Double? = nil
    ) {
        if let voiceIdentifier {
            utterance.voice = voice(for: voiceIdentifier, language: language)
        } else {
            utterance.voice = selectedVoice(for: language)
        }
        let normalizedRate = Float(
            SpeechPlaybackPreferences.normalizedRate(
                Double(rateMultiplier ?? Float(speechRateMultiplier))
            )
        )
        utterance.rate = min(
            max(0.47 * normalizedRate, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.postUtteranceDelay = SpeechPlaybackPreferences.normalizedSentencePause(
            sentencePause ?? self.sentencePause
        )
    }

    private func selectedVoice(for language: CaptureLanguage) -> AVSpeechSynthesisVoice? {
        let identifier = selectedVoiceIdentifier(for: language)
        return voice(for: identifier, language: language)
    }

    private func voice(
        for identifier: String,
        language: CaptureLanguage
    ) -> AVSpeechSynthesisVoice? {
        if identifier != QuoteSpeechVoiceIdentifier.systemAutomatic {
            return AVSpeechSynthesisVoice(identifier: identifier)
        }
        return rankedVoices(for: language).first
    }

    private func systemPreviewKey(for identifier: String, language: CaptureLanguage) -> String {
        "system:\(language.rawValue):\(identifier)"
    }

    private func supertonicPreviewKey(for voice: SupertonicVoicePreset) -> String {
        "supertonic:\(voice.rawValue)"
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

    private func loadPlaybackPreferences() {
        let savedRate: Double
        if defaults.object(forKey: SpeechPlaybackPreferences.rateDefaultsKey) != nil {
            savedRate = defaults.double(forKey: SpeechPlaybackPreferences.rateDefaultsKey)
        } else if defaults.object(forKey: SpeechPlaybackPreferences.legacyPageReaderRateDefaultsKey) != nil {
            savedRate = defaults.double(
                forKey: SpeechPlaybackPreferences.legacyPageReaderRateDefaultsKey
            )
        } else {
            savedRate = SpeechPlaybackPreferences.defaultRate
        }
        speechRateMultiplier = SpeechPlaybackPreferences.normalizedRate(savedRate)
        defaults.set(speechRateMultiplier, forKey: SpeechPlaybackPreferences.rateDefaultsKey)

        let savedPause = defaults.object(
            forKey: SpeechPlaybackPreferences.sentencePauseDefaultsKey
        ) != nil
            ? defaults.double(forKey: SpeechPlaybackPreferences.sentencePauseDefaultsKey)
            : SpeechPlaybackPreferences.defaultSentencePause
        sentencePause = SpeechPlaybackPreferences.normalizedSentencePause(savedPause)
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
        synthesizer.usesApplicationAudioSession = true
        self.synthesizer = synthesizer
        return synthesizer
    }

    private func activateSystemSpeechAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        managesSystemAudioSession = true
    }

    private func deactivateSystemSpeechAudioSession() {
        guard managesSystemAudioSession else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            managesSystemAudioSession = false
        } catch {
            quoteSpeechLogger.error(
                "quote_speech_audio_deactivation_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
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

private final class QuoteSpeechPlayerWeakReference: @unchecked Sendable {
    weak var value: QuoteSpeechPlayer?

    init(_ value: QuoteSpeechPlayer) {
        self.value = value
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
