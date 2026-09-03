@preconcurrency import AVFoundation
import SwiftUI

struct ISBNScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manualISBN = ""
    @State private var isManualEntryVisible = false
    @State private var scannerUnavailableMessage: String?

    let onISBN: (String, Bool) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                #if targetEnvironment(simulator)
                simulatorFallback
                #else
                ISBNScannerPreview { isbn in
                    onISBN(isbn, true)
                    dismiss()
                } onUnavailable: { message in
                    scannerUnavailableMessage = message
                }
                .ignoresSafeArea()

                if let scannerUnavailableMessage {
                    scannerUnavailableOverlay(scannerUnavailableMessage)
                } else {
                    scannerOverlay
                }
                #endif
            }
            .navigationTitle("ISBN 스캔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    #if targetEnvironment(simulator)
                    EmptyView()
                    #else
                    Button(isManualEntryVisible ? "스캔" : "직접 입력") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isManualEntryVisible.toggle()
                        }
                    }
                    #endif
                }
            }
            .overlineKeyboardDismissToolbar()
        }
    }

    private func scannerUnavailableOverlay(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(message)
                    .font(.overline(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)

            manualISBNControls(backgroundOpacity: 0.88)
        }
        .padding(24)
        .background(.black.opacity(0.42))
    }

    private var scannerOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text("책 뒤표지의 ISBN 바코드를 프레임 안에 맞춰 주세요.")
                    .font(.overline(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.bottom, isManualEntryVisible ? 16 : 40)

            if isManualEntryVisible {
                manualISBNControls(backgroundOpacity: 0.88)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .frame(width: 270, height: 140)
        }
    }

    private var simulatorFallback: some View {
        VStack(spacing: 18) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.overlineAccent)

            VStack(spacing: 8) {
                Text("시뮬레이터에서는 카메라 스캔을 사용할 수 없습니다.")
                    .font(.overline(.headline))
                    .foregroundStyle(Color.overlineInk)

                Text("실제 기기에서는 ISBN 바코드를 자동으로 읽습니다.")
                    .font(.overline(.subheadline))
                    .foregroundStyle(Color.overlineMutedInk)
                    .multilineTextAlignment(.center)
            }

            manualISBNControls(backgroundOpacity: 0.78)
        }
        .padding(24)
        .background(Color.overlineCanvas.ignoresSafeArea())
    }

    private func manualISBNControls(backgroundOpacity: Double) -> some View {
        VStack(spacing: 10) {
            TextField("ISBN 입력", text: $manualISBN)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.white.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                onISBN(manualISBN.filter(\.isNumber), false)
                dismiss()
            } label: {
                Label("ISBN 적용", systemImage: "checkmark.circle")
                    .font(.overline(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualISBN.filter(\.isNumber).count < 10)
        }
    }
}

private struct ISBNScannerPreview: UIViewControllerRepresentable {
    let onISBN: (String) -> Void
    let onUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> ISBNScannerViewController {
        let controller = ISBNScannerViewController()
        controller.onISBN = onISBN
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ uiViewController: ISBNScannerViewController, context: Context) {}
}

private final class ISBNScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onISBN: ((String) -> Void)?
    var onUnavailable: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "vote.aib.bzogak.isbn-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didDetectISBN = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAccessIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func requestCameraAccessIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    self?.notifyUnavailable("ISBN 스캔을 사용하려면 카메라 권한이 필요합니다.")
                    return
                }
                self?.configureAndStart()
            }
        default:
            notifyUnavailable("카메라 권한이 꺼져 있어 ISBN을 직접 입력해 주세요.")
            return
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard session.inputs.isEmpty, session.outputs.isEmpty else {
                startSession()
                return
            }

            guard
                let camera = CameraDeviceSelection.preferredBackCamera(),
                let input = try? AVCaptureDeviceInput(device: camera),
                session.canAddInput(input)
            else {
                notifyUnavailable("이 기기에서는 ISBN 스캔 카메라를 사용할 수 없습니다.")
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            CameraDeviceSelection.logSelectedCamera(camera)
            CameraDeviceSelection.applyPreferredCenterCropZoom(to: camera)

            let metadataOutput = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadataOutput) else {
                session.commitConfiguration()
                notifyUnavailable("ISBN 바코드 스캔을 시작할 수 없습니다.")
                return
            }

            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            let supportedTypes = metadataOutput.availableMetadataObjectTypes.filter {
                [.ean13, .ean8, .upce, .code128].contains($0)
            }

            guard !supportedTypes.isEmpty else {
                session.commitConfiguration()
                notifyUnavailable("이 기기에서는 ISBN 바코드 형식을 스캔할 수 없습니다.")
                return
            }

            metadataOutput.metadataObjectTypes = supportedTypes
            session.commitConfiguration()

            Task { @MainActor in
                self.installPreviewLayerIfNeeded()
            }

            startSession()
        }
    }

    private func notifyUnavailable(_ message: String) {
        Task { @MainActor [weak self] in
            self?.onUnavailable?(message)
        }
    }

    private func installPreviewLayerIfNeeded() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func startSession() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let isbn = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .compactMap(\.stringValue)
            .map { $0.filter(\.isNumber) }
            .first { value in
                (value.count == 13 && (value.hasPrefix("978") || value.hasPrefix("979"))) || value.count == 10
            }

        guard let isbn else { return }
        Task { @MainActor [weak self] in
            self?.handleDetectedISBN(isbn)
        }
    }

    private func handleDetectedISBN(_ isbn: String) {
        guard !didDetectISBN else { return }
        didDetectISBN = true
        onISBN?(isbn)
    }
}

#Preview {
    ISBNScannerSheet { _, _ in }
}
