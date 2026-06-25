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
                    onCommit: commitSelection,
                    onMiss: showCaptureGuidance,
                    openSettings: openAppSettings
                )

                if let captureMessage {
                    CaptureStatusStrip(message: captureMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                CaptureMetadataBar(
                    pageReference: $pageReferenceText,
                    tagsText: $tagsText
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
            cameraScanner.start()
        }
        .onDisappear {
            cameraScanner.stop()
            speechRecorder.cancel()
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

    private func commitSelection() {
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

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            lastSaved = library.addCapturedHighlight(
                text: text,
                memo: memo,
                language: CaptureLanguage.detect(from: text),
                pageReference: liveText.isEmpty ? "p. 42" : (inferredPageReference ?? "Camera"),
                explicitPageReference: pageReferenceText,
                tagsText: tagsText,
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
                tagsText: tagsText
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
            let hasMemo = !memo.trimmed.isEmpty
            let durationMilliseconds = captureElapsedMilliseconds()
            let highlight = library.addCapturedHighlight(
                text: text,
                memo: memo,
                language: CaptureLanguage.detect(from: text),
                pageReference: recognitionResult.inferredPageReference ?? "OCR",
                explicitPageReference: pageReferenceText,
                tagsText: tagsText,
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

    var body: some View {
        Menu {
            ForEach(library.books) { book in
                Button {
                    library.selectBook(book.id)
                } label: {
                    Label(
                        book.title,
                        systemImage: library.selectedBookID == book.id ? "checkmark.circle.fill" : "book.closed"
                    )
                }
            }

            Divider()

            Button(action: openAddBook) {
                Label("책 추가", systemImage: "plus")
            }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.54), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("저장할 책 선택")
    }
}

private struct CaptureStage: View {
    @Binding var selectedLineIDs: Set<Int>
    @Binding var selectedCameraLineIDs: Set<CameraRecognizedTextLine.ID>
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let cameraScanner: CameraTextScanner
    let isRecognizingText: Bool
    let onCommit: () -> Void
    let onMiss: () -> Void
    let openSettings: () -> Void
    @State private var previousDragLocation: CGPoint?
    @State private var pendingCameraDragRects: [CGRect] = []
    @State private var activeHighlighterPoints: [CGPoint] = []
    @State private var activeHighlighterPagePoints: [CGPoint] = []
    @State private var pendingCameraCommit = false
    @State private var pendingCameraCommitTask: Task<Void, Never>?
    @State private var pendingCameraMissTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.12, blue: 0.12))

                if cameraScanner.canUseLiveCamera {
                    CameraPreview(session: cameraScanner.session)
                        .overlay(Color.black.opacity(0.12))

                    CameraPageBoundaryOverlay(page: cameraScanner.detectedPage)

                    ConfirmedCameraHighlightOverlay(
                        lines: cameraScanner.selectedLineSnapshots(for: selectedCameraLineIDs)
                    )

                    LiveHighlighterStrokeOverlay(
                        points: activeHighlighterPoints,
                        pagePoints: activeHighlighterPagePoints,
                        page: cameraScanner.detectedPage
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
                                isSelected: selectedLineIDs.contains(line.id)
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

                if !cameraScanner.canUseLiveCamera || cameraScanner.detectedPage == nil {
                    FocusBracket()
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
                        .padding(.horizontal, CaptureStageMetrics.focusHorizontalPadding)
                        .padding(.top, CaptureStageMetrics.focusTopPadding)
                        .padding(.bottom, CaptureStageMetrics.focusBottomPadding)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .accessibilityLabel("Overline capture preview")
            .onChange(of: cameraScanner.recognitionUpdateCount) { _, _ in
                resolvePendingCameraSelection(in: proxy.size)
            }
            .onChange(of: cameraScanner.isAnalyzingText) { _, isAnalyzing in
                if !isAnalyzing {
                    if pendingCameraCommitTask == nil {
                        let shouldShowMiss = pendingCameraCommit && selectedCameraLineIDs.isEmpty && !activeHighlighterPoints.isEmpty
                        cancelPendingCameraMiss()
                        pendingCameraDragRects.removeAll()
                        activeHighlighterPoints.removeAll()
                        activeHighlighterPagePoints.removeAll()
                        pendingCameraCommit = false
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
            pendingCameraDragRects.removeAll()
            activeHighlighterPoints.removeAll()
            activeHighlighterPagePoints.removeAll()
            pendingCameraCommit = false
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
            pendingCameraCommit = true
            resolvePendingCameraSelection(in: size)
            if !selectedCameraLineIDs.isEmpty {
                commitPendingCameraSelection()
            } else {
                schedulePendingCameraMiss()
            }
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

        let matches = cameraScanner.lines.compactMap { line -> CameraStrokeLineMatch? in
            guard isLineInDetectedPage(line) else { return nil }
            guard let score = cameraStrokeScore(for: line, in: size) else { return nil }
            return CameraStrokeLineMatch(id: line.id, score: score)
        }

        let selectedMatches = selectedMatches(from: matches)
        let selectedIDs = Set(selectedMatches.map(\.id))
        if !selectedIDs.isEmpty {
            cameraScanner.cacheSelectedLines(for: selectedIDs)
            selectedCameraLineIDs = selectedIDs
        }

        if pendingCameraCommit, !selectedCameraLineIDs.isEmpty {
            captureMetricsLogger.info("camera_ar_match line_count=\(selectedCameraLineIDs.count, privacy: .public) candidate_count=\(matches.count, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) multiline=\(isMultiLineCameraGestureLikely(), privacy: .public)")
            commitPendingCameraSelection()
        }
    }

    private func commitPendingCameraSelection() {
        guard pendingCameraCommitTask == nil else { return }

        cancelPendingCameraMiss()
        pendingCameraCommit = false
        pendingCameraDragRects.removeAll()
        cameraScanner.stopSwipeRecognition(clearResults: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        pendingCameraCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }

            activeHighlighterPoints.removeAll()
            activeHighlighterPagePoints.removeAll()
            pendingCameraCommitTask = nil
            onCommit()
        }
    }

    private func cancelPendingCameraCommit() {
        pendingCameraCommitTask?.cancel()
        pendingCameraCommitTask = nil
    }

    private func schedulePendingCameraMiss() {
        guard pendingCameraMissTask == nil else { return }

        let updateCountAtGestureEnd = cameraScanner.recognitionUpdateCount
        pendingCameraMissTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(2.4)

            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                guard pendingCameraCommit, selectedCameraLineIDs.isEmpty else {
                    pendingCameraMissTask = nil
                    return
                }

                if cameraScanner.recognitionUpdateCount > updateCountAtGestureEnd {
                    break
                }
            }

            guard !Task.isCancelled else { return }
            guard pendingCameraCommit, selectedCameraLineIDs.isEmpty else {
                pendingCameraMissTask = nil
                return
            }
            captureMetricsLogger.info("camera_ar_miss update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) line_count=\(cameraScanner.lines.count, privacy: .public)")
            pendingCameraCommit = false
            pendingCameraDragRects.removeAll()
            activeHighlighterPoints.removeAll()
            activeHighlighterPagePoints.removeAll()
            pendingCameraMissTask = nil
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
        pendingCameraCommit = false
        pendingCameraDragRects.removeAll()
        selectedCameraLineIDs.removeAll()
        activeHighlighterPoints = [point]
        if let pagePoint = pageProjection(in: size)?.normalizedPoint(for: point) {
            activeHighlighterPagePoints = [pagePoint]
        } else {
            activeHighlighterPagePoints.removeAll()
        }
        cameraScanner.beginSwipeRecognition(duration: 4.5)
    }

    private func appendHighlighterPoint(_ point: CGPoint, previousLocation: CGPoint?, in size: CGSize) {
        if activeHighlighterPoints.isEmpty, let previousLocation {
            activeHighlighterPoints.append(previousLocation)
        }

        guard activeHighlighterPoints.last.map({ distance(from: $0, to: point) > 3 }) ?? true else {
            return
        }

        activeHighlighterPoints.append(point)
        appendPageAnchoredHighlighterPoint(point, in: size)
        if activeHighlighterPoints.count > 80 {
            activeHighlighterPoints.removeFirst(activeHighlighterPoints.count - 80)
        }
        if activeHighlighterPagePoints.count > 80 {
            activeHighlighterPagePoints.removeFirst(activeHighlighterPagePoints.count - 80)
        }
    }

    private func appendPageAnchoredHighlighterPoint(_ point: CGPoint, in size: CGSize) {
        guard let pagePoint = pageProjection(in: size)?.normalizedPoint(for: point) else {
            return
        }

        guard activeHighlighterPagePoints.last.map({ distance(from: $0, to: pagePoint) > 0.008 }) ?? true else {
            return
        }

        activeHighlighterPagePoints.append(pagePoint)
    }

    private func distance(from firstPoint: CGPoint, to secondPoint: CGPoint) -> CGFloat {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }

    private func isLineInDetectedPage(_ line: CameraRecognizedTextLine) -> Bool {
        guard let page = cameraScanner.detectedPage else { return true }

        let overlap = line.boundingBox.intersection(page.boundingBox)
        guard !overlap.isNull else { return false }

        let lineArea = max(line.boundingBox.width * line.boundingBox.height, 0.0001)
        return (overlap.width * overlap.height) / lineArea >= 0.42
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
        let perpendicularAllowance = max(line.displayThickness(in: size) * 1.08, 14)
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
        let pageDirectionScore = cameraScanner.detectedPage
            .map { pageStrokeDirectionScore(for: $0, in: size, axis: axis) } ?? 0.72
        let score = overlapRatio * 0.50 + closeness * 0.30 + pointRatio * 0.12 + pageDirectionScore * 0.08

        guard score >= 0.30 else { return nil }
        return score
    }

    private func selectedMatches(from matches: [CameraStrokeLineMatch]) -> [CameraStrokeLineMatch] {
        let sortedMatches = matches.sorted { $0.score > $1.score }
        guard let bestMatch = sortedMatches.first else { return [] }

        guard isMultiLineCameraGestureLikely() else {
            return [bestMatch]
        }

        let cutoff = max(0.42, bestMatch.score * 0.86)
        return sortedMatches
            .prefix(3)
            .filter { $0.score >= cutoff }
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

    private func pageStrokeDirectionScore(for page: CameraDetectedPage, in size: CGSize, axis: CameraStrokeAxis) -> CGFloat {
        let corners = page.displayCorners(in: size)
        guard corners.count == 4 else { return 0.72 }

        let topVector = CGVector(
            dx: corners[1].x - corners[0].x,
            dy: corners[1].y - corners[0].y
        )
        let bottomVector = CGVector(
            dx: corners[2].x - corners[3].x,
            dy: corners[2].y - corners[3].y
        )
        let pageVector = CGVector(
            dx: topVector.dx + bottomVector.dx,
            dy: topVector.dy + bottomVector.dy
        )
        let length = hypot(pageVector.dx, pageVector.dy)
        guard length > 0.001 else { return 0.72 }

        let normalizedPageVector = CGVector(dx: pageVector.dx / length, dy: pageVector.dy / length)
        return abs(normalizedPageVector.dx * axis.direction.dx + normalizedPageVector.dy * axis.direction.dy)
    }

    private func pageProjection(in size: CGSize) -> CameraPageProjection? {
        guard let page = cameraScanner.detectedPage else { return nil }
        return CameraPageProjection(page: page, in: size)
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
                        .fill(Color.overlineHighlight.opacity(0.66))
                        .frame(height: 12)
                        .offset(y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }
}

private struct CameraPageBoundaryOverlay: View {
    let page: CameraDetectedPage?

    var body: some View {
        GeometryReader { proxy in
            if let page {
                page.displayPath(in: proxy.size)
                    .stroke(
                        Color.white.opacity(0.66),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [12, 9])
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
                    .padding(1)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: page)
        .allowsHitTesting(false)
    }
}

private struct ConfirmedCameraHighlightOverlay: View {
    let lines: [CameraRecognizedTextLine]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard !lines.isEmpty else { return }

                var highlightContext = context
                highlightContext.blendMode = .plusLighter

                for line in lines {
                    let path = confirmedHighlightPath(for: line, in: size)
                    highlightContext.fill(
                        path,
                        with: .color(Color.overlineHighlight.opacity(0.34))
                    )
                    highlightContext.stroke(
                        path,
                        with: .color(.white.opacity(0.10)),
                        lineWidth: 1.2
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
            return inflatedQuadrilateralPath(corners, amount: max(line.displayThickness(in: size) * 0.22, 3))
        }

        let rect = line.displayRect(in: size).insetBy(dx: -6, dy: -max(line.displayRect(in: size).height * 0.16, 3))
        return Path(roundedRect: rect, cornerRadius: max(rect.height * 0.48, 4))
    }

    private func inflatedQuadrilateralPath(_ corners: [CGPoint], amount: CGFloat) -> Path {
        let center = corners.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x / CGFloat(corners.count), y: partial.y + point.y / CGFloat(corners.count))
        }
        let inflatedCorners = corners.map { point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = max(hypot(dx, dy), 0.001)
            return CGPoint(
                x: point.x + dx / length * amount,
                y: point.y + dy / length * amount
            )
        }

        return Path { path in
            guard let firstPoint = inflatedCorners.first else { return }
            path.move(to: firstPoint)
            inflatedCorners.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }
}

private struct LiveHighlighterStrokeOverlay: View {
    let points: [CGPoint]
    let pagePoints: [CGPoint]
    let page: CameraDetectedPage?

    var body: some View {
        Canvas { context, size in
            let renderPoints = resolvedRenderPoints(in: size)
            guard renderPoints.count > 1 else { return }

            if let page {
                context.clip(to: page.displayPath(in: size))
            }

            let simplifiedPoints = simplifiedStrokePoints(renderPoints)
            let width = highlighterWidth(for: renderPoints)
            let path = smoothPath(simplifiedPoints)
            let ribbonPath = ribbonPath(for: simplifiedPoints, width: width)
            var baseContext = context
            baseContext.blendMode = .plusLighter
            baseContext.fill(
                ribbonPath,
                with: .color(Color.overlineHighlight.opacity(0.42))
            )
            baseContext.stroke(
                path,
                with: .color(Color.overlineHighlight.opacity(0.22)),
                style: StrokeStyle(lineWidth: max(width * 0.62, 8), lineCap: .butt, lineJoin: .round)
            )
            baseContext.stroke(
                path.offsetBy(dx: 0, dy: -width * 0.14),
                with: .color(.white.opacity(0.12)),
                style: StrokeStyle(lineWidth: max(width * 0.16, 2), lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.04), value: points.count + pagePoints.count)
    }

    private func resolvedRenderPoints(in size: CGSize) -> [CGPoint] {
        guard
            let page,
            !pagePoints.isEmpty,
            let projection = CameraPageProjection(page: page, in: size)
        else {
            return points
        }

        return pagePoints.map { projection.displayPoint(for: $0) }
    }

    private func highlighterWidth(for points: [CGPoint]) -> CGFloat {
        let length = zip(points, points.dropFirst())
            .reduce(CGFloat.zero) { partial, pair in
                partial + hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y)
            }
        return min(max(length * 0.025, 13), 22)
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

private struct CameraPageProjection {
    private let topLeft: CGPoint
    private let topRight: CGPoint
    private let bottomRight: CGPoint
    private let bottomLeft: CGPoint
    private let xAxis: CGVector
    private let yAxis: CGVector
    private let determinant: CGFloat

    init?(page: CameraDetectedPage, in size: CGSize) {
        let corners = page.displayCorners(in: size)
        guard corners.count == 4 else { return nil }

        let xAxis = CGVector(
            dx: ((corners[1].x - corners[0].x) + (corners[2].x - corners[3].x)) / 2,
            dy: ((corners[1].y - corners[0].y) + (corners[2].y - corners[3].y)) / 2
        )
        let yAxis = CGVector(
            dx: ((corners[3].x - corners[0].x) + (corners[2].x - corners[1].x)) / 2,
            dy: ((corners[3].y - corners[0].y) + (corners[2].y - corners[1].y)) / 2
        )
        let determinant = xAxis.dx * yAxis.dy - xAxis.dy * yAxis.dx
        guard abs(determinant) > 0.001 else { return nil }

        self.topLeft = corners[0]
        self.topRight = corners[1]
        self.bottomRight = corners[2]
        self.bottomLeft = corners[3]
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.determinant = determinant
    }

    func normalizedPoint(for point: CGPoint) -> CGPoint {
        let dx = point.x - topLeft.x
        let dy = point.y - topLeft.y
        let u = (dx * yAxis.dy - dy * yAxis.dx) / determinant
        let v = (xAxis.dx * dy - xAxis.dy * dx) / determinant

        return CGPoint(
            x: min(max(u, -0.08), 1.08),
            y: min(max(v, -0.08), 1.08)
        )
    }

    func displayPoint(for normalizedPoint: CGPoint) -> CGPoint {
        let top = lerp(topLeft, topRight, normalizedPoint.x)
        let bottom = lerp(bottomLeft, bottomRight, normalizedPoint.x)
        return lerp(top, bottom, normalizedPoint.y)
    }

    private func lerp(_ firstPoint: CGPoint, _ secondPoint: CGPoint, _ progress: CGFloat) -> CGPoint {
        CGPoint(
            x: firstPoint.x + (secondPoint.x - firstPoint.x) * progress,
            y: firstPoint.y + (secondPoint.y - firstPoint.y) * progress
        )
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
            return "OCR 처리 중"
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
        if isTorchOn {
            return "light.max.fill"
        }
        return isLowLight ? "light.min" : "light.max"
    }

    private var torchTint: Color {
        if isTorchOn {
            return .white
        }
        return isLowLight ? Color.overlineHighlight : .white
    }

    private var torchAccessibilityValue: String {
        guard let frameBrightness else {
            return canToggleTorch ? "밝기 측정 전" : "사용할 수 없음"
        }

        let brightnessPercent = Int((frameBrightness * 100).rounded())
        if isLowLight {
            return "어두움, 밝기 \(brightnessPercent)%"
        }
        return "밝기 \(brightnessPercent)%"
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

private struct FocusBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 30

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
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

    var body: some View {
        HStack(spacing: 8) {
            MetadataField(
                systemImage: "text.book.closed",
                placeholder: "p. 42",
                text: $pageReference,
                minWidth: 82
            )
            .frame(width: 106)

            MetadataField(
                systemImage: "tag",
                placeholder: "#철학 #인용",
                text: $tagsText,
                minWidth: 0
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
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
