import Foundation
import OSLog
import PhotosUI
import SwiftUI
import UIKit

private let captureMetricsLogger = Logger(subsystem: "aib.Overline", category: "CaptureMetrics")

struct CaptureView: View {
    @Environment(ReadingLibrary.self) private var library
    @State private var selectedLineIDs: Set<Int> = []
    @State private var selectedCameraLineIDs: Set<CameraRecognizedTextLine.ID> = []
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cameraScanner = CameraTextScanner()
    @State private var speechRecorder = SpeechMemoRecorder()
    @State private var memo = ""
    @State private var pageReferenceText = ""
    @State private var tagsText = ""
    @State private var memoBeforeSpeech = ""
    @State private var lastSaved: Highlight?
    @State private var captureMessage: CaptureMessage?
    @State private var isRecognizingText = false
    @State private var presentedSheet: CaptureSheet?
    @State private var captureScreenOpenedAt = Date()
    @State private var delayedCameraStartTask: Task<Void, Never>?
    @State private var isHighlighterGestureActive = false
    @State private var selectedTone: StickyTone = .yellow

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CaptureBookSelector(
                    library: library,
                    openAddBook: { presentedSheet = .addBook }
                )

                CaptureStage(
                    selectedLineIDs: $selectedLineIDs,
                    selectedCameraLineIDs: $selectedCameraLineIDs,
                    selectedPhotoItem: $selectedPhotoItem,
                    cameraScanner: cameraScanner,
                    isRecognizingText: isRecognizingText,
                    selectedTone: selectedTone,
                    onCommit: commitSelection,
                    onMiss: showCaptureGuidance,
                    openSettings: openAppSettings,
                    onHighlighterGestureActiveChanged: { isActive in
                        isHighlighterGestureActive = isActive
                    }
                )

                if let captureMessage {
                    CaptureStatusStrip(message: captureMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                CaptureMetadataBar(
                    pageReference: $pageReferenceText,
                    tagsText: $tagsText,
                    selectedTone: $selectedTone
                )

                MemoComposerCard(
                    memo: $memo,
                    isListening: speechRecorder.isRecording,
                    voiceErrorMessage: speechRecorder.errorMessage,
                    toggleVoiceMemo: toggleVoiceMemo,
                    quickSave: saveQuickThought,
                    openSettings: openAppSettings
                )

                if let lastSaved {
                    SavedHighlightStrip(highlight: lastSaved)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
            .padding(.bottom, 92)
        }
        .scrollIndicators(.hidden)
        .overlineBottomMenuCompaction()
        .background(Color.overlineCanvas.ignoresSafeArea())
        .task(id: selectedPhotoItem) {
            await recognizeSelectedPhoto()
        }
        .onAppear {
            captureScreenOpenedAt = .now
            captureMetricsLogger.info("capture_screen_opened")
            scheduleCameraStart()
        }
        .onDisappear {
            delayedCameraStartTask?.cancel()
            delayedCameraStartTask = nil
            isHighlighterGestureActive = false
            speechRecorder.cancel()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                cameraScanner.stop(clearRecognitionResults: false)
            }
        }
        .onChange(of: speechRecorder.transcript) { _, transcript in
            guard speechRecorder.isRecording else { return }
            memo = mergedSpeechMemo(base: memoBeforeSpeech, transcript: transcript)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addBook:
                AddBookSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func toggleVoiceMemo() {
        Task {
            if speechRecorder.isRecording {
                markSpeechMemoIfNeeded()
                speechRecorder.stopRecording()
                memoBeforeSpeech = ""
            } else {
                memoBeforeSpeech = memo
                await speechRecorder.startRecording()
            }
        }
    }

    private func mergedSpeechMemo(base: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmed
        guard !trimmedTranscript.isEmpty else { return base }
        guard !base.trimmed.isEmpty else { return trimmedTranscript }
        return "\(base.trimmed)\n\(trimmedTranscript)"
    }

    private func markSpeechMemoIfNeeded() {
        guard !speechRecorder.transcript.trimmed.isEmpty else { return }
        MVPReadinessStore.markVerified(.speechMemo, detail: "온디바이스 STT 전사 저장")
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func scheduleCameraStart() {
        delayedCameraStartTask?.cancel()
        delayedCameraStartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }

            while isHighlighterGestureActive {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }

            cameraScanner.start()
            delayedCameraStartTask = nil
        }
    }

    private func commitSelection() {
        guard !isRecognizingText else { return }

        Task { @MainActor in
            await commitSelectionAsync()
        }
    }

    @MainActor
    private func commitSelectionAsync() async {
        let liveText = cameraScanner.text(for: selectedCameraLineIDs)
        let isLiveCapture = !liveText.isEmpty
        let selectedLineCount = isLiveCapture ? selectedCameraLineIDs.count : selectedLineIDs.count
        let averageConfidence = isLiveCapture ? cameraScanner.averageConfidence(for: selectedCameraLineIDs) : nil
        let frameBrightness = isLiveCapture ? cameraScanner.frameBrightness : nil
        let durationMilliseconds = captureElapsedMilliseconds()
        let text = liveText.isEmpty
            ? SampleData.pageLines
                .filter { selectedLineIDs.contains($0.id) }
                .map(\.text)
                .joined(separator: " ")
                .trimmed
            : liveText

        guard !text.isEmpty else {
            showCaptureGuidance()
            return
        }

        let source = isLiveCapture ? "camera" : "mock"
        let hasMemo = !memo.trimmed.isEmpty
        let pathStepCount = capturePathStepCount(for: source)
        let detectedLanguage = CaptureLanguage.detect(from: text)
        if isLiveCapture {
            MVPReadinessStore.markVerified(
                .capturePath,
                detail: "\(pathStepCount)단계 · \(selectedLineCount)줄 · \(captureQualitySummary(confidence: averageConfidence, brightness: frameBrightness))"
            )
        }
        if isLiveCapture && durationMilliseconds <= 10_000 {
            MVPReadinessStore.markVerified(
                .captureSpeed,
                detail: "\(captureDurationLabel(milliseconds: durationMilliseconds)) · \(selectedLineCount)줄"
            )
        }
        let inferredPageReference = isLiveCapture ? cameraScanner.inferredPageReference() : nil
        let snapshotData = liveText.isEmpty ? nil : cameraScanner.currentSnapshotJPEGData(for: selectedCameraLineIDs)
        if isLiveCapture, cameraScanner.detectedPage != nil {
            MVPReadinessStore.markVerified(
                .pageBoundary,
                detail: "페이지 경계 감지 상태에서 \(selectedLineCount)줄 저장"
            )
        }
        if isLiveCapture, snapshotData != nil {
            MVPReadinessStore.markVerified(
                .snapshotCrop,
                detail: "선택 영역 스냅샷 생성 · \(selectedLineCount)줄"
            )
        }
        if isLiveCapture, cameraScanner.isLowLight {
            MVPReadinessStore.markVerified(
                .lowLight,
                detail: "\(captureQualitySummary(confidence: averageConfidence, brightness: frameBrightness))"
            )
        }

        let refinedText: String
        if isLiveCapture {
            refinedText = text
        } else {
            isRecognizingText = true
            captureMessage = .processing
            refinedText = await refinedOCRText(
                for: OCRTextRefinementRequest(
                    selectedText: text,
                    pageText: text,
                    selectedLines: [],
                    pageLines: [],
                    language: detectedLanguage,
                    selectedLineCount: selectedLineCount,
                    allowsBoundaryTrimming: false
                )
            )
            isRecognizingText = false
        }

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            lastSaved = library.addCapturedHighlight(
                text: refinedText,
                memo: memo,
                language: CaptureLanguage.detect(from: refinedText),
                pageReference: liveText.isEmpty ? "p. 42" : (inferredPageReference ?? ""),
                explicitPageReference: pageReferenceText,
                tagsText: tagsText,
                stickyTone: selectedTone,
                snapshotData: snapshotData
            )
            selectedLineIDs.removeAll()
            selectedCameraLineIDs.removeAll()
            clearComposerInputs()
            captureMessage = .saved(
                lineCount: selectedLineCount,
                confidence: averageConfidence,
                durationMilliseconds: durationMilliseconds
            )
        }
        cameraScanner.stopSwipeRecognition()

        logCaptureSaved(
            source: source,
            lineCount: selectedLineCount,
            confidence: averageConfidence,
            brightness: frameBrightness,
            hasMemo: hasMemo,
            durationMilliseconds: durationMilliseconds,
            pathStepCount: pathStepCount
        )
        resetCaptureTimer()
    }

