import AVFoundation
import Observation
import SwiftUI
import UIKit

enum CaptureExperienceMode: String, CaseIterable, Identifiable {
    case highlight
    case reader

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlight: "글조각"
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
                        .font(.subheadline.weight(.semibold))
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

struct ReadingPage: Identifiable {
    let id = UUID()
    let text: String
    let language: CaptureLanguage
    let recognizedLineCount: Int
    let omittedLineCount: Int
}

@MainActor
@Observable
final class PageReadingSession: NSObject, AVSpeechSynthesizerDelegate {
    static let maximumPageCount = 10

    private(set) var pages: [ReadingPage] = []
    private(set) var currentPageIndex = 0
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var isWaitingForNextPage = false

    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private weak var voiceSettings: QuoteSpeechPlayer?

    var currentPage: ReadingPage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var canAddPage: Bool {
        pages.count < Self.maximumPageCount || currentPageIndex > 0
    }

    var canMoveBackward: Bool {
        currentPageIndex > 0
    }

    var canMoveForward: Bool {
        currentPageIndex + 1 < pages.count
    }

    func connectVoiceSettings(_ voiceSettings: QuoteSpeechPlayer) {
        self.voiceSettings = voiceSettings
    }

    @discardableResult
    func addPage(_ page: ReadingPage) -> Bool {
        if pages.count >= Self.maximumPageCount, currentPageIndex > 0 {
            pages.removeFirst()
            currentPageIndex -= 1
        }

        guard pages.count < Self.maximumPageCount else { return false }

        let shouldBeginPlayback = pages.isEmpty || isWaitingForNextPage
        pages.append(page)

        if shouldBeginPlayback {
            currentPageIndex = pages.count - 1
            speakCurrentPage()
        }

        return true
    }

    func togglePlayback() {
        if isPaused {
            if activeSynthesizer().continueSpeaking() {
                isPaused = false
                isSpeaking = true
            }
            return
        }

        if isSpeaking {
            if activeSynthesizer().pauseSpeaking(at: .word) {
                isPaused = true
            }
            return
        }

        speakCurrentPage()
    }

    func pauseIfNeeded() {
        guard isSpeaking, !isPaused else { return }
        if activeSynthesizer().pauseSpeaking(at: .word) {
            isPaused = true
        }
    }

    func moveBackward() {
        guard canMoveBackward else { return }
        currentPageIndex -= 1
        speakCurrentPage()
    }

    func moveForward() {
        guard canMoveForward else { return }
        currentPageIndex += 1
        speakCurrentPage()
    }

    func endSession() {
        stopPlayback()
        pages.removeAll()
        currentPageIndex = 0
        isWaitingForNextPage = false
        voiceSettings = nil
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

    private func speakCurrentPage() {
        guard let page = currentPage, let voiceSettings else { return }

        stopPlayback()
        let utterance = voiceSettings.configuredUtterance(for: page.text, language: page.language)
        currentUtterance = utterance
        isSpeaking = true
        isPaused = false
        isWaitingForNextPage = false
        activeSynthesizer().speak(utterance)
    }

    private func stopPlayback() {
        currentUtterance = nil
        if let synthesizer, synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isPaused = false
    }

    private func finishIfCurrent(_ utteranceID: ObjectIdentifier) {
        guard
            let currentUtterance,
            ObjectIdentifier(currentUtterance) == utteranceID
        else {
            return
        }

        self.currentUtterance = nil
        isSpeaking = false
        isPaused = false

        if canMoveForward {
            currentPageIndex += 1
            speakCurrentPage()
        } else {
            isWaitingForNextPage = true
        }
    }

    private func cancelIfCurrent(_ utteranceID: ObjectIdentifier) {
        guard
            let currentUtterance,
            ObjectIdentifier(currentUtterance) == utteranceID
        else {
            return
        }

        self.currentUtterance = nil
        isSpeaking = false
        isPaused = false
    }

    private func activeSynthesizer() -> AVSpeechSynthesizer {
        if let synthesizer {
            return synthesizer
        }

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
        self.synthesizer = synthesizer
        return synthesizer
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
        let referenceBox = recognition.page?.boundingBox ?? boundingBox(for: pageLines)
        let bodyLines = pageLines.filter { line in
            !isPageMarginMetadata(line, referenceBox: referenceBox)
        }
        let text = OCRTextAssembler(
            pageLines: bodyLines,
            selectedLines: bodyLines,
            trimsBoundaryFragments: false
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

    private func isPageMarginMetadata(
        _ line: CameraRecognizedTextLine,
        referenceBox: CGRect?
    ) -> Bool {
        guard let referenceBox, referenceBox.height > 0.001 else { return false }

        let relativeY = (line.boundingBox.midY - referenceBox.minY) / referenceBox.height
        let edgeDistance = min(abs(relativeY), abs(1 - relativeY))
        guard edgeDistance <= 0.14 else { return false }
        guard line.text.count <= 48 else { return false }

        return PageReferenceInference.inferredPageReference(
            from: [PageReferenceLine(text: line.text, boundingBox: line.boundingBox)],
            pageBoundingBox: referenceBox
        ) != nil
    }

    private func boundingBox(for lines: [CameraRecognizedTextLine]) -> CGRect? {
        guard let firstLine = lines.first else { return nil }
        return lines.dropFirst().reduce(firstLine.boundingBox) { result, line in
            result.union(line.boundingBox)
        }
    }
}

struct PageReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(QuoteSpeechPlayer.self) private var quoteSpeechPlayer

    let cameraScanner: CameraTextScanner

    @State private var readingSession = PageReadingSession()
    @State private var isAwaitingFrozenFrame = false
    @State private var isProcessingPage = false
    @State private var errorMessage: String?
    @State private var captureTimeoutTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var showsExitConfirmation = false

    var body: some View {
        ZStack {
            OverlineCanvasBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    cameraStage

                    if let errorMessage {
                        readerStatus(message: errorMessage, systemImage: "exclamationmark.triangle")
                    } else if readingSession.pages.isEmpty {
                        readerStatus(message: "인식 내용은 저장되지 않습니다", systemImage: "lock")
                    }

                    if !readingSession.pages.isEmpty {
                        readingControls
                        recognizedTextPreview
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveDismissDisabled(!readingSession.pages.isEmpty)
        .confirmationDialog(
            "읽기를 종료할까요?",
            isPresented: $showsExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("읽기 종료", role: .destructive, action: closeReader)
            Button("계속 읽기", role: .cancel) {}
        } message: {
            Text("인식한 내용은 저장되지 않고 바로 삭제됩니다.")
        }
        .onAppear {
            quoteSpeechPlayer.stop()
            readingSession.connectVoiceSettings(quoteSpeechPlayer)
            prepareCamera()
        }
        .onDisappear {
            cancelPendingRecognition()
            readingSession.endSession()
            cameraScanner.stopSwipeRecognition(clearResults: true)
            cameraScanner.clearFrozenFrame()
            if scenePhase == .active {
                cameraScanner.start()
            }
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
                cameraScanner.start()
            } else {
                cancelPendingRecognition()
                readingSession.pauseIfNeeded()
                cameraScanner.stop(clearRecognitionResults: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            cancelPendingRecognition()
            readingSession.endSession()
            cameraScanner.clearFrozenFrame()
            errorMessage = "메모리 보호를 위해 읽기 세션을 종료했습니다."
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
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

            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.overlineInk)
                    .frame(width: 46, height: 46)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("읽기 종료")
        }
    }

    private var cameraStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)

            if cameraScanner.canUseLiveCamera {
                CameraPreview(session: cameraScanner.session)

                if let frozenFrameImage = cameraScanner.frozenFrameImage {
                    Image(uiImage: frozenFrameImage)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                }

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1.5)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 34)
                    .allowsHitTesting(false)
            } else {
                unavailableCameraView
            }

            if cameraScanner.canToggleTorch {
                Button {
                    cameraScanner.toggleTorch()
                } label: {
                    Image(systemName: cameraScanner.isTorchOn ? "bolt.fill" : "bolt.slash")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.36), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityLabel(cameraScanner.isTorchOn ? "조명 끄기" : "조명 켜기")
            }

            captureButton
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .aspectRatio(0.78, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("페이지 촬영")
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
                } else if !readingSession.pages.isEmpty {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.overlineAccent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapturePage)
        .accessibilityLabel(readingSession.pages.isEmpty ? "페이지 촬영" : "다음 페이지 추가")
    }

