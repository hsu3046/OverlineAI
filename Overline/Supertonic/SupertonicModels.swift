import Foundation

enum SpeechEngineChoice: String, CaseIterable, Identifiable {
    case system
    case supertonic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: LocalizedStringResource("iPhone 음성", locale: AppLocale.uiLocale))
        case .supertonic: String(localized: LocalizedStringResource("고품질 온디바이스", locale: AppLocale.uiLocale))
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
        case .f1: String(localized: LocalizedStringResource("여성 1", locale: AppLocale.uiLocale))
        case .f2: String(localized: LocalizedStringResource("여성 2", locale: AppLocale.uiLocale))
        case .f3: String(localized: LocalizedStringResource("여성 3", locale: AppLocale.uiLocale))
        case .f4: String(localized: LocalizedStringResource("여성 4", locale: AppLocale.uiLocale))
        case .f5: String(localized: LocalizedStringResource("여성 5", locale: AppLocale.uiLocale))
        case .m1: String(localized: LocalizedStringResource("남성 1", locale: AppLocale.uiLocale))
        case .m2: String(localized: LocalizedStringResource("남성 2", locale: AppLocale.uiLocale))
        case .m3: String(localized: LocalizedStringResource("남성 3", locale: AppLocale.uiLocale))
        case .m4: String(localized: LocalizedStringResource("남성 4", locale: AppLocale.uiLocale))
        case .m5: String(localized: LocalizedStringResource("남성 5", locale: AppLocale.uiLocale))
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
        case .balanced: String(localized: LocalizedStringResource("균형", locale: AppLocale.uiLocale))
        case .high: String(localized: LocalizedStringResource("고음질", locale: AppLocale.uiLocale))
        }
    }

    var detail: String {
        switch self {
        case .balanced: String(localized: LocalizedStringResource("빠른 생성", locale: AppLocale.uiLocale))
        case .high: String(localized: LocalizedStringResource("더 정교한 음성", locale: AppLocale.uiLocale))
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
            String(localized: LocalizedStringResource("읽을 문장이 없습니다.", locale: AppLocale.uiLocale))
        case .packNotInstalled:
            String(localized: LocalizedStringResource("고품질 음성 팩을 먼저 받아주세요.", locale: AppLocale.uiLocale))
        case .invalidDownload(let filename):
            "\(filename) 파일을 확인하지 못했습니다. 다시 받아주세요."
        case .invalidAudio:
            String(localized: LocalizedStringResource("생성된 음성을 재생할 수 없습니다.", locale: AppLocale.uiLocale))
        case .modelUnavailable:
            String(localized: LocalizedStringResource("고품질 음성 모델을 준비하지 못했습니다.", locale: AppLocale.uiLocale))
        case .insufficientStorage:
            String(localized: LocalizedStringResource("고품질 음성 팩을 받으려면 iPhone 저장 공간을 조금 더 확보해주세요.", locale: AppLocale.uiLocale))
        }
    }
}

struct SupertonicModelPaths: Sendable {
    let onnxDirectory: URL
    let voiceStyleDirectory: URL
}
