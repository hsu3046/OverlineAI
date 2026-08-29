import Foundation
import OSLog
import PhotosUI
import SwiftUI
import UIKit

private let captureMetricsLogger = Logger(subsystem: "aib.Overline", category: "CaptureMetrics")

struct CaptureView: View {
    let cameraScanner: CameraTextScanner
    let isActive: Bool

    @Environment(ReadingLibrary.self) private var library
    @Environment(LLMSettingsStore.self) private var llmSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedLineIDs: Set<Int> = []
    @State private var selectedCameraLineIDs: Set<CameraRecognizedTextLine.ID> = []
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var speechRecorder = SpeechMemoRecorder()
    @State private var memo = ""
    @State private var pageReferenceText = ""
    @State private var tagsText = ""
    @State private var composerTagsBaseline = ""
    @State private var memoBeforeSpeech = ""
    @State private var lastSaved: Highlight?
    @State private var amendTargetHighlightID: Highlight.ID?
    @State private var amendDebounceTask: Task<Void, Never>?
    @State private var captureMessage: CaptureMessage?
    @State private var isRecognizingText = false
    @State private var presentedSheet: CaptureSheet?
    @State private var captureScreenOpenedAt = Date()
    @State private var delayedCameraStartTask: Task<Void, Never>?
    @State private var delayedCameraStopTask: Task<Void, Never>?
    @State private var isHighlighterGestureActive = false
    @AppStorage("capture.autoRecognitionEnabled") private var isAutoRecognitionEnabled = true
    @State private var selectedTone: StickyTone = .yellow
    @State private var memoFocusRequest = 0
    @State private var captureExperience: CaptureExperienceMode = .highlight

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 16) {
                    CaptureExperiencePicker(selection: $captureExperience)

                    CaptureBookSelector(
                        library: library,
                        openAddBook: { presentedSheet = .addBook }
                    )

                    CaptureStage(
                        selectedLineIDs: $selectedLineIDs,
                        selectedCameraLineIDs: $selectedCameraLineIDs,
                        selectedPhotoItem: $selectedPhotoItem,
                        isAutoRecognitionEnabled: $isAutoRecognitionEnabled,
                        cameraScanner: cameraScanner,
                        isRecognizingText: isRecognizingText,
                        selectedTone: selectedTone,
                        onCommit: commitSelection,
                        onRestartCapture: startNewCameraCapture,
                        onMiss: showCaptureGuidance,
                        openSettings: openAppSettings,
                        onHighlighterGestureActiveChanged: { isActive in
                            isHighlighterGestureActive = isActive
                        }
                    )

                    if let captureMessage {
                        CaptureStatusStrip(
                            message: captureMessage,
                            deleteAction: canDeleteLastSavedHighlight ? { deleteLastSavedHighlight() } : nil
                        )
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    CaptureMetadataBar(
                        pageReference: $pageReferenceText,
                        tagsText: $tagsText,
                        selectedTone: $selectedTone
                    )

                    MemoComposerCard(
                        memo: $memo,
                        tone: selectedTone,
                        hasPendingCapture: amendTargetHighlightID != nil,
                        canSave: amendTargetHighlightID != nil || !memo.trimmed.isEmpty,
                        focusRequest: memoFocusRequest,
                        isListening: speechRecorder.isRecording,
                        voiceErrorMessage: speechRecorder.errorMessage,
                        toggleVoiceMemo: toggleVoiceMemo,
                        save: saveComposer,
                        openSettings: openAppSettings
                    )

                    Color.clear
                        .frame(height: CaptureViewMetrics.memoKeyboardComfortSpacing)
                        .id(CaptureScrollTarget.memoKeyboardComfort)
                        .accessibilityHidden(true)

                }
                .padding(16)
                .padding(.bottom, 92)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlineBottomMenuCompaction()
            .task(id: selectedPhotoItem) {
                await recognizeSelectedPhoto()
            }
            .onAppear {
                captureScreenOpenedAt = .now
                captureMetricsLogger.info("capture_screen_opened")
                prefillTagsFromSelectedBookIfNeeded()
                if isActive {
                    scheduleCameraStart()
                }
            }
            .onDisappear {
                applyAmendIfNeeded(clearAfterSave: true, showConfirmation: false)
                amendDebounceTask?.cancel()
                amendDebounceTask = nil
                delayedCameraStartTask?.cancel()
                delayedCameraStartTask = nil
                delayedCameraStopTask?.cancel()
                delayedCameraStopTask = nil
                isHighlighterGestureActive = false
                speechRecorder.cancel()
                scheduleCameraStopAfterGrace()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    scheduleCameraStart()
                } else {
                    applyAmendIfNeeded(clearAfterSave: true, showConfirmation: false)
                    delayedCameraStartTask?.cancel()
                    delayedCameraStartTask = nil
                    isHighlighterGestureActive = false
                    speechRecorder.cancel()
                    scheduleCameraStopAfterGrace()
                }
            }
            .onChange(of: speechRecorder.transcript) { _, transcript in
                guard speechRecorder.isRecording else { return }
                memo = mergedSpeechMemo(base: memoBeforeSpeech, transcript: transcript)
            }
            .onChange(of: memo) { _, _ in
                scheduleAmendIfNeeded()
            }
            .onChange(of: pageReferenceText) { _, _ in
                scheduleAmendIfNeeded()
            }
            .onChange(of: tagsText) { _, _ in
                scheduleAmendIfNeeded()
            }
            .onChange(of: selectedTone) { _, _ in
                scheduleAmendIfNeeded()
            }
            .onChange(of: library.selectedBookID) { _, _ in
                prefillTagsFromSelectedBookIfNeeded()
            }
            .onChange(of: memoFocusRequest) { _, _ in
                scrollMemoIntoKeyboardComfort(using: scrollProxy)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if isActive {
                        scheduleCameraStart()
                    }
                } else {
                    applyAmendIfNeeded(clearAfterSave: true, showConfirmation: false)
                    delayedCameraStartTask?.cancel()
                    delayedCameraStartTask = nil
                    delayedCameraStopTask?.cancel()
                    delayedCameraStopTask = nil
                    cameraScanner.stop(clearRecognitionResults: false)
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .addBook:
                    AddBookSheet()
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(isPresented: pageReaderPresentation) {
                PageReaderView(cameraScanner: cameraScanner)
            }
        }
    }

    private var pageReaderPresentation: Binding<Bool> {
        Binding(
            get: { captureExperience == .reader },
            set: { isPresented in
                if !isPresented {
                    captureExperience = .highlight
                }
            }
        )
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
        guard isActive, scenePhase == .active else { return }
        delayedCameraStopTask?.cancel()
        delayedCameraStopTask = nil
        delayedCameraStartTask?.cancel()

        guard isHighlighterGestureActive else {
            delayedCameraStartTask = nil
            cameraScanner.start()
            return
        }

        delayedCameraStartTask = Task { @MainActor in
            while isHighlighterGestureActive {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
            }

            guard isActive, scenePhase == .active else { return }
            cameraScanner.start()
            delayedCameraStartTask = nil
        }
    }

    private func scheduleCameraStopAfterGrace() {
        delayedCameraStopTask?.cancel()
        delayedCameraStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, !isActive else { return }

            cameraScanner.stop(clearRecognitionResults: false)
            delayedCameraStopTask = nil
        }
    }

    private func scrollMemoIntoKeyboardComfort(using scrollProxy: ScrollViewProxy) {
        let requestID = memoFocusRequest
        let target = CaptureScrollTarget.memoKeyboardComfort

        DispatchQueue.main.async {
            guard requestID == memoFocusRequest else { return }
            withAnimation(.smooth(duration: 0.30, extraBounce: 0.02)) {
                scrollProxy.scrollTo(target, anchor: .bottom)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard requestID == memoFocusRequest else { return }
            withAnimation(.smooth(duration: 0.24, extraBounce: 0.02)) {
                scrollProxy.scrollTo(target, anchor: .bottom)
            }
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
        applyAmendIfNeeded(clearAfterSave: true, showConfirmation: false)
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
        if isLiveCapture, cameraScanner.detectedPage != nil {
            MVPReadinessStore.markVerified(
                .pageBoundary,
                detail: "페이지 경계 감지 상태에서 \(selectedLineCount)줄 저장"
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

        var savedHighlightID: Highlight.ID?
        var savedPageReference: String?
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            let highlight = library.addCapturedHighlight(
                text: refinedText,
                memo: memo,
                language: CaptureLanguage.detect(from: refinedText),
                pageReference: liveText.isEmpty ? "p.42" : (inferredPageReference ?? ""),
                explicitPageReference: pageReferenceText,
                tagsText: tagsText,
                stickyTone: selectedTone
            )
            lastSaved = highlight
            amendTargetHighlightID = highlight.id
            savedHighlightID = highlight.id
            savedPageReference = highlight.pageReference
            composerTagsBaseline = tagsText
            prefillPageReferenceIfNeeded(from: highlight.pageReference)
            selectedLineIDs.removeAll()
            selectedCameraLineIDs.removeAll()
            captureMessage = .saved(
                lineCount: selectedLineCount,
                confidence: averageConfidence,
                durationMilliseconds: durationMilliseconds
            )
        }
        if let savedHighlightID {
            scheduleAutomaticTagGeneration(for: savedHighlightID)
        }
        memoFocusRequest += 1
        cameraScanner.stopSwipeRecognition()
        logCaptureSaved(
            source: source,
            lineCount: selectedLineCount,
            confidence: averageConfidence,
            brightness: frameBrightness,
            hasMemo: !memo.trimmed.isEmpty,
            durationMilliseconds: durationMilliseconds,
            pathStepCount: pathStepCount,
            pageReference: savedPageReference
        )
        resetCaptureTimer()
    }

    private func saveComposer() {
        if amendTargetHighlightID != nil {
            applyAmendIfNeeded(clearAfterSave: true, showConfirmation: true)
        } else {
            saveQuickThought()
        }
    }

    private func startNewCameraCapture() {
        applyAmendIfNeeded(clearAfterSave: true, showConfirmation: false)

        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            selectedLineIDs.removeAll()
            selectedCameraLineIDs.removeAll()
            captureMessage = nil
        }

        cameraScanner.clearSelectedLineCache()
        cameraScanner.clearFrozenFrame()
        cameraScanner.stopSwipeRecognition(clearResults: true)
        cameraScanner.start()
        resetCaptureTimer()
    }

    private func saveQuickThought() {
        guard !memo.trimmed.isEmpty else { return }

        var savedHighlightID: Highlight.ID?
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            let highlight = library.addQuickThought(
                memo,
                pageReference: pageReferenceText,
                tagsText: tagsText,
                stickyTone: selectedTone
            )
            lastSaved = highlight
            savedHighlightID = highlight.id
            composerTagsBaseline = tagsText
            clearComposerInputs()
            captureMessage = .saved(
                lineCount: 1,
                confidence: nil,
                durationMilliseconds: nil
            )
        }
        if let savedHighlightID {
            scheduleAutomaticTagGeneration(for: savedHighlightID)
        }
    }

    private var canDeleteLastSavedHighlight: Bool {
        guard captureMessage?.allowsLastSavedDeletion == true else { return false }
        return amendTargetHighlightID != nil || lastSaved != nil
    }

    private func deleteLastSavedHighlight() {
        amendDebounceTask?.cancel()
        amendDebounceTask = nil

        let targetID = amendTargetHighlightID ?? lastSaved?.id
        guard let targetID else { return }

        library.deleteHighlight(targetID)
        amendTargetHighlightID = nil
        lastSaved = nil

        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            captureMessage = .guidance("글조각 삭제됨")
        }
    }

    private func scheduleAmendIfNeeded() {
        guard amendTargetHighlightID != nil else { return }

        amendDebounceTask?.cancel()
        amendDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            applyAmendIfNeeded(clearAfterSave: false, showConfirmation: false)
        }
    }

    private func applyAmendIfNeeded(clearAfterSave: Bool, showConfirmation: Bool) {
        amendDebounceTask?.cancel()
        amendDebounceTask = nil

        guard
            let amendTargetHighlightID,
            let highlight = library.highlight(with: amendTargetHighlightID)
        else {
            self.amendTargetHighlightID = nil
            return
        }

        let pageReference = amendedPageReference(existing: highlight.pageReference)
        let tagsTextForUpdate = composerTagsUnchangedFromBaseline
            ? highlight.tags.joined(separator: " ")
            : tagsText
        library.updateHighlight(
            amendTargetHighlightID,
            text: highlight.text,
            memo: memo,
            pageReference: pageReference,
            tagsText: tagsTextForUpdate,
            bookID: library.bookID(containing: amendTargetHighlightID),
            stickyTone: selectedTone,
            isReviewed: highlight.reviewedAt != nil
        )

        if let updatedHighlight = library.highlight(with: amendTargetHighlightID) {
            lastSaved = updatedHighlight
        }

        if clearAfterSave {
            self.amendTargetHighlightID = nil
            clearComposerInputs()
            if showConfirmation {
                captureMessage = .memoSaved
            }
            composerTagsBaseline = tagsText
        }
    }

    private func amendedPageReference(existing pageReference: String) -> String {
        let pageNumber = filteredPageNumber(pageReferenceText)
        guard !pageNumber.isEmpty else { return pageReference }
        return "p.\(pageNumber)"
    }

    @MainActor
    private func recognizeSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        applyAmendIfNeeded(clearAfterSave: true, showConfirmation: false)

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
            let durationMilliseconds = captureElapsedMilliseconds()

            var savedHighlightID: Highlight.ID?
            var savedPageReference: String?
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                let highlight = library.addCapturedHighlight(
                    text: refinedText,
                    memo: memo,
                    language: CaptureLanguage.detect(from: refinedText),
                    pageReference: recognitionResult.inferredPageReference ?? "OCR",
                    explicitPageReference: pageReferenceText,
                    tagsText: tagsText,
                    stickyTone: selectedTone
                )
                lastSaved = highlight
                amendTargetHighlightID = highlight.id
                savedHighlightID = highlight.id
                savedPageReference = highlight.pageReference
                composerTagsBaseline = tagsText
                prefillPageReferenceIfNeeded(from: highlight.pageReference)
                selectedLineIDs.removeAll()
                selectedCameraLineIDs.removeAll()
                captureMessage = .saved(
                    lineCount: recognitionResult.lineCount,
                    confidence: nil,
                    durationMilliseconds: durationMilliseconds
                )
            }
            if let savedHighlightID {
                scheduleAutomaticTagGeneration(for: savedHighlightID)
            }
            memoFocusRequest += 1
            logCaptureSaved(
                source: "photo",
                lineCount: recognitionResult.lineCount,
                confidence: nil,
                brightness: nil,
                hasMemo: !memo.trimmed.isEmpty,
                durationMilliseconds: durationMilliseconds,
                pathStepCount: capturePathStepCount(for: "photo"),
                pageReference: savedPageReference
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
        tagsText = defaultTagsTextForSelectedBook()
        composerTagsBaseline = tagsText
    }

    private func prefillTagsFromSelectedBookIfNeeded() {
        guard tagsText.trimmed.isEmpty else { return }
        tagsText = defaultTagsTextForSelectedBook()
        composerTagsBaseline = tagsText
    }

    private func defaultTagsTextForSelectedBook() -> String {
        library.suggestedTagsForSelectedBook().joined(separator: " ")
    }

    private func scheduleAutomaticTagGeneration(for highlightID: Highlight.ID) {
        guard let configuration = llmSettings.activeConfiguration else {
            captureMetricsLogger.info("auto_tags_skipped reason=no_provider")
            return
        }

        guard
            let highlight = library.highlight(with: highlightID),
            let bookID = library.bookID(containing: highlightID),
            let book = library.book(with: bookID)
        else {
            captureMetricsLogger.info("auto_tags_skipped reason=missing_highlight")
            return
        }

        let originalText = highlight.text
        let originalMemo = highlight.memo
        let originalTags = highlight.tags

        let request = LLMTagRequest(
            provider: configuration.provider,
            modelID: configuration.modelID,
            credential: configuration.credential,
            bookTitle: book.title,
            bookAuthor: book.author,
            bookSummary: book.summary,
            text: highlight.text,
            memo: highlight.memo,
            existingTags: highlight.tags,
            mode: .automaticAppend
        )

        captureMetricsLogger.info(
            "auto_tags_requested provider=\(configuration.provider.rawValue, privacy: .public) model=\(configuration.modelID, privacy: .public)"
        )

        Task { @MainActor in
            do {
                let generatedTags = try await LLMInsightClient().generateTags(request)
                guard !generatedTags.isEmpty else {
                    captureMetricsLogger.info("auto_tags_empty provider=\(configuration.provider.rawValue, privacy: .public)")
                    return
                }

                guard
                    let currentHighlight = library.highlight(with: highlightID),
                    library.bookID(containing: highlightID) == bookID
                else {
                    captureMetricsLogger.info("auto_tags_skipped reason=missing_before_apply")
                    return
                }

                guard
                    currentHighlight.text == originalText,
                    currentHighlight.memo == originalMemo,
                    currentHighlight.tags == originalTags
                else {
                    captureMetricsLogger.info("auto_tags_skipped reason=highlight_changed")
                    return
                }

                guard library.appendTags(generatedTags, to: highlightID) else {
                    captureMetricsLogger.info("auto_tags_skipped reason=no_new_tags")
                    return
                }

                if lastSaved?.id == highlightID, let updatedHighlight = library.highlight(with: highlightID) {
                    lastSaved = updatedHighlight
                }
                if
                    amendTargetHighlightID == highlightID,
                    composerTagsUnchangedFromBaseline,
                    let updatedHighlight = library.highlight(with: highlightID)
                {
                    let updatedTagsText = updatedHighlight.tags.joined(separator: " ")
                    composerTagsBaseline = updatedTagsText
                    tagsText = updatedTagsText
                }
                captureMessage = .tagsSuggested
                captureMetricsLogger.info(
                    "auto_tags_applied provider=\(configuration.provider.rawValue, privacy: .public) count=\(generatedTags.count, privacy: .public)"
                )
            } catch {
                llmSettings.handleRequestError(error, configuration: configuration)
                captureMetricsLogger.error(
                    "auto_tags_failed provider=\(configuration.provider.rawValue, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)"
                )
            }
        }
    }

    private var composerTagsUnchangedFromBaseline: Bool {
        tagsText.trimmed == composerTagsBaseline.trimmed
    }

    private func prefillPageReferenceIfNeeded(from pageReference: String) {
        guard
            pageReferenceText.trimmed.isEmpty,
            let pageNumber = pageNumberInput(from: pageReference)
        else {
            return
        }

        pageReferenceText = pageNumber
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
        pathStepCount: Int,
        pageReference: String? = nil
    ) {
        let confidencePercent = confidence.map { Int(($0 * 100).rounded()) } ?? -1
        let brightnessPercent = brightness.map { Int(($0 * 100).rounded()) } ?? -1
        let loggedPageReference = pageReference?.trimmed.isEmpty == false ? pageReference?.trimmed ?? "-" : "-"

        captureMetricsLogger.info(
            "capture_saved source=\(source, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public) path_steps=\(pathStepCount, privacy: .public) line_count=\(lineCount, privacy: .public) confidence_percent=\(confidencePercent, privacy: .public) brightness_percent=\(brightnessPercent, privacy: .public) has_memo=\(hasMemo, privacy: .public) page_reference=\(loggedPageReference, privacy: .public)"
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

private enum CaptureSheet: Identifiable {
    case addBook

    var id: String {
        switch self {
        case .addBook: "addBook"
        }
    }
}

private enum CaptureScrollTarget: Hashable {
    case memoKeyboardComfort
}

private enum CaptureViewMetrics {
    static let memoKeyboardComfortSpacing: CGFloat = 220
}

private struct CaptureBookSelector: View {
    let library: ReadingLibrary
    let openAddBook: () -> Void
    @State private var isSelectionSheetPresented = false

    var body: some View {
        OverlineBookSelectorButton(
            title: library.selectedBook?.title ?? "Inbox",
            height: 52,
            cornerRadius: 26
        ) {
            isSelectionSheetPresented = true
        }
        .accessibilityLabel("저장할 책 선택")
        .sheet(isPresented: $isSelectionSheetPresented) {
            OverlineBookPickerSheet(
                title: "책 선택",
                books: library.books,
                selectedBookID: library.selectedBookID,
                addBook: openAddBook,
                onSelect: { bookID in
                    guard let bookID else { return }
                    library.selectBook(bookID)
                }
            )
            .presentationDetents([.height(selectionSheetHeight), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.thinMaterial)
        }
    }

    private var selectionSheetHeight: CGFloat {
        OverlineBookPickerMetrics.sheetHeight(bookCount: library.books.count, includesAddBook: true)
    }
}

private struct CaptureStage: View {
    @Binding var selectedLineIDs: Set<Int>
    @Binding var selectedCameraLineIDs: Set<CameraRecognizedTextLine.ID>
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var isAutoRecognitionEnabled: Bool
    let cameraScanner: CameraTextScanner
    let isRecognizingText: Bool
    let selectedTone: StickyTone
    let onCommit: () -> Void
    let onRestartCapture: () -> Void
    let onMiss: () -> Void
    let openSettings: () -> Void
    let onHighlighterGestureActiveChanged: (Bool) -> Void
    @State private var previousDragLocation: CGPoint?
    @State private var cameraGestureStartLocation: CGPoint?
    @State private var ignoresCurrentCameraDrag = false
    @State private var pendingCameraDragRects: [CGRect] = []
    @State private var activeHighlighterPoints: [CGPoint] = []
    @State private var confirmedCameraLines: [CameraRecognizedTextLine] = []
    @State private var isCaptureLocked = false
    @State private var pendingCameraCommit = false
    @State private var pendingCameraCommitTask: Task<Void, Never>?
    @State private var pendingCameraMissTask: Task<Void, Never>?
    @State private var delayedCameraRecognitionTask: Task<Void, Never>?
    @State private var pendingCameraGestures: [PendingCameraGesture] = []
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

                    ConfirmedCameraHighlightOverlay(
                        lines: confirmedCameraLines,
                        tone: selectedTone
                    )

                    ForEach(pendingCameraGestures) { gesture in
                        LiveHighlighterStrokeOverlay(
                            points: gesture.points,
                            tone: selectedTone
                        )
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

                if !isCaptureLocked {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
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
                                    let shouldFinishSelection = !ignoresCurrentCameraDrag
                                    previousDragLocation = nil
                                    cameraGestureStartLocation = nil
                                    ignoresCurrentCameraDrag = false

                                    if shouldFinishSelection {
                                        finishLineSelection(in: proxy.size)
                                    } else {
                                        onHighlighterGestureActiveChanged(false)
                                    }
                                }
                        )
                }

                if !isCaptureLocked {
                    CameraHUD(
                        selectedPhotoItem: $selectedPhotoItem,
                        isAutoRecognitionEnabled: $isAutoRecognitionEnabled,
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
                }

                if isCaptureLocked {
                    NewCameraCaptureButton(action: restartLiveCameraCapture)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.96))
                        )
                } else {
                    if showsManualRecognitionControls {
                        ManualCameraRecognitionControls(
                            phase: cameraFeedbackPhase,
                            canRecognize: showsManualRecognitionButton,
                            recognizeAction: {
                                startManualCameraRecognition(in: proxy.size)
                            },
                            resetAction: resetManualCameraSelection
                        )
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.96))
                        )
                    } else {
                        CameraCaptureFeedbackPill(phase: cameraFeedbackPhase)
                            .padding(.bottom, 22)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .allowsHitTesting(false)
                    }
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
                guard recognitionStartedStrokeID == pendingCameraStrokeID else { return }
                resolvePendingCameraSelection(in: proxy.size)
            }
            .onChange(of: cameraScanner.isAnalyzingText) { _, isAnalyzing in
                if !isAnalyzing {
                    guard !isCaptureLocked else { return }
                    if pendingCameraCommitTask == nil {
                        let shouldShowMiss = pendingCameraCommit &&
                            recognitionStartedStrokeID == pendingCameraStrokeID &&
                            selectedCameraLineIDs.isEmpty &&
                            hasPendingCameraGesturePoints
                        cancelPendingCameraMiss()
                        pendingCameraDragRects.removeAll()
                        activeHighlighterPoints.removeAll()
                        pendingCameraGestures.removeAll()
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
            .onChange(of: isAutoRecognitionEnabled) { _, isEnabled in
                guard isEnabled else { return }
                resetManualCameraSelection()
            }
        }
        .aspectRatio(0.84, contentMode: .fit)
        .onDisappear {
            cancelPendingCameraCommit()
            cancelPendingCameraMiss()
            cancelDelayedCameraRecognition()
            pendingCameraDragRects.removeAll()
            activeHighlighterPoints.removeAll()
            pendingCameraGestures.removeAll()
            confirmedCameraLines.removeAll()
            isCaptureLocked = false
            cameraScanner.clearFrozenFrame()
            pendingCameraCommit = false
            pendingCameraStrokeID = nil
            recognitionStartedStrokeID = nil
            pendingCameraSelectionMode = nil
            cameraGestureStartLocation = nil
            ignoresCurrentCameraDrag = false
            setCameraFeedbackPhase(.idle)
        }
    }

    private var showsManualRecognitionButton: Bool {
        !isAutoRecognitionEnabled &&
            pendingCameraCommit &&
            !pendingCameraGestures.isEmpty &&
            recognitionStartedStrokeID == nil &&
            delayedCameraRecognitionTask == nil &&
            !cameraScanner.isAnalyzingText
    }

    private var showsManualRecognitionControls: Bool {
        !isAutoRecognitionEnabled &&
            pendingCameraCommit &&
            !pendingCameraGestures.isEmpty
    }

    private var hasPendingCameraGesturePoints: Bool {
        !activeHighlighterPoints.isEmpty || pendingCameraGestures.contains { !$0.points.isEmpty }
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
            guard isValidCameraHighlighterGesture(in: size) else {
                let hasQueuedManualGestures = !isAutoRecognitionEnabled && !pendingCameraGestures.isEmpty
                activeHighlighterPoints.removeAll()
                pendingCameraDragRects.removeAll()
                if !hasQueuedManualGestures {
                    cameraScanner.clearFrozenFrame()
                }
                cameraScanner.stopSwipeRecognition()
                onHighlighterGestureActiveChanged(false)
                if hasQueuedManualGestures {
                    pendingCameraCommit = true
                    pendingCameraStrokeID = pendingCameraGestures.last?.id
                    setCameraFeedbackPhase(.manualReady)
                } else {
                    setCameraFeedbackPhase(.idle)
                }
                return
            }

            let strokeID = activeCameraStrokeID
            let selectionMode = cameraGestureSelectionMode(in: size)
            let rawPointCount = activeHighlighterPoints.count
            let rawBounds = boundingRect(for: activeHighlighterPoints)
            activeHighlighterPoints = correctedHighlighterPoints(
                activeHighlighterPoints,
                mode: selectionMode
            )
            let correctedBounds = boundingRect(for: activeHighlighterPoints)
            captureMetricsLogger.info(
                "camera_ar_gesture_finished stroke_id=\(strokeID, privacy: .public) mode=\(selectionMode.rawValue, privacy: .public) stage=\(debugSizeDescription(size), privacy: .public) raw_points=\(rawPointCount, privacy: .public) corrected_points=\(activeHighlighterPoints.count, privacy: .public) raw_bounds=\(debugRectDescription(rawBounds), privacy: .public) corrected_bounds=\(debugRectDescription(correctedBounds), privacy: .public)"
            )
            onHighlighterGestureActiveChanged(false)
            pendingCameraCommit = true
            pendingCameraStrokeID = strokeID
            pendingCameraSelectionMode = selectionMode
            recognitionStartedStrokeID = nil

            if !isAutoRecognitionEnabled {
                pendingCameraGestures.append(
                    PendingCameraGesture(
                        id: strokeID,
                        points: activeHighlighterPoints,
                        dragRects: pendingCameraDragRects,
                        mode: selectionMode
                    )
                )
                if pendingCameraGestures.count > 12 {
                    pendingCameraGestures.removeFirst(pendingCameraGestures.count - 12)
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    activeHighlighterPoints.removeAll()
                }
                pendingCameraDragRects.removeAll()
                setCameraFeedbackPhase(.manualReady)
                return
            }

            let recognitionProfile = cameraRecognitionProfile()
            setCameraFeedbackPhase(.holding)
            startDelayedCameraRecognition(for: strokeID, profile: recognitionProfile)
            schedulePendingCameraMiss(in: size, strokeID: strokeID, profile: recognitionProfile)
            return
        }

        onCommit()
    }

    private func selectCameraLine(from previousLocation: CGPoint?, to location: CGPoint, in size: CGSize) {
        guard !isCaptureLocked, !ignoresCurrentCameraDrag else { return }

        let focusRect = CaptureStageMetrics.focusRect(in: size)
        let dragRect = dragRect(from: previousLocation, to: location)

        guard focusRect.intersects(dragRect) else { return }

        let startLocation = cameraGestureStartLocation ?? previousLocation ?? location
        if cameraGestureStartLocation == nil {
            cameraGestureStartLocation = startLocation
        }

        if activeHighlighterPoints.isEmpty {
            let dx = location.x - startLocation.x
            let dy = location.y - startLocation.y
            let distance = hypot(dx, dy)
            guard distance >= 14 else { return }

            if abs(dy) > max(abs(dx) * 1.6, 30) {
                ignoresCurrentCameraDrag = true
                onHighlighterGestureActiveChanged(false)
                return
            }

            beginCameraStroke(at: startLocation, in: size)
            appendHighlighterPoint(startLocation, previousLocation: nil, in: size)
        }

        appendHighlighterPoint(location, previousLocation: previousLocation, in: size)
        pendingCameraDragRects.append(dragRect)
        if pendingCameraDragRects.count > 36 {
            pendingCameraDragRects.removeFirst(pendingCameraDragRects.count - 36)
        }
    }

    private func resolvePendingCameraSelection(in size: CGSize) {
        guard cameraScanner.canUseLiveCamera else { return }
        guard pendingCameraCommit else { return }

        let gestures = pendingSelectionGestures(in: size)
        guard !gestures.isEmpty else { return }

        let pageLines = cameraScanner.lines
        var selectedIDs = Set<CameraRecognizedTextLine.ID>()
        var candidateCount = 0
        var debugCandidateSummaries: [String] = []

        for gesture in gestures {
            let result = cameraSelectionResult(for: gesture, pageLines: pageLines, in: size)
            selectedIDs.formUnion(result.selectedIDs)
            candidateCount += result.candidateCount
            debugCandidateSummaries.append(result.debugSummary)
        }

        let selectedLines = pageLines.filter { selectedIDs.contains($0.id) }
        let modeSummary = gestures.count == 1 ? gestures[0].mode.rawValue : "mixed"
        captureMetricsLogger.info(
            "camera_ar_resolve stroke_id=\(pendingCameraStrokeID ?? -1, privacy: .public) mode=\(modeSummary, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) ocr_line_count=\(pageLines.count, privacy: .public) candidate_count=\(candidateCount, privacy: .public) selected_count=\(selectedIDs.count, privacy: .public) gesture_bounds=\(debugRectDescription(boundingRect(for: gestures.flatMap(\.points))), privacy: .public) ocr=\(debugLineGeometrySummary(pageLines, in: size), privacy: .public) candidates=\(debugCandidateSummaries.joined(separator: "|"), privacy: .public) selected=\(debugLineGeometrySummary(selectedLines, in: size), privacy: .public)"
        )

        if !selectedIDs.isEmpty {
            cameraScanner.cacheSelectedLines(for: selectedIDs)
            selectedCameraLineIDs = selectedIDs
        }

        if pendingCameraCommit, !selectedCameraLineIDs.isEmpty {
            captureMetricsLogger.info(
                "camera_ar_match line_count=\(selectedCameraLineIDs.count, privacy: .public) candidate_count=\(candidateCount, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) mode=\(modeSummary, privacy: .public)"
            )
            commitPendingCameraSelection()
        }
    }

    private func pendingSelectionGestures(in size: CGSize) -> [PendingCameraGesture] {
        if !pendingCameraGestures.isEmpty {
            return pendingCameraGestures
        }

        guard !activeHighlighterPoints.isEmpty || !pendingCameraDragRects.isEmpty else { return [] }
        return [
            PendingCameraGesture(
                id: pendingCameraStrokeID ?? activeCameraStrokeID,
                points: activeHighlighterPoints,
                dragRects: pendingCameraDragRects,
                mode: pendingCameraSelectionMode ?? cameraGestureSelectionMode(in: size)
            )
        ]
    }

    private func cameraSelectionResult(
        for gesture: PendingCameraGesture,
        pageLines: [CameraRecognizedTextLine],
        in size: CGSize
    ) -> CameraGestureSelectionResult {
        switch gesture.mode {
        case .region:
            let regionLines = pageLines.filter { line in
                cameraRegionSelectionContains(line: line, in: size, points: gesture.points)
            }
            return CameraGestureSelectionResult(
                selectedIDs: Set(regionLines.map(\.id)),
                candidateCount: regionLines.count,
                debugSummary: debugLineGeometrySummary(regionLines, in: size)
            )
        case .line:
            let matches = strokeLineMatches(
                from: pageLines,
                in: size,
                points: gesture.points,
                dragRects: gesture.dragRects
            )
            let selectedMatches = selectedLineMatches(from: matches)
            return CameraGestureSelectionResult(
                selectedIDs: Set(selectedMatches.map(\.id)),
                candidateCount: matches.count,
                debugSummary: debugScoreSummary(matches, lines: pageLines, in: size)
            )
        }
    }

    private func strokeLineMatches(from lines: [CameraRecognizedTextLine], in size: CGSize) -> [CameraStrokeLineMatch] {
        strokeLineMatches(
            from: lines,
            in: size,
            points: activeHighlighterPoints,
            dragRects: pendingCameraDragRects
        )
    }

    private func strokeLineMatches(
        from lines: [CameraRecognizedTextLine],
        in size: CGSize,
        points: [CGPoint],
        dragRects: [CGRect]
    ) -> [CameraStrokeLineMatch] {
        lines.compactMap { line -> CameraStrokeLineMatch? in
            guard let score = cameraStrokeScore(
                for: line,
                in: size,
                points: points,
                dragRects: dragRects
            ) else { return nil }
            return CameraStrokeLineMatch(id: line.id, score: score)
        }
    }

    private func commitPendingCameraSelection() {
        guard pendingCameraCommitTask == nil else { return }

        cancelPendingCameraMiss()
        cancelDelayedCameraRecognition()
        confirmedCameraLines = cameraScanner.selectedLineSnapshots(for: selectedCameraLineIDs)
        withAnimation(.easeOut(duration: 0.16)) {
            activeHighlighterPoints.removeAll()
        }
        pendingCameraCommit = false
        pendingCameraDragRects.removeAll()
        pendingCameraGestures.removeAll()
        pendingCameraStrokeID = nil
        recognitionStartedStrokeID = nil
        pendingCameraSelectionMode = nil
        setCameraFeedbackPhase(.saving)
        cameraScanner.stopSwipeRecognition(clearResults: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        pendingCameraCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.smooth(duration: 0.24, extraBounce: 0.02)) {
                isCaptureLocked = true
            }
            pendingCameraCommitTask = nil
            setCameraFeedbackPhase(.idle)
            onCommit()
            cameraScanner.stop(clearRecognitionResults: false)
        }
    }

    private func restartLiveCameraCapture() {
        cancelPendingCameraCommit()
        cancelPendingCameraMiss()
        cancelDelayedCameraRecognition()
        pendingCameraDragRects.removeAll()
        activeHighlighterPoints.removeAll()
        pendingCameraGestures.removeAll()
        confirmedCameraLines.removeAll()
        selectedCameraLineIDs.removeAll()
        pendingCameraCommit = false
        pendingCameraStrokeID = nil
        recognitionStartedStrokeID = nil
        pendingCameraSelectionMode = nil
        cameraGestureStartLocation = nil
        ignoresCurrentCameraDrag = false
        onHighlighterGestureActiveChanged(false)
        setCameraFeedbackPhase(.idle)

        withAnimation(.smooth(duration: 0.22, extraBounce: 0.02)) {
            isCaptureLocked = false
        }

        onRestartCapture()
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

    private func startManualCameraRecognition(in size: CGSize) {
        guard cameraScanner.canUseLiveCamera else { return }
        guard !isAutoRecognitionEnabled else { return }
        guard pendingCameraCommit, !pendingCameraGestures.isEmpty else { return }
        guard delayedCameraRecognitionTask == nil, !cameraScanner.isAnalyzingText else { return }

        let strokeID = pendingCameraStrokeID ?? pendingCameraGestures.last?.id ?? activeCameraStrokeID
        let recognitionProfile = cameraRecognitionProfile()
        pendingCameraStrokeID = strokeID
        recognitionStartedStrokeID = nil
        setCameraFeedbackPhase(.holding)
        startDelayedCameraRecognition(for: strokeID, profile: recognitionProfile)
        schedulePendingCameraMiss(in: size, strokeID: strokeID, profile: recognitionProfile)
    }

    private func resetManualCameraSelection() {
        cancelPendingCameraCommit()
        cancelPendingCameraMiss()
        cancelDelayedCameraRecognition()
        cameraScanner.stopSwipeRecognition()
        cameraScanner.clearFrozenFrame()
        pendingCameraCommit = false
        pendingCameraDragRects.removeAll()
        pendingCameraGestures.removeAll()
        activeHighlighterPoints.removeAll()
        selectedCameraLineIDs.removeAll()
        pendingCameraStrokeID = nil
        recognitionStartedStrokeID = nil
        pendingCameraSelectionMode = nil
        cameraGestureStartLocation = nil
        ignoresCurrentCameraDrag = false
        onHighlighterGestureActiveChanged(false)
        setCameraFeedbackPhase(.idle)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                "camera_ar_miss stroke_id=\(strokeID, privacy: .public) mode=\((pendingCameraSelectionMode ?? .line).rawValue, privacy: .public) warmup=\(profile.isWarmup, privacy: .public) update_count=\(cameraScanner.recognitionUpdateCount, privacy: .public) line_count=\(cameraScanner.lines.count, privacy: .public) gesture_bounds=\(debugRectDescription(boundingRect(for: pendingSelectionGestures(in: size).flatMap(\.points))), privacy: .public) ocr=\(debugLineGeometrySummary(cameraScanner.lines, in: size), privacy: .public)"
            )
            pendingCameraCommit = false
            pendingCameraDragRects.removeAll()
            activeHighlighterPoints.removeAll()
            pendingCameraGestures.removeAll()
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
        if isAutoRecognitionEnabled || pendingCameraGestures.isEmpty || cameraScanner.frozenFrameImage == nil {
            cameraScanner.freezeNextFrame()
        }
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
        cameraStrokeScore(
            for: line,
            in: size,
            points: activeHighlighterPoints,
            dragRects: pendingCameraDragRects
        )
    }

    private func cameraStrokeScore(
        for line: CameraRecognizedTextLine,
        in size: CGSize,
        points: [CGPoint],
        dragRects: [CGRect]
    ) -> CGFloat? {
        let lineRect = line.displayRect(in: size)

        guard !points.isEmpty else {
            let expandedLineRect = lineRect.insetBy(dx: -12, dy: -12)
            return dragRects.contains { expandedLineRect.intersects($0) } ? 0.32 : nil
        }

        if let axis = cameraStrokeAxis(points: points) {
            return directionalCameraStrokeScore(for: line, in: size, axis: axis, points: points)
        }

        let verticalAllowance = max(lineRect.height * 0.95, 14)
        let horizontalAllowance = max(lineRect.height * 0.9, 12)
        let matchingRect = lineRect.insetBy(dx: -horizontalAllowance, dy: -verticalAllowance)
        let gestureBounds = boundingRect(for: points).insetBy(dx: -8, dy: -8)

        guard matchingRect.intersects(gestureBounds) else { return nil }

        let nearbyPoints = points.filter { point in
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
        let pointRatio = min(CGFloat(nearbyPoints.count) / max(CGFloat(points.count), 1), 1)
        let closeness = 1 - min(nearestDistance / max(verticalAllowance, 1), 1)
        let score = overlapRatio * 0.62 + closeness * 0.28 + pointRatio * 0.10

        guard score >= 0.28 else { return nil }
        return score
    }

    private func directionalCameraStrokeScore(for line: CameraRecognizedTextLine, in size: CGSize, axis: CameraStrokeAxis) -> CGFloat? {
        directionalCameraStrokeScore(for: line, in: size, axis: axis, points: activeHighlighterPoints)
    }

    private func directionalCameraStrokeScore(
        for line: CameraRecognizedTextLine,
        in size: CGSize,
        axis: CameraStrokeAxis,
        points: [CGPoint]
    ) -> CGFloat? {
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
        let nearbyPoints = points.filter { point in
            expandedLineProjection.contains(axis.projection(of: point)) &&
                abs(axis.perpendicularDistance(to: point)) <= perpendicularAllowance
        }
        guard !nearbyPoints.isEmpty else { return nil }

        let pointRatio = min(CGFloat(nearbyPoints.count) / max(CGFloat(points.count), 1), 1)
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

    private func isValidCameraHighlighterGesture(in size: CGSize) -> Bool {
        let points = activeHighlighterPoints
        guard points.count >= 2 else { return false }

        let bounds = boundingRect(for: points)
        let length = pathLength(for: points)

        switch cameraGestureSelectionMode(in: size) {
        case .line:
            return bounds.width >= 54 &&
                length >= 54 &&
                bounds.width >= max(bounds.height * 1.12, 1)
        case .region:
            return bounds.width >= 64 &&
                bounds.height >= 38 &&
                length >= 120
        }
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
        cameraRegionSelectionContains(line: line, in: size, points: selectionGesturePoints(in: size))
    }

    private func cameraRegionSelectionContains(
        line: CameraRecognizedTextLine,
        in size: CGSize,
        points: [CGPoint]
    ) -> Bool {
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
        guard let axis = cameraStrokeAxis(points: activeHighlighterPoints), activeHighlighterPoints.count >= 4 else {
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
        cameraStrokeAxis(points: activeHighlighterPoints)
    }

    private func cameraStrokeAxis(points: [CGPoint]) -> CameraStrokeAxis? {
        guard
            let firstPoint = points.first,
            let lastPoint = points.last
        else {
            return nil
        }

        let dx = lastPoint.x - firstPoint.x
        let dy = lastPoint.y - firstPoint.y
        let length = hypot(dx, dy)
        guard length >= 14 else { return nil }

        let direction = CGVector(dx: dx / length, dy: dy / length)
        let projections = points.map { point in
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

private struct CameraGestureSelectionResult {
    let selectedIDs: Set<CameraRecognizedTextLine.ID>
    let candidateCount: Int
    let debugSummary: String
}

private struct PendingCameraGesture: Identifiable {
    let id: Int
    let points: [CGPoint]
    let dragRects: [CGRect]
    let mode: CameraGestureSelectionMode
}

private enum CameraCaptureFeedbackPhase: Equatable {
    case idle
    case drawing
    case manualReady
    case holding
    case reading
    case saving

    var isVisible: Bool {
        switch self {
        case .manualReady, .holding, .reading, .saving:
            return true
        case .idle, .drawing:
            return false
        }
    }

    var text: String {
        switch self {
        case .idle, .drawing:
            return ""
        case .manualReady:
            return "인식 대기"
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
        case .manualReady:
            return "text.viewfinder"
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
        case .idle, .drawing, .manualReady, .holding:
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

private struct NewCameraCaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("새 글조각", systemImage: "camera")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .cameraCaptureFeedbackSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("새 글조각 캡쳐")
    }
}

private struct ManualCameraRecognitionControls: View {
    let phase: CameraCaptureFeedbackPhase
    let canRecognize: Bool
    let recognizeAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: resetAction) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(width: 34, height: 34)
                    .cameraCaptureFeedbackSurface()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("선택 취소")

            if canRecognize {
                Button(action: recognizeAction) {
                    Label("인식", systemImage: "text.viewfinder")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .cameraCaptureFeedbackSurface()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("선택한 글조각 인식")
            } else {
                CameraCaptureFeedbackPill(phase: phase)
            }
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
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
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
    case captured(lineCount: Int)
    case saved(lineCount: Int, confidence: Float?, durationMilliseconds: Int?)
    case memoSaved
    case tagsSuggested
    case guidance(String)
    case error(String)

    var systemImage: String {
        switch self {
        case .processing:
            return "text.viewfinder"
        case .captured:
            return "square.and.pencil"
        case .saved, .memoSaved:
            return "checkmark.circle.fill"
        case .tagsSuggested:
            return "tag.fill"
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
        case .captured(let lineCount):
            return lineCount > 0 ? "\(lineCount)줄 준비됨 · 메모 추가 또는 바로 저장" : "글조각 준비됨 · 메모 추가 또는 바로 저장"
        case .saved:
            return "글조각 저장됨"
        case .memoSaved:
            return "메모 반영됨"
        case .tagsSuggested:
            return "태그 추천됨"
        case .guidance(let message):
            return message
        case .error(let message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .processing, .captured:
            return Color.overlineAccent
        case .saved, .memoSaved, .tagsSuggested:
            return Color.overlineAccent
        case .guidance:
            return Color.overlineMutedInk
        case .error:
            return Color.overlineCoral
        }
    }

    var allowsLastSavedDeletion: Bool {
        switch self {
        case .saved, .memoSaved, .tagsSuggested:
            return true
        case .processing, .captured, .guidance, .error:
            return false
        }
    }
}

private struct CaptureStatusStrip: View {
    let message: CaptureMessage
    let deleteAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Label(message.text, systemImage: message.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.color)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let deleteAction {
                Button(action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.overlineCoral.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("방금 저장한 글조각 삭제")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, deleteAction == nil ? 12 : 8)
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
    @Binding var isAutoRecognitionEnabled: Bool
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

            Button {
                isAutoRecognitionEnabled.toggle()
            } label: {
                HUDAutoButton(isActive: isAutoRecognitionEnabled)
            }
            .buttonStyle(.plain)
            .disabled(isRecognizingText)
            .accessibilityLabel("자동 인식")
            .accessibilityValue(isAutoRecognitionEnabled ? "켜짐" : "꺼짐")

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

private struct HUDAutoButton: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            if !isActive {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .frame(width: 24, height: 1.4)
                    .rotationEffect(.degrees(45))
            }
        }
        .foregroundStyle(isActive ? Color.overlineAccent : Color.white.opacity(0.40))
        .frame(width: 36, height: 36)
        .background {
            if isActive {
                Circle()
                    .fill(Color.overlineAccent.opacity(0.20))
            }
        }
        .overlay {
            if isActive {
                Circle()
                    .stroke(Color.overlineAccent.opacity(0.58), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
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
    }
}

private extension StickyTone {
    var memoPaperGradientColors: [Color] {
        switch self {
        case .yellow:
            [
                Color(red: 1.00, green: 0.91, blue: 0.48),
                Color(red: 0.97, green: 0.80, blue: 0.38)
            ]
        case .rose:
            [
                Color(red: 1.00, green: 0.75, blue: 0.80),
                Color(red: 0.96, green: 0.58, blue: 0.68)
            ]
        case .blue:
            [
                Color(red: 0.73, green: 0.88, blue: 0.98),
                Color(red: 0.53, green: 0.77, blue: 0.91)
            ]
        case .mint:
            [
                Color(red: 0.75, green: 0.91, blue: 0.80),
                Color(red: 0.55, green: 0.80, blue: 0.66)
            ]
        }
    }
}

private struct MemoComposerCard: View {
    @Binding var memo: String
    let tone: StickyTone
    let hasPendingCapture: Bool
    let canSave: Bool
    let focusRequest: Int
    let isListening: Bool
    let voiceErrorMessage: String?
    let toggleVoiceMemo: () -> Void
    let save: () -> Void
    let openSettings: () -> Void
    @FocusState private var isMemoFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                MemoPaperLines(lineCount: lineCount)

                if memo.isEmpty {
                    Text(hasPendingCapture ? "필요하면 메모 추가" : "떠오른 생각을 바로 적기")
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
                    .focused($isMemoFocused)
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

                Button(action: save) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSave ? Color.overlineInk.opacity(0.66) : Color.overlineInk.opacity(0.24))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel(hasPendingCapture ? "글조각 저장" : "메모 저장")
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
                colors: tone.memoPaperGradientColors,
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
        .onChange(of: focusRequest) { _, _ in
            isMemoFocused = true
        }
        .animation(.smooth(duration: 0.22, extraBounce: 0.02), value: tone)
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
            PageReferenceField(pageNumber: $pageReference)
            .frame(width: 74)

            TagEntryField(tagsText: $tagsText)
            .frame(maxWidth: .infinity)

            HighlightTonePicker(selectedTone: $selectedTone)
        }
        .padding(.horizontal, 2)
    }
}

private struct PageReferenceField: View {
    @Binding var pageNumber: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "text.book.closed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineInk.opacity(0.38))
                .frame(width: 15)

            HStack(spacing: 0) {
                Text("p.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.overlineInk.opacity(0.52))

                TextField("42", text: $pageNumber)
                    .keyboardType(.numberPad)
                    .onChange(of: pageNumber) { _, newValue in
                        let filteredValue = filteredPageNumber(newValue)
                        guard filteredValue != newValue else { return }
                        pageNumber = filteredValue
                    }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.overlineInk.opacity(0.68))
            .tint(Color.overlineAccent)
            .lineLimit(1)
        }
        .frame(minWidth: 58, minHeight: 28)
        .padding(.horizontal, 4)
    }
}

private struct TagEntryField: View {
    @Binding var tagsText: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tag")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineInk.opacity(0.38))
                .frame(width: 15)

            TextField("태그", text: $tagsText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.overlineInk.opacity(0.68))
                .tint(Color.overlineAccent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1)
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 4)
    }
}

private func filteredPageNumber(_ value: String) -> String {
    String(value.filter { $0.isNumber }.prefix(4))
}

private func pageNumberInput(from pageReference: String) -> String? {
    let pageNumber = filteredPageNumber(pageReference)
    return pageNumber.isEmpty ? nil : pageNumber
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

#Preview {
    NavigationStack {
        CaptureView(cameraScanner: CameraTextScanner(), isActive: true)
            .navigationTitle("캡처")
    }
    .environment(ReadingLibrary.preview)
    .environment(LLMSettingsStore())
}
