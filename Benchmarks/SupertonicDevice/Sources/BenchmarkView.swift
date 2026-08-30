import SwiftUI

struct BenchmarkView: View {
    @State private var model = BenchmarkViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("한국어 문단") {
                    TextEditor(text: $model.text)
                        .frame(minHeight: 170)
                }

                Section("합성 설정") {
                    Picker("목소리", selection: $model.voice) {
                        ForEach(SupertonicVoice.allCases) { voice in
                            Text(voice.title).tag(voice)
                        }
                    }

                    Picker("품질 단계", selection: $model.steps) {
                        ForEach([5, 8, 12], id: \.self) { steps in
                            Text("\(steps)").tag(steps)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("속도", selection: $model.speed) {
                        ForEach([0.8, 1.0, 1.2, 1.4], id: \.self) { speed in
                            Text(speed.formatted(.number.precision(.fractionLength(1))) + "x")
                                .tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("실기기 측정") {
                    Button("모델 준비") {
                        model.prepareModel()
                    }
                    .disabled(model.isBusy || model.isPrepared)

                    Button("생성 및 재생") {
                        model.generateAndPlay()
                    }
                    .disabled(model.isBusy || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("재생 중지", role: .destructive) {
                        model.stopPlayback()
                    }
                    .disabled(!model.isPlaying)
                }

                if let status = model.status {
                    Section("상태") {
                        Text(status)
                    }
                }

                if let metrics = model.metrics {
                    Section("측정 결과") {
                        metricRow("모델 준비", metrics.prepareMilliseconds.map { "\($0) ms" })
                        metricRow("합성", "\(metrics.synthesisMilliseconds) ms")
                        metricRow("오디오", metrics.audioDuration.formatted(.number.precision(.fractionLength(2))) + " s")
                        metricRow("RTF", metrics.rtf.formatted(.number.precision(.fractionLength(3))))
                        metricRow("재생 요청까지", "\(metrics.firstAudioRequestMilliseconds) ms")
                        metricRow("준비 전 메모리", metrics.memoryBeforePrepare.formattedBytes)
                        metricRow("준비 후 메모리", metrics.memoryAfterPrepare.formattedBytes)
                        metricRow("합성 후 메모리", metrics.memoryAfterSynthesis.formattedBytes)
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section("오류") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Supertonic 실기기 측정")
        }
    }

    @ViewBuilder
    private func metricRow(_ title: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(title, value: value)
        }
    }
}
