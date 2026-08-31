import AVFoundation
import NaturalLanguage
import Observation
import OSLog
import SwiftUI
import UIKit

private let pageReaderMetricsLogger = Logger(subsystem: "aib.Overline", category: "PageReaderMetrics")

enum CaptureExperienceMode: String, CaseIterable, Identifiable {
    case highlight
    case reader

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlight: "밑줄긋기"
        case .reader: "읽어주기"
        }
    }

    var systemImage: String {
        switch self {
        case .highlight: "highlighter"
        case .reader: "speaker.wave.2"
        }
    }
}

struct CaptureExperiencePicker: View {
    @Binding var selection: CaptureExperienceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureExperienceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.overline(.subheadline, weight: .semibold))
                        .foregroundStyle(selection == mode ? Color.overlineInk : Color.overlineMutedInk)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .contentShape(Rectangle())
                        .background {
                            if selection == mode {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("캡처 방식")
    }
}

nonisolated struct ReadingCue: Identifiable, Sendable {
    let id: Int
    let text: String
    let range: NSRange
}

nonisolated struct ReadingPage: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let language: CaptureLanguage
    let recognizedLineCount: Int
    let omittedLineCount: Int
    let cues: [ReadingCue]

    init(
        text: String,
        language: CaptureLanguage,
        recognizedLineCount: Int,
        omittedLineCount: Int
    ) {
        self.text = text
        self.language = language
        self.recognizedLineCount = recognizedLineCount
        self.omittedLineCount = omittedLineCount
        cues = ReadingCueTokenizer.cues(in: text, language: language)
    }
}

nonisolated private enum ReadingCueTokenizer {
    static func cues(in text: String, language: CaptureLanguage) -> [ReadingCue] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(naturalLanguage(for: language))

        let cues = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .compactMap { range -> ReadingCue? in
                let cueText = String(text[range]).trimmed
                guard !cueText.isEmpty else { return nil }
                let nsRange = NSRange(range, in: text)
                return ReadingCue(id: nsRange.location, text: cueText, range: nsRange)
            }

        guard cues.isEmpty else { return cues }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return [ReadingCue(id: 0, text: text, range: fullRange)]
    }

    private static func naturalLanguage(for language: CaptureLanguage) -> NLLanguage {
        switch language {
        case .korean: .korean
        case .english: .english
        case .japanese: .japanese
        }
    }
}

private struct SystemReadingUtteranceContext {
    let pageIndex: Int
    let cueIndex: Int
    let sourceLocation: Int
}

@MainActor
@Observable
final class PageReadingSession: NSObject, AVSpeechSynthesizerDelegate {
    static let maximumPageCount = 10

    private(set) var pages: [ReadingPage] = [] {
        didSet { updateRemotePlaybackState() }
    }
    private(set) var currentPageIndex = 0 {
        didSet { updateRemotePlaybackState() }
    }
    private(set) var isSpeaking = false {
        didSet { updateRemotePlaybackState() }
    }
    private(set) var isPaused = false {
        didSet { updateRemotePlaybackState() }
    }
    private(set) var isPreparingSpeech = false
    private(set) var isWaitingForNextPage = false
    private(set) var playbackErrorMessage: String?
    private(set) var activeCueIndex = 0
    private(set) var speechRateMultiplier: Float = 1
    private(set) var sentencePause = SpeechPlaybackPreferences.defaultSentencePause
    fileprivate private(set) var lyricsCues: [ReadingLyricsCue] = []

    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var systemUtteranceContexts: [ObjectIdentifier: SystemReadingUtteranceContext] = [:]
    @ObservationIgnored private var systemUtterances: [ObjectIdentifier: AVSpeechUtterance] = [:]
    @ObservationIgnored private var systemUtteranceOrder: [ObjectIdentifier] = []
    @ObservationIgnored private var refreshSystemQueueAfterCurrentSentence = false
    @ObservationIgnored private weak var voiceSettings: QuoteSpeechPlayer?
    @ObservationIgnored private var currentUtteranceSourceLocation = 0
    @ObservationIgnored private var pendingStartCueIndex: Int?
    @ObservationIgnored private let supertonicAudioPlayer = SupertonicAudioPlayer()
    @ObservationIgnored private var supertonicPlaybackTask: Task<Void, Never>?
    @ObservationIgnored private var supertonicSynthesisTasks: [ReadingLyricsCueID: Task<SupertonicAudio, Error>] = [:]
    @ObservationIgnored private var supertonicPlaybackToken: UUID?
    @ObservationIgnored private var pendingSupertonicAudio: (id: ReadingLyricsCueID, audio: SupertonicAudio)?
    @ObservationIgnored private var activePlaybackUsesSupertonic = false
    @ObservationIgnored private let remoteControls = PageReaderRemoteControls()
    @ObservationIgnored private var managesSystemAudioSession = false
    @ObservationIgnored private var shouldResumeAfterInterruption = false

    var currentPage: ReadingPage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var canAddPage: Bool {
        pages.count < Self.maximumPageCount
    }

    var canMoveForward: Bool {
        currentPageIndex + 1 < pages.count
    }

    func connectVoiceSettings(_ voiceSettings: QuoteSpeechPlayer) {
        self.voiceSettings = voiceSettings
    }

    @discardableResult
    func appendPage(_ page: ReadingPage) -> Bool {
        guard pages.count < Self.maximumPageCount else { return false }
        pages.append(page)
        lyricsCues.append(contentsOf: Self.makeLyricsCues(for: [page]))
        return true
    }

    func prepareForManualPlayback(
        atPageIndex requestedPageIndex: Int? = nil,
        cueIndex requestedCueIndex: Int? = nil,
        refreshAudio: Bool = false
    ) {
        guard !pages.isEmpty else { return }

        guard !isSpeaking else { return }

        let pageIndex = min(max(requestedPageIndex ?? currentPageIndex, 0), pages.count - 1)
        let page = pages[pageIndex]
        let cueIndex = min(
            max(requestedCueIndex ?? activeCueIndex, 0),
            max(page.cues.count - 1, 0)
        )
        currentPageIndex = pageIndex
        activeCueIndex = cueIndex
        pendingStartCueIndex = cueIndex
        isWaitingForNextPage = false
        playbackErrorMessage = nil

        guard
            let voiceSettings,
            voiceSettings.usesSupertonic(for: page.language),
            page.cues.indices.contains(cueIndex)
        else {
            cancelPreparedSupertonicAudio()
            return
        }

        let cue = page.cues[cueIndex]
        let id = ReadingLyricsCueID(pageID: page.id, cueID: cue.id)
        if refreshAudio {
            cancelPreparedSupertonicAudio()
        } else {
            let unrelatedIDs = supertonicSynthesisTasks.keys.filter { $0 != id }
            for unrelatedID in unrelatedIDs {
                supertonicSynthesisTasks[unrelatedID]?.cancel()
                supertonicSynthesisTasks[unrelatedID] = nil
            }
        }

        guard supertonicSynthesisTasks[id] == nil else { return }
        supertonicSynthesisTasks[id] = makeSupertonicSynthesisTask(
            text: cue.text,
            voiceSettings: voiceSettings
        )
    }

    func restorePages(
        _ pages: [ReadingPage],
        currentPageIndex: Int,
        activeCueIndex: Int
    ) {
        stopPlayback()
        self.pages = Array(pages.prefix(Self.maximumPageCount))
        lyricsCues = Self.makeLyricsCues(for: self.pages)
        self.currentPageIndex = min(max(currentPageIndex, 0), max(self.pages.count - 1, 0))
        let cueCount = currentPage?.cues.count ?? 0
        self.activeCueIndex = min(max(activeCueIndex, 0), max(cueCount - 1, 0))
        isWaitingForNextPage = false
        pendingStartCueIndex = self.activeCueIndex
    }