    private func saveQuickThought() {
        guard !memo.trimmed.isEmpty else { return }

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            lastSaved = library.addQuickThought(
                memo,
                pageReference: pageReferenceText,
                tagsText: tagsText,
                stickyTone: selectedTone
            )
            clearComposerInputs()
        }
    }

    @MainActor
    private func recognizeSelectedPhoto() async {
        guard let selectedPhotoItem else { return }

        isRecognizingText = true
        captureMessage = .processing

        defer {
            isRecognizingText = false
            self.selectedPhotoItem = nil
        }

        do {
            guard
                let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                throw OCRTextRecognizerError.invalidImage
            }

            let recognitionResult = try await OCRTextRecognizer().recognizeTextResult(in: image)
            let text = recognitionResult.text
            let detectedLanguage = CaptureLanguage.detect(from: text)
            let refinedText = await refinedOCRText(
                for: OCRTextRefinementRequest(
                    selectedText: text,
                    pageText: text,
                    selectedLines: [],
                    pageLines: [],
                    language: detectedLanguage,
                    selectedLineCount: recognitionResult.lineCount,
                    allowsBoundaryTrimming: false
                )
            )
            let hasMemo = !memo.trimmed.isEmpty
            let durationMilliseconds = captureElapsedMilliseconds()
            let highlight = library.addCapturedHighlight(
                text: refinedText,
                memo: memo,
                language: CaptureLanguage.detect(from: refinedText),
                pageReference: recognitionResult.inferredPageReference ?? "OCR",
                explicitPageReference: pageReferenceText,
                tagsText: tagsText,
                stickyTone: selectedTone,
                snapshotData: image.overlineSnapshotJPEGData()
            )

            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                lastSaved = highlight
                selectedLineIDs.removeAll()
                selectedCameraLineIDs.removeAll()
                clearComposerInputs()
                captureMessage = .saved(
                    lineCount: recognitionResult.lineCount,
                    confidence: nil,
                    durationMilliseconds: durationMilliseconds
                )
            }

            logCaptureSaved(
                source: "photo",
                lineCount: recognitionResult.lineCount,
                confidence: nil,
                brightness: nil,
                hasMemo: hasMemo,
                durationMilliseconds: durationMilliseconds,
                pathStepCount: capturePathStepCount(for: "photo")
            )
            resetCaptureTimer()
        } catch {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                captureMessage = .error(error.localizedDescription)
            }
        }
    }

    private func refinedOCRText(for request: OCRTextRefinementRequest) async -> String {
        await Task.detached(priority: .utility) {
            await OCRTextRefiner().refinedText(for: request)
        }
        .value
    }

    private func clearComposerInputs() {
        memo.removeAll()
        pageReferenceText.removeAll()
        tagsText.removeAll()
    }

    private func captureElapsedMilliseconds() -> Int {
        Int((Date().timeIntervalSince(captureScreenOpenedAt) * 1000).rounded())
    }

    private func resetCaptureTimer() {
        captureScreenOpenedAt = .now
    }

    private func captureDurationLabel(milliseconds: Int) -> String {
        let seconds = Double(milliseconds) / 1000
        return "\(seconds.formatted(.number.precision(.fractionLength(1))))초"
    }

    private func captureQualitySummary(confidence: Float?, brightness: Float?) -> String {
        let confidenceText = confidence.map { "신뢰도 \(Int(($0 * 100).rounded()))%" } ?? "신뢰도 -"
        let brightnessText = brightness.map { "밝기 \(Int(($0 * 100).rounded()))%" } ?? "밝기 -"
        return "\(confidenceText) · \(brightnessText)"
    }

    private func capturePathStepCount(for source: String) -> Int {
        switch source {
        case "camera", "mock":
            return 2
        case "photo":
            return 3
        default:
            return 3
        }
    }

    private func logCaptureSaved(
        source: String,
        lineCount: Int,
        confidence: Float?,
        brightness: Float?,
        hasMemo: Bool,
        durationMilliseconds: Int,
        pathStepCount: Int
    ) {
        let confidencePercent = confidence.map { Int(($0 * 100).rounded()) } ?? -1
        let brightnessPercent = brightness.map { Int(($0 * 100).rounded()) } ?? -1

        captureMetricsLogger.info(
            "capture_saved source=\(source, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public) path_steps=\(pathStepCount, privacy: .public) line_count=\(lineCount, privacy: .public) confidence_percent=\(confidencePercent, privacy: .public) brightness_percent=\(brightnessPercent, privacy: .public) has_memo=\(hasMemo, privacy: .public)"
        )

        CapturePerformanceStore.add(
            CapturePerformanceRecord(
                source: source,
                durationMilliseconds: durationMilliseconds,
                lineCount: lineCount,
                confidencePercent: confidence.map { Int(($0 * 100).rounded()) },
                brightnessPercent: brightness.map { Int(($0 * 100).rounded()) },
                hasMemo: hasMemo,
                pathStepCount: pathStepCount
            )
        )
    }

    private func showCaptureGuidance() {
        let message: String

        if cameraScanner.canUseLiveCamera {
            if cameraScanner.lines.isEmpty {
                if cameraScanner.isLowLight {
                    message = "조명이 어두워요. 플래시를 켜거나 페이지를 더 밝게 비춰 주세요."
                } else {
                    message = "글자를 아직 찾지 못했어요. 페이지를 밝게 비추고 1-2초 기다려 주세요."
                }
            } else {
                message = "인식된 글자 위를 좌우로 그어 주세요."
            }
        } else {
            message = "저장할 문장 위를 좌우로 그어 주세요."
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            captureMessage = .guidance(message)
        }
    }
}

private extension UIImage {
    func overlineSnapshotJPEGData(maxDimension: CGFloat = 1400, compressionQuality: CGFloat = 0.78) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return jpegData(compressionQuality: compressionQuality) }

        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return renderedImage.jpegData(compressionQuality: compressionQuality)
    }
}

private enum CaptureSheet: Identifiable {
    case addBook

    var id: String {
        switch self {
        case .addBook: "addBook"
        }
    }
}

private struct CaptureBookSelector: View {
    let library: ReadingLibrary
    let openAddBook: () -> Void
    @State private var isSelectionPresented = false

    var body: some View {
        Button {
            isSelectionPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "book.closed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.overlineAccent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(library.selectedBook?.title ?? "Inbox")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.overlineInk)
                        .lineLimit(1)

                    Text(library.selectedBook?.author ?? "Overline")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.58))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .captureBookSelectionSurface(cornerRadius: 30)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("저장할 책 선택")
        .popover(isPresented: $isSelectionPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            CaptureBookSelectionPanel(
                library: library,
                selectBook: { bookID in
                    library.selectBook(bookID)
                    isSelectionPresented = false
                },
                addBook: {
                    isSelectionPresented = false
                    openAddBook()
                }
            )
            .frame(width: min(UIScreen.main.bounds.width - 32, 360))
            .capturePopoverPresentation()
        }
    }
}

private struct CaptureBookSelectionPanel: View {
    let library: ReadingLibrary
    let selectBook: (ReadingBook.ID) -> Void
    let addBook: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(library.books) { book in
                        Button {
                            selectBook(book.id)
                        } label: {
                            CaptureBookSelectionRow(
                                title: book.title,
                                subtitle: book.author,
                                isSelected: library.selectedBookID == book.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 300)

            if !library.books.isEmpty {
                Divider()
                    .padding(.horizontal, 18)
            }

            Button(action: addBook) {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .frame(width: 28)
                        .foregroundStyle(Color.overlineAccent)

                    Text("책 추가")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(Color.overlineInk)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .captureBookSelectionSurface(cornerRadius: 30)
    }
}

private struct CaptureBookSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "book.closed")
                .font(.title3.weight(.semibold))
                .frame(width: 28)
                .foregroundStyle(isSelected ? Color.overlineAccent : Color.overlineMutedInk.opacity(0.62))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(Color.overlineInk)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.overlineMutedInk.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private extension View {
    @ViewBuilder
    func captureBookSelectionSurface(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                }
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.14)),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.54), lineWidth: 1)
                }
        } else {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.54), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func capturePopoverPresentation() -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.clear)
        } else {
            self
        }
    }
}