    private var unavailableCameraView: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.title)
            Text(cameraUnavailableMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(24)
    }

    private var readingControls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(readingSession.currentPageIndex + 1) / \(readingSession.pages.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.overlineInk)

                Spacer()

                if let currentPage = readingSession.currentPage, currentPage.omittedLineCount > 0 {
                    Text("페이지 정보 제외됨")
                        .font(.caption)
                        .foregroundStyle(Color.overlineMutedInk)
                }
            }

            HStack(spacing: 34) {
                readerControlButton(
                    systemImage: "backward.end.fill",
                    label: "이전 페이지",
                    isEnabled: readingSession.canMoveBackward,
                    action: readingSession.moveBackward
                )

                Button(action: readingSession.togglePlayback) {
                    Image(systemName: readingSession.isSpeaking && !readingSession.isPaused ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.overlineAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(readingSession.isSpeaking && !readingSession.isPaused ? "일시정지" : "재생")

                readerControlButton(
                    systemImage: "forward.end.fill",
                    label: "다음 페이지",
                    isEnabled: readingSession.canMoveForward,
                    action: readingSession.moveForward
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }

    private var recognizedTextPreview: some View {
        Group {
            if let currentPage = readingSession.currentPage {
                Text(currentPage.text)
                    .font(.body)
                    .foregroundStyle(Color.overlineInk)
                    .lineSpacing(4)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.overlinePaper.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.66), lineWidth: 1)
                    }
                    .accessibilityLabel("현재 페이지 인식 내용")
            }
        }
    }

    private var canCapturePage: Bool {
        cameraScanner.canUseLiveCamera
            && !isAwaitingFrozenFrame
            && !isProcessingPage
            && readingSession.canAddPage
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
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.overlineMutedInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func readerControlButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.overlineInk : Color.overlineMutedInk.opacity(0.35))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func prepareCamera() {
        cameraScanner.stopSwipeRecognition(clearResults: true)
        cameraScanner.clearSelectedLineCache()
        cameraScanner.clearFrozenFrame()
        cameraScanner.start()
    }

    private func capturePage() {
        guard canCapturePage else { return }

        errorMessage = nil
        isAwaitingFrozenFrame = true
        cameraScanner.stopSwipeRecognition(clearResults: true)
        cameraScanner.clearFrozenFrame()
        cameraScanner.start()
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
            if scenePhase == .active {
                cameraScanner.start()
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

            guard readingSession.addPage(page) else {
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

    private func requestClose() {
        if readingSession.pages.isEmpty {
            closeReader()
        } else {
            showsExitConfirmation = true
        }
    }

    private func closeReader() {
        cancelPendingRecognition()
        readingSession.endSession()
        cameraScanner.clearFrozenFrame()
        dismiss()
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
