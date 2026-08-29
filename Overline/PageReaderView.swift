import AVFoundation
import NaturalLanguage
import Observation
import SwiftUI
import UIKit

enum CaptureExperienceMode: String, CaseIterable, Identifiable {
    case highlight
    case reader

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlight: "밑줄긋기"
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

struct ReadingCue: Identifiable {
    let id: Int
    let text: String
    let range: NSRange
}

struct ReadingPage: Identifiable {
    let id = UUID()
    let text: String
    let language: CaptureLanguage
    let recognizedLineCount: Int
    let omittedLineCount: Int
    let cues: [ReadingCue]

    init(
        text: String,
        language: CaptureLanguage,
        recognizedLineCount: Int,
        omittedLineCount: Int
    ) {
        self.text = text
        self.language = language
        self.recognizedLineCount = recognizedLineCount
        self.omittedLineCount = omittedLineCount
        cues = ReadingCueTokenizer.cues(in: text, language: language)
    }
}

private enum ReadingCueTokenizer {
    static func cues(in text: String, language: CaptureLanguage) -> [ReadingCue] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(naturalLanguage(for: language))

        let cues = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .compactMap { range -> ReadingCue? in
                let cueText = String(text[range]).trimmed
                guard !cueText.isEmpty else { return nil }
                let nsRange = NSRange(range, in: text)
                return ReadingCue(id: nsRange.location, text: cueText, range: nsRange)
            }

        guard cues.isEmpty else { return cues }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return [ReadingCue(id: 0, text: text, range: fullRange)]
    }

    private static func naturalLanguage(for language: CaptureLanguage) -> NLLanguage {
        switch language {
        case .korean: .korean
        case .english: .english
        case .japanese: .japanese
        }
    }
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
    private(set) var activeCueIndex = 0
    private(set) var speechRateMultiplier: Float = 1

    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private weak var voiceSettings: QuoteSpeechPlayer?
    @ObservationIgnored private var currentUtteranceSourceLocation = 0
    @ObservationIgnored private var pendingStartCueIndex: Int?

    var currentPage: ReadingPage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var canAddPage: Bool {
        pages.count < Self.maximumPageCount
    }

    var canMoveForward: Bool {
        currentPageIndex + 1 < pages.count
    }

    func connectVoiceSettings(_ voiceSettings: QuoteSpeechPlayer) {
        self.voiceSettings = voiceSettings
    }

    @discardableResult
    func appendPage(_ page: ReadingPage) -> Bool {
        guard pages.count < Self.maximumPageCount else { return false }
        pages.append(page)
        return true
    }

    func beginPlayback(atPageIndex pageIndex: Int = 0) {
        guard pages.indices.contains(pageIndex) else { return }
        currentPageIndex = pageIndex
        pendingStartCueIndex = nil
        speakCurrentPage()
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

        let startCueIndex = pendingStartCueIndex ?? 0
        pendingStartCueIndex = nil
        speakCurrentPage(startingAtCueIndex: startCueIndex)
    }

    func pauseIfNeeded() {
        guard isSpeaking, !isPaused else { return }
        if activeSynthesizer().pauseSpeaking(at: .word) {
            isPaused = true
        }
    }

    func resumeIfPaused() {
        guard isPaused else { return }
        if activeSynthesizer().continueSpeaking() {
            isPaused = false
            isSpeaking = true
        }
    }

    func updateSpeechRateMultiplier(_ multiplier: Float) {
        let normalizedMultiplier = min(max(multiplier, 0.8), 1.4)
        guard abs(speechRateMultiplier - normalizedMultiplier) > 0.001 else { return }

        speechRateMultiplier = normalizedMultiplier
        guard currentUtterance != nil else { return }

        let cueIndex = activeCueIndex
        if isPaused {
            stopPlayback()
            pendingStartCueIndex = cueIndex
        } else {
            speakCurrentPage(startingAtCueIndex: cueIndex)
        }
    }

