import AVFoundation
import Observation
import Speech

enum SpeechMemoState: Equatable {
    case idle
    case requestingPermission
    case recording
    case failed(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
}

@MainActor
@Observable
final class SpeechMemoRecorder {
    var state: SpeechMemoState = .idle
    var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var errorMessage: String? {
        if case .failed(let message) = state {
            return message
        }
        return nil
    }

    var isRecording: Bool {
        state.isRecording
    }

    func startRecording() async {
        guard !isRecording else { return }

        state = .requestingPermission
        transcript = ""

        guard await requestSpeechAuthorization() else {
            state = .failed("음성 인식 권한이 필요합니다.")
            return
        }

        guard await requestMicrophoneAuthorization() else {
            state = .failed("마이크 권한이 필요합니다.")
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            state = .failed("지금은 음성 인식을 사용할 수 없습니다.")
            return
        }

        guard recognizer.supportsOnDeviceRecognition else {
            state = .failed("이 기기에서는 온디바이스 음성 인식을 사용할 수 없습니다.")
            return
        }

        do {
            try startAudioRecognition(with: recognizer)
            state = .recording
        } catch {
            stopRecording()
            state = .failed("음성 메모를 시작할 수 없습니다.")
        }
    }

    func stopRecording() {
        guard audioEngine.isRunning || recognitionTask != nil else {
            state = .idle
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if state.isRecording || state == .requestingPermission {
            state = .idle
        }
    }

    func cancel() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
    }

    private func startAudioRecognition(with recognizer: SFSpeechRecognizer) throws {
        cancel()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            transcript = result.bestTranscription.formattedString

            if result.isFinal {
                stopRecording()
            }
        }

        if let error, isRecording {
            stopRecording()
            state = .failed(error.localizedDescription)
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}