    func togglePlayback() {
        if isPaused {
            claimPlaybackOwnership()
            activateRemoteControlsIfNeeded()
            if activePlaybackUsesSupertonic {
                if let pendingSupertonicAudio {
                    self.pendingSupertonicAudio = nil
                    playSupertonicAudio(
                        pendingSupertonicAudio.audio,
                        id: pendingSupertonicAudio.id,
                        token: supertonicPlaybackToken
                    )
                } else {
                    do {
                        try supertonicAudioPlayer.resume()
                        isPaused = false
                        isSpeaking = true
                    } catch {
                        failPlaybackToStart()
                    }
                }
                return
            }
            do {
                try activateSystemSpeechAudioSession()
            } catch {
                failPlaybackToStart()
                return
            }
            if activeSynthesizer().continueSpeaking() {
                isPaused = false
                isSpeaking = true
            }
            return
        }

        if isSpeaking {
            if activePlaybackUsesSupertonic {
                supertonicAudioPlayer.pause()
                isPaused = true
                return
            }
            if activeSynthesizer().pauseSpeaking(at: .word) {
                isPaused = true
            }
            return
        }

        let startCueIndex = pendingStartCueIndex ?? 0
        pendingStartCueIndex = nil
        speakCurrentPage(startingAtCueIndex: startCueIndex)
    }

    func refreshAfterVoiceSettings(
        configurationChanged: Bool,
        wasActiveWhenOpened: Bool,
        wasPlayingWhenOpened: Bool
    ) {
        let isCurrentlyActive = isSpeaking || isPaused || isPreparingSpeech
        let wasInterruptedByPreview = wasActiveWhenOpened && !isCurrentlyActive
        guard configurationChanged || wasInterruptedByPreview else { return }

        let targetPageIndex = currentPageIndex
        let targetCueIndex = activeCueIndex
        if isCurrentlyActive {
            stopPlayback()
        }
        pendingStartCueIndex = targetCueIndex

        if wasPlayingWhenOpened {
            currentPageIndex = targetPageIndex
            speakCurrentPage(startingAtCueIndex: targetCueIndex)
        } else {
            prepareForManualPlayback(
                atPageIndex: targetPageIndex,
                cueIndex: targetCueIndex,
                refreshAudio: true
            )
        }
    }

    func stopForExternalPlayback() {
        guard isSpeaking || isPaused || isPreparingSpeech else {
            remoteControls.deactivate()
            return
        }
        pendingStartCueIndex = activeCueIndex
        stopPlayback()
        remoteControls.deactivate()
    }

    func pauseIfNeeded() {
        guard isSpeaking, !isPaused else { return }
        if activePlaybackUsesSupertonic {
            supertonicAudioPlayer.pause()
            isPaused = true
            return
        }
        if activeSynthesizer().pauseSpeaking(at: .word) {
            isPaused = true
        }
    }

    func resumeIfPaused() {
        guard isPaused else { return }
        if activePlaybackUsesSupertonic {
            if let pendingSupertonicAudio {
                self.pendingSupertonicAudio = nil
                playSupertonicAudio(
                    pendingSupertonicAudio.audio,
                    id: pendingSupertonicAudio.id,
                    token: supertonicPlaybackToken
                )
            } else {
                do {
                    try supertonicAudioPlayer.resume()
                    isPaused = false
                    isSpeaking = true
                } catch {
                    failPlaybackToStart()
                }
            }
            return
        }
        do {
            try activateSystemSpeechAudioSession()
        } catch {
            failPlaybackToStart()
            return
        }
        if activeSynthesizer().continueSpeaking() {
            isPaused = false
            isSpeaking = true
        }
    }

