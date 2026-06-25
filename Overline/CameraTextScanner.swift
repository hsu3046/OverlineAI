@preconcurrency import AVFoundation
import CoreImage
import Observation
import SwiftUI
import UIKit
@preconcurrency import Vision

struct CameraRecognizedTextLine: Identifiable, Hashable {
    let id: String
    let text: String
    let boundingBox: CGRect
    let quadrilateral: CameraTextQuadrilateral?
    let confidence: VNConfidence

    nonisolated init(
        id: String? = nil,
        text: String,
        boundingBox: CGRect,
        quadrilateral: CameraTextQuadrilateral? = nil,
        confidence: VNConfidence
    ) {
        self.id = id ?? Self.stableID(text: text, boundingBox: boundingBox)
        self.text = text
        self.boundingBox = boundingBox
        self.quadrilateral = quadrilateral
        self.confidence = confidence
    }

    private nonisolated static func stableID(text: String, boundingBox: CGRect) -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let x = Int((boundingBox.minX * 1000).rounded())
        let y = Int((boundingBox.midY * 1000).rounded())
        let width = Int((boundingBox.width * 1000).rounded())
        return "\(normalizedText)|\(x)|\(y)|\(width)"
    }

    func displayRect(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> CGRect {
        CameraVisionGeometry.displayRect(
            for: boundingBox,
            in: size,
            videoAspectRatio: videoAspectRatio
        )
    }

    func displaySamplePoints(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> [CGPoint] {
        guard let corners = quadrilateral?.displayCorners(in: size, videoAspectRatio: videoAspectRatio), corners.count == 4 else {
            return displayRect(in: size, videoAspectRatio: videoAspectRatio).samplePoints
        }

        let topMidpoint = midpoint(corners[0], corners[1])
        let rightMidpoint = midpoint(corners[1], corners[2])
        let bottomMidpoint = midpoint(corners[2], corners[3])
        let leftMidpoint = midpoint(corners[3], corners[0])
        let center = midpoint(topMidpoint, bottomMidpoint)
        return corners + [topMidpoint, rightMidpoint, bottomMidpoint, leftMidpoint, center]
    }

    func displayThickness(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> CGFloat {
        guard let corners = quadrilateral?.displayCorners(in: size, videoAspectRatio: videoAspectRatio), corners.count == 4 else {
            return displayRect(in: size, videoAspectRatio: videoAspectRatio).height
        }

        let leftHeight = hypot(corners[0].x - corners[3].x, corners[0].y - corners[3].y)
        let rightHeight = hypot(corners[1].x - corners[2].x, corners[1].y - corners[2].y)
        return max((leftHeight + rightHeight) / 2, 1)
    }

    private func midpoint(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (firstPoint.x + secondPoint.x) / 2,
            y: (firstPoint.y + secondPoint.y) / 2
        )
    }
}

struct CameraTextQuadrilateral: Hashable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    nonisolated init(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    nonisolated init(rectangle: VNRectangleObservation) {
        self.init(
            topLeft: rectangle.topLeft,
            topRight: rectangle.topRight,
            bottomRight: rectangle.bottomRight,
            bottomLeft: rectangle.bottomLeft
        )
    }

    func displayCorners(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft].map {
            CameraVisionGeometry.displayPoint(
                for: $0,
                in: size,
                videoAspectRatio: videoAspectRatio
            )
        }
    }
}

