import AVFoundation

@MainActor
final class InMemoryAudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var completion: (() -> Void)?

    init() {
        engine.attach(playerNode)
    }

    func play(
        samples: [Float],
        sampleRate: Double,
        completion: @escaping () -> Void
    ) throws {
        stop()

        guard !samples.isEmpty,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else {
            throw AudioPlayerError.invalidBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.completion = completion
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.completion?()
                self.completion = nil
            }
        }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        completion = nil
    }
}
private enum AudioPlayerError: LocalizedError {
    case invalidBuffer

    var errorDescription: String? {
        "생성된 음성을 재생 버퍼로 만들 수 없습니다."
    }
}
