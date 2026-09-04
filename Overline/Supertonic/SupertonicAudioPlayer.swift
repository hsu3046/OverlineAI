import AVFoundation
import OSLog

private let supertonicAudioLogger = Logger(
    subsystem: "vote.aib.bzogak",
    category: "SupertonicAudio"
)

@MainActor
final class SupertonicAudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var completion: (() -> Void)?
    private var connectedSampleRate: Double?
    private var isAudioSessionActive = false

    init() {
        engine.attach(playerNode)
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    func prepareForPlayback() throws {
        try activatePlaybackSessionIfNeeded()
    }

    func play(_ audio: SupertonicAudio, completion: @escaping () -> Void) throws {
        cancelScheduledPlayback()

        guard
            !audio.samples.isEmpty,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: audio.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audio.samples.count)
            ),
            let channel = buffer.floatChannelData?[0]
        else {
            throw SupertonicError.invalidAudio
        }

        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        audio.samples.withUnsafeBufferPointer { source in
            guard let sourceAddress = source.baseAddress else { return }
            channel.update(from: sourceAddress, count: audio.samples.count)
        }

        do {
            try activatePlaybackSessionIfNeeded()
            if connectedSampleRate != audio.sampleRate {
                engine.disconnectNodeOutput(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                connectedSampleRate = audio.sampleRate
            }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            stop()
            throw error
        }

        self.completion = completion
        let callbackTarget = SupertonicAudioPlayerWeakReference(self)
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in
                callbackTarget.value?.finishScheduledPlayback()
            }
        }
        playerNode.play()
    }

    func pause() {
        guard playerNode.isPlaying else { return }
        playerNode.pause()
    }

    func markAudioSessionInterrupted() {
        isAudioSessionActive = false
    }

    func resume() throws {
        guard !playerNode.isPlaying else { return }
        try activatePlaybackSessionIfNeeded()
        if !engine.isRunning, connectedSampleRate != nil {
            engine.prepare()
            try engine.start()
        }
        playerNode.play()
    }

    func stop() {
        cancelScheduledPlayback()
        if engine.isRunning {
            engine.stop()
        }
        deactivateAudioSession()
    }

    func tearDown() {
        stop()
    }

    private func finishScheduledPlayback() {
        let completion = completion
        self.completion = nil
        completion?()
    }

    private func cancelScheduledPlayback() {
        playerNode.stop()
        completion = nil
    }

    private func activatePlaybackSessionIfNeeded() throws {
        let audioSession = AVAudioSession.sharedInstance()
        guard
            !isAudioSessionActive
                || audioSession.category != .playback
                || audioSession.mode != .default
                || !engine.isRunning
        else {
            return
        }

        logAudioSession(event: "activation_requested", session: audioSession)
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)
        isAudioSessionActive = true
        logAudioSession(event: "activated", session: audioSession)
    }

    private func deactivateAudioSession() {
        guard isAudioSessionActive else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = false
            logAudioSession(event: "deactivated", session: audioSession)
        } catch {
            supertonicAudioLogger.error(
                "supertonic_audio event=deactivation_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func logAudioSession(event: String, session: AVAudioSession) {
        let outputs = session.currentRoute.outputs
            .map(\.portType.rawValue)
            .joined(separator: ",")
        supertonicAudioLogger.info(
            "supertonic_audio event=\(event, privacy: .public) category=\(session.category.rawValue, privacy: .public) mode=\(session.mode.rawValue, privacy: .public) outputs=\(outputs, privacy: .public) engine_running=\(self.engine.isRunning, privacy: .public)"
        )
    }
}

private final class SupertonicAudioPlayerWeakReference: @unchecked Sendable {
    weak var value: SupertonicAudioPlayer?

    init(_ value: SupertonicAudioPlayer) {
        self.value = value
    }
}