private struct CaptureStage: View {
    @Binding var selectedLineIDs: Set<Int>
    @Binding var selectedCameraLineIDs: Set<CameraRecognizedTextLine.ID>
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let cameraScanner: CameraTextScanner
    let isRecognizingText: Bool
    let selectedTone: StickyTone
    let onCommit: () -> Void
    let onMiss: () -> Void
    let openSettings: () -> Void
    let onHighlighterGestureActiveChanged: (Bool) -> Void
    @State private var previousDragLocation: CGPoint?
    @State private var pendingCameraDragRects: [CGRect] = []
    @State private var activeHighlighterPoints: [CGPoint] = []
    @State private var pendingCameraCommit = false
    @State private var pendingCameraCommitTask: Task<Void, Never>?
    @State private var pendingCameraMissTask: Task<Void, Never>?
    @State private var delayedCameraRecognitionTask: Task<Void, Never>?
    @State private var activeCameraStrokeID = 0
    @State private var pendingCameraStrokeID: Int?
    @State private var recognitionStartedStrokeID: Int?
    @State private var pendingCameraSelectionMode: CameraGestureSelectionMode?
    @State private var cameraRecognitionAttemptCount = 0
    @State private var cameraFeedbackPhase: CameraCaptureFeedbackPhase = .idle

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.12, blue: 0.12))

                if cameraScanner.canUseLiveCamera {
                    CameraPreview(session: cameraScanner.session)
                        .overlay(Color.black.opacity(0.12))

                    if let frozenFrameImage = cameraScanner.frozenFrameImage {
                        Image(uiImage: frozenFrameImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .overlay(Color.black.opacity(0.12))
                            .transition(.opacity.animation(.easeOut(duration: 0.10)))
                            .allowsHitTesting(false)
                    }

                    LiveHighlighterStrokeOverlay(
                        points: activeHighlighterPoints,
                        tone: selectedTone
                    )
                } else {
                    PaperPage()
                        .padding(.horizontal, 34)
                        .padding(.top, 58)
                        .padding(.bottom, 34)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(SampleData.pageLines) { line in
                            CapturedLine(
                                text: line.text,
                                weight: line.weight,
                                isSelected: selectedLineIDs.contains(line.id),
                                tone: selectedTone
                            )
                        }
                    }
                    .padding(.horizontal, 54)
                    .padding(.top, 82)
                    .padding(.bottom, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                selectLine(
                                    from: previousDragLocation,
                                    to: value.location,
                                    in: proxy.size
                                )
                                previousDragLocation = value.location
                            }
                            .onEnded { _ in
                                previousDragLocation = nil
                                finishLineSelection(in: proxy.size)
                            }
                    )

                CameraHUD(
                    selectedPhotoItem: $selectedPhotoItem,
                    scannerStatus: cameraScanner.status,
                    isRecognizingText: isRecognizingText || cameraScanner.isAnalyzingText,
                    isTorchOn: cameraScanner.isTorchOn,
                    isLowLight: cameraScanner.isLowLight,
                    frameBrightness: cameraScanner.frameBrightness,
                    canToggleTorch: cameraScanner.canToggleTorch,
                    toggleTorch: {
                        cameraScanner.toggleTorch()
                    },
                    openSettings: openSettings
                )
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                CameraCaptureFeedbackPill(phase: cameraFeedbackPhase)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .accessibilityLabel("Overline capture preview")
            .onChange(of: cameraScanner.recognitionUpdateCount) { _, _ in
                guard recognitionStartedStrokeID == pendingCameraStrokeID else { return }
                resolvePendingCameraSelection(in: proxy.size)
            }
            .onChange(of: cameraScanner.isAnalyzingText) { _, isAnalyzing in
                if !isAnalyzing {
                    if pendingCameraCommitTask == nil {
                        let shouldShowMiss = pendingCameraCommit &&
                            recognitionStartedStrokeID == pendingCameraStrokeID &&
                            selectedCameraLineIDs.isEmpty &&
                            !activeHighlighterPoints.isEmpty
                        cancelPendingCameraMiss()
                        pendingCameraDragRects.removeAll()
                        activeHighlighterPoints.removeAll()
                        cameraScanner.clearFrozenFrame()
                        pendingCameraCommit = false
                        pendingCameraStrokeID = nil
                        recognitionStartedStrokeID = nil
                        pendingCameraSelectionMode = nil
                        setCameraFeedbackPhase(.idle)
                        if shouldShowMiss {
                            onMiss()
                        }
                    }
                }
            }
        }
        .aspectRatio(0.84, contentMode: .fit)
        .onDisappear {
            cancelPendingCameraCommit()
            cancelPendingCameraMiss()
            cancelDelayedCameraRecognition()
            pendingCameraDragRects.removeAll()
            activeHighlighterPoints.removeAll()
            cameraScanner.clearFrozenFrame()
            pendingCameraCommit = false
            pendingCameraStrokeID = nil
            recognitionStartedStrokeID = nil
            pendingCameraSelectionMode = nil
            setCameraFeedbackPhase(.idle)
        }
    }

    private func selectLine(from previousLocation: CGPoint?, to location: CGPoint, in size: CGSize) {
        if cameraScanner.canUseLiveCamera {
            selectCameraLine(from: previousLocation, to: location, in: size)
            return
        }

        let top = size.height * 0.22
        let rowHeight = size.height * 0.082
        let index = Int(((location.y - top) / rowHeight).rounded(.down))

        guard SampleData.pageLines.indices.contains(index) else { return }

        let expectedCenter = top + (CGFloat(index) + 0.5) * rowHeight
        guard abs(location.y - expectedCenter) < rowHeight * 0.65 else { return }

        selectedLineIDs.insert(SampleData.pageLines[index].id)
    }

    private func finishLineSelection(in size: CGSize) {
        if cameraScanner.canUseLiveCamera {
            guard !activeHighlighterPoints.isEmpty else { return }
            let strokeID = activeCameraStrokeID
            let selectionMode = cameraGestureSelectionMode(in: size)
            let rawPointCount = activeHighlighterPoints.count
            let rawBounds = boundingRect(for: activeHighlighterPoints)
            activeHighlighterPoints = correctedHighlighterPoints(
                activeHighlighterPoints,
                mode: selectionMode
            )
            let correctedBounds = boundingRect(for: activeHighlighterPoints)
            let recognitionProfile = cameraRecognitionProfile()
            captureMetricsLogger.info(
                "camera_ar_gesture_finished stroke_id=\(strokeID, privacy: .public) mode=\(selectionMode.rawValue, privacy: .public) stage=\(debugSizeDescription(size), privacy: .public) raw_points=\(rawPointCount, privacy: .public) corrected_points=\(activeHighlighterPoints.count, privacy: .public) raw_bounds=\(debugRectDescription(rawBounds), privacy: .public) corrected_bounds=\(debugRectDescription(correctedBounds), privacy: .public)"
            )
            onHighlighterGestureActiveChanged(false)
            pendingCameraCommit = true
            setCameraFeedbackPhase(.holding)
            pendingCameraStrokeID = strokeID
            pendingCameraSelectionMode = selectionMode
            recognitionStartedStrokeID = nil
            startDelayedCameraRecognition(for: strokeID, profile: recognitionProfile)
            schedulePendingCameraMiss(in: size, strokeID: strokeID, profile: recognitionProfile)
            return
        }

        onCommit()
    }

    private func selectCameraLine(from previousLocation: CGPoint?, to location: CGPoint, in size: CGSize) {
        let focusRect = CaptureStageMetrics.focusRect(in: size)
        let dragRect = dragRect(from: previousLocation, to: location)

        guard focusRect.intersects(dragRect) else { return }

        if activeHighlighterPoints.isEmpty {
            beginCameraStroke(at: location, in: size)
        }

        appendHighlighterPoint(location, previousLocation: previousLocation, in: size)
        pendingCameraDragRects.append(dragRect)
        if pendingCameraDragRects.count > 36 {
            pendingCameraDragRects.removeFirst(pendingCameraDragRects.count - 36)
        }
    }

    private func resolvePendingCameraSelection(in size: CGSize) {
        guard cameraScanner.canUseLiveCamera else { return }
        guard !activeHighlighterPoints.isEmpty || !pendingCameraDragRects.isEmpty else { return }
        guard pendingCameraCommit else { return }

        let selectionMode = pendingCameraSelectionMode ?? cameraGestureSelectionMode(in: size)
        let pageLines = cameraScanner.lines
        let selectedIDs: Set<CameraRecognizedTextLine.ID>
        let candidateCount: Int
        let debugCandidateSummary: String

        switch selectionMode {
        case .region:
            let regionLines = pageLines.filter { line in
                cameraRegionSelectionContains(line: line, in: size)
            }
            selectedIDs = Set(regionLines.map(\.id))
            candidateCount = regionLines.count
            debugCandidateSummary = debugLineGeometrySummary(regionLines, in: size)
        case .line:
            let matches = strokeLineMatches(from: pageLines, in: size)
            let selectedMatches = selectedLineMatches(from: matches)
            selectedIDs = Set(selectedMatches.map(\.id))
            candidateCount = matches.count
            debugCandidateSummary = debugScoreSummary(matches, lines: pageLines, in: size)
        }

        let selectedLines = pageLines.filter { selectedIDs.contains($0.id) }
        captureMetricsLogger.info(
            "camera_ar_resolve stroke_id=\(pendingCameraStrokeID ?? -1, privacy: .public) mode=\(selectionMode.rawValue, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) ocr_line_count=\(pageLines.count, privacy: .public) candidate_count=\(candidateCount, privacy: .public) selected_count=\(selectedIDs.count, privacy: .public) gesture_bounds=\(debugRectDescription(boundingRect(for: activeHighlighterPoints)), privacy: .public) ocr=\(debugLineGeometrySummary(pageLines, in: size), privacy: .public) candidates=\(debugCandidateSummary, privacy: .public) selected=\(debugLineGeometrySummary(selectedLines, in: size), privacy: .public)"
        )

        if !selectedIDs.isEmpty {
            cameraScanner.cacheSelectedLines(for: selectedIDs)
            selectedCameraLineIDs = selectedIDs
        }

        if pendingCameraCommit, !selectedCameraLineIDs.isEmpty {
            captureMetricsLogger.info(
                "camera_ar_match line_count=\(selectedCameraLineIDs.count, privacy: .public) candidate_count=\(candidateCount, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) mode=\(selectionMode.rawValue, privacy: .public)"
            )
            commitPendingCameraSelection()
        }
    }

    private func strokeLineMatches(from lines: [CameraRecognizedTextLine], in size: CGSize) -> [CameraStrokeLineMatch] {
        lines.compactMap { line -> CameraStrokeLineMatch? in
            guard let score = cameraStrokeScore(for: line, in: size) else { return nil }
            return CameraStrokeLineMatch(id: line.id, score: score)
        }
    }

    private func commitPendingCameraSelection() {
        guard pendingCameraCommitTask == nil else { return }

        cancelPendingCameraMiss()
        cancelDelayedCameraRecognition()
        pendingCameraCommit = false
        pendingCameraDragRects.removeAll()
        pendingCameraStrokeID = nil
        recognitionStartedStrokeID = nil
        pendingCameraSelectionMode = nil
        setCameraFeedbackPhase(.saving)
        cameraScanner.stopSwipeRecognition(clearResults: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        pendingCameraCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            activeHighlighterPoints.removeAll()
            pendingCameraCommitTask = nil
            setCameraFeedbackPhase(.idle)
            onCommit()
            cameraScanner.clearFrozenFrame()
        }
    }

    private func cancelPendingCameraCommit() {
        pendingCameraCommitTask?.cancel()
        pendingCameraCommitTask = nil
    }

    private func startDelayedCameraRecognition(for strokeID: Int, profile: CameraRecognitionProfile) {
        cancelDelayedCameraRecognition()
        delayedCameraRecognitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: profile.startDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard pendingCameraCommit, pendingCameraStrokeID == strokeID else { return }
            recognitionStartedStrokeID = strokeID
            cameraRecognitionAttemptCount += 1
            cameraScanner.start()
            setCameraFeedbackPhase(.reading)
            captureMetricsLogger.info(
                "camera_ar_recognition_started stroke_id=\(strokeID, privacy: .public) warmup=\(profile.isWarmup, privacy: .public) frozen=\((cameraScanner.frozenFrameImage != nil), privacy: .public) delay_ms=\(profile.startDelayMilliseconds, privacy: .public) duration_ms=\(profile.durationMilliseconds, privacy: .public) max_frames=\(profile.maxFrames, privacy: .public) min_frame_gap_ms=\(profile.minimumFrameIntervalMilliseconds, privacy: .public)"
            )
            if cameraScanner.frozenFrameImage != nil {
                cameraScanner.beginFrozenFrameRecognition()
            } else {
                cameraScanner.beginSwipeRecognition(
                    duration: profile.duration,
                    maxFrames: profile.maxFrames,
                    minimumFrameInterval: profile.minimumFrameInterval
                )
            }
        }
    }

    private func cancelDelayedCameraRecognition() {
        delayedCameraRecognitionTask?.cancel()
        delayedCameraRecognitionTask = nil
    }

    private func schedulePendingCameraMiss(
        in size: CGSize,
        strokeID: Int,
        profile: CameraRecognitionProfile
    ) {
        guard pendingCameraMissTask == nil else { return }

        pendingCameraMissTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(profile.timeout)

            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                guard pendingCameraCommit, pendingCameraStrokeID == strokeID else {
                    pendingCameraMissTask = nil
                    return
                }

                if recognitionStartedStrokeID == strokeID, cameraScanner.recognitionUpdateCount > 0 {
                    resolvePendingCameraSelection(in: size)
                    guard pendingCameraCommit, selectedCameraLineIDs.isEmpty else {
                        pendingCameraMissTask = nil
                        return
                    }
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }

            guard !Task.isCancelled else { return }
            guard pendingCameraCommit, pendingCameraStrokeID == strokeID, selectedCameraLineIDs.isEmpty else {
                pendingCameraMissTask = nil
                return
            }

            captureMetricsLogger.info(
                "camera_ar_miss stroke_id=\(strokeID, privacy: .public) mode=\((pendingCameraSelectionMode ?? .line).rawValue, privacy: .public) warmup=\(profile.isWarmup, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) line_count=\(cameraScanner.lines.count, privacy: .public) gesture_bounds=\(debugRectDescription(boundingRect(for: activeHighlighterPoints)), privacy: .public) ocr=\(debugLineGeometrySummary(cameraScanner.lines, in: size), privacy: .public)"
            )
            pendingCameraCommit = false
            pendingCameraDragRects.removeAll()
            activeHighlighterPoints.removeAll()
            cameraScanner.clearFrozenFrame()
            pendingCameraMissTask = nil
            pendingCameraStrokeID = nil
            recognitionStartedStrokeID = nil
            pendingCameraSelectionMode = nil
            setCameraFeedbackPhase(.idle)
            cameraScanner.stopSwipeRecognition()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onMiss()
        }
    }

    private func cancelPendingCameraMiss() {
        pendingCameraMissTask?.cancel()
        pendingCameraMissTask = nil
    }

    private func beginCameraStroke(at point: CGPoint, in size: CGSize) {
        cancelPendingCameraCommit()
        cancelPendingCameraMiss()
        cancelDelayedCameraRecognition()
        cameraScanner.stopSwipeRecognition()
        cameraScanner.start()
        cameraScanner.freezeNextFrame()
        activeCameraStrokeID += 1
        onHighlighterGestureActiveChanged(true)
        pendingCameraCommit = false
        pendingCameraStrokeID = nil
        recognitionStartedStrokeID = nil
        pendingCameraSelectionMode = nil
        setCameraFeedbackPhase(.drawing)
        pendingCameraDragRects.removeAll()
        selectedCameraLineIDs.removeAll()
        activeHighlighterPoints = [point]
    }

    private func setCameraFeedbackPhase(_ phase: CameraCaptureFeedbackPhase) {
        guard cameraFeedbackPhase != phase else { return }

        withAnimation(.smooth(duration: 0.22, extraBounce: 0.03)) {
            cameraFeedbackPhase = phase
        }
    }

    private func cameraRecognitionProfile() -> CameraRecognitionProfile {
        let isWarmup = cameraRecognitionAttemptCount < 2
        return isWarmup ? .warmup : .normal
    }

    private func appendHighlighterPoint(_ point: CGPoint, previousLocation: CGPoint?, in size: CGSize) {
        if activeHighlighterPoints.isEmpty, let previousLocation {
            activeHighlighterPoints.append(previousLocation)
        }

        guard activeHighlighterPoints.last.map({ distance(from: $0, to: point) > 3 }) ?? true else {
            return
        }

        activeHighlighterPoints.append(point)
        if activeHighlighterPoints.count > 220 {
            activeHighlighterPoints.removeFirst(activeHighlighterPoints.count - 220)
        }
    }

    private func distance(from firstPoint: CGPoint, to secondPoint: CGPoint) -> CGFloat {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }

    private func cameraStrokeScore(for line: CameraRecognizedTextLine, in size: CGSize) -> CGFloat? {
        let lineRect = line.displayRect(in: size)

        guard !activeHighlighterPoints.isEmpty else {
            let expandedLineRect = lineRect.insetBy(dx: -12, dy: -12)
            return pendingCameraDragRects.contains { expandedLineRect.intersects($0) } ? 0.32 : nil
        }

        if let axis = cameraStrokeAxis() {
            return directionalCameraStrokeScore(for: line, in: size, axis: axis)
        }

        let verticalAllowance = max(lineRect.height * 0.95, 14)
        let horizontalAllowance = max(lineRect.height * 0.9, 12)
        let matchingRect = lineRect.insetBy(dx: -horizontalAllowance, dy: -verticalAllowance)
        let gestureBounds = boundingRect(for: activeHighlighterPoints).insetBy(dx: -8, dy: -8)

        guard matchingRect.intersects(gestureBounds) else { return nil }

        let nearbyPoints = activeHighlighterPoints.filter { point in
            matchingRect.contains(point)
                || (point.x >= matchingRect.minX && point.x <= matchingRect.maxX && abs(point.y - lineRect.midY) <= verticalAllowance)
        }

        guard !nearbyPoints.isEmpty else { return nil }

        let nearestDistance = nearbyPoints
            .map { abs($0.y - lineRect.midY) }
            .min() ?? .greatestFiniteMagnitude
        guard nearestDistance <= verticalAllowance else { return nil }

        let strokeRange = horizontalRange(for: nearbyPoints)
        let lineRange = lineRect.minX...lineRect.maxX
        let overlap = max(min(strokeRange.upperBound, lineRange.upperBound) - max(strokeRange.lowerBound, lineRange.lowerBound), 0)
        let overlapRatio = min(overlap / max(lineRect.width, 1), 1)
        let pointRatio = min(CGFloat(nearbyPoints.count) / max(CGFloat(activeHighlighterPoints.count), 1), 1)
        let closeness = 1 - min(nearestDistance / max(verticalAllowance, 1), 1)
        let score = overlapRatio * 0.62 + closeness * 0.28 + pointRatio * 0.10

        guard score >= 0.28 else { return nil }
        return score
    }

    private func directionalCameraStrokeScore(for line: CameraRecognizedTextLine, in size: CGSize, axis: CameraStrokeAxis) -> CGFloat? {
        let samplePoints = line.displaySamplePoints(in: size)
        let lineProjection = projectionRange(for: samplePoints, axis: axis)
        let perpendicularAllowance = max(line.displayThickness(in: size) * 1.42, 18)
        let minimumLineWidth = max(lineProjection.upperBound - lineProjection.lowerBound, 1)
        let overlap = max(
            min(axis.projectionRange.upperBound, lineProjection.upperBound) -
                max(axis.projectionRange.lowerBound, lineProjection.lowerBound),
            0
        )
        let overlapRatio = min(overlap / minimumLineWidth, 1)

        guard overlapRatio > 0.07 else { return nil }

        let nearestDistance = samplePoints
            .map { abs(axis.perpendicularDistance(to: $0)) }
            .min() ?? .greatestFiniteMagnitude
        guard nearestDistance <= perpendicularAllowance else { return nil }

        let expandedLineProjection = (lineProjection.lowerBound - 12)...(lineProjection.upperBound + 12)
        let nearbyPoints = activeHighlighterPoints.filter { point in
            expandedLineProjection.contains(axis.projection(of: point)) &&
                abs(axis.perpendicularDistance(to: point)) <= perpendicularAllowance
        }
        guard !nearbyPoints.isEmpty else { return nil }

        let pointRatio = min(CGFloat(nearbyPoints.count) / max(CGFloat(activeHighlighterPoints.count), 1), 1)
        let closeness = 1 - min(nearestDistance / perpendicularAllowance, 1)
        let pageDirectionScore: CGFloat = 0.72
        let score = overlapRatio * 0.50 + closeness * 0.30 + pointRatio * 0.12 + pageDirectionScore * 0.08

        guard score >= 0.30 else { return nil }
        return score
    }

    private func selectedMatches(from matches: [CameraStrokeLineMatch], allowsMultiple: Bool) -> [CameraStrokeLineMatch] {
        let sortedMatches = matches.sorted { $0.score > $1.score }
        guard let bestMatch = sortedMatches.first else { return [] }
        guard bestMatch.score >= 0.40 else { return [] }

        guard allowsMultiple, isMultiLineCameraGestureLikely() else {
            return [bestMatch]
        }

        let cutoff = max(0.42, bestMatch.score * 0.86)
        return sortedMatches
            .prefix(3)
            .filter { $0.score >= cutoff }
    }

    private func selectedLineMatches(from matches: [CameraStrokeLineMatch]) -> [CameraStrokeLineMatch] {
        let sortedMatches = matches.sorted { $0.score > $1.score }
        guard let bestMatch = sortedMatches.first, bestMatch.score >= 0.40 else { return [] }

        let cutoff = max(0.38, bestMatch.score * 0.74)
        return Array(sortedMatches.filter { $0.score >= cutoff }.prefix(8))
    }

    private func cameraGestureSelectionMode(in size: CGSize) -> CameraGestureSelectionMode {
        let points = selectionGesturePoints(in: size)
        guard points.count >= 8 else { return .line }

        let bounds = boundingRect(for: points)
        let minimumDimension = min(bounds.width, bounds.height)
        let maximumDimension = max(bounds.width, bounds.height)
        guard bounds.width >= 64, bounds.height >= 38, minimumDimension / max(maximumDimension, 1) >= 0.18 else {
            return .line
        }

        let length = pathLength(for: points)
        let closureDistance = points.first.flatMap { firstPoint in
            points.last.map { distance(from: firstPoint, to: $0) }
        } ?? .greatestFiniteMagnitude
        let closedLoop = closureDistance <= max(minimumDimension * 0.78, 42)
        let hasLoopLength = length >= maximumDimension * 2.05
        let boxedArea = gestureTouchesRegionEdges(points, in: bounds) && length >= maximumDimension * 2.2

        return (hasLoopLength && (closedLoop || boxedArea)) ? .region : .line
    }

    private func cameraRegionSelectionContains(line: CameraRecognizedTextLine, in size: CGSize) -> Bool {
        let points = selectionGesturePoints(in: size)
        guard points.count >= 3 else { return false }

        let bounds = boundingRect(for: points).insetBy(dx: -10, dy: -10)
        let lineRect = line.displayRect(in: size)
        guard bounds.intersects(lineRect) else { return false }

        let center = CGPoint(x: lineRect.midX, y: lineRect.midY)
        let samplePoints = line.displaySamplePoints(in: size) + [center]
        let insidePolygon = samplePoints.contains { point in
            bounds.contains(point) && pointInPolygon(point, polygon: points)
        }

        if insidePolygon {
            return true
        }

        return bounds.contains(center) && gestureTouchesRegionEdges(points, in: bounds.insetBy(dx: 10, dy: 10))
    }

    private func selectionGesturePoints(in size: CGSize) -> [CGPoint] {
        activeHighlighterPoints
    }

    private func correctedHighlighterPoints(
        _ points: [CGPoint],
        mode: CameraGestureSelectionMode
    ) -> [CGPoint] {
        guard points.count >= 2 else { return points }

        switch mode {
        case .line:
            return correctedLinePoints(from: points)
        case .region:
            return correctedRegionPoints(from: points)
        }
    }

    private func correctedLinePoints(from points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let centroid = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        .divided(by: CGFloat(points.count))

        let covariance = points.reduce((xx: CGFloat.zero, yy: CGFloat.zero, xy: CGFloat.zero)) { partial, point in
            let dx = point.x - centroid.x
            let dy = point.y - centroid.y
            return (
                xx: partial.xx + dx * dx,
                yy: partial.yy + dy * dy,
                xy: partial.xy + dx * dy
            )
        }

        let angle = 0.5 * atan2(2 * covariance.xy, covariance.xx - covariance.yy)
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let projections = points.map { point in
            (point.x - centroid.x) * direction.x + (point.y - centroid.y) * direction.y
        }
        let minProjection = projections.min() ?? 0
        let maxProjection = projections.max() ?? 0
        let extensionLength: CGFloat = 8

        let start = CGPoint(
            x: centroid.x + direction.x * (minProjection - extensionLength),
            y: centroid.y + direction.y * (minProjection - extensionLength)
        )
        let end = CGPoint(
            x: centroid.x + direction.x * (maxProjection + extensionLength),
            y: centroid.y + direction.y * (maxProjection + extensionLength)
        )

        return [start, end]
    }

    private func correctedRegionPoints(from points: [CGPoint]) -> [CGPoint] {
        let bounds = boundingRect(for: points).insetBy(dx: -6, dy: -6)
        guard bounds.width > 0, bounds.height > 0 else { return points }

        if shouldCorrectRegionAsOval(points, bounds: bounds) {
            return ellipsePoints(in: bounds)
        }

        return rectanglePoints(in: bounds)
    }

    private func shouldCorrectRegionAsOval(_ points: [CGPoint], bounds: CGRect) -> Bool {
        guard points.count >= 12, bounds.width > 0, bounds.height > 0 else { return false }

        let aspectRatio = max(bounds.width, bounds.height) / max(min(bounds.width, bounds.height), 1)
        guard aspectRatio <= 1.85 else { return false }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let halfWidth = max(bounds.width / 2, 1)
        let halfHeight = max(bounds.height / 2, 1)
        let cornerLikeCount = points.filter { point in
            let normalizedX = abs((point.x - center.x) / halfWidth)
            let normalizedY = abs((point.y - center.y) / halfHeight)
            return normalizedX > 0.72 && normalizedY > 0.72
        }
        .count
        let cornerRatio = CGFloat(cornerLikeCount) / CGFloat(points.count)

        return cornerRatio < 0.18
    }

    private func rectanglePoints(in bounds: CGRect) -> [CGPoint] {
        [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.minY)
        ]
    }

    private func ellipsePoints(in bounds: CGRect) -> [CGPoint] {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radiusX = bounds.width / 2
        let radiusY = bounds.height / 2
        let segmentCount = 40

        return (0...segmentCount).map { index in
            let angle = CGFloat(index) / CGFloat(segmentCount) * .pi * 2
            return CGPoint(
                x: center.x + cos(angle) * radiusX,
                y: center.y + sin(angle) * radiusY
            )
        }
    }

    private func pathLength(for points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(CGFloat.zero) { partial, pair in
            partial + distance(from: pair.0, to: pair.1)
        }
    }

    private func gestureTouchesRegionEdges(_ points: [CGPoint], in bounds: CGRect) -> Bool {
        let edgeBand = max(min(bounds.width, bounds.height) * 0.22, 14)
        let touchesLeft = points.contains { abs($0.x - bounds.minX) <= edgeBand }
        let touchesRight = points.contains { abs($0.x - bounds.maxX) <= edgeBand }
        let touchesTop = points.contains { abs($0.y - bounds.minY) <= edgeBand }
        let touchesBottom = points.contains { abs($0.y - bounds.maxY) <= edgeBand }

        return touchesLeft && touchesRight && touchesTop && touchesBottom
    }

    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var isInside = false
        var previousIndex = polygon.count - 1

        for currentIndex in polygon.indices {
            let currentPoint = polygon[currentIndex]
            let previousPoint = polygon[previousIndex]
            let crossesY = (currentPoint.y > point.y) != (previousPoint.y > point.y)

            if crossesY {
                let denominator = previousPoint.y - currentPoint.y
                if abs(denominator) > 0.001 {
                    let intersectX = (previousPoint.x - currentPoint.x) * (point.y - currentPoint.y) / denominator + currentPoint.x
                    if point.x < intersectX {
                        isInside.toggle()
                    }
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }

    private func isMultiLineCameraGestureLikely() -> Bool {
        guard let axis = cameraStrokeAxis(), activeHighlighterPoints.count >= 4 else {
            return false
        }

        let perpendicularDistances = activeHighlighterPoints.map { axis.perpendicularDistance(to: $0) }
        let minDistance = perpendicularDistances.min() ?? 0
        let maxDistance = perpendicularDistances.max() ?? minDistance
        let perpendicularSpread = maxDistance - minDistance
        let verticalSpread = boundingRect(for: activeHighlighterPoints).height

        return perpendicularSpread >= 32 || verticalSpread >= 48
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let firstPoint = points.first else { return .zero }

        return points.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    private func horizontalRange(for points: [CGPoint]) -> ClosedRange<CGFloat> {
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? minX
        return minX...maxX
    }

    private func cameraStrokeAxis() -> CameraStrokeAxis? {
        guard
            let firstPoint = activeHighlighterPoints.first,
            let lastPoint = activeHighlighterPoints.last
        else {
            return nil
        }

        let dx = lastPoint.x - firstPoint.x
        let dy = lastPoint.y - firstPoint.y
        let length = hypot(dx, dy)
        guard length >= 14 else { return nil }

        let direction = CGVector(dx: dx / length, dy: dy / length)
        let projections = activeHighlighterPoints.map { point in
            (point.x - firstPoint.x) * direction.dx + (point.y - firstPoint.y) * direction.dy
        }
        let minProjection = projections.min() ?? 0
        let maxProjection = projections.max() ?? length

        return CameraStrokeAxis(
            origin: firstPoint,
            direction: direction,
            projectionRange: minProjection...maxProjection
        )
    }

    private func projectionRange(for points: [CGPoint], axis: CameraStrokeAxis) -> ClosedRange<CGFloat> {
        let projections = points.map { axis.projection(of: $0) }
        let minProjection = projections.min() ?? 0
        let maxProjection = projections.max() ?? minProjection
        return minProjection...maxProjection
    }

    private func dragRect(from previousLocation: CGPoint?, to location: CGPoint) -> CGRect {
        guard let previousLocation else {
            return CGRect(origin: location, size: .zero).insetBy(dx: -6, dy: -6)
        }

        let minX = min(previousLocation.x, location.x)
        let maxX = max(previousLocation.x, location.x)
        let minY = min(previousLocation.y, location.y)
        let maxY = max(previousLocation.y, location.y)

        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
        .insetBy(dx: -8, dy: -10)
    }

    private func debugSizeDescription(_ size: CGSize) -> String {
        String(format: "%.0fx%.0f", Double(size.width), Double(size.height))
    }

    private func debugRectDescription(_ rect: CGRect) -> String {
        guard !rect.isNull, !rect.isInfinite else { return "-" }

        return String(
            format: "x%.1f,y%.1f,w%.1f,h%.1f",
            Double(rect.minX),
            Double(rect.minY),
            Double(rect.width),
            Double(rect.height)
        )
    }

    private func debugLineGeometrySummary(
        _ lines: [CameraRecognizedTextLine],
        in size: CGSize,
        limit: Int = 4
    ) -> String {
        guard !lines.isEmpty else { return "-" }

        return lines
            .prefix(limit)
            .map { line in
                let confidence = Int((line.confidence * 100).rounded())
                return "#\(line.readingIndex)@\(debugRectDescription(line.displayRect(in: size))):c\(confidence)"
            }
            .joined(separator: ";")
    }

    private func debugScoreSummary(
        _ matches: [CameraStrokeLineMatch],
        lines: [CameraRecognizedTextLine],
        in size: CGSize,
        limit: Int = 5
    ) -> String {
        guard !matches.isEmpty else { return "-" }

        let linesByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
        return matches
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { match in
                guard let line = linesByID[match.id] else {
                    return String(format: "?:s%.2f", Double(match.score))
                }

                return String(
                    format: "#%d:s%.2f@%@",
                    line.readingIndex,
                    Double(match.score),
                    debugRectDescription(line.displayRect(in: size))
                )
            }
            .joined(separator: ";")
    }
}

private extension CGPoint {
    func divided(by value: CGFloat) -> CGPoint {
        guard value != 0 else { return self }
        return CGPoint(x: x / value, y: y / value)
    }
}

private enum CaptureStageMetrics {
    static let focusHorizontalPadding: CGFloat = 26
    static let focusTopPadding: CGFloat = 46
    static let focusBottomPadding: CGFloat = 30

    static func focusRect(in size: CGSize) -> CGRect {
        CGRect(
            x: focusHorizontalPadding,
            y: focusTopPadding,
            width: max(size.width - focusHorizontalPadding * 2, 0),
            height: max(size.height - focusTopPadding - focusBottomPadding, 0)
        )
    }
}

private struct PaperPage: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.overlinePaper)

            VStack(spacing: 11) {
                ForEach(0..<15, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 4) ? Color.overlineCoral.opacity(0.16) : Color.overlineInk.opacity(0.07))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.overlineCoral.opacity(0.22))
                .frame(width: 2)
                .padding(.leading, 28)
                .padding(.vertical, 16)
        }
    }
}