struct CameraDetectedPage: Hashable {
    let boundingBox: CGRect
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    nonisolated init(
        boundingBox: CGRect,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        self.boundingBox = boundingBox
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    func displayPath(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> Path {
        let points = displayCorners(in: size, videoAspectRatio: videoAspectRatio)

        return Path { path in
            guard let firstPoint = points.first else { return }
            path.move(to: firstPoint)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
    }

    func displayCorners(in size: CGSize, videoAspectRatio: CGFloat = 9.0 / 16.0) -> [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft].map {
            CameraVisionGeometry.displayPoint(
                for: $0,
                in: size,
                videoAspectRatio: videoAspectRatio
            )
        }
    }

    nonisolated var area: CGFloat {
        boundingBox.width * boundingBox.height
    }
}

private enum CameraVisionGeometry {
    static func displayRect(
        for boundingBox: CGRect,
        in size: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGRect {
        let aspectFillRect = aspectFillRect(
            for: CGSize(width: videoAspectRatio, height: 1),
            in: size
        )
        let rect = CGRect(
            x: boundingBox.minX * size.width,
            y: (1 - boundingBox.maxY) * size.height,
            width: boundingBox.width * size.width,
            height: boundingBox.height * size.height
        )

        return CGRect(
            x: aspectFillRect.minX + rect.minX * aspectFillRect.width / max(size.width, 1),
            y: aspectFillRect.minY + rect.minY * aspectFillRect.height / max(size.height, 1),
            width: rect.width * aspectFillRect.width / max(size.width, 1),
            height: rect.height * aspectFillRect.height / max(size.height, 1)
        )
    }

    static func displayPoint(
        for normalizedPoint: CGPoint,
        in size: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGPoint {
        let aspectFillRect = aspectFillRect(
            for: CGSize(width: videoAspectRatio, height: 1),
            in: size
        )
        let imagePoint = CGPoint(
            x: normalizedPoint.x * size.width,
            y: (1 - normalizedPoint.y) * size.height
        )

        return CGPoint(
            x: aspectFillRect.minX + imagePoint.x * aspectFillRect.width / max(size.width, 1),
            y: aspectFillRect.minY + imagePoint.y * aspectFillRect.height / max(size.height, 1)
        )
    }

    private static func aspectFillRect(for sourceSize: CGSize, in targetSize: CGSize) -> CGRect {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            targetSize.width > 0,
            targetSize.height > 0
        else {
            return CGRect(origin: .zero, size: targetSize)
        }

        let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let fittedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return CGRect(
            x: (targetSize.width - fittedSize.width) / 2,
            y: (targetSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

private extension CGRect {
    var samplePoints: [CGPoint] {
        [
            CGPoint(x: minX, y: minY),
            CGPoint(x: midX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: midY),
            CGPoint(x: midX, y: midY),
            CGPoint(x: maxX, y: midY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: midX, y: maxY),
            CGPoint(x: maxX, y: maxY)
        ]
    }
}

enum CameraScannerStatus: Equatable {
    case idle
    case requestingPermission
    case running
    case unavailable(String)
}

@MainActor
@Observable
final class CameraTextScanner {
    @ObservationIgnored private let core: CameraTextScannerCore
    @ObservationIgnored private var recognitionWindowTask: Task<Void, Never>?
    @ObservationIgnored private var selectedLineCache: [CameraRecognizedTextLine.ID: CameraRecognizedTextLine] = [:]

    var status: CameraScannerStatus = .idle
    var lines: [CameraRecognizedTextLine] = []
    var detectedPage: CameraDetectedPage?
    var frameBrightness: Float?
    var isTorchOn = false
    var isAnalyzingText = false
    var recognitionUpdateCount = 0

    var session: AVCaptureSession {
        core.session
    }

    init(core: CameraTextScannerCore = CameraTextScannerCore()) {
        self.core = core
        core.onLines = { [weak self] lines in
            Task { @MainActor in
                self?.lines = lines
                self?.recognitionUpdateCount += 1
            }
        }
        core.onPage = { [weak self] page in
            Task { @MainActor in
                self?.detectedPage = page
            }
        }
        core.onBrightness = { [weak self] brightness in
            Task { @MainActor in
                self?.frameBrightness = brightness
            }
        }
        core.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.status = .unavailable(message)
            }
        }
    }

    var canUseLiveCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        switch status {
        case .running, .requestingPermission:
            true
        case .idle:
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        case .unavailable:
            false
        }
        #endif
    }

    var canToggleTorch: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        core.isTorchAvailable
        #endif
    }

    var isLowLight: Bool {
        guard let frameBrightness else { return false }
        return frameBrightness < 0.28
    }

    func start() {
        #if targetEnvironment(simulator)
        status = .unavailable("시뮬레이터에서는 카메라 대신 목업 캡처를 사용합니다.")
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .running
            core.start()
        case .notDetermined:
            status = .requestingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.status = .running
                        self?.core.start()
                    } else {
                        self?.status = .unavailable("카메라 권한이 필요합니다.")
                    }
                }
            }
        default:
            status = .unavailable("카메라 권한이 필요합니다.")
        }
        #endif
    }

    func stop() {
        stopSwipeRecognition()
        core.stop()
        if isTorchOn {
            setTorch(false)
        }
    }

