import AVFoundation

@MainActor
final class SupertonicAudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var completion: (() -> Void)?
    private var connectedSampleRate: Double?

    init() {
        engine.attach(playerNode)
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    func play(_ audio: SupertonicAudio, completion: @escaping () -> Void) throws {
        stop()

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

        if connectedSampleRate != audio.sampleRate {
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            connectedSampleRate = audio.sampleRate
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
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

    func resume() {
        guard !playerNode.isPlaying else { return }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        completion = nil
    }

    func tearDown() {
        stop()
        engine.stop()
    }

    private func finishScheduledPlayback() {
        let completion = completion
        self.completion = nil
        completion?()
    }
}

private final class SupertonicAudioPlayerWeakReference: @unchecked Sendable {
    weak var value: SupertonicAudioPlayer?

    init(_ value: SupertonicAudioPlayer) {
        self.value = value
    }
}