    func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            shouldResumeAfterInterruption = isSpeaking && !isPaused
            supertonicAudioPlayer.markAudioSessionInterrupted()
            pauseIfNeeded()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            let shouldResume = shouldResumeAfterInterruption && options.contains(.shouldResume)
            shouldResumeAfterInterruption = false
            if shouldResume {
                resumeIfPaused()
            }
        @unknown default:
            shouldResumeAfterInterruption = false
        }
    }

    func handleAudioRouteChange(_ notification: Notification) {
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
        else {
            return
        }
        pauseIfNeeded()
    }

    func trimPreparedAudioForMemoryPressure() {
        guard activePlaybackUsesSupertonic else { return }

        let activeID: ReadingLyricsCueID? = if
            pages.indices.contains(currentPageIndex),
            pages[currentPageIndex].cues.indices.contains(activeCueIndex)
        {
            ReadingLyricsCueID(
                pageID: pages[currentPageIndex].id,
                cueID: pages[currentPageIndex].cues[activeCueIndex].id
            )
        } else {
            nil
        }
        let disposableIDs = supertonicSynthesisTasks.keys.filter { $0 != activeID }
        for id in disposableIDs {
            supertonicSynthesisTasks[id]?.cancel()
            supertonicSynthesisTasks[id] = nil
        }
    }

    func updateSpeechRateMultiplier(_ multiplier: Float) {
        let normalizedMultiplier = Float(
            SpeechPlaybackPreferences.normalizedRate(Double(multiplier))
        )
        guard abs(speechRateMultiplier - normalizedMultiplier) > 0.001 else { return }

        speechRateMultiplier = normalizedMultiplier
        guard currentUtterance != nil || activePlaybackUsesSupertonic else { return }

        let cueIndex = activeCueIndex
        if activePlaybackUsesSupertonic {
            let wasPaused = isPaused
            stopPlayback()
            pendingStartCueIndex = cueIndex
            if !wasPaused {
                speakCurrentPage(startingAtCueIndex: cueIndex)
            }
            return
        }
        if isPaused {
            stopPlayback()
            pendingStartCueIndex = cueIndex
        } else {
            speakCurrentPage(startingAtCueIndex: cueIndex)
        }
    }

    func updateSentencePause(_ pause: Double) {
        let normalizedPause = SpeechPlaybackPreferences.normalizedSentencePause(pause)
        guard abs(sentencePause - normalizedPause) > 0.001 else { return }

        sentencePause = normalizedPause
        if activePlaybackUsesSupertonic {
            let currentID: ReadingLyricsCueID? = if
                pages.indices.contains(currentPageIndex),
                pages[currentPageIndex].cues.indices.contains(activeCueIndex)
            {
                ReadingLyricsCueID(
                    pageID: pages[currentPageIndex].id,
                    cueID: pages[currentPageIndex].cues[activeCueIndex].id
                )
            } else {
                nil
            }
            let prefetchedIDs = supertonicSynthesisTasks.keys.filter { $0 != currentID }
            for id in prefetchedIDs {
                supertonicSynthesisTasks[id]?.cancel()
                supertonicSynthesisTasks[id] = nil
            }
        } else if currentUtterance != nil {
            refreshSystemQueueAfterCurrentSentence = true
        }
    }

    func endSession() {
        let currentVoiceSettings = voiceSettings
        stopPlayback()
        pages.removeAll()
        lyricsCues.removeAll()
        currentPageIndex = 0
        activeCueIndex = 0
        isWaitingForNextPage = false
        pendingStartCueIndex = nil
        voiceSettings = nil
        remoteControls.deactivate()
        currentVoiceSettings?.releaseSupertonicRuntime()
    }

    private func claimPlaybackOwnership() {
        voiceSettings?.stop()
        NotificationCenter.default.post(
            name: .overlinePageReadingWillStart,
            object: self
        )
    }

    private func activateRemoteControlsIfNeeded() {
        remoteControls.activate(
            onPlay: { [weak self] in
                guard let self, !isSpeaking || isPaused else { return }
                togglePlayback()
            },
            onPause: { [weak self] in
                guard let self, isSpeaking, !isPaused else { return }
                pauseIfNeeded()
            },
            onToggle: { [weak self] in
                self?.togglePlayback()
            }
        )
        updateRemotePlaybackState()
    }

    private func updateRemotePlaybackState() {
        remoteControls.update(
            pageIndex: currentPageIndex,
            pageCount: pages.count,
            isPlaying: isSpeaking,
            isPaused: isPaused
        )
    }

    private static func makeLyricsCues(for pages: [ReadingPage]) -> [ReadingLyricsCue] {
        pages.flatMap { page in
            page.cues.map { cue in
                ReadingLyricsCue(
                    id: ReadingLyricsCueID(pageID: page.id, cueID: cue.id),
                    text: cue.text
                )
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.startIfQueued(utteranceID)
        }
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
            self?.cancelIfCurrent(utteranceID)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.updateActiveCue(for: characterRange, utteranceID: utteranceID)
        }
    }

    private func speakCurrentPage(startingAtCueIndex requestedCueIndex: Int = 0) {
        guard let page = currentPage, let voiceSettings else { return }

        let cueIndex = min(max(requestedCueIndex, 0), max(page.cues.count - 1, 0))
        let preparedSupertonicID: ReadingLyricsCueID? = if
            voiceSettings.usesSupertonic(for: page.language),
            page.cues.indices.contains(cueIndex)
        {
            ReadingLyricsCueID(pageID: page.id, cueID: page.cues[cueIndex].id)
        } else {
            nil
        }
        claimPlaybackOwnership()
        stopPlayback(preservingSupertonicSynthesisID: preparedSupertonicID)
        activateRemoteControlsIfNeeded()
        playbackErrorMessage = nil
        if voiceSettings.usesSupertonic(for: page.language) {
            startSupertonicCue(pageIndex: currentPageIndex, cueIndex: cueIndex)
            return
        }

        do {
            try activateSystemSpeechAudioSession()
        } catch {
            playbackErrorMessage = "오디오를 시작하지 못했습니다. 다시 시도해 주세요."
            return
        }
        let utterances = queuedSystemUtterances(
            startingAtPageIndex: currentPageIndex,
            cueIndex: cueIndex,
            voiceSettings: voiceSettings
        )
        guard !utterances.isEmpty else {
            deactivateSystemSpeechAudioSession()
            return
        }

        currentUtterance = utterances.first
        currentUtteranceSourceLocation = page.cues[cueIndex].range.location
        pendingStartCueIndex = nil
        activeCueIndex = cueIndex
        isSpeaking = true
        isPaused = false
        isWaitingForNextPage = false
        let synthesizer = activeSynthesizer()
        for utterance in utterances {
            synthesizer.speak(utterance)
        }
    }

    private func queuedSystemUtterances(
        startingAtPageIndex startPageIndex: Int,
        cueIndex startCueIndex: Int,
        voiceSettings: QuoteSpeechPlayer
    ) -> [AVSpeechUtterance] {
        guard pages.indices.contains(startPageIndex) else { return [] }
        var utterances: [AVSpeechUtterance] = []
        let page = pages[startPageIndex]
        guard page.cues.indices.contains(startCueIndex) else { return [] }

        for cueIndex in startCueIndex..<page.cues.count {
            let cue = page.cues[cueIndex]
            let utterance = voiceSettings.configuredUtterance(
                for: cue.text,
                language: page.language,
                rateMultiplier: speechRateMultiplier,
                sentencePause: sentencePause
            )
            let utteranceID = ObjectIdentifier(utterance)
            systemUtteranceContexts[utteranceID] = SystemReadingUtteranceContext(
                pageIndex: startPageIndex,
                cueIndex: cueIndex,
                sourceLocation: cue.range.location
            )
            systemUtterances[utteranceID] = utterance
            systemUtteranceOrder.append(utteranceID)
            utterances.append(utterance)
        }
        return utterances
    }

    private func stopPlayback(
        preservingSupertonicSynthesisID preservedID: ReadingLyricsCueID? = nil
    ) {
        supertonicPlaybackTask?.cancel()
        supertonicPlaybackTask = nil
        let preservedTask = preservedID.flatMap { supertonicSynthesisTasks[$0] }
        for (id, task) in supertonicSynthesisTasks where id != preservedID {
            task.cancel()
        }
        supertonicSynthesisTasks.removeAll()
        if let preservedID, let preservedTask {
            supertonicSynthesisTasks[preservedID] = preservedTask
        }
        supertonicPlaybackToken = nil
        pendingSupertonicAudio = nil
        supertonicAudioPlayer.stop()
        activePlaybackUsesSupertonic = false
        isPreparingSpeech = false
        currentUtterance = nil
        currentUtteranceSourceLocation = 0
        systemUtteranceContexts.removeAll()
        systemUtterances.removeAll()
        systemUtteranceOrder.removeAll()
        refreshSystemQueueAfterCurrentSentence = false
        if let synthesizer, synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateSystemSpeechAudioSession()
        isSpeaking = false
        isPaused = false
    }

    private func cancelPreparedSupertonicAudio() {
        supertonicSynthesisTasks.values.forEach { $0.cancel() }
        supertonicSynthesisTasks.removeAll()
    }

    private func failPlaybackToStart() {
        stopPlayback()
        playbackErrorMessage = "오디오를 시작하지 못했습니다. 다시 시도해 주세요."
    }

    private func startSupertonicCue(pageIndex: Int, cueIndex: Int) {
        guard
            pages.indices.contains(pageIndex),
            pages[pageIndex].cues.indices.contains(cueIndex),
            let voiceSettings
        else {
            return
        }

        let page = pages[pageIndex]
        let cue = page.cues[cueIndex]
        let id = ReadingLyricsCueID(pageID: page.id, cueID: cue.id)
        let token = UUID()

        do {
            try supertonicAudioPlayer.prepareForPlayback()
        } catch {
            playbackErrorMessage = "오디오를 시작하지 못했습니다. 다시 시도해 주세요."
            isSpeaking = false
            isPaused = false
            return
        }

        supertonicPlaybackTask?.cancel()
        supertonicPlaybackTask = nil
        currentPageIndex = pageIndex
        activeCueIndex = cueIndex
        activePlaybackUsesSupertonic = true
        supertonicPlaybackToken = token
        pendingStartCueIndex = nil
        pendingSupertonicAudio = nil
        playbackErrorMessage = nil
        isWaitingForNextPage = false
        isSpeaking = true
        isPaused = false
        isPreparingSpeech = true

        let synthesisTask = supertonicSynthesisTasks[id] ?? makeSupertonicSynthesisTask(
            text: cue.text,
            voiceSettings: voiceSettings
        )
        supertonicSynthesisTasks[id] = synthesisTask
        supertonicPlaybackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await synthesisTask.value
                try Task.checkCancellation()
                guard supertonicPlaybackToken == token else { return }
                supertonicSynthesisTasks[id] = nil
                isPreparingSpeech = false
                if isPaused {
                    pendingSupertonicAudio = (id, audio)
                } else {
                    playSupertonicAudio(audio, id: id, token: token)
                }
            } catch is CancellationError {
                return
            } catch {
                guard supertonicPlaybackToken == token else { return }
                supertonicSynthesisTasks[id] = nil
                supertonicAudioPlayer.stop()
                playbackErrorMessage = error.localizedDescription
                activePlaybackUsesSupertonic = false
                isPreparingSpeech = false
                isSpeaking = false
                isPaused = false
            }
        }
    }

    private func makeSupertonicSynthesisTask(
        text: String,
        voiceSettings: QuoteSpeechPlayer
    ) -> Task<SupertonicAudio, Error> {
        let speed = speechRateMultiplier
        return Task {
            try await voiceSettings.synthesizeSupertonic(
                text: text,
                speedMultiplier: speed,
                sentencePause: sentencePause
            )
        }
    }

    private func playSupertonicAudio(
        _ audio: SupertonicAudio,
        id: ReadingLyricsCueID,
        token: UUID?
    ) {
        guard let token, supertonicPlaybackToken == token else { return }
        do {
            try supertonicAudioPlayer.play(audio) { [weak self] in
                self?.finishSupertonicCue(id: id, token: token)
            }
            isSpeaking = true
            isPaused = false
            isPreparingSpeech = false
            prefetchNextSupertonicCue(afterPageIndex: currentPageIndex, cueIndex: activeCueIndex)
        } catch {
            playbackErrorMessage = error.localizedDescription
            activePlaybackUsesSupertonic = false
            isSpeaking = false
            isPaused = false
            isPreparingSpeech = false
        }
    }

    private func prefetchNextSupertonicCue(afterPageIndex pageIndex: Int, cueIndex: Int) {
        guard
            let next = nextCue(afterPageIndex: pageIndex, cueIndex: cueIndex),
            let voiceSettings,
            voiceSettings.usesSupertonic(for: next.page.language)
        else {
            return
        }

        let id = ReadingLyricsCueID(pageID: next.page.id, cueID: next.cue.id)
        guard supertonicSynthesisTasks[id] == nil else { return }
        supertonicSynthesisTasks[id] = makeSupertonicSynthesisTask(
            text: next.cue.text,
            voiceSettings: voiceSettings
        )
    }

    private func finishSupertonicCue(id: ReadingLyricsCueID, token: UUID) {
        guard supertonicPlaybackToken == token else { return }
        supertonicPlaybackTask = nil
        supertonicPlaybackToken = nil
        pendingSupertonicAudio = nil
        isSpeaking = false
        isPaused = false
        isPreparingSpeech = false

        if let next = nextCue(afterPageIndex: currentPageIndex, cueIndex: activeCueIndex) {
            if voiceSettings?.usesSupertonic(for: next.page.language) == true {
                startSupertonicCue(pageIndex: next.pageIndex, cueIndex: next.cueIndex)
            } else {
                currentPageIndex = next.pageIndex
                speakCurrentPage(startingAtCueIndex: next.cueIndex)
            }
        } else {
            supertonicAudioPlayer.stop()
            activePlaybackUsesSupertonic = false
            isWaitingForNextPage = true
        }
    }

    private func nextCue(
        afterPageIndex pageIndex: Int,
        cueIndex: Int
    ) -> (pageIndex: Int, cueIndex: Int, page: ReadingPage, cue: ReadingCue)? {
        guard pages.indices.contains(pageIndex) else { return nil }
        let page = pages[pageIndex]
        if page.cues.indices.contains(cueIndex + 1) {
            return (pageIndex, cueIndex + 1, page, page.cues[cueIndex + 1])
        }

        let nextPageIndex = pageIndex + 1
        guard
            pages.indices.contains(nextPageIndex),
            let firstCue = pages[nextPageIndex].cues.first
        else {
            return nil
        }
        return (nextPageIndex, 0, pages[nextPageIndex], firstCue)
    }

    private func startIfQueued(_ utteranceID: ObjectIdentifier) {
        guard
            let context = systemUtteranceContexts[utteranceID],
            let utterance = systemUtterances[utteranceID]
        else {
            return
        }
        currentUtterance = utterance
        currentPageIndex = context.pageIndex
        activeCueIndex = context.cueIndex
        currentUtteranceSourceLocation = context.sourceLocation
        isSpeaking = true
        isPaused = false
        isWaitingForNextPage = false
    }

    private func finishIfCurrent(_ utteranceID: ObjectIdentifier) {
        guard systemUtteranceContexts.removeValue(forKey: utteranceID) != nil else { return }
        systemUtterances.removeValue(forKey: utteranceID)
        systemUtteranceOrder.removeAll(where: { $0 == utteranceID })

        if let currentUtterance,
           ObjectIdentifier(currentUtterance) == utteranceID {
            self.currentUtterance = nil
            currentUtteranceSourceLocation = 0
        }

        if
            refreshSystemQueueAfterCurrentSentence,
            let nextUtteranceID = systemUtteranceOrder.first,
            let nextContext = systemUtteranceContexts[nextUtteranceID]
        {
            refreshSystemQueueAfterCurrentSentence = false
            currentPageIndex = nextContext.pageIndex
            speakCurrentPage(startingAtCueIndex: nextContext.cueIndex)
            return
        }

        guard systemUtteranceOrder.isEmpty else { return }
        refreshSystemQueueAfterCurrentSentence = false
        pendingStartCueIndex = nil
        isSpeaking = false
        isPaused = false
        if canMoveForward {
            currentPageIndex += 1
            speakCurrentPage()
        } else {
            deactivateSystemSpeechAudioSession()
            isWaitingForNextPage = true
        }
    }

    private func cancelIfCurrent(_ utteranceID: ObjectIdentifier) {
        guard systemUtteranceContexts.removeValue(forKey: utteranceID) != nil else { return }
        systemUtterances.removeValue(forKey: utteranceID)
        systemUtteranceOrder.removeAll(where: { $0 == utteranceID })
        if let currentUtterance,
           ObjectIdentifier(currentUtterance) == utteranceID {
            self.currentUtterance = nil
            currentUtteranceSourceLocation = 0
        }

        guard systemUtteranceOrder.isEmpty else { return }
        refreshSystemQueueAfterCurrentSentence = false
        pendingStartCueIndex = activeCueIndex
        deactivateSystemSpeechAudioSession()
        isSpeaking = false
        isPaused = false
    }

    private func updateActiveCue(
        for spokenRange: NSRange,
        utteranceID: ObjectIdentifier
    ) {
        guard
            let context = systemUtteranceContexts[utteranceID],
            pages.indices.contains(context.pageIndex)
        else {
            return
        }
        currentPageIndex = context.pageIndex
        activeCueIndex = context.cueIndex
        currentUtteranceSourceLocation = context.sourceLocation + spokenRange.location
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
            pageReaderMetricsLogger.error(
                "page_reader_system_audio_deactivation_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

struct PageReadingTextResult {
    let text: String
    let language: CaptureLanguage
    let recognizedLineCount: Int
    let omittedLineCount: Int
}

struct PageReadingTextProcessor {
    func process(_ recognition: CameraFrozenFrameRecognitionResult) throws -> PageReadingTextResult {
        let pageLines = linesInsideDetectedPage(recognition)
        let bodyLines = OCRPageMarginMetadataFilter.bodyLines(
            from: pageLines,
            pageBoundingBox: recognition.page?.boundingBox
        )
        let text = OCRTextAssembler(
            pageLines: bodyLines,
            selectedLines: bodyLines,
            boundaryTrimming: .none
        )
        .assembledText()
        .trimmed

        guard !text.isEmpty else {
            throw OCRTextRecognizerError.noTextFound
        }

        return PageReadingTextResult(
            text: text,
            language: CaptureLanguage.detect(from: text),
            recognizedLineCount: pageLines.count,
            omittedLineCount: pageLines.count - bodyLines.count
        )
    }

    private func linesInsideDetectedPage(
        _ recognition: CameraFrozenFrameRecognitionResult
    ) -> [CameraRecognizedTextLine] {
        guard
            let pageBox = recognition.page?.boundingBox,
            pageBox.width * pageBox.height >= 0.12
        else {
            return recognition.lines
        }

        let containedLines = recognition.lines.filter { line in
            pageBox.insetBy(dx: -0.025, dy: -0.025).contains(
                CGPoint(x: line.boundingBox.midX, y: line.boundingBox.midY)
            )
        }
        return containedLines.count >= max(3, recognition.lines.count / 2)
            ? containedLines
            : recognition.lines
    }

}

private enum PageReaderStage {
    case camera
    case lyrics
}

private struct ReadingLyricsCueID: Hashable {
    let pageID: ReadingPage.ID
    let cueID: ReadingCue.ID
}

private struct ReadingLyricsCue: Identifiable {
    let id: ReadingLyricsCueID
    let text: String
}

private struct PageReaderLyricsStage: View {
    let pages: [ReadingPage]
    let lyricsCues: [ReadingLyricsCue]
    let currentPageIndex: Int
    let activeCueIndex: Int
    let isContentReady: Bool
    @State private var scrollPosition: ReadingLyricsCue.ID?

    var body: some View {
        Group {
            if isContentReady {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            Color.clear
                                .frame(height: verticalScrollInset(for: geometry.size.height))
                                .accessibilityHidden(true)

                            ForEach(lyricsCues) { cue in
                                cueText(cue, isActive: cue.id == activeCueID)
                                    .id(cue.id)
                            }

                            Color.clear
                                .frame(height: verticalScrollInset(for: geometry.size.height))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 22)
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $scrollPosition, anchor: .center)
                    .onAppear {
                        scrollPosition = activeCueID
                    }
                    .onChange(of: activeCueID) { _, cueID in
                        withAnimation(.smooth(duration: 0.72, extraBounce: 0)) {
                            scrollPosition = cueID
                        }
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.overlineMutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.overlinePaper
                .overlay(Color.overlineMutedInk.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineMutedInk.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("본문 낭독")
    }

    private var activeCueID: ReadingLyricsCue.ID? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        let page = pages[currentPageIndex]
        let cueIndex = min(max(activeCueIndex, 0), max(page.cues.count - 1, 0))
        guard page.cues.indices.contains(cueIndex) else { return nil }
        return ReadingLyricsCueID(pageID: page.id, cueID: page.cues[cueIndex].id)
    }

    private func cueText(_ cue: ReadingLyricsCue, isActive: Bool) -> some View {
        Text(cue.text)
            .font(.overline(.title2, weight: .bold))
            .foregroundStyle(isActive ? Color.overlineInk : Color.overlineMutedInk)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isActive ? 1 : 0.30)
            .animation(.easeInOut(duration: 0.34), value: isActive)
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func verticalScrollInset(for height: CGFloat) -> CGFloat {
        max(height * 0.38, 96)
    }
}

struct PageReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer
    @Environment(LLMSettingsStore.self) private var llmSettings

    let cameraScanner: CameraTextScanner
    let requestedAt: TimeInterval?
    let onCloseToTab: (AppTab) -> Void

    @State private var readingSession = PageReadingSession()
    @State private var isAwaitingFrozenFrame = false
    @State private var isProcessingPage = false
    @State private var errorMessage: String?
    @State private var captureTimeoutTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var cameraPreparationTask: Task<Void, Never>?
    @State private var finishTransitionTask: Task<Void, Never>?
    @State private var initialDraftTask: Task<Void, Never>?
    @State private var resumeDraftTask: Task<Void, Never>?
    @State private var draftProgressSaveTask: Task<Void, Never>?
    @State private var showsExitConfirmation = false
    @State private var showsStoredDraftPrompt = false
    @State private var showsReplacementConfirmation = false
    @State private var showsSpeechSettings = false
    @State private var readerStage: PageReaderStage = .camera
    @State private var isCameraPreviewReady = false
    @State private var isLyricsContentReady = false
    @State private var pageCountBeforeCapture = 0
    @State private var wasWaitingForNextPageBeforeCapture = false
    @State private var storedDraft: PageReadingDraft?
    @State private var activeDraftID: PageReadingDraft.ID?
    @State private var pendingDestinationTab: AppTab?
    @State private var speechSettingsRevision = 0
    @State private var speechSettingsWasActive = false
    @State private var speechSettingsWasPlaying = false

    var body: some View {
        ZStack {
            OverlineCanvasBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header

                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                if let errorMessage = errorMessage ?? readingSession.playbackErrorMessage {
                    readerStatus(message: errorMessage, systemImage: "exclamationmark.triangle")
                } else if readerStage == .camera {
                    if readingSession.pages.isEmpty {
                        readerStatus(message: "촬영한 사진은 저장되지 않습니다", systemImage: "lock")
                    } else {
                        readerStatus(
                            message: "\(readingSession.pages.count)쪽 준비됨",
                            systemImage: "doc.on.doc"
                        )
                    }
                }

                if readerStage == .lyrics, !readingSession.pages.isEmpty {
                    readingControls
                }
            }
            .padding(16)
            .padding(.bottom, 4)
        }
        .interactiveDismissDisabled(!readingSession.pages.isEmpty)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OverlineBottomMenuBar(
                selectedTab: .capture,
                isCompact: false,
                selectTab: { tab in
                    requestClose(to: tab)
                }
            )
        }
        .confirmationDialog(
            "읽던 내용을 임시로 보관할까요?",
            isPresented: $showsExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("7일간 임시 보관", action: requestTemporarySave)
            Button("지금 지우기", role: .destructive, action: discardCurrentAndClose)
            Button("계속 읽기", role: .cancel) {
                pendingDestinationTab = nil
            }
        } message: {
            Text("임시 보관한 글은 7일간 저장됩니다.")
        }
        .confirmationDialog(
            "어떤 글을 임시로 보관할까요?",
            isPresented: $showsReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("새 글로 바꾸기", role: .destructive, action: saveTemporaryDraftAndClose)
            Button("이전 글 유지", action: closeReader)
            Button("계속 읽기", role: .cancel) {
                pendingDestinationTab = nil
            }
        } message: {
            Text("새 글을 보관하면 이전에 보관한 글은 지워집니다.")
        }
        .alert("임시 보관한 글이 있어요", isPresented: $showsStoredDraftPrompt) {
            Button("이어서 듣기", action: resumeStoredDraft)
            Button("새로 시작", action: beginNewReading)
        } message: {
            Text(storedDraftRemainingMessage)
        }
        .sheet(isPresented: $showsSpeechSettings, onDismiss: refreshPreparedSpeech) {
            OverlineSettingsSheet(
                settings: llmSettings,
                initialDestination: .textSpeech
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            let elapsedMilliseconds = requestElapsedMilliseconds
            pageReaderMetricsLogger.info(
                "page_reader_view_appeared elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
            )
            quoteSpeechPlayer.stop()
            cameraScanner.previewRouter.selectOwner("reader")
            readingSession.connectVoiceSettings(quoteSpeechPlayer)
            readingSession.updateSpeechRateMultiplier(
                Float(quoteSpeechPlayer.speechRateMultiplier)
            )
            readingSession.updateSentencePause(quoteSpeechPlayer.sentencePause)
            scheduleCameraPreparation()
            initialDraftTask?.cancel()
            initialDraftTask = Task { @MainActor in
                await prepareInitialReadingState()
            }
        }
        .onChange(of: quoteSpeechPlayer.speechRateMultiplier) { _, multiplier in
            readingSession.updateSpeechRateMultiplier(Float(multiplier))
        }
        .onChange(of: quoteSpeechPlayer.sentencePause) { _, pause in
            readingSession.updateSentencePause(pause)
        }
        .onDisappear {
            pageReaderMetricsLogger.info(
                "camera_handoff event=reader_disappeared scene=\(String(describing: scenePhase), privacy: .public) stage=\(String(describing: readerStage), privacy: .public)"
            )
            cancelPendingRecognition()
            cameraPreparationTask?.cancel()
            cameraPreparationTask = nil
            finishTransitionTask?.cancel()
            finishTransitionTask = nil
            initialDraftTask?.cancel()
            initialDraftTask = nil
            resumeDraftTask?.cancel()
            resumeDraftTask = nil
            readingSession.endSession()
            cameraScanner.stopSwipeRecognition(clearResults: true)
            cameraScanner.clearFrozenFrame()
        }
        .onChange(of: cameraScanner.frozenFrameImage != nil) { _, hasFrozenFrame in
            guard hasFrozenFrame, isAwaitingFrozenFrame else { return }
            captureTimeoutTask?.cancel()
            captureTimeoutTask = nil
            isAwaitingFrozenFrame = false
            recognitionTask?.cancel()
            recognitionTask = Task {
                await recognizeFrozenPage()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if readerStage == .camera {
                    scheduleCameraPreparation()
                }
            } else {
                updateStoredDraftProgress()
                cancelPendingRecognition()
                finishTransitionTask?.cancel()
                finishTransitionTask = nil
                if readerStage == .lyrics {
                    isLyricsContentReady = true
                }
                cameraPreparationTask?.cancel()
                cameraPreparationTask = nil
                isCameraPreviewReady = false
                cameraScanner.stop(clearRecognitionResults: false, owner: "reader.scene_inactive")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            readingSession.handleAudioSessionInterruption(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            readingSession.handleAudioRouteChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlineQuoteSpeechWillStart)) { _ in
            readingSession.stopForExternalPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlinePageReadingWillStart)) { notification in
            guard
                let owner = notification.object as? PageReadingSession,
                owner !== readingSession
            else {
                return
            }
            readingSession.stopForExternalPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            cancelPendingRecognition()
            resumeDraftTask?.cancel()
            resumeDraftTask = nil
            finishTransitionTask?.cancel()
            finishTransitionTask = nil
            cameraScanner.clearFrozenFrame()
            if readingSession.isSpeaking {
                readingSession.trimPreparedAudioForMemoryPressure()
                return
            }
            readingSession.endSession()
            resetCaptureContext()
            isLyricsContentReady = false
            readerStage = .camera
            activeDraftID = nil
            scheduleCameraPreparation()
            errorMessage = "메모리 보호를 위해 읽기 세션을 종료했습니다."
        }
    }

    private var header: some View {
        CaptureExperiencePicker(
            selection: Binding(
                get: { .reader },
                set: { mode in
                    if mode == .highlight {
                        requestClose()
                    }
                }
            )
        )
    }

    @ViewBuilder
    private var stageContent: some View {
        if readerStage == .lyrics {
            PageReaderLyricsStage(
                pages: readingSession.pages,
                lyricsCues: readingSession.lyricsCues,
                currentPageIndex: readingSession.currentPageIndex,
                activeCueIndex: readingSession.activeCueIndex,
                isContentReady: isLyricsContentReady
            )
        } else {
            cameraStage
        }
    }

    private var cameraStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)

            if isCameraPreviewReady, cameraScanner.canUseLiveCamera {
                CameraPreview(router: cameraScanner.previewRouter, owner: "reader")

                if let frozenFrameImage = cameraScanner.frozenFrameImage {
                    Image(uiImage: frozenFrameImage)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
            } else if isCameraPreviewReady {
                unavailableCameraView
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("카메라 준비 중")
            }

            if isCameraPreviewReady, cameraScanner.canToggleTorch {
                Button {
                    cameraScanner.toggleTorch()
                } label: {
                    Image(systemName: cameraScanner.isTorchOn ? "bolt.fill" : "bolt.slash")
                        .font(.overline(.headline))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.36), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityLabel(cameraScanner.isTorchOn ? "조명 끄기" : "조명 켜기")
            }

            captureControls
                .padding(.bottom, 18)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("페이지 촬영")
    }

    private var captureControls: some View {
        ZStack {
            captureButton

            HStack {
                Spacer()
                finishCaptureButton
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78)
    }

    private var captureButton: some View {
        Button(action: capturePage) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(canCapturePage ? 0.96 : 0.48))
                    .frame(width: 68, height: 68)
                Circle()
                    .stroke(Color.white.opacity(0.86), lineWidth: 3)
                    .frame(width: 78, height: 78)

                if isProcessingPage || isAwaitingFrozenFrame {
                    ProgressView()
                        .tint(Color.overlineAccent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapturePage)
        .accessibilityLabel("페이지 촬영")
    }

    private var finishCaptureButton: some View {
        Button(action: finishCapture) {
            Image(systemName: "checkmark")
                .font(.overline(.title3, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    canFinishCapture ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.36),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!canFinishCapture)
        .accessibilityLabel("촬영 완료")
    }

    private var unavailableCameraView: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.overline(.title))
            Text(cameraUnavailableMessage)
                .font(.overline(.subheadline))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(24)
    }

    private var readingControls: some View {
        ZStack {
            Button(action: readingSession.togglePlayback) {
                ZStack {
                    Circle()
                        .fill(Color.overlineAccent)
                        .frame(width: 58, height: 58)

                    if readingSession.isPreparingSpeech && !readingSession.isPaused {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: readingSession.isSpeaking && !readingSession.isPaused ? "pause.fill" : "play.fill")
                            .font(.overline(.title2, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(readingSession.isSpeaking && !readingSession.isPaused ? "일시정지" : "재생")

            HStack {
                Button(action: openCameraForNextPage) {
                    Image(systemName: "plus")
                        .font(.overline(.title3, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .disabled(!readingSession.canAddPage)
                .opacity(readingSession.canAddPage ? 1 : 0.30)
                .accessibilityLabel("페이지 추가")

                Spacer()

                Button {
                    openSpeechSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.overline(.title3, weight: .semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("텍스트 낭독 설정")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }

    private var canCapturePage: Bool {
        readerStage == .camera
            && isCameraPreviewReady
            && initialDraftTask == nil
            && !showsStoredDraftPrompt
            && cameraScanner.canUseLiveCamera
            && !isAwaitingFrozenFrame
            && !isProcessingPage
            && readingSession.canAddPage
    }

    private var canFinishCapture: Bool {
        readerStage == .camera
            && !readingSession.pages.isEmpty
            && !isAwaitingFrozenFrame
            && !isProcessingPage
    }

    private var cameraUnavailableMessage: String {
        switch cameraScanner.status {
        case .unavailable(let message): message
        case .requestingPermission: "카메라 권한 확인 중"
        case .idle, .running: "카메라를 준비하고 있습니다"
        }
    }

    private func readerStatus(message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.overline(.footnote, weight: .medium))
            .foregroundStyle(Color.overlineMutedInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func prepareCamera() {
        cameraScanner.stopSwipeRecognition(clearResults: true)
        cameraScanner.clearSelectedLineCache()
        cameraScanner.clearFrozenFrame()
        cameraScanner.start(owner: "reader.prepare")
    }

    private func scheduleCameraPreparation() {
        cameraPreparationTask?.cancel()
        cameraPreparationTask = nil
        isCameraPreviewReady = false

        cameraPreparationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard
                !Task.isCancelled,
                scenePhase == .active,
                readerStage == .camera
            else {
                return
            }

            prepareCamera()
            isCameraPreviewReady = true
            let elapsedMilliseconds = requestElapsedMilliseconds
            pageReaderMetricsLogger.info(
                "page_reader_camera_ready elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
            )
            cameraPreparationTask = nil
        }
    }

    private func openCameraForNextPage() {
        guard readingSession.canAddPage else {
            errorMessage = "한 번에 최대 \(PageReadingSession.maximumPageCount)쪽까지 준비할 수 있습니다."
            return
        }

        finishTransitionTask?.cancel()
        finishTransitionTask = nil
        errorMessage = nil
        pageCountBeforeCapture = readingSession.pages.count
        wasWaitingForNextPageBeforeCapture = readingSession.isWaitingForNextPage
        readingSession.pauseIfNeeded()
        isLyricsContentReady = false
        withAnimation(.easeInOut(duration: 0.22)) {
            readerStage = .camera
        }
        scheduleCameraPreparation()
    }

    private func finishCapture() {
        guard canFinishCapture else { return }

        finishTransitionTask?.cancel()
        let addedPages = readingSession.pages.count - pageCountBeforeCapture
        let previousPageCount = pageCountBeforeCapture
        let shouldPrepareAddedPages = wasWaitingForNextPageBeforeCapture && addedPages > 0

        isCameraPreviewReady = false
        isLyricsContentReady = false
        readerStage = .lyrics

        finishTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, readerStage == .lyrics else { return }

            isLyricsContentReady = true
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, readerStage == .lyrics else { return }

            if previousPageCount == 0 {
                readingSession.prepareForManualPlayback(atPageIndex: 0, cueIndex: 0)
            } else if shouldPrepareAddedPages {
                readingSession.prepareForManualPlayback(
                    atPageIndex: previousPageCount,
                    cueIndex: 0
                )
            } else {
                readingSession.prepareForManualPlayback()
            }

            await Task.yield()
            guard !Task.isCancelled else { return }
            cameraScanner.stop(clearRecognitionResults: false, owner: "reader.finish_capture")
            cameraScanner.clearFrozenFrame()
            finishTransitionTask = nil
        }

        resetCaptureContext()
    }

    private func capturePage() {
        guard canCapturePage else { return }

        errorMessage = nil
        isAwaitingFrozenFrame = true
        cameraScanner.stopSwipeRecognition(clearResults: true)
        cameraScanner.clearFrozenFrame()
        cameraScanner.start(owner: "reader.capture")
        cameraScanner.freezeNextFrame()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        captureTimeoutTask?.cancel()
        captureTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, isAwaitingFrozenFrame else { return }
            isAwaitingFrozenFrame = false
            cameraScanner.clearFrozenFrame()
            errorMessage = "페이지를 촬영하지 못했습니다. 다시 시도해 주세요."
        }
    }

    @MainActor
    private func recognizeFrozenPage() async {
        isProcessingPage = true
        defer {
            isProcessingPage = false
            recognitionTask = nil
            cameraScanner.clearFrozenFrame()
            if scenePhase == .active, readerStage == .camera {
                cameraScanner.start(owner: "reader.recognition_complete")
            }
        }

        do {
            let recognition = try await cameraScanner.recognizeFrozenPage()
            try Task.checkCancellation()
            let textResult = try PageReadingTextProcessor().process(recognition)
            try Task.checkCancellation()
            let page = ReadingPage(
                text: textResult.text,
                language: textResult.language,
                recognizedLineCount: textResult.recognizedLineCount,
                omittedLineCount: textResult.omittedLineCount
            )

            guard readingSession.appendPage(page) else {
                errorMessage = "한 번에 최대 \(PageReadingSession.maximumPageCount)쪽까지 준비할 수 있습니다."
                return
            }

            errorMessage = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch let error as OCRTextRecognizerError {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            errorMessage = "페이지의 글자를 읽지 못했습니다. 다시 촬영해 주세요."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func requestClose(to destinationTab: AppTab? = nil) {
        pendingDestinationTab = destinationTab
        if readingSession.pages.isEmpty {
            closeReader()
        } else if currentContentMatchesStoredDraft {
            saveStoredProgressAndClose()
        } else {
            showsExitConfirmation = true
        }
    }

    @MainActor
    private func prepareInitialReadingState() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let draft = await PageReadingDraftStore.shared.load()
        guard !Task.isCancelled else { return }

        let durationMilliseconds = elapsedMilliseconds(since: startedAt)
        pageReaderMetricsLogger.info(
            "page_reader_draft_loaded duration_ms=\(durationMilliseconds, privacy: .public) has_draft=\(draft != nil, privacy: .public)"
        )
        initialDraftTask = nil
        if let draft {
            storedDraft = draft
            showsStoredDraftPrompt = true
        }
    }

    private var storedDraftRemainingMessage: String {
        guard let storedDraft else { return "" }
        let remainingSeconds = max(storedDraft.expiresAt.timeIntervalSinceNow, 1)
        let remainingDays = max(1, Int(ceil(remainingSeconds / (24 * 60 * 60))))
        return "\(remainingDays)일 남았어요."
    }

    private func beginNewReading() {
        activeDraftID = nil
        isLyricsContentReady = false
        readerStage = .camera
        scheduleCameraPreparation()
    }

    private func resumeStoredDraft() {
        guard let draft = storedDraft else {
            beginNewReading()
            return
        }

        activeDraftID = draft.id
        isCameraPreviewReady = false
        isLyricsContentReady = false
        readerStage = .lyrics
        cameraPreparationTask?.cancel()
        cameraPreparationTask = nil
        cameraScanner.stop(clearRecognitionResults: false, owner: "reader.resume_draft")
        cameraScanner.clearFrozenFrame()

        resumeDraftTask?.cancel()
        resumeDraftTask = Task { @MainActor in
            defer { resumeDraftTask = nil }
            let startedAt = ProcessInfo.processInfo.systemUptime
            let tokenizationTask = Task.detached(priority: .userInitiated) { () -> [ReadingPage]? in
                var pages: [ReadingPage] = []
                pages.reserveCapacity(draft.pages.count)
                for page in draft.pages {
                    guard !Task.isCancelled else { return nil }
                    pages.append(ReadingPage(
                        text: page.text,
                        language: page.language,
                        recognizedLineCount: page.recognizedLineCount,
                        omittedLineCount: page.omittedLineCount
                    ))
                }
                return pages
            }
            let tokenizedPages = await withTaskCancellationHandler {
                await tokenizationTask.value
            } onCancel: {
                tokenizationTask.cancel()
            }
            guard
                let pages = tokenizedPages,
                !Task.isCancelled,
                readerStage == .lyrics
            else {
                return
            }

            let durationMilliseconds = elapsedMilliseconds(since: startedAt)
            let characterCount = draft.pages.reduce(0) { $0 + $1.text.count }
            pageReaderMetricsLogger.info(
                "page_reader_draft_tokenized duration_ms=\(durationMilliseconds, privacy: .public) page_count=\(pages.count, privacy: .public) character_count=\(characterCount, privacy: .public)"
            )

            guard !pages.isEmpty else {
                beginNewReading()
                return
            }

            guard !Task.isCancelled, readerStage == .lyrics else { return }
            readingSession.restorePages(
                pages,
                currentPageIndex: draft.currentPageIndex,
                activeCueIndex: draft.activeCueIndex
            )
            await Task.yield()
            guard !Task.isCancelled, readerStage == .lyrics else { return }

            isLyricsContentReady = true
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, readerStage == .lyrics else { return }

            readingSession.prepareForManualPlayback(
                atPageIndex: draft.currentPageIndex,
                cueIndex: draft.activeCueIndex
            )
        }
    }

    private func refreshPreparedSpeech() {
        readingSession.updateSpeechRateMultiplier(
            Float(quoteSpeechPlayer.speechRateMultiplier)
        )
        readingSession.updateSentencePause(quoteSpeechPlayer.sentencePause)
        readingSession.refreshAfterVoiceSettings(
            configurationChanged: speechSettingsRevision
                != quoteSpeechPlayer.playbackConfigurationRevision,
            wasActiveWhenOpened: speechSettingsWasActive,
            wasPlayingWhenOpened: speechSettingsWasPlaying
        )
        speechSettingsWasActive = false
        speechSettingsWasPlaying = false
    }

    private func openSpeechSettings() {
        speechSettingsRevision = quoteSpeechPlayer.playbackConfigurationRevision
        speechSettingsWasActive = readingSession.isSpeaking
            || readingSession.isPaused
            || readingSession.isPreparingSpeech
        speechSettingsWasPlaying = readingSession.isSpeaking && !readingSession.isPaused
        showsSpeechSettings = true
    }

    private func requestTemporarySave() {
        if let storedDraft, activeDraftID != storedDraft.id {
            Task { @MainActor in
                await Task.yield()
                showsReplacementConfirmation = true
            }
        } else {
            saveTemporaryDraftAndClose()
        }
    }

    private func saveTemporaryDraftAndClose() {
        guard let draft = makeTemporaryDraft() else {
            errorMessage = "임시 보관할 글이 없습니다."
            return
        }

        let pendingProgressSave = draftProgressSaveTask
        draftProgressSaveTask = nil
        Task { @MainActor in
            do {
                await pendingProgressSave?.value
                try await PageReadingDraftStore.shared.save(draft)
                storedDraft = draft
                activeDraftID = draft.id
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                closeReader()
            } catch {
                errorMessage = "글을 임시 보관하지 못했습니다. 다시 시도해 주세요."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private var currentContentMatchesStoredDraft: Bool {
        guard let storedDraft, activeDraftID == storedDraft.id else { return false }
        return storedDraft.expiresAt > .now && storedDraft.pages == currentDraftPages
    }

    private func saveStoredProgressAndClose() {
        guard let storedDraft, activeDraftID == storedDraft.id else {
            showsExitConfirmation = true
            return
        }

        let updatedDraft = PageReadingDraft(
            id: storedDraft.id,
            createdAt: storedDraft.createdAt,
            expiresAt: storedDraft.expiresAt,
            currentPageIndex: readingSession.currentPageIndex,
            activeCueIndex: readingSession.activeCueIndex,
            pages: currentDraftPages
        )
        guard
            updatedDraft.currentPageIndex != storedDraft.currentPageIndex
                || updatedDraft.activeCueIndex != storedDraft.activeCueIndex
        else {
            closeReader()
            return
        }

        let pendingProgressSave = draftProgressSaveTask
        draftProgressSaveTask = nil
        Task { @MainActor in
            do {
                await pendingProgressSave?.value
                try await PageReadingDraftStore.shared.save(updatedDraft)
                self.storedDraft = updatedDraft
                closeReader()
            } catch {
                errorMessage = "읽던 위치를 저장하지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    private var currentDraftPages: [PageReadingDraftPage] {
        readingSession.pages.map { page in
            PageReadingDraftPage(
                text: page.text,
                language: page.language,
                recognizedLineCount: page.recognizedLineCount,
                omittedLineCount: page.omittedLineCount
            )
        }
    }

    private func makeTemporaryDraft(now: Date = .now) -> PageReadingDraft? {
        guard !readingSession.pages.isEmpty else { return nil }
        return PageReadingDraft(
            id: activeDraftID ?? UUID(),
            createdAt: now,
            expiresAt: now.addingTimeInterval(PageReadingDraftStore.retentionInterval),
            currentPageIndex: readingSession.currentPageIndex,
            activeCueIndex: readingSession.activeCueIndex,
            pages: currentDraftPages
        )
    }

    private func updateStoredDraftProgress() {
        guard
            let storedDraft,
            activeDraftID == storedDraft.id,
            currentContentMatchesStoredDraft,
            !readingSession.pages.isEmpty
        else {
            return
        }

        let updatedDraft = PageReadingDraft(
            id: storedDraft.id,
            createdAt: storedDraft.createdAt,
            expiresAt: storedDraft.expiresAt,
            currentPageIndex: readingSession.currentPageIndex,
            activeCueIndex: readingSession.activeCueIndex,
            pages: currentDraftPages
        )
        let previousSave = draftProgressSaveTask
        draftProgressSaveTask = Task { @MainActor in
            await previousSave?.value
            do {
                try await PageReadingDraftStore.shared.save(updatedDraft)
                guard
                    activeDraftID == updatedDraft.id,
                    self.storedDraft?.id == updatedDraft.id,
                    currentDraftPages == updatedDraft.pages
                else { return }
                self.storedDraft = updatedDraft
            } catch {
                // Closing the reader retries this write and reports any failure to the user.
            }
        }
    }

    private func discardCurrentAndClose() {
        guard activeDraftID == storedDraft?.id else {
            closeReader()
            return
        }

        let pendingProgressSave = draftProgressSaveTask
        draftProgressSaveTask = nil
        Task { @MainActor in
            do {
                await pendingProgressSave?.value
                try await PageReadingDraftStore.shared.delete()
                storedDraft = nil
                activeDraftID = nil
                closeReader()
            } catch {
                errorMessage = "임시 보관한 글을 지우지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    private func closeReader() {
        let destinationTab = pendingDestinationTab
        pendingDestinationTab = nil
        cancelPendingRecognition()
        initialDraftTask?.cancel()
        initialDraftTask = nil
        resumeDraftTask?.cancel()
        resumeDraftTask = nil
        finishTransitionTask?.cancel()
        finishTransitionTask = nil
        cameraPreparationTask?.cancel()
        cameraPreparationTask = nil
        readingSession.endSession()
        cameraScanner.clearFrozenFrame()
        resetCaptureContext()
        if let destinationTab {
            onCloseToTab(destinationTab)
        }
        dismiss()
    }

    private var requestElapsedMilliseconds: Int {
        guard let requestedAt else { return 0 }
        return elapsedMilliseconds(since: requestedAt)
    }

    private func elapsedMilliseconds(since start: TimeInterval) -> Int {
        Int(max(0, (ProcessInfo.processInfo.systemUptime - start) * 1_000).rounded())
    }

    private func resetCaptureContext() {
        pageCountBeforeCapture = 0
        wasWaitingForNextPageBeforeCapture = false
    }

    private func cancelPendingRecognition() {
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isAwaitingFrozenFrame = false
        cameraScanner.clearFrozenFrame()
    }
}