private struct CapturedLine: View {
    let text: String
    let weight: Font.Weight
    let isSelected: Bool
    let tone: StickyTone

    var body: some View {
        Text(text)
            .font(.system(size: weight == .semibold ? 21 : 16, weight: weight, design: .serif))
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .foregroundStyle(Color.overlineInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(tone.paper.opacity(0.42))
                        .frame(height: 12)
                        .offset(y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }
}

private struct ConfirmedCameraHighlightOverlay: View {
    let lines: [CameraRecognizedTextLine]
    let tone: StickyTone

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard !lines.isEmpty else { return }

                var glowContext = context
                glowContext.addFilter(.blur(radius: 3.2))

                let highlightContext = context

                for line in lines {
                    let path = confirmedHighlightPath(for: line, in: size)
                    glowContext.fill(
                        path,
                        with: .color(tone.paper.opacity(0.08))
                    )
                    highlightContext.fill(
                        path,
                        with: .color(tone.paper.opacity(0.20))
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func confirmedHighlightPath(for line: CameraRecognizedTextLine, in size: CGSize) -> Path {
        if let corners = line.quadrilateral?.displayCorners(in: size), corners.count == 4 {
            return centeredHighlightBand(corners, thickness: line.displayThickness(in: size))
        }

        let lineRect = line.displayRect(in: size)
        let bandHeight = min(max(lineRect.height * 0.56, 9), 18)
        let rect = CGRect(
            x: lineRect.minX - 6,
            y: lineRect.midY - bandHeight / 2,
            width: lineRect.width + 12,
            height: bandHeight
        )
        return Path(roundedRect: rect, cornerRadius: max(bandHeight * 0.48, 4))
    }

    private func centeredHighlightBand(_ corners: [CGPoint], thickness: CGFloat) -> Path {
        let leftMidpoint = midpoint(corners[0], corners[3])
        let rightMidpoint = midpoint(corners[1], corners[2])
        let dx = rightMidpoint.x - leftMidpoint.x
        let dy = rightMidpoint.y - leftMidpoint.y
        let length = max(hypot(dx, dy), 0.001)
        let direction = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let halfHeight = min(max(thickness * 0.34, 4.5), 9)
        let extensionLength = min(max(thickness * 0.18, 3), 7)
        let start = CGPoint(
            x: leftMidpoint.x - direction.x * extensionLength,
            y: leftMidpoint.y - direction.y * extensionLength
        )
        let end = CGPoint(
            x: rightMidpoint.x + direction.x * extensionLength,
            y: rightMidpoint.y + direction.y * extensionLength
        )
        let bandCorners = [
            CGPoint(x: start.x + normal.x * halfHeight, y: start.y + normal.y * halfHeight),
            CGPoint(x: end.x + normal.x * halfHeight, y: end.y + normal.y * halfHeight),
            CGPoint(x: end.x - normal.x * halfHeight, y: end.y - normal.y * halfHeight),
            CGPoint(x: start.x - normal.x * halfHeight, y: start.y - normal.y * halfHeight)
        ]

        return Path { path in
            guard let firstPoint = bandCorners.first else { return }
            path.move(to: firstPoint)
            bandCorners.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }

    private func midpoint(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (firstPoint.x + secondPoint.x) / 2,
            y: (firstPoint.y + secondPoint.y) / 2
        )
    }
}

private struct LiveHighlighterStrokeOverlay: View {
    let points: [CGPoint]
    let tone: StickyTone

    var body: some View {
        GeometryReader { _ in
            let renderPoints = points

            if renderPoints.count > 1 {
                let simplifiedPoints = simplifiedStrokePoints(renderPoints)
                let width = highlighterWidth(for: renderPoints)
                let path = smoothPath(simplifiedPoints)
                let mainRibbonPath = ribbonPath(for: simplifiedPoints, width: width)
                let glowRibbonPath = ribbonPath(for: simplifiedPoints, width: width * 1.12)

                ZStack {
                    glowRibbonPath
                        .fill(tone.paper.opacity(0.08))

                    mainRibbonPath
                        .fill(tone.paper.opacity(0.24))

                    path
                        .stroke(
                            tone.paper.opacity(0.06),
                            style: StrokeStyle(lineWidth: max(width * 0.48, 6), lineCap: .butt, lineJoin: .round)
                        )

                    path
                        .offsetBy(dx: 0, dy: -width * 0.12)
                        .stroke(
                            Color.white.opacity(0.025),
                            style: StrokeStyle(lineWidth: max(width * 0.12, 1.6), lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func highlighterWidth(for points: [CGPoint]) -> CGFloat {
        17
    }

    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])

        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }

        if let last = points.last {
            path.addLine(to: last)
        }

        return path
    }

    private func simplifiedStrokePoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }

        return points.reduce(into: [CGPoint]()) { result, point in
            guard let lastPoint = result.last else {
                result.append(point)
                return
            }

            if hypot(lastPoint.x - point.x, lastPoint.y - point.y) >= 4 {
                result.append(point)
            }
        }
    }

    private func ribbonPath(for points: [CGPoint], width: CGFloat) -> Path {
        guard points.count > 1 else { return Path() }

        let halfWidth = width / 2
        let leftEdge = points.indices.map { index in
            let normal = strokeNormal(at: index, in: points)
            return CGPoint(
                x: points[index].x + normal.x * halfWidth,
                y: points[index].y + normal.y * halfWidth
            )
        }
        let rightEdge = points.indices.map { index in
            let normal = strokeNormal(at: index, in: points)
            return CGPoint(
                x: points[index].x - normal.x * halfWidth,
                y: points[index].y - normal.y * halfWidth
            )
        }

        return Path { path in
            guard let firstPoint = leftEdge.first else { return }
            path.move(to: firstPoint)
            leftEdge.dropFirst().forEach { path.addLine(to: $0) }
            rightEdge.reversed().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }

    private func strokeNormal(at index: Int, in points: [CGPoint]) -> CGPoint {
        let previousPoint = points[max(index - 1, 0)]
        let nextPoint = points[min(index + 1, points.count - 1)]
        let dx = nextPoint.x - previousPoint.x
        let dy = nextPoint.y - previousPoint.y
        let length = max(hypot(dx, dy), 0.001)
        return CGPoint(x: -dy / length, y: dx / length)
    }
}

private struct CameraStrokeLineMatch {
    let id: CameraRecognizedTextLine.ID
    let score: CGFloat
}

private enum CameraCaptureFeedbackPhase: Equatable {
    case idle
    case drawing
    case holding
    case reading
    case saving

    var isVisible: Bool {
        switch self {
        case .holding, .reading, .saving:
            return true
        case .idle, .drawing:
            return false
        }
    }

    var text: String {
        switch self {
        case .idle, .drawing:
            return ""
        case .holding:
            return "잠시 그대로 있어 주세요"
        case .reading:
            return "글조각 읽는 중"
        case .saving:
            return "저장하는 중"
        }
    }

    var systemImage: String {
        switch self {
        case .idle, .drawing:
            return "sparkles"
        case .holding:
            return "hand.raised"
        case .reading:
            return "text.viewfinder"
        case .saving:
            return "checkmark.circle"
        }
    }

    var showsProgress: Bool {
        switch self {
        case .reading, .saving:
            return true
        case .idle, .drawing, .holding:
            return false
        }
    }
}

private struct CameraCaptureFeedbackPill: View {
    let phase: CameraCaptureFeedbackPhase

    var body: some View {
        if phase.isVisible {
            HStack(spacing: 8) {
                if phase.showsProgress {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.78))
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: phase.systemImage)
                        .font(.caption.weight(.semibold))
                        .frame(width: 16, height: 16)
                }

                Text(phase.text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .cameraCaptureFeedbackSurface()
            .transition(
                .move(edge: .bottom)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.96))
            )
            .accessibilityLabel(phase.text)
        }
    }
}

private extension View {
    @ViewBuilder
    func cameraCaptureFeedbackSurface() -> some View {
        if #available(iOS 26.0, *) {
            self
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.16))
                }
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.10)),
                    in: .rect(cornerRadius: 24)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
        }
    }
}

