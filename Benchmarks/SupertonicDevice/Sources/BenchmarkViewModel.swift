import Foundation
import Observation
import OSLog

private let benchmarkLogger = Logger(subsystem: "aib.Overline.SupertonicBenchmark", category: "Performance")

enum SupertonicVoice: String, CaseIterable, Identifiable {
    case female1 = "F1"
    case female2 = "F2"
    case female3 = "F3"
    case female4 = "F4"
    case female5 = "F5"
    case male1 = "M1"
    case male2 = "M2"
    case male3 = "M3"
    case male4 = "M4"
    case male5 = "M5"

    var id: String { rawValue }

    var title: String {
        rawValue.hasPrefix("F")
            ? "여성 \(rawValue.dropFirst()) · \(rawValue)"
            : "남성 \(rawValue.dropFirst()) · \(rawValue)"
    }
}

struct BenchmarkMetrics {
    let voice: SupertonicVoice
    let steps: Int
    let speed: Double
    let prepareMilliseconds: Int?
    let synthesisMilliseconds: Int
    let audioDuration: Double
    let firstAudioRequestMilliseconds: Int
    let memoryBeforePrepare: UInt64
    let memoryAfterPrepare: UInt64
    let memoryAfterSynthesis: UInt64

    var rtf: Double {
        guard audioDuration > 0 else { return 0 }
        return Double(synthesisMilliseconds) / 1_000 / audioDuration
    }
}

@MainActor
@Observable
final class BenchmarkViewModel {
    var text = "여름의 향기를 느낀 건 오랜만의 일이었다. 바다 내음과 먼 기적 소리, 석양 무렵의 바람이 오래된 기억을 천천히 불러냈다. 그러나 모든 것은 예전과 조금씩 달라져 있었다."
    var voice: SupertonicVoice = .female1
    var steps = 8
    var speed = 1.0
    private(set) var isBusy = false
    private(set) var isPrepared = false
    private(set) var isPlaying = false
    private(set) var status: String?
    private(set) var metrics: BenchmarkMetrics?
    private(set) var errorMessage: String?

    @ObservationIgnored private let service = SupertonicBenchmarkService()
    @ObservationIgnored private let player = InMemoryAudioPlayer()
    @ObservationIgnored private var prepareMilliseconds: Int?
    @ObservationIgnored private var memoryBeforePrepare = MemoryUsage.residentBytes
    @ObservationIgnored private var memoryAfterPrepare = MemoryUsage.residentBytes

    func prepareModel() {
        guard !isBusy, !isPrepared else { return }
        isBusy = true
        status = "모델을 준비하고 있습니다."
        errorMessage = nil
        memoryBeforePrepare = MemoryUsage.residentBytes

        Task {
            do {
                let start = ContinuousClock.now
                try await service.prepare()
                let elapsed = Self.milliseconds(since: start)
                let preparedMemory = MemoryUsage.residentBytes

                prepareMilliseconds = elapsed
                memoryAfterPrepare = preparedMemory
                isPrepared = true
                isBusy = false
                status = "모델 준비가 끝났습니다."
                benchmarkLogger.info(
                    "supertonic_benchmark event=model_prepared duration_ms=\(elapsed, privacy: .public) memory_bytes=\(preparedMemory, privacy: .public)"
                )
            } catch {
                handle(error)
            }
        }
    }

    func generateAndPlay() {
        guard !isBusy else { return }
        isBusy = true
        status = isPrepared ? "음성을 만들고 있습니다." : "모델을 준비하고 음성을 만들고 있습니다."
        errorMessage = nil
        player.stop()
        isPlaying = false

        let requestStarted = ContinuousClock.now
        let selectedText = text
        let selectedVoice = voice
        let selectedSteps = steps
        let selectedSpeed = Float(speed)
        let initialMemory = MemoryUsage.residentBytes
        if !isPrepared {
            memoryBeforePrepare = initialMemory
        }

        Task {
            do {
                var loadDuration: Int?
                if !isPrepared {
                    let prepareStarted = ContinuousClock.now
                    try await service.prepare()
                    loadDuration = Self.milliseconds(since: prepareStarted)
                    prepareMilliseconds = loadDuration
                    memoryAfterPrepare = MemoryUsage.residentBytes
                    isPrepared = true
                }

                let synthesisStarted = ContinuousClock.now
                let audio = try await service.synthesize(
                    text: selectedText,
                    voice: selectedVoice,
                    steps: selectedSteps,
                    speed: selectedSpeed
                )
                let synthesisDuration = Self.milliseconds(since: synthesisStarted)
                let memoryAfterSynthesis = MemoryUsage.residentBytes

                try player.play(samples: audio.samples, sampleRate: audio.sampleRate) { [weak self] in
                    self?.isPlaying = false
                    self?.status = "재생이 끝났습니다."
                }
                let firstAudioRequest = Self.milliseconds(since: requestStarted)
                isPlaying = true
                isBusy = false
                status = "재생 중입니다."
                metrics = BenchmarkMetrics(
                    voice: selectedVoice,
                    steps: selectedSteps,
                    speed: Double(selectedSpeed),
                    prepareMilliseconds: loadDuration ?? prepareMilliseconds,
                    synthesisMilliseconds: synthesisDuration,
                    audioDuration: audio.duration,
                    firstAudioRequestMilliseconds: firstAudioRequest,
                    memoryBeforePrepare: memoryBeforePrepare,
                    memoryAfterPrepare: memoryAfterPrepare,
                    memoryAfterSynthesis: memoryAfterSynthesis
                )

                benchmarkLogger.info(
                    "supertonic_benchmark event=synthesis_completed prepare_ms=\((loadDuration ?? 0), privacy: .public) synthesis_ms=\(synthesisDuration, privacy: .public) first_audio_request_ms=\(firstAudioRequest, privacy: .public) audio_seconds=\(audio.duration, privacy: .public) rtf=\((Double(synthesisDuration) / 1000 / audio.duration), privacy: .public) memory_bytes=\(memoryAfterSynthesis, privacy: .public) steps=\(selectedSteps, privacy: .public) speed=\(selectedSpeed, privacy: .public) voice=\(selectedVoice.rawValue, privacy: .public)"
                )
            } catch {
                handle(error)
            }
        }
    }

    func stopPlayback() {
        player.stop()
        isPlaying = false
        status = "재생을 멈췄습니다."
    }

    private func handle(_ error: Error) {
        isBusy = false
        isPlaying = false
        status = nil
        errorMessage = error.localizedDescription
        benchmarkLogger.error(
            "supertonic_benchmark event=failed error=\(error.localizedDescription, privacy: .public)"
        )
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int((Double(duration.components.seconds) * 1_000)
            + (Double(duration.components.attoseconds) / 1_000_000_000_000_000))
    }
}

extension UInt64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }
}
