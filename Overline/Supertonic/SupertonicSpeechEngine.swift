import Foundation
import OnnxRuntimeBindings

actor SupertonicSpeechEngine {
    private var environment: ORTEnv?
    private var textToSpeech: TextToSpeech?
    private var styles: [SupertonicVoicePreset: Style] = [:]
    private var preparedPaths: SupertonicModelPaths?

    func synthesize(
        text: String,
        voice: SupertonicVoicePreset,
        quality: SupertonicQuality,
        speed: Float,
        paths: SupertonicModelPaths
    ) throws -> SupertonicAudio {
        try Task.checkCancellation()
        try prepareIfNeeded(paths: paths)

        guard let textToSpeech else {
            throw SupertonicError.modelUnavailable
        }
        let style = try style(for: voice, paths: paths)
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else {
            throw SupertonicError.emptyText
        }

        let result = try textToSpeech.call(
            normalizedText,
            "ko",
            style,
            quality.rawValue,
            speed: speed,
            silenceDuration: 0.12
        )
        try Task.checkCancellation()

        let sampleCount = min(
            Int(Double(textToSpeech.sampleRate) * Double(result.duration)),
            result.wav.count
        )
        let samples = Array(result.wav.prefix(sampleCount))
        guard !samples.isEmpty else {
            throw SupertonicError.invalidAudio
        }
        return SupertonicAudio(
            samples: samples,
            sampleRate: Double(textToSpeech.sampleRate)
        )
    }

    func unload() {
        styles.removeAll()
        textToSpeech = nil
        environment = nil
        preparedPaths = nil
    }

    private func prepareIfNeeded(paths: SupertonicModelPaths) throws {
        if let preparedPaths,
           preparedPaths.onnxDirectory == paths.onnxDirectory,
           textToSpeech != nil {
            return
        }

        unload()
        let environment = try ORTEnv(loggingLevel: .warning)
        let textToSpeech = try loadTextToSpeech(paths.onnxDirectory.path, false, environment)
        self.environment = environment
        self.textToSpeech = textToSpeech
        preparedPaths = paths
    }

    private func style(
        for voice: SupertonicVoicePreset,
        paths: SupertonicModelPaths
    ) throws -> Style {
        if let style = styles[voice] {
            return style
        }

        let styleURL = paths.voiceStyleDirectory
            .appendingPathComponent(voice.rawValue)
            .appendingPathExtension("json")
        let style = try loadVoiceStyle([styleURL.path], verbose: false)
        styles[voice] = style
        return style
    }
}