private enum CameraGestureSelectionMode: String {
    case line
    case region
}

private struct CameraRecognitionProfile {
    let isWarmup: Bool
    let startDelay: TimeInterval
    let duration: TimeInterval
    let timeout: TimeInterval
    let maxFrames: Int
    let minimumFrameInterval: TimeInterval

    var startDelayNanoseconds: UInt64 {
        UInt64(startDelay * 1_000_000_000)
    }

    var startDelayMilliseconds: Int {
        Int((startDelay * 1000).rounded())
    }

    var durationMilliseconds: Int {
        Int((duration * 1000).rounded())
    }

    var minimumFrameIntervalMilliseconds: Int {
        Int((minimumFrameInterval * 1000).rounded())
    }

    static let warmup = CameraRecognitionProfile(
        isWarmup: true,
        startDelay: 0.34,
        duration: 4.0,
        timeout: 4.35,
        maxFrames: 8,
        minimumFrameInterval: 0.30
    )

    static let normal = CameraRecognitionProfile(
        isWarmup: false,
        startDelay: 0.16,
        duration: 2.6,
        timeout: 2.95,
        maxFrames: 5,
        minimumFrameInterval: 0.24
    )
}

private struct CameraStrokeAxis {
    let origin: CGPoint
    let direction: CGVector
    let projectionRange: ClosedRange<CGFloat>

