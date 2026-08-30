import Foundation
import OnnxRuntimeBindings

struct GeneratedAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let duration: Double
}
actor SupertonicBenchmarkService {
    private var environment: ORTEnv?
    private var textToSpeech: TextToSpeech?
    private var styles: [SupertonicVoice: Style] = [:]

    func prepare() throws {
        guard textToSpeech == nil else { return }

        let onnxDirectory = try Self.resourceDirectory(named: "onnx")
        let environment = try ORTEnv(loggingLevel: .warning)
        let textToSpeech = try loadTextToSpeech(onnxDirectory.path, false, environment)
        var styles: [SupertonicVoice: Style] = [:]

        for voice in SupertonicVoice.allCases {
            let styleURL = try Self.resourceFile(
                named: voice.rawValue,
                extension: "json",
                subdirectory: "voice_styles"
            )
            styles[voice] = try loadVoiceStyle([styleURL.path], verbose: false)
        }

        self.environment = environment
        self.textToSpeech = textToSpeech
        self.styles = styles
    }

    func synthesize(
        text: String,
        voice: SupertonicVoice,
        steps: Int,
        speed: Float
    ) throws -> GeneratedAudio {
        if textToSpeech == nil {
            try prepare()
        }
        guard let textToSpeech, let style = styles[voice] else {
            throw BenchmarkError.modelUnavailable
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw BenchmarkError.emptyText
        }

        let result = try textToSpeech.call(
            normalizedText,
            "ko",
            style,
            steps,
            speed: speed,
            silenceDuration: 0.18
        )
        let requestedSampleCount = min(
            Int(Double(textToSpeech.sampleRate) * Double(result.duration)),
            result.wav.count
        )
        let samples = Array(result.wav.prefix(requestedSampleCount))
        return GeneratedAudio(
            samples: samples,
            sampleRate: Double(textToSpeech.sampleRate),
            duration: Double(samples.count) / Double(textToSpeech.sampleRate)
        )
    }

    private static func resourceDirectory(named name: String) throws -> URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        throw BenchmarkError.missingResource(name)
    }

    private static func resourceFile(
        named name: String,
        extension fileExtension: String,
        subdirectory: String
    ) throws -> URL {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) else {
            throw BenchmarkError.missingResource("\(subdirectory)/\(name).\(fileExtension)")
        }
        return url
    }
}

private enum BenchmarkError: LocalizedError {
    case emptyText
    case missingResource(String)
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "읽을 문장을 입력하세요."
        case .missingResource(let path):
            "모델 파일을 찾을 수 없습니다: \(path). prepare.sh를 먼저 실행하세요."
        case .modelUnavailable:
            "음성 모델을 준비하지 못했습니다."
        }
    }
}
