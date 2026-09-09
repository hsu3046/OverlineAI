import SwiftUI

enum CaptureTutorialStep: Int {
    case addBook, bookForm, chooseBook, capture, selection, saved

    var title: String {
        switch self {
        case .addBook: "책 등록하기"
        case .bookForm: "책 정보 입력하기"
        case .chooseBook: "저장할 책 선택하기"
        case .capture: "책 페이지 캡처하기"
        case .selection: "문장 선택하기"
        case .saved: "글조각 활용하기"
        }
    }

    var message: String {
        switch self {
        case .addBook: "위의 + 버튼으로 읽고 있는 책을 등록하세요."
        case .bookForm: "책을 검색하거나 책 이름을 직접 입력한 뒤, 오른쪽 위 체크를 누르세요. 등록한 책은 내 책장에 남습니다."
        case .chooseBook: "위에서 글조각을 담을 책을 선택하세요. 지금 표시된 책에 저장됩니다."
        case .capture: "글 캡처를 누르거나 오른쪽 사진 버튼으로 책 페이지를 불러오세요."
        case .selection: "문장에 밑줄이나 네모를 그려보세요. 손을 떼면 자동으로 인식해 저장합니다."
        case .saved: "저장한 글조각은 책장에서 메모를 더하거나 음성으로 들을 수 있어요. 인사이트에서 생각을 정리해보세요. 지우개는 화면의 선택만 지웁니다."
        }
    }
}

@MainActor @Observable
final class CaptureTutorial {
    static let completedKey = "captureTutorialCompletedV2"
    var step: CaptureTutorialStep?
    var replayRequested = false

    func start() { step = .addBook }

    func previous() {
        guard let step else { return }
        self.step = CaptureTutorialStep(rawValue: max(0, step.rawValue - 1))
    }

    func next() {
        guard let step else { return }
        if let next = CaptureTutorialStep(rawValue: step.rawValue + 1) {
            self.step = next
        } else {
            finish()
        }
    }

    func advance(from expected: CaptureTutorialStep, to next: CaptureTutorialStep) {
        guard step == expected else { return }
        step = next
    }

    func finish() {
        step = nil
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }
}

private struct CaptureTutorialKey: EnvironmentKey {
    static let defaultValue: CaptureTutorial? = nil
}

extension EnvironmentValues {
    var captureTutorial: CaptureTutorial? {
        get { self[CaptureTutorialKey.self] }
        set { self[CaptureTutorialKey.self] = newValue }
    }
}

// Keep instructions beside real controls, including inside presented sheets.
struct CaptureTutorialTip: View {
    @Environment(\.captureTutorial) private var tutorial
    @AccessibilityFocusState private var headingFocused: Bool
    let step: CaptureTutorialStep

    var body: some View {
        if tutorial?.step == step {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(step.title)
                        .font(.overline(.headline, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                    Spacer()
                    Button("건너뛰기") { tutorial?.finish() }
                        .font(.overline(.caption))
                        .foregroundStyle(Color.tutorialSecondary)
                        .padding(.vertical, 8)
                }
                Text(step.message)
                    .font(.overline(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text("\(step.rawValue + 1) / 6")
                        .font(.overline(.caption))
                        .foregroundStyle(Color.tutorialSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Button("이전") { tutorial?.previous() }
                        .font(.overline(.caption))
                        .foregroundStyle(Color.tutorialSecondary.opacity(step == .addBook ? 0.4 : 1))
                        .disabled(step == .addBook)
                        .frame(minWidth: 44, minHeight: 44)
                    Button(step == .saved ? "완료" : "다음") { tutorial?.next() }
                        .font(.overline(.subheadline, weight: .bold))
                        .foregroundStyle(Color.overlineInk)
                        .frame(minWidth: 88, minHeight: 44)
                        .background(Color.tutorialAccent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Color.overlineInk)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
            .background(Color.tutorialAccent, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.tutorialAccent, lineWidth: 2)
            }
            .onAppear { headingFocused = true }
        }
    }
}

extension Color {
    static let tutorialAccent = StickyTone.yellow.paper
    static let tutorialSecondary = Color(white: 0.42)
}

extension View {
    func tutorialHighlight(_ isActive: Bool, cornerRadius: CGFloat = 12) -> some View {
        overlay {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.tutorialAccent, lineWidth: 2.5)
                    .padding(-5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct TutorialUnderlineGesture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress: CGFloat = 0
    @State private var isVisible = false

    private var shouldAnimate: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { proxy in
            let start = proxy.size.width * 0.2
            let distance = proxy.size.width * 0.6
            let y = proxy.size.height * 0.5
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: start, y: y))
                    path.addLine(to: CGPoint(x: start + distance * progress, y: y))
                }
                .stroke(Color.tutorialAccent.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .position(x: start + distance * progress + 12, y: y + 20)
            }
            .opacity(isVisible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: shouldAnimate) {
            progress = 0
            isVisible = scenePhase == .active
            guard shouldAnimate else {
                progress = 0.65
                return
            }
            // Demonstrate twice, then leave the real page unobstructed.
            for _ in 0..<2 {
                progress = 0
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeInOut(duration: 1.4)) { progress = 1 }
                    try await Task.sleep(for: .milliseconds(1900))
                } catch { return }
            }
            isVisible = false
        }
    }
}