    func projection(of point: CGPoint) -> CGFloat {
        (point.x - origin.x) * direction.dx + (point.y - origin.y) * direction.dy
    }

    func perpendicularDistance(to point: CGPoint) -> CGFloat {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return dx * (-direction.dy) + dy * direction.dx
    }
}

private enum CaptureMessage: Equatable {
    case processing
    case saved(lineCount: Int, confidence: Float?, durationMilliseconds: Int?)
    case guidance(String)
    case error(String)

    var systemImage: String {
        switch self {
        case .processing:
            return "text.viewfinder"
        case .saved:
            return "checkmark.circle.fill"
        case .guidance:
            return "hand.draw"
        case .error:
            return "exclamationmark.circle"
        }
    }

    var text: String {
        switch self {
        case .processing:
            return "글조각 정리 중"
        case .saved(let lineCount, let confidence, let durationMilliseconds):
            var parts = ["글조각 저장됨"]
            if lineCount > 0 {
                parts.append("\(lineCount)줄")
            }
            if let durationMilliseconds, durationMilliseconds > 0 {
                let seconds = Double(durationMilliseconds) / 1000
                parts.append("\(seconds.formatted(.number.precision(.fractionLength(1))))초")
            }
            if let confidence {
                parts.append("신뢰도 \(Int((confidence * 100).rounded()))%")
                if confidence < 0.55 {
                    parts.append("검수 필요")
                }
            }
            return parts.joined(separator: " · ")
        case .guidance(let message):
            return message
        case .error(let message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .processing:
            return Color.overlineAccent
        case .saved:
            return Color.overlineAccent
        case .guidance:
            return Color.overlineMutedInk
        case .error:
            return Color.overlineCoral
        }
    }
}

private struct CaptureStatusStrip: View {
    let message: CaptureMessage