    func endSession() {
        stopPlayback()
        pages.removeAll()
        currentPageIndex = 0
        activeCueIndex = 0
        isWaitingForNextPage = false
        pendingStartCueIndex = nil
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

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.updateActiveCue(for: characterRange, utteranceID: utteranceID)
        }
    }

    private func speakCurrentPage(startingAtCueIndex requestedCueIndex: Int = 0) {
        guard let page = currentPage, let voiceSettings else { return }

        stopPlayback()
        let cueIndex = min(max(requestedCueIndex, 0), max(page.cues.count - 1, 0))
        let sourceLocation = page.cues.indices.contains(cueIndex)
            ? page.cues[cueIndex].range.location
            : 0
        let sourceText = (page.text as NSString).substring(from: sourceLocation)
        let utterance = voiceSettings.configuredUtterance(
            for: sourceText,
            language: page.language,
            rateMultiplier: speechRateMultiplier
        )
        currentUtterance = utterance
        currentUtteranceSourceLocation = sourceLocation
        pendingStartCueIndex = nil
        activeCueIndex = cueIndex
        isSpeaking = true
        isPaused = false
        isWaitingForNextPage = false
        activeSynthesizer().speak(utterance)
    }

    private func stopPlayback() {
        currentUtterance = nil
        currentUtteranceSourceLocation = 0
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
        currentUtteranceSourceLocation = 0
        pendingStartCueIndex = nil
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
        currentUtteranceSourceLocation = 0
        isSpeaking = false
        isPaused = false
    }

    private func updateActiveCue(
        for spokenRange: NSRange,
        utteranceID: ObjectIdentifier
    ) {
        guard
            let currentUtterance,
            ObjectIdentifier(currentUtterance) == utteranceID,
            let currentPage
        else {
            return
        }

        let absoluteSpokenLocation = currentUtteranceSourceLocation + spokenRange.location
        let cueIndex = currentPage.cues.lastIndex { cue in
            cue.range.location <= absoluteSpokenLocation
        } ?? 0
        guard activeCueIndex != cueIndex else { return }
        activeCueIndex = cueIndex
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

private enum PageReaderStage {
    case camera
    case lyrics
}

private struct ReadingLyricsCueID: Hashable {
    let pageID: ReadingPage.ID
    let cueID: ReadingCue.ID
}

private struct ReadingLyricsCue: Identifiable {
    let id: ReadingLyricsCueID
    let text: String
}

private struct PageReaderLyricsStage: View {
    let pages: [ReadingPage]
    let currentPageIndex: Int
    let activeCueIndex: Int
    let isContentReady: Bool
    @State private var scrollPosition: ReadingLyricsCue.ID?

    var body: some View {
        Group {
            if isContentReady {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            Color.clear
                                .frame(height: verticalScrollInset(for: geometry.size.height))
                                .accessibilityHidden(true)

                            ForEach(lyricsCues) { cue in
                                cueText(cue, isActive: cue.id == activeCueID)
                                    .id(cue.id)
                            }

                            Color.clear
                                .frame(height: verticalScrollInset(for: geometry.size.height))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 22)
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $scrollPosition, anchor: .center)
                    .onAppear {
                        scrollPosition = activeCueID
                    }
                    .onChange(of: activeCueID) { _, cueID in
                        withAnimation(.smooth(duration: 0.72, extraBounce: 0)) {
                            scrollPosition = cueID
                        }
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.overlineMutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.overlinePaper
                .overlay(Color.overlineMutedInk.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineMutedInk.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("본문 낭독")
    }

    private var lyricsCues: [ReadingLyricsCue] {
        pages.flatMap { page in
            page.cues.map { cue in
                ReadingLyricsCue(
                    id: ReadingLyricsCueID(pageID: page.id, cueID: cue.id),
                    text: cue.text
                )
            }
        }
    }

    private var activeCueID: ReadingLyricsCue.ID? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        let page = pages[currentPageIndex]
        let cueIndex = min(max(activeCueIndex, 0), max(page.cues.count - 1, 0))
        guard page.cues.indices.contains(cueIndex) else { return nil }
        return ReadingLyricsCueID(pageID: page.id, cueID: page.cues[cueIndex].id)
    }

    private func cueText(_ cue: ReadingLyricsCue, isActive: Bool) -> some View {
        Text(cue.text)
            .font(.title2.weight(.bold))
            .foregroundStyle(isActive ? Color.overlineInk : Color.overlineMutedInk)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isActive ? 1 : 0.30)
            .animation(.easeInOut(duration: 0.34), value: isActive)
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func verticalScrollInset(for height: CGFloat) -> CGFloat {
        max(height * 0.38, 96)
    }
}

private enum PageReadingSpeed: Double, CaseIterable, Identifiable {
    case relaxed = 0.8
    case normal = 1.0
    case brisk = 1.2
    case fast = 1.4

    var id: Double { rawValue }

    var title: String {
        String(format: "%.1f×", rawValue)
    }
}

private struct PageReaderSpeechSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var speedMultiplier: Double

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 4) {
                    ForEach(PageReadingSpeed.allCases) { speed in
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                speedMultiplier = speed.rawValue
                            }
                        } label: {
                            Text(speed.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.overlineInk)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background {
                                    if isSelected(speed) {
                                        Capsule(style: .continuous)
                                            .fill(Color.white.opacity(0.88))
                                    }
                                }
                                .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected(speed) ? [.isSelected] : [])
                    }
                }
                .padding(4)
                .background(Color.overlineMutedInk.opacity(0.12), in: Capsule(style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()
            }
            .navigationTitle("읽기 속도")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("완료")
                }
            }
        }
    }

    private func isSelected(_ speed: PageReadingSpeed) -> Bool {
        abs(speedMultiplier - speed.rawValue) < 0.001
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
    @State private var cameraPreparationTask: Task<Void, Never>?
    @State private var finishTransitionTask: Task<Void, Never>?
    @State private var showsExitConfirmation = false
    @State private var showsSpeechSettings = false
    @State private var readerStage: PageReaderStage = .camera
    @State private var isCameraPreviewReady = false
    @State private var isLyricsContentReady = false
    @State private var pageCountBeforeCapture = 0
    @State private var resumesPlaybackAfterCapture = false
    @State private var wasWaitingForNextPageBeforeCapture = false
    @AppStorage("pageReader.speechRateMultiplier") private var speechRateMultiplier = 1.0

    var body: some View {
        ZStack {
            OverlineCanvasBackground()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header

                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                if let errorMessage {
                    readerStatus(message: errorMessage, systemImage: "exclamationmark.triangle")
                } else if readerStage == .camera {
                    if readingSession.pages.isEmpty {
                        readerStatus(message: "인식 내용은 저장되지 않습니다", systemImage: "lock")
                    } else {
                        readerStatus(
                            message: "\(readingSession.pages.count)쪽 준비됨",
                            systemImage: "doc.on.doc"
                        )
                    }
                }

                if readerStage == .lyrics, !readingSession.pages.isEmpty {
                    readingControls
                }
            }
            .padding(16)
            .padding(.bottom, 4)
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
        .sheet(isPresented: $showsSpeechSettings) {
            PageReaderSpeechSettingsView(speedMultiplier: $speechRateMultiplier)
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            quoteSpeechPlayer.stop()
            readingSession.connectVoiceSettings(quoteSpeechPlayer)
            readingSession.updateSpeechRateMultiplier(Float(speechRateMultiplier))
            scheduleCameraPreparation()
        }
        .onChange(of: speechRateMultiplier) { _, multiplier in
            readingSession.updateSpeechRateMultiplier(Float(multiplier))
        }
        .onDisappear {
            cancelPendingRecognition()
            cameraPreparationTask?.cancel()
            cameraPreparationTask = nil
            finishTransitionTask?.cancel()
            finishTransitionTask = nil
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
                if readerStage == .camera {
                    scheduleCameraPreparation()
                }
            } else {
                cancelPendingRecognition()
                finishTransitionTask?.cancel()
                finishTransitionTask = nil
                if readerStage == .lyrics {
                    isLyricsContentReady = true
                }
                cameraPreparationTask?.cancel()
                cameraPreparationTask = nil
                isCameraPreviewReady = false
                readingSession.pauseIfNeeded()
                cameraScanner.stop(clearRecognitionResults: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            cancelPendingRecognition()
            finishTransitionTask?.cancel()
            finishTransitionTask = nil
            readingSession.endSession()
            cameraScanner.clearFrozenFrame()
            resetCaptureContext()
            isLyricsContentReady = false
            readerStage = .camera
            scheduleCameraPreparation()
            errorMessage = "메모리 보호를 위해 읽기 세션을 종료했습니다."
        }
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var stageContent: some View {
        if readerStage == .lyrics, !readingSession.pages.isEmpty {
            PageReaderLyricsStage(
                pages: readingSession.pages,
                currentPageIndex: readingSession.currentPageIndex,
                activeCueIndex: readingSession.activeCueIndex,
                isContentReady: isLyricsContentReady
            )
        } else {
            cameraStage
        }
    }

    private var cameraStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)

            if isCameraPreviewReady, cameraScanner.canUseLiveCamera {
                CameraPreview(session: cameraScanner.session)

                if let frozenFrameImage = cameraScanner.frozenFrameImage {
                    Image(uiImage: frozenFrameImage)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
            } else if isCameraPreviewReady {
                unavailableCameraView
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("카메라 준비 중")
            }

            if isCameraPreviewReady, cameraScanner.canToggleTorch {
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

            captureControls
                .padding(.bottom, 18)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("페이지 촬영")
    }

    private var captureControls: some View {
        ZStack {
            captureButton

            HStack {
                Spacer()
                finishCaptureButton
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78)
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
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapturePage)
        .accessibilityLabel("페이지 촬영")
    }

    private var finishCaptureButton: some View {
        Button(action: finishCapture) {
            Image(systemName: "checkmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    canFinishCapture ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.36),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!canFinishCapture)
        .accessibilityLabel("촬영 완료")
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
        ZStack {
            Button(action: readingSession.togglePlayback) {
                Image(systemName: readingSession.isSpeaking && !readingSession.isPaused ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.overlineAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(readingSession.isSpeaking && !readingSession.isPaused ? "일시정지" : "재생")

            HStack {
                Button(action: openCameraForNextPage) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .disabled(!readingSession.canAddPage)
                .opacity(readingSession.canAddPage ? 1 : 0.30)
                .accessibilityLabel("페이지 추가")

                Spacer()

                Button {
                    showsSpeechSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.overlineMutedInk)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("읽기 속도 설정")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }

    private var canCapturePage: Bool {
        readerStage == .camera
            && isCameraPreviewReady
            && cameraScanner.canUseLiveCamera
            && !isAwaitingFrozenFrame
            && !isProcessingPage
            && readingSession.canAddPage
    }

    private var canFinishCapture: Bool {
        readerStage == .camera
            && !readingSession.pages.isEmpty
            && !isAwaitingFrozenFrame
            && !isProcessingPage
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

    private func prepareCamera() {
        cameraScanner.stopSwipeRecognition(clearResults: true)
        cameraScanner.clearSelectedLineCache()
        cameraScanner.clearFrozenFrame()
        cameraScanner.start()
    }

    private func scheduleCameraPreparation() {
        cameraPreparationTask?.cancel()
        cameraPreparationTask = nil
        isCameraPreviewReady = false

        cameraPreparationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard
                !Task.isCancelled,
                scenePhase == .active,
                readerStage == .camera
            else {
                return
            }

            prepareCamera()
            isCameraPreviewReady = true
            cameraPreparationTask = nil
        }
    }

    private func openCameraForNextPage() {
        guard readingSession.canAddPage else {
            errorMessage = "한 번에 최대 \(PageReadingSession.maximumPageCount)쪽까지 준비할 수 있습니다."
            return
        }

        finishTransitionTask?.cancel()
        finishTransitionTask = nil
        errorMessage = nil
        pageCountBeforeCapture = readingSession.pages.count
        resumesPlaybackAfterCapture = readingSession.isSpeaking && !readingSession.isPaused
        wasWaitingForNextPageBeforeCapture = readingSession.isWaitingForNextPage
        readingSession.pauseIfNeeded()
        isLyricsContentReady = false
        withAnimation(.easeInOut(duration: 0.22)) {
            readerStage = .camera
        }
        scheduleCameraPreparation()
    }

    private func finishCapture() {
        guard canFinishCapture else { return }

        finishTransitionTask?.cancel()
        let addedPages = readingSession.pages.count - pageCountBeforeCapture
        let previousPageCount = pageCountBeforeCapture
        let shouldResumePlayback = resumesPlaybackAfterCapture
        let shouldStartAddedPages = wasWaitingForNextPageBeforeCapture && addedPages > 0

        isCameraPreviewReady = false
        isLyricsContentReady = false
        readerStage = .lyrics

        finishTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, readerStage == .lyrics else { return }

            isLyricsContentReady = true
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, readerStage == .lyrics else { return }

            if previousPageCount == 0 {
                readingSession.beginPlayback()
            } else if shouldStartAddedPages {
                readingSession.beginPlayback(atPageIndex: previousPageCount)
            } else if shouldResumePlayback {
                readingSession.resumeIfPaused()
            }

            await Task.yield()
            guard !Task.isCancelled else { return }
            cameraScanner.stop(clearRecognitionResults: false)
            cameraScanner.clearFrozenFrame()
            finishTransitionTask = nil
        }

        resetCaptureContext()
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
            if scenePhase == .active, readerStage == .camera {
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

            guard readingSession.appendPage(page) else {
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
        finishTransitionTask?.cancel()
        finishTransitionTask = nil
        cameraPreparationTask?.cancel()
        cameraPreparationTask = nil
        readingSession.endSession()
        cameraScanner.clearFrozenFrame()
        resetCaptureContext()
        dismiss()
    }

    private func resetCaptureContext() {
        pageCountBeforeCapture = 0
        resumesPlaybackAfterCapture = false
        wasWaitingForNextPageBeforeCapture = false
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