    func beginSwipeRecognition(duration: TimeInterval = 3.2, resetResults: Bool = true) {
        if resetResults || !isAnalyzingText {
            lines.removeAll()
            recognitionUpdateCount = 0
            selectedLineCache.removeAll()
        }

        core.activateRecognition(for: duration)
        isAnalyzingText = true

        recognitionWindowTask?.cancel()
        recognitionWindowTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.stopSwipeRecognition()
            }
        }
    }

    func stopSwipeRecognition(clearResults: Bool = true) {
        recognitionWindowTask?.cancel()
        recognitionWindowTask = nil
        core.deactivateRecognition()
        isAnalyzingText = false

        if clearResults {
            lines.removeAll()
            selectedLineCache.removeAll()
        }
    }

    func cacheSelectedLines(for selectedIDs: Set<CameraRecognizedTextLine.ID>) {
        for line in lines where selectedIDs.contains(line.id) {
            selectedLineCache[line.id] = line
        }
    }

    func clearSelectedLineCache() {
        selectedLineCache.removeAll()
    }

    func selectedLineSnapshots(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> [CameraRecognizedTextLine] {
        selectedLines(for: selectedIDs)
    }

    func text(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> String {
        selectedLines(for: selectedIDs)
            .map(\.text)
            .joined(separator: " ")
            .trimmed
    }

    func averageConfidence(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> Float? {
        let confidences = selectedLines(for: selectedIDs)
            .map(\.confidence)

        guard !confidences.isEmpty else { return nil }
        return confidences.reduce(0, +) / Float(confidences.count)
    }

    func inferredPageReference() -> String? {
        PageReferenceInference.inferredPageReference(
            from: lines.map {
                PageReferenceLine(text: $0.text, boundingBox: $0.boundingBox)
            }
        )
    }

    func currentSnapshotJPEGData() -> Data? {
        core.currentSnapshotJPEGData()
    }

    func currentSnapshotJPEGData(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> Data? {
        let selectedBoxes = selectedLines(for: selectedIDs)
            .map(\.boundingBox)

        return core.currentSnapshotJPEGData(croppedTo: selectedBoxes)
    }

    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    private func setTorch(_ enabled: Bool) {
        core.setTorchEnabled(enabled) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let isEnabled):
                    self?.isTorchOn = isEnabled
                case .failure(let error):
                    self?.isTorchOn = false
                    self?.status = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    private func selectedLines(for selectedIDs: Set<CameraRecognizedTextLine.ID>) -> [CameraRecognizedTextLine] {
        let liveMatches = lines.filter { selectedIDs.contains($0.id) }
        guard !liveMatches.isEmpty else {
            let cachedMatches = selectedLineCache.values
                .filter { selectedIDs.contains($0.id) }
                .sorted(by: readingOrder)
            return deduplicatedSelection(cachedMatches)
        }

        var mergedLines = liveMatches
        let liveIDs = Set(liveMatches.map(\.id))
        let cachedMatches = selectedLineCache.values
            .filter { selectedIDs.contains($0.id) && !liveIDs.contains($0.id) }
        mergedLines.append(contentsOf: cachedMatches)
        return deduplicatedSelection(mergedLines.sorted(by: readingOrder))
    }

    private func readingOrder(_ lhs: CameraRecognizedTextLine, _ rhs: CameraRecognizedTextLine) -> Bool {
        let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        if yDelta > 0.025 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func deduplicatedSelection(_ lines: [CameraRecognizedTextLine]) -> [CameraRecognizedTextLine] {
        lines.reduce(into: [CameraRecognizedTextLine]()) { result, line in
            let normalizedText = line.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let hasEquivalentLine = result.contains { existingLine in
                existingLine.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedText &&
                    abs(existingLine.boundingBox.midY - line.boundingBox.midY) < 0.025
            }

            if !hasEquivalentLine {
                result.append(line)
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

nonisolated final class CameraTextScannerCore: @unchecked Sendable {
    let session = AVCaptureSession()
    var onLines: (([CameraRecognizedTextLine]) -> Void)?
    var onPage: ((CameraDetectedPage?) -> Void)?
    var onBrightness: ((Float?) -> Void)?
    var onFailure: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "aib.overline.camera.session")
    private let visionQueue = DispatchQueue(label: "aib.overline.camera.vision", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sampleBufferDelegate = CameraSampleBufferDelegate()
    private let ciContext = CIContext()
    private let snapshotLock = NSLock()

    private var isConfigured = false
    private var isRecognizingFrame = false
    private var lastRecognitionTime = Date.distantPast
    private var lastPageDetectionTime = Date.distantPast
    private var cameraDevice: AVCaptureDevice?
    private var latestSnapshotData: Data?
    private var latestSnapshotImage: UIImage?
    private var latestDetectedPage: CameraDetectedPage?
    private var pageMissCount = 0
    private let recognitionLock = NSLock()
    private var recognitionDeadline = Date.distantPast

    init() {
        sampleBufferDelegate.owner = self
    }

    func activateRecognition(for duration: TimeInterval) {
        recognitionLock.lock()
        recognitionDeadline = max(recognitionDeadline, Date().addingTimeInterval(duration))
        recognitionLock.unlock()
    }

    func deactivateRecognition() {
        recognitionLock.lock()
        recognitionDeadline = .distantPast
        recognitionLock.unlock()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                if !isConfigured {
                    try configureSession()
                    isConfigured = true
                }

                if !session.isRunning {
                    session.startRunning()
                }
            } catch {
                onFailure?(error.localizedDescription)
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        defer {
            session.commitConfiguration()
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else {
            throw CameraScannerError.cameraUnavailable
        }
        cameraDevice = camera

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraScannerError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: visionQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CameraScannerError.cannotAddOutput
        }
        session.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.videoRotationAngle = 90
    }

    fileprivate func handle(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard !isRecognizingFrame else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        if !isRecognitionActive(at: now) {
            detectPageIfNeeded(in: pixelBuffer, at: now)
            return
        }

        guard now.timeIntervalSince(lastRecognitionTime) > 0.65 else {
            return
        }

        onBrightness?(averageBrightness(from: pixelBuffer))
        storeSnapshotData(from: pixelBuffer)

        isRecognizingFrame = true
        lastRecognitionTime = now

        let textRequest = VNRecognizeTextRequest()
        let documentRequest = VNDetectDocumentSegmentationRequest()

        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["ko-KR", "en-US", "ja-JP"]
        textRequest.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )
            .perform([documentRequest, textRequest])

            let recognizedLines = (textRequest.results ?? [])
                .compactMap { observation -> CameraRecognizedTextLine? in
                    guard
                        let candidate = observation.topCandidates(1).first,
                        !candidate.string.trimmed.isEmpty
                    else {
                        return nil
                    }

                    let textRange = candidate.string.startIndex..<candidate.string.endIndex
                    let recognizedTextBox = (try? candidate.boundingBox(for: textRange)) ?? nil

                    return CameraRecognizedTextLine(
                        text: candidate.string.trimmed,
                        boundingBox: recognizedTextBox?.boundingBox ?? observation.boundingBox,
                        quadrilateral: recognizedTextBox.map(CameraTextQuadrilateral.init(rectangle:)),
                        confidence: candidate.confidence
                    )
                }
                .sorted { lhs, rhs in
                    let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                    if yDelta > 0.025 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }

            let detectedPage = bestPageCandidate(from: documentRequest.results ?? [])
            let displayPage = resolvedDisplayPage(for: detectedPage)

            onLines?(recognizedLines)
            onPage?(displayPage)
        } catch {
            snapshotLock.lock()
            latestDetectedPage = nil
            pageMissCount = 0
            snapshotLock.unlock()
            onPage?(nil)
        }

        isRecognizingFrame = false
    }

    private func detectPageIfNeeded(in pixelBuffer: CVPixelBuffer, at date: Date) {
        guard date.timeIntervalSince(lastPageDetectionTime) > 1.2 else {
            return
        }

        isRecognizingFrame = true
        lastPageDetectionTime = date

        let documentRequest = VNDetectDocumentSegmentationRequest()

        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )
            .perform([documentRequest])

            let detectedPage = bestPageCandidate(from: documentRequest.results ?? [])
            let displayPage = resolvedDisplayPage(for: detectedPage)
            onPage?(displayPage)
        } catch {
            onPage?(nil)
        }

        isRecognizingFrame = false
    }

    private func isRecognitionActive(at date: Date) -> Bool {
        recognitionLock.lock()
        let isActive = recognitionDeadline > date
        recognitionLock.unlock()
        return isActive
    }

    private func averageBrightness(from pixelBuffer: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4
        let stepX = max(width / 24, 1)
        let stepY = max(height / 24, 1)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total: Float = 0
        var sampleCount: Float = 0

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let blue = Float(buffer[offset])
                let green = Float(buffer[offset + 1])
                let red = Float(buffer[offset + 2])
                total += (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }
        return min(max(total / sampleCount, 0), 1)
    }

    func currentSnapshotJPEGData() -> Data? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return latestSnapshotData
    }

    func currentSnapshotJPEGData(croppedTo boundingBoxes: [CGRect]) -> Data? {
        snapshotLock.lock()
        let image = latestSnapshotImage
        let fallbackData = latestSnapshotData
        let detectedPage = latestDetectedPage
        snapshotLock.unlock()

        if
            let image,
            let detectedPage,
            let correctedData = perspectiveCorrectedJPEGData(
                croppedTo: boundingBoxes,
                in: image,
                page: detectedPage
            )
        {
            return correctedData
        }

        guard
            !boundingBoxes.isEmpty,
            let image,
            let cgImage = image.cgImage,
            let cropRect = cropRect(
                for: boundingBoxes,
                pageBoundingBox: detectedPage?.boundingBox,
                in: CGSize(width: cgImage.width, height: cgImage.height)
            ),
            let croppedCGImage = cgImage.cropping(to: cropRect)
        else {
            return fallbackData
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
            .jpegData(compressionQuality: 0.78)
            ?? fallbackData
    }

    private func storeSnapshotData(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        let image = UIImage(cgImage: cgImage)
        guard let data = image.jpegData(compressionQuality: 0.72) else {
            return
        }

        snapshotLock.lock()
        latestSnapshotData = data
        latestSnapshotImage = image
        snapshotLock.unlock()
    }

    private func perspectiveCorrectedJPEGData(
        croppedTo boundingBoxes: [CGRect],
        in image: UIImage,
        page: CameraDetectedPage
    ) -> Data? {
        guard
            !boundingBoxes.isEmpty,
            page.area > 0.08,
            let correctedImage = perspectiveCorrectedPageImage(from: image, page: page),
            let correctedCGImage = correctedImage.cgImage
        else {
            return nil
        }

        let correctedSize = CGSize(width: correctedCGImage.width, height: correctedCGImage.height)
        let correctedBoxes = boundingBoxes.compactMap { box -> CGRect? in
            let clippedBox = box.intersection(page.boundingBox)
            guard
                !clippedBox.isNull,
                clippedBox.width > 0,
                clippedBox.height > 0,
                page.boundingBox.width > 0,
                page.boundingBox.height > 0
            else {
                return nil
            }

            let x = normalized((clippedBox.minX - page.boundingBox.minX) / page.boundingBox.width)
            let y = normalized((clippedBox.minY - page.boundingBox.minY) / page.boundingBox.height)
            let maxX = normalized((clippedBox.maxX - page.boundingBox.minX) / page.boundingBox.width)
            let maxY = normalized((clippedBox.maxY - page.boundingBox.minY) / page.boundingBox.height)

            return CGRect(
                x: x,
                y: y,
                width: max(maxX - x, 0),
                height: max(maxY - y, 0)
            )
        }

        guard
            let cropRect = cropRect(for: correctedBoxes, pageBoundingBox: nil, in: correctedSize),
            let croppedCGImage = correctedCGImage.cropping(to: cropRect)
        else {
            return correctedImage.jpegData(compressionQuality: 0.78)
        }

        return UIImage(cgImage: croppedCGImage, scale: correctedImage.scale, orientation: .up)
            .jpegData(compressionQuality: 0.78)
    }

    private func perspectiveCorrectedPageImage(from image: UIImage, page: CameraDetectedPage) -> UIImage? {
        guard
            let cgImage = image.cgImage,
            let filter = CIFilter(name: "CIPerspectiveCorrection")
        else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let ciImage = CIImage(cgImage: cgImage)
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: ciPoint(for: page.topLeft, in: imageSize)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: ciPoint(for: page.topRight, in: imageSize)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: ciPoint(for: page.bottomRight, in: imageSize)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: ciPoint(for: page.bottomLeft, in: imageSize)), forKey: "inputBottomLeft")

        guard
            let outputImage = filter.outputImage,
            let correctedCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return UIImage(cgImage: correctedCGImage, scale: image.scale, orientation: .up)
    }

    private func ciPoint(for normalizedPoint: CGPoint, in imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalized(normalizedPoint.x) * imageSize.width,
            y: normalized(normalizedPoint.y) * imageSize.height
        )
    }

    private func normalized(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func bestPageCandidate(from observations: [VNRectangleObservation]) -> CameraDetectedPage? {
        observations
            .map {
                CameraDetectedPage(
                    boundingBox: $0.boundingBox,
                    topLeft: $0.topLeft,
                    topRight: $0.topRight,
                    bottomRight: $0.bottomRight,
                    bottomLeft: $0.bottomLeft
                )
            }
            .filter(isUsableBookPage)
            .max { pageScore($0) < pageScore($1) }
    }

    private func isUsableBookPage(_ page: CameraDetectedPage) -> Bool {
        let box = page.boundingBox.standardized
        let area = box.width * box.height
        let aspectRatio = box.width / max(box.height, 0.001)

        guard area >= 0.16, area <= 0.96 else { return false }
        guard box.width >= 0.36, box.height >= 0.34 else { return false }
        guard aspectRatio >= 0.42, aspectRatio <= 1.65 else { return false }
        guard abs(box.midX - 0.5) <= 0.42, abs(box.midY - 0.5) <= 0.44 else { return false }
        return true
    }

    private func pageScore(_ page: CameraDetectedPage) -> CGFloat {
        let box = page.boundingBox.standardized
        let centerPenalty = abs(box.midX - 0.5) * 0.18 + abs(box.midY - 0.5) * 0.12
        let aspectPenalty = abs((box.width / max(box.height, 0.001)) - 0.72) * 0.08
        return page.area - centerPenalty - aspectPenalty
    }

    private func resolvedDisplayPage(for detectedPage: CameraDetectedPage?) -> CameraDetectedPage? {
        snapshotLock.lock()
        defer {
            snapshotLock.unlock()
        }

        if let detectedPage {
            latestDetectedPage = detectedPage
            pageMissCount = 0
            return detectedPage
        }

        pageMissCount += 1
        if pageMissCount < 3 {
            return latestDetectedPage
        }

        latestDetectedPage = nil
        return nil
    }

    private func cropRect(
        for boundingBoxes: [CGRect],
        pageBoundingBox: CGRect?,
        in imageSize: CGSize
    ) -> CGRect? {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let lineRects = boundingBoxes.map { box in
            CGRect(
                x: box.minX * imageSize.width,
                y: (1 - box.maxY) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
        }
        let pageRect = pageBoundingBox.map { box in
            CGRect(
                x: box.minX * imageSize.width,
                y: (1 - box.maxY) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            .insetBy(dx: -imageSize.width * 0.015, dy: -imageSize.height * 0.015)
            .intersection(imageBounds)
        }

        guard var cropRect = lineRects.first else { return nil }
        for rect in lineRects.dropFirst() {
            cropRect = cropRect.union(rect)
        }

        let minWidth = imageSize.width * 0.78
        let minHeight = imageSize.height * 0.20
        cropRect = cropRect.insetBy(
            dx: -max(24, imageSize.width * 0.045),
            dy: -max(26, cropRect.height * 1.4)
        )

        if cropRect.width < minWidth {
            cropRect = cropRect.insetBy(dx: -(minWidth - cropRect.width) / 2, dy: 0)
        }

        if cropRect.height < minHeight {
            cropRect = cropRect.insetBy(dx: 0, dy: -(minHeight - cropRect.height) / 2)
        }

        let cropBounds = pageRect?.isNull == false ? pageRect ?? imageBounds : imageBounds
        let boundedRect = cropRect.intersection(cropBounds).intersection(imageBounds).integral
        guard boundedRect.width >= 2, boundedRect.height >= 2 else { return nil }
        return boundedRect
    }

    var isTorchAvailable: Bool {
        if let cameraDevice {
            return cameraDevice.hasTorch
        }

        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasTorch == true
    }

    func setTorchEnabled(_ enabled: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard
                let camera = cameraDevice ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                camera.hasTorch,
                camera.isTorchAvailable
            else {
                completion(.failure(CameraScannerError.torchUnavailable))
                return
            }

            do {
                try camera.lockForConfiguration()
                defer {
                    camera.unlockForConfiguration()
                }

                if enabled {
                    try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    camera.torchMode = .off
                }

                completion(.success(camera.torchMode == .on))
            } catch {
                completion(.failure(CameraScannerError.cannotSetTorch))
            }
        }
    }
}

nonisolated private final class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    weak var owner: CameraTextScannerCore?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        owner?.handle(sampleBuffer)
    }
}

private enum CameraScannerError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case torchUnavailable
    case cannotSetTorch

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "카메라를 사용할 수 없습니다."
        case .cannotAddInput:
            "카메라 입력을 연결할 수 없습니다."
        case .cannotAddOutput:
            "카메라 프레임 출력을 연결할 수 없습니다."
        case .torchUnavailable:
            "이 기기에서는 플래시를 사용할 수 없습니다."
        case .cannotSetTorch:
            "플래시를 전환할 수 없습니다."
        }
    }
}
