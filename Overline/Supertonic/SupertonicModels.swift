import Foundation

enum SpeechEngineChoice: String, CaseIterable, Identifiable {
    case system
    case supertonic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "iPhone 음성"
        case .supertonic: "고품질 온디바이스"
        }
    }
}

enum SupertonicVoicePreset: String, CaseIterable, Identifiable, Sendable {
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case m5 = "M5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .f1: "여성 1"
        case .f2: "여성 2"
        case .f3: "여성 3"
        case .f4: "여성 4"
        case .f5: "여성 5"
        case .m1: "남성 1"
        case .m2: "남성 2"
        case .m3: "남성 3"
        case .m4: "남성 4"
        case .m5: "남성 5"
        }
    }

    var pickerTitle: String {
        "\(title) · \(rawValue)"
    }
}

enum SupertonicQuality: Int, CaseIterable, Identifiable, Sendable {
    case balanced = 8
    case high = 12

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .balanced: "균형"
        case .high: "고음질"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "빠른 생성"
        case .high: "더 정교한 음성"
        }
    }
}

enum SupertonicAssetState: Equatable {
    case unavailable
    case downloading(progress: Double)
    case installed
    case failed(message: String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

struct SupertonicAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }

    func appendingSilence(duration: TimeInterval) -> SupertonicAudio {
        guard duration > 0, sampleRate > 0 else { return self }
        let silenceSampleCount = Int((duration * sampleRate).rounded())
        guard silenceSampleCount > 0 else { return self }

        var samplesWithSilence = samples
        samplesWithSilence.append(contentsOf: repeatElement(0, count: silenceSampleCount))
        return SupertonicAudio(samples: samplesWithSilence, sampleRate: sampleRate)
    }
}

enum SupertonicError: LocalizedError {
    case emptyText
    case packNotInstalled
    case invalidDownload(String)
    case invalidAudio
    case modelUnavailable
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "읽을 문장이 없습니다."
        case .packNotInstalled:
            "고품질 음성 팩을 먼저 받아주세요."
        case .invalidDownload(let filename):
            "\(filename) 파일을 확인하지 못했습니다. 다시 받아주세요."
        case .invalidAudio:
            "생성된 음성을 재생할 수 없습니다."
        case .modelUnavailable:
            "고품질 음성 모델을 준비하지 못했습니다."
        case .insufficientStorage:
            "고품질 음성 팩을 받으려면 iPhone 저장 공간을 조금 더 확보해주세요."
        }
    }
}

struct SupertonicModelPaths: Sendable {
    let onnxDirectory: URL
    let voiceStyleDirectory: URL
}