    var body: some View {
        Label(message.text, systemImage: message.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(message.color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.46), lineWidth: 1)
            }
    }
}

private struct CameraHUD: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let scannerStatus: CameraScannerStatus
    let isRecognizingText: Bool
    let isTorchOn: Bool
    let isLowLight: Bool
    let frameBrightness: Float?
    let canToggleTorch: Bool
    let toggleTorch: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            if showsCameraSettingsButton {
                Button(action: openSettings) {
                    HUDIconButton(systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("카메라 권한 설정 열기")
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HUDIconButton(systemImage: "photo")
            }
            .buttonStyle(.plain)
            .disabled(isRecognizingText)
            .accessibilityLabel("사진에서 OCR")

            Button(action: toggleTorch) {
                HUDIconButton(
                    systemImage: torchSystemImage,
                    isActive: isTorchOn || isLowLight,
                    tint: torchTint,
                    isEnabled: canToggleTorch
                )
            }
            .buttonStyle(.plain)
            .disabled(!canToggleTorch)
            .accessibilityLabel(isTorchOn ? "플래시 끄기" : "플래시 켜기")
            .accessibilityValue(torchAccessibilityValue)
        }
    }

    private var showsCameraSettingsButton: Bool {
        guard case .unavailable(let message) = scannerStatus else { return false }
        return message.contains("권한")
    }

    private var torchSystemImage: String {
        isTorchOn ? "bolt.fill" : "bolt.slash.fill"
    }

    private var torchTint: Color {
        if isTorchOn {
            return Color.overlineHighlight
        }
        return .white.opacity(isLowLight ? 0.92 : 0.72)
    }

    private var torchAccessibilityValue: String {
        guard let frameBrightness else {
            return canToggleTorch ? (isTorchOn ? "켜짐" : "꺼짐") : "사용할 수 없음"
        }

        let brightnessPercent = Int((frameBrightness * 100).rounded())
        let torchState = isTorchOn ? "켜짐" : "꺼짐"
        if isLowLight {
            return "\(torchState), 어두움, 밝기 \(brightnessPercent)%"
        }
        return "\(torchState), 밝기 \(brightnessPercent)%"
    }
}

private struct HUDIconButton: View {
    let systemImage: String
    var isActive = false
    var tint: Color = .white
    var isEnabled = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : .white.opacity(0.38))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(isActive ? 0.30 : 0.18), radius: 2, y: 1)
    }
}

private struct MemoComposerCard: View {
    @Binding var memo: String
    let isListening: Bool
    let voiceErrorMessage: String?
    let toggleVoiceMemo: () -> Void
    let quickSave: () -> Void
    let openSettings: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                MemoPaperLines(lineCount: lineCount)

                if memo.isEmpty {
                    Text("떠오른 생각을 바로 적기")
                        .font(.system(size: MemoNoteMetrics.fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.overlineMutedInk.opacity(0.62))
                        .padding(.top, MemoNoteMetrics.textTopInset)
                        .padding(.leading, MemoNoteMetrics.textLeadingInset)
                        .padding(.trailing, MemoNoteMetrics.actionButtonSpace)
                }

                TextEditor(text: $memo)
                    .font(.system(size: MemoNoteMetrics.fontSize, weight: .medium, design: .rounded))
                    .lineSpacing(MemoNoteMetrics.lineSpacing)
                    .foregroundStyle(Color.overlineInk)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: noteHeight - MemoNoteMetrics.editorTopInset)
                    .padding(.top, MemoNoteMetrics.editorTopInset)
                    .padding(.leading, MemoNoteMetrics.editorLeadingInset)
                    .padding(.trailing, MemoNoteMetrics.actionButtonSpace)
                    .accessibilityLabel("Memo")
            }
            .frame(height: noteHeight)

            HStack(spacing: 2) {
                Button(action: toggleVoiceMemo) {
                    Image(systemName: isListening ? "stop.circle.fill" : "mic")
                        .font(.subheadline.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isListening ? Color.overlineCoral.opacity(0.82) : Color.overlineInk.opacity(0.54))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isListening ? "음성 메모 중지" : "음성 메모 시작")

                Button(action: quickSave) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(memo.trimmed.isEmpty ? Color.overlineInk.opacity(0.28) : Color.overlineInk.opacity(0.62))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(memo.trimmed.isEmpty)
                .accessibilityLabel("Save memo")
            }
            .padding(.top, MemoNoteMetrics.actionButtonTopInset)
            .padding(.trailing, MemoNoteMetrics.actionButtonTrailingInset)
            .frame(maxWidth: .infinity, alignment: .topTrailing)

            if let voiceErrorMessage {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(voiceErrorMessage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.overlineCoral)
                        .lineLimit(2)

                    if showsVoiceSettingsButton {
                        Button(action: openSettings) {
                            Label("설정", systemImage: "gearshape")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.overlineInk.opacity(0.66))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("음성 메모 권한 설정 열기")
                    }
                }
                .padding(.leading, MemoNoteMetrics.textLeadingInset)
                .padding(.trailing, MemoNoteMetrics.actionButtonSpace)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.91, blue: 0.48),
                    Color(red: 0.97, green: 0.80, blue: 0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.34))
                .frame(width: 92, height: 14)
                .offset(y: -7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineInk.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.overlineInk.opacity(0.12), radius: 10, y: 5)
        .frame(height: noteHeight)
    }

    private var lineCount: Int {
        let estimatedTypedLines = memo.isEmpty ? 1 : memo
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                max(1, Int(ceil(Double(line.count) / MemoNoteMetrics.charactersPerLine)))
            }
            .reduce(0, +)

        return min(max(estimatedTypedLines + 2, MemoNoteMetrics.minimumLineCount), MemoNoteMetrics.maximumLineCount)
    }

    private var noteHeight: CGFloat {
        MemoNoteMetrics.topInset + MemoNoteMetrics.bottomInset + CGFloat(lineCount) * MemoNoteMetrics.lineHeight
    }

    private var showsVoiceSettingsButton: Bool {
        guard let voiceErrorMessage else { return false }
        return voiceErrorMessage.contains("권한")
    }
}

private struct CaptureMetadataBar: View {
    @Binding var pageReference: String
    @Binding var tagsText: String
    @Binding var selectedTone: StickyTone

    var body: some View {
        HStack(spacing: 4) {
            MetadataField(
                systemImage: "text.book.closed",
                placeholder: "p. 42",
                text: $pageReference,
                minWidth: 58
            )
            .frame(width: 74)

            MetadataField(
                systemImage: "tag",
                placeholder: "#철학 #인용",
                text: $tagsText,
                minWidth: 0
            )
            .frame(maxWidth: .infinity)

            HighlightTonePicker(selectedTone: $selectedTone)
        }
        .padding(.horizontal, 2)
    }
}

private struct MetadataField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let minWidth: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineInk.opacity(0.38))
                .frame(width: 15)

            TextField(placeholder, text: $text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineInk.opacity(0.68))
                .tint(Color.overlineAccent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1)
        }
        .frame(minWidth: minWidth, minHeight: 28)
        .padding(.horizontal, 4)
    }
}

private struct HighlightTonePicker: View {
    @Binding var selectedTone: StickyTone

    private let tones: [StickyTone] = [.yellow, .rose, .blue, .mint]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tones, id: \.self) { tone in
                Button {
                    withAnimation(.smooth(duration: 0.18, extraBounce: 0.04)) {
                        selectedTone = tone
                    }
                } label: {
                    Circle()
                        .fill(tone.paper)
                        .frame(width: selectedTone == tone ? 15 : 12, height: selectedTone == tone ? 15 : 12)
                        .overlay {
                            if selectedTone == tone {
                                Circle()
                                    .stroke(Color.overlineInk.opacity(0.42), lineWidth: 1.4)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tone.accessibilityName) 형광펜")
                .accessibilityAddTraits(selectedTone == tone ? [.isSelected] : [])
            }
        }
        .fixedSize()
    }
}

private struct MemoPaperLines: View {
    let lineCount: Int

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<lineCount, id: \.self) { index in
                let y = MemoNoteMetrics.firstRuleOffset + CGFloat(index) * MemoNoteMetrics.lineHeight

                Path { path in
                    path.move(to: CGPoint(x: MemoNoteMetrics.ruleHorizontalInset, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width - MemoNoteMetrics.ruleHorizontalInset, y: y))
                }
                .stroke(Color.overlineInk.opacity(0.10), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private enum MemoNoteMetrics {
    static let fontSize: CGFloat = 17
    static let lineSpacing: CGFloat = 14
    static let lineHeight: CGFloat = 34
    static let topInset: CGFloat = 18
    static let bottomInset: CGFloat = 20
    static let firstRuleOffset: CGFloat = 49
    static let textTopInset: CGFloat = 30
    static let textLeadingInset: CGFloat = 21
    static let editorTopInset: CGFloat = 17
    static let editorLeadingInset: CGFloat = 13
    static let ruleHorizontalInset: CGFloat = 23
    static let actionButtonSpace: CGFloat = 80
    static let actionButtonTopInset: CGFloat = 10
    static let actionButtonTrailingInset: CGFloat = 12
    static let minimumLineCount = 6
    static let maximumLineCount = 10
    static let charactersPerLine = 22.0
}

private struct SavedHighlightStrip: View {
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.overlineAccent)

            VStack(alignment: .leading, spacing: 5) {
                Text("저장됨")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.overlineInk)
                Text(highlight.text)
                    .font(.caption)
                    .foregroundStyle(Color.overlineMutedInk)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.overlineAccent.opacity(0.24), lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack {
        CaptureView()
            .navigationTitle("캡처")
    }
    .environment(ReadingLibrary.preview)
}
