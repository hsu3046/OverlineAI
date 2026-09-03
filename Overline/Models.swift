import Foundation
import Observation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let overlineHighlightsRemoved = Notification.Name("overline.highlightsRemoved")
    static let overlineQuoteSpeechWillStart = Notification.Name("overline.quoteSpeechWillStart")
    static let overlinePageReadingWillStart = Notification.Name("overline.pageReadingWillStart")
}

enum OverlineNotificationUserInfoKey {
    static let highlightIDs = "highlightIDs"
}

nonisolated enum StickyTone: String, Codable, CaseIterable, Sendable {
    case yellow
    case blue
    case rose
    case mint

    var paper: Color {
        switch self {
        case .yellow: Color(red: 0.98, green: 0.86, blue: 0.31)
        case .blue: Color(red: 0.56, green: 0.79, blue: 0.92)
        case .rose: Color(red: 0.95, green: 0.58, blue: 0.67)
        case .mint: Color(red: 0.58, green: 0.82, blue: 0.68)
        }
    }

    var ink: Color {
        switch self {
        case .yellow: Color(red: 0.30, green: 0.23, blue: 0.08)
        case .blue: Color(red: 0.08, green: 0.22, blue: 0.33)
        case .rose: Color(red: 0.34, green: 0.10, blue: 0.16)
        case .mint: Color(red: 0.08, green: 0.24, blue: 0.15)
        }
    }

    var accessibilityName: String {
        switch self {
        case .yellow: "노랑"
        case .rose: "핑크"
        case .blue: "파랑"
        case .mint: "녹색"
        }
    }
}

nonisolated enum CoverTheme: String, Codable, CaseIterable, Sendable {
    case forest
    case cobalt
    case vermilion

    var gradient: LinearGradient {
        switch self {
        case .forest:
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.31, blue: 0.25),
                    Color(red: 0.52, green: 0.67, blue: 0.38),
                    Color(red: 0.94, green: 0.84, blue: 0.49)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cobalt:
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.18, blue: 0.36),
                    Color(red: 0.18, green: 0.47, blue: 0.76),
                    Color(red: 0.93, green: 0.62, blue: 0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vermilion:
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.12, blue: 0.14),
                    Color(red: 0.82, green: 0.32, blue: 0.23),
                    Color(red: 0.98, green: 0.78, blue: 0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

nonisolated enum CaptureLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case korean
    case english
    case japanese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var shortTitle: String {
        switch self {
        case .korean: "KR"
        case .english: "EN"
        case .japanese: "JP"
        }
    }

    var tag: String {
        switch self {
        case .korean: "#한국어"
        case .english: "#English"
        case .japanese: "#日本語"
        }
    }

    nonisolated static func detect(from text: String) -> CaptureLanguage {
        if text.range(of: #"[가-힣]"#, options: .regularExpression) != nil {
            return .korean
        }

        if text.range(of: #"[ぁ-ゟ゠-ヿ]"#, options: .regularExpression) != nil {
            return .japanese
        }

        return .english
    }
}

nonisolated enum HighlightSource: String, Codable, Sendable {
    case sample
    case capture
    case shortcut
}

nonisolated enum BookMetadataSource: String, Codable, CaseIterable, Sendable {
    case manual
    case kakao
    case aladin
    case google
}

nonisolated struct Highlight: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var text: String
    var memo: String
    var pageReference: String
    var createdAt: Date
    var language: CaptureLanguage
    var tags: [String]
    var stickyTone: StickyTone
    var source: HighlightSource
    var reviewedAt: Date?

    init(
        id: UUID = UUID(),
        text: String,
        memo: String,
        pageReference: String,
        createdAt: Date = .now,
        language: CaptureLanguage,
        tags: [String],
        stickyTone: StickyTone,
        source: HighlightSource,
        reviewedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.memo = memo
        self.pageReference = pageReference
        self.createdAt = createdAt
        self.language = language
        self.tags = tags
        self.stickyTone = stickyTone
        self.source = source
        self.reviewedAt = reviewedAt
    }
}

nonisolated struct LibraryInsight: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var categoryRaw: String
    var prompt: String
    var body: String
    var sourceCount: Int
    var sourceHighlightIDs: [Highlight.ID]?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        categoryRaw: String,
        prompt: String,
        body: String,
        sourceCount: Int,
        sourceHighlightIDs: [Highlight.ID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.prompt = prompt
        self.body = body
        self.sourceCount = sourceCount
        self.sourceHighlightIDs = sourceHighlightIDs
        self.createdAt = createdAt
    }
}

nonisolated enum ReadingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case reading
    case completed
    case paused
    case abandoned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reading: "읽는 중"
        case .completed: "완독"
        case .paused: "잠시 멈춤"
        case .abandoned: "중단"
        }
    }

    var systemImage: String {
        switch self {
        case .reading: "book.pages"
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .abandoned: "stop.circle"
        }
    }
}

nonisolated struct ReadingRecord: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var status: ReadingStatus
    var rating: Double?
    var review: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        status: ReadingStatus,
        rating: Double? = nil,
        review: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.rating = rating
        self.review = review
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DeletedHighlightSnapshot: Identifiable, Hashable {
    let id = UUID()
    let highlight: Highlight
    let bookID: ReadingBook.ID
    let index: Int
}

struct DeletedInsightSnapshot: Identifiable, Hashable {
    let id = UUID()
    let insight: LibraryInsight
    let index: Int
}

struct CapturePerformanceRecord: Identifiable, Hashable, Codable {
    var id: UUID
    var createdAt: Date
    var source: String
    var durationMilliseconds: Int
    var lineCount: Int
    var confidencePercent: Int?
    var brightnessPercent: Int?
    var hasMemo: Bool
    var pathStepCount: Int?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: String,
        durationMilliseconds: Int,
        lineCount: Int,
        confidencePercent: Int? = nil,
        brightnessPercent: Int? = nil,
        hasMemo: Bool,
        pathStepCount: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.durationMilliseconds = durationMilliseconds
        self.lineCount = lineCount
        self.confidencePercent = confidencePercent
        self.brightnessPercent = brightnessPercent
        self.hasMemo = hasMemo
        self.pathStepCount = pathStepCount
    }

    var isCameraCapture: Bool {
        source == "camera"
    }

    var meetsSpeedTarget: Bool {
        isCameraCapture && durationMilliseconds <= 10_000
    }

    var meetsPathTarget: Bool {
        guard isCameraCapture, let pathStepCount else { return false }
        return pathStepCount <= 3
    }

    var durationLabel: String {
        let seconds = Double(durationMilliseconds) / 1000
        return "\(seconds.formatted(.number.precision(.fractionLength(1))))초"
    }

    var pathStepLabel: String {
        guard let pathStepCount else { return "-" }
        return "\(pathStepCount)단계"
    }

    var confidenceLabel: String {
        confidencePercent.map { "\($0)%" } ?? "-"
    }

    var brightnessLabel: String {
        brightnessPercent.map { "\($0)%" } ?? "-"
    }
}

enum CapturePerformanceStore {
    private static let key = "overline.capturePerformance.records.v1"
    private static let recordLimit = 50

    static func load() -> [CapturePerformanceRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let records = try? JSONDecoder().decode([CapturePerformanceRecord].self, from: data)
        else {
            return []
        }

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    static func add(_ record: CapturePerformanceRecord) {
        let records = ([record] + load())
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recordLimit)
        save(Array(records))
    }

    private static func save(_ records: [CapturePerformanceRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct AppUsageMetrics: Codable, Equatable {
    var totalOpenCount: Int
    var firstOpenAt: Date?
    var lastOpenAt: Date?
    var activeDayStamps: [String]

    init(
        totalOpenCount: Int = 0,
        firstOpenAt: Date? = nil,
        lastOpenAt: Date? = nil,
        activeDayStamps: [String] = []
    ) {
        self.totalOpenCount = totalOpenCount
        self.firstOpenAt = firstOpenAt
        self.lastOpenAt = lastOpenAt
        self.activeDayStamps = activeDayStamps
    }

    func activeDayCount(inLast dayCount: Int = 7, now: Date = .now) -> Int {
        let activeDays = Set(activeDayStamps)
        let recentDays = Set((0..<dayCount).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: now)
                .map { AppUsageMetricsStore.dayStamp(for: $0) }
        })
        return activeDays.intersection(recentDays).count
    }

    func d7StatusLabel(now: Date = .now) -> String {
        guard let firstOpenAt else { return "-" }
        let firstDay = Calendar.current.startOfDay(for: firstOpenAt)
        let today = Calendar.current.startOfDay(for: now)
        let dayOffset = Calendar.current.dateComponents([.day], from: firstDay, to: today).day ?? 0

        guard dayOffset >= 7 else {
            return "D+\(max(dayOffset, 0))"
        }

        guard
            let d7Date = Calendar.current.date(byAdding: .day, value: 7, to: firstDay)
        else {
            return "-"
        }

        return activeDayStamps.contains(AppUsageMetricsStore.dayStamp(for: d7Date)) ? "재방문" : "미확인"
    }
}

enum AppUsageMetricsStore {
    private static let key = "overline.appUsageMetrics.v1"
    private static let duplicateOpenThreshold: TimeInterval = 60

    static func load() -> AppUsageMetrics {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let metrics = try? JSONDecoder().decode(AppUsageMetrics.self, from: data)
        else {
            return AppUsageMetrics()
        }

        return metrics
    }

    static func recordOpen(now: Date = .now) {
        var metrics = load()
        if
            let lastOpenAt = metrics.lastOpenAt,
            now.timeIntervalSince(lastOpenAt) < duplicateOpenThreshold
        {
            return
        }

        metrics.totalOpenCount += 1
        metrics.firstOpenAt = metrics.firstOpenAt ?? now
        metrics.lastOpenAt = now

        let todayStamp = dayStamp(for: now)
        var activeDayStamps = Set(metrics.activeDayStamps)
        activeDayStamps.insert(todayStamp)
        metrics.activeDayStamps = activeDayStamps.sorted()

        save(metrics)
    }

    static func dayStamp(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func save(_ metrics: AppUsageMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct MVPReadinessChecklist: Codable, Equatable {
    var captureSpeedVerified: Bool
    var capturePathVerified: Bool
    var ocrAccuracyVerified: Bool
    var pageBoundaryVerified: Bool
    var snapshotCropVerified: Bool
    var lowLightVerified: Bool
    var isbnScanVerified: Bool
    var speechMemoVerified: Bool
    var kakaoSearchVerified: Bool
    var llmInsightVerified: Bool
    var captureSpeedVerifiedAt: Date?
    var capturePathVerifiedAt: Date?
    var ocrAccuracyVerifiedAt: Date?
    var pageBoundaryVerifiedAt: Date?
    var snapshotCropVerifiedAt: Date?
    var lowLightVerifiedAt: Date?
    var isbnScanVerifiedAt: Date?
    var speechMemoVerifiedAt: Date?
    var kakaoSearchVerifiedAt: Date?
    var llmInsightVerifiedAt: Date?
    var note: String
    var updatedAt: Date

    init(
        captureSpeedVerified: Bool = false,
        capturePathVerified: Bool = false,
        ocrAccuracyVerified: Bool = false,
        pageBoundaryVerified: Bool = false,
        snapshotCropVerified: Bool = false,
        lowLightVerified: Bool = false,
        isbnScanVerified: Bool = false,
        speechMemoVerified: Bool = false,
        kakaoSearchVerified: Bool = false,
        llmInsightVerified: Bool = false,
        captureSpeedVerifiedAt: Date? = nil,
        capturePathVerifiedAt: Date? = nil,
        ocrAccuracyVerifiedAt: Date? = nil,
        pageBoundaryVerifiedAt: Date? = nil,
        snapshotCropVerifiedAt: Date? = nil,
        lowLightVerifiedAt: Date? = nil,
        isbnScanVerifiedAt: Date? = nil,
        speechMemoVerifiedAt: Date? = nil,
        kakaoSearchVerifiedAt: Date? = nil,
        llmInsightVerifiedAt: Date? = nil,
        note: String = "",
        updatedAt: Date = .now
    ) {
        self.captureSpeedVerified = captureSpeedVerified
        self.capturePathVerified = capturePathVerified
        self.ocrAccuracyVerified = ocrAccuracyVerified
        self.pageBoundaryVerified = pageBoundaryVerified
        self.snapshotCropVerified = snapshotCropVerified
        self.lowLightVerified = lowLightVerified
        self.isbnScanVerified = isbnScanVerified
        self.speechMemoVerified = speechMemoVerified
        self.kakaoSearchVerified = kakaoSearchVerified
        self.llmInsightVerified = llmInsightVerified
        self.captureSpeedVerifiedAt = captureSpeedVerifiedAt
        self.capturePathVerifiedAt = capturePathVerifiedAt
        self.ocrAccuracyVerifiedAt = ocrAccuracyVerifiedAt
        self.pageBoundaryVerifiedAt = pageBoundaryVerifiedAt
        self.snapshotCropVerifiedAt = snapshotCropVerifiedAt
        self.lowLightVerifiedAt = lowLightVerifiedAt
        self.isbnScanVerifiedAt = isbnScanVerifiedAt
        self.speechMemoVerifiedAt = speechMemoVerifiedAt
        self.kakaoSearchVerifiedAt = kakaoSearchVerifiedAt
        self.llmInsightVerifiedAt = llmInsightVerifiedAt
        self.note = note
        self.updatedAt = updatedAt
    }

    var completedCount: Int {
        [
            captureSpeedVerified,
            capturePathVerified,
            ocrAccuracyVerified,
            pageBoundaryVerified,
            snapshotCropVerified,
            lowLightVerified,
            isbnScanVerified,
            speechMemoVerified,
            kakaoSearchVerified,
            llmInsightVerified
        ]
        .filter { $0 }
        .count
    }

    var totalCount: Int { MVPReadinessItem.allCases.count }

    var isReady: Bool {
        completedCount == totalCount
    }

    private enum CodingKeys: String, CodingKey {
        case captureSpeedVerified
        case capturePathVerified
        case ocrAccuracyVerified
        case pageBoundaryVerified
        case snapshotCropVerified
        case lowLightVerified
        case isbnScanVerified
        case speechMemoVerified
        case kakaoSearchVerified
        case llmInsightVerified
        case captureSpeedVerifiedAt
        case capturePathVerifiedAt
        case ocrAccuracyVerifiedAt
        case pageBoundaryVerifiedAt
        case snapshotCropVerifiedAt
        case lowLightVerifiedAt
        case isbnScanVerifiedAt
        case speechMemoVerifiedAt
        case kakaoSearchVerifiedAt
        case llmInsightVerifiedAt
        case note
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureSpeedVerified = try container.decodeIfPresent(Bool.self, forKey: .captureSpeedVerified) ?? false
        capturePathVerified = try container.decodeIfPresent(Bool.self, forKey: .capturePathVerified) ?? false
        ocrAccuracyVerified = try container.decodeIfPresent(Bool.self, forKey: .ocrAccuracyVerified) ?? false
        pageBoundaryVerified = try container.decodeIfPresent(Bool.self, forKey: .pageBoundaryVerified) ?? false
        snapshotCropVerified = try container.decodeIfPresent(Bool.self, forKey: .snapshotCropVerified) ?? false
        lowLightVerified = try container.decodeIfPresent(Bool.self, forKey: .lowLightVerified) ?? false
        isbnScanVerified = try container.decodeIfPresent(Bool.self, forKey: .isbnScanVerified) ?? false
        speechMemoVerified = try container.decodeIfPresent(Bool.self, forKey: .speechMemoVerified) ?? false
        kakaoSearchVerified = try container.decodeIfPresent(Bool.self, forKey: .kakaoSearchVerified) ?? false
        llmInsightVerified = try container.decodeIfPresent(Bool.self, forKey: .llmInsightVerified) ?? false
        captureSpeedVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .captureSpeedVerifiedAt)
        capturePathVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .capturePathVerifiedAt)
        ocrAccuracyVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .ocrAccuracyVerifiedAt)
        pageBoundaryVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .pageBoundaryVerifiedAt)
        snapshotCropVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .snapshotCropVerifiedAt)
        lowLightVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .lowLightVerifiedAt)
        isbnScanVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .isbnScanVerifiedAt)
        speechMemoVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .speechMemoVerifiedAt)
        kakaoSearchVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .kakaoSearchVerifiedAt)
        llmInsightVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .llmInsightVerifiedAt)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    mutating func normalizeVerificationDates(now: Date = .now) {
        captureSpeedVerifiedAt = captureSpeedVerified ? (captureSpeedVerifiedAt ?? now) : nil
        capturePathVerifiedAt = capturePathVerified ? (capturePathVerifiedAt ?? now) : nil
        ocrAccuracyVerifiedAt = ocrAccuracyVerified ? (ocrAccuracyVerifiedAt ?? now) : nil
        pageBoundaryVerifiedAt = pageBoundaryVerified ? (pageBoundaryVerifiedAt ?? now) : nil
        snapshotCropVerifiedAt = snapshotCropVerified ? (snapshotCropVerifiedAt ?? now) : nil
        lowLightVerifiedAt = lowLightVerified ? (lowLightVerifiedAt ?? now) : nil
        isbnScanVerifiedAt = isbnScanVerified ? (isbnScanVerifiedAt ?? now) : nil
        speechMemoVerifiedAt = speechMemoVerified ? (speechMemoVerifiedAt ?? now) : nil
        kakaoSearchVerifiedAt = kakaoSearchVerified ? (kakaoSearchVerifiedAt ?? now) : nil
        llmInsightVerifiedAt = llmInsightVerified ? (llmInsightVerifiedAt ?? now) : nil
    }
}

enum MVPReadinessItem: String, Codable, CaseIterable, Identifiable {
    case captureSpeed
    case capturePath
    case ocrAccuracy
    case pageBoundary
    case snapshotCrop
    case lowLight
    case isbnScan
    case speechMemo
    case kakaoSearch
    case llmInsight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureSpeed:
            "10초 안에 캡처 저장"
        case .capturePath:
            "캡처 경로 3탭 이하"
        case .ocrAccuracy:
            "한국어 OCR 90% 이상"
        case .pageBoundary:
            "페이지 경계 감지"
        case .snapshotCrop:
            "원문 사진 미저장"
        case .lowLight:
            "저조도 캡처"
        case .isbnScan:
            "ISBN 스캔"
        case .speechMemo:
            "음성 메모"
        case .kakaoSearch:
            "도서 API"
        case .llmInsight:
            "LLM 인사이트"
        }
    }

    var systemImage: String {
        switch self {
        case .captureSpeed:
            "timer"
        case .capturePath:
            "hand.tap"
        case .ocrAccuracy:
            "text.viewfinder"
        case .pageBoundary:
            "doc.viewfinder"
        case .snapshotCrop:
            "crop"
        case .lowLight:
            "flashlight.on.fill"
        case .isbnScan:
            "barcode.viewfinder"
        case .speechMemo:
            "mic"
        case .kakaoSearch:
            "k.circle"
        case .llmInsight:
            "sparkles"
        }
    }
}

struct MVPDeviceTestSession: Identifiable, Hashable, Codable {
    var id: UUID
    var createdAt: Date
    var runtime: String
    var deviceName: String
    var osVersion: String
    var appVersion: String
    var passedItemRawValues: [String]
    var failedItemRawValues: [String]
    var openItemRawValues: [String]
    var note: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        runtime: String,
        deviceName: String,
        osVersion: String,
        appVersion: String,
        passedItems: [MVPReadinessItem],
        failedItems: [MVPReadinessItem] = [],
        openItems: [MVPReadinessItem],
        note: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.runtime = runtime
        self.deviceName = deviceName
        self.osVersion = osVersion
        self.appVersion = appVersion
        passedItemRawValues = passedItems.map(\.rawValue)
        failedItemRawValues = failedItems.map(\.rawValue)
        openItemRawValues = openItems.map(\.rawValue)
        self.note = note
    }

    var passedItems: [MVPReadinessItem] {
        passedItemRawValues.compactMap(MVPReadinessItem.init(rawValue:))
    }

    var openItems: [MVPReadinessItem] {
        openItemRawValues.compactMap(MVPReadinessItem.init(rawValue:))
    }

    var failedItems: [MVPReadinessItem] {
        failedItemRawValues.compactMap(MVPReadinessItem.init(rawValue:))
    }

    var passedCount: Int {
        passedItems.count
    }

    var failedCount: Int {
        failedItems.count
    }

    var openCount: Int {
        openItems.count
    }

    var isPhysicalDeviceEvidence: Bool {
        runtime == "Device"
    }

    var evidenceLabel: String {
        isPhysicalDeviceEvidence ? "실제 기기" : "시뮬레이터"
    }

    var isPassingEvidence: Bool {
        isPhysicalDeviceEvidence
            && passedCount == MVPReadinessItem.allCases.count
            && failedCount == 0
            && openCount == 0
    }

    var summary: String {
        let passedSummary = "\(passedCount)/\(MVPReadinessItem.allCases.count) 통과"
        var unresolved: [String] = []
        if failedCount > 0 {
            unresolved.append("\(failedCount) 실패")
        }
        if openCount > 0 {
            unresolved.append("\(openCount) 미확인")
        }

        guard !unresolved.isEmpty else { return passedSummary }
        return "\(passedSummary) · \(unresolved.joined(separator: " · "))"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case runtime
        case deviceName
        case osVersion
        case appVersion
        case passedItemRawValues
        case failedItemRawValues
        case openItemRawValues
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime) ?? "-"
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "-"
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion) ?? "-"
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "-"
        passedItemRawValues = try container.decodeIfPresent([String].self, forKey: .passedItemRawValues) ?? []
        failedItemRawValues = try container.decodeIfPresent([String].self, forKey: .failedItemRawValues) ?? []
        openItemRawValues = try container.decodeIfPresent([String].self, forKey: .openItemRawValues) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum MVPDeviceTestSessionStore {
    private static let key = "overline.mvpDeviceTestSessions.v1"
    private static let recordLimit = 30

    static func load() -> [MVPDeviceTestSession] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let sessions = try? JSONDecoder().decode([MVPDeviceTestSession].self, from: data)
        else {
            return []
        }

        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    static func add(_ session: MVPDeviceTestSession) {
        let sessions = ([session] + load())
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recordLimit)
        save(Array(sessions))
    }

    private static func save(_ sessions: [MVPDeviceTestSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct MVPVerificationEvent: Identifiable, Hashable, Codable {
    var id: UUID
    var createdAt: Date
    var itemRaw: String
    var title: String
    var detail: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        item: MVPReadinessItem,
        detail: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        itemRaw = item.rawValue
        title = item.title
        self.detail = detail
    }

    var item: MVPReadinessItem? {
        MVPReadinessItem(rawValue: itemRaw)
    }

    var displayTitle: String {
        item?.title ?? title
    }

    var systemImage: String {
        item?.systemImage ?? "checkmark.seal"
    }
}

enum MVPVerificationEventStore {
    private static let key = "overline.mvpVerificationEvents.v1"
    private static let recordLimit = 100

    static func load() -> [MVPVerificationEvent] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let events = try? JSONDecoder().decode([MVPVerificationEvent].self, from: data)
        else {
            return []
        }

        return events.sorted { $0.createdAt > $1.createdAt }
    }

    static func add(_ event: MVPVerificationEvent) {
        let events = ([event] + load())
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recordLimit)
        save(Array(events))
    }

    private static func save(_ events: [MVPVerificationEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum MVPReadinessStore {
    private static let key = "overline.mvpReadiness.v1"

    static func load() -> MVPReadinessChecklist {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let checklist = try? JSONDecoder().decode(MVPReadinessChecklist.self, from: data)
        else {
            return MVPReadinessChecklist()
        }

        return checklist
    }

    static func save(_ checklist: MVPReadinessChecklist) {
        let now = Date()
        var updatedChecklist = checklist
        updatedChecklist.updatedAt = now
        updatedChecklist.normalizeVerificationDates(now: now)
        guard let data = try? JSONEncoder().encode(updatedChecklist) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func markVerified(_ item: MVPReadinessItem, detail: String = "") {
        let now = Date()
        var checklist = load()
        switch item {
        case .captureSpeed:
            checklist.captureSpeedVerified = true
            checklist.captureSpeedVerifiedAt = now
        case .capturePath:
            checklist.capturePathVerified = true
            checklist.capturePathVerifiedAt = now
        case .ocrAccuracy:
            checklist.ocrAccuracyVerified = true
            checklist.ocrAccuracyVerifiedAt = now
        case .pageBoundary:
            checklist.pageBoundaryVerified = true
            checklist.pageBoundaryVerifiedAt = now
        case .snapshotCrop:
            checklist.snapshotCropVerified = true
            checklist.snapshotCropVerifiedAt = now
        case .lowLight:
            checklist.lowLightVerified = true
            checklist.lowLightVerifiedAt = now
        case .isbnScan:
            checklist.isbnScanVerified = true
            checklist.isbnScanVerifiedAt = now
        case .speechMemo:
            checklist.speechMemoVerified = true
            checklist.speechMemoVerifiedAt = now
        case .kakaoSearch:
            checklist.kakaoSearchVerified = true
            checklist.kakaoSearchVerifiedAt = now
        case .llmInsight:
            checklist.llmInsightVerified = true
            checklist.llmInsightVerifiedAt = now
        }
        save(checklist)
        MVPVerificationEventStore.add(
            MVPVerificationEvent(
                createdAt: now,
                item: item,
                detail: detail
            )
        )
    }
}

struct LLMUsageMetrics: Codable, Equatable {
    var requestedCount: Int
    var completedCount: Int
    var failedCount: Int
    var lastUsedAt: Date?

    init(
        requestedCount: Int = 0,
        completedCount: Int = 0,
        failedCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.requestedCount = requestedCount
        self.completedCount = completedCount
        self.failedCount = failedCount
        self.lastUsedAt = lastUsedAt
    }
}

enum LLMUsageMetricsStore {
    private static let key = "overline.llmUsageMetrics.v1"

    static func load() -> LLMUsageMetrics {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let metrics = try? JSONDecoder().decode(LLMUsageMetrics.self, from: data)
        else {
            return LLMUsageMetrics()
        }

        return metrics
    }

    static func recordRequested() {
        var metrics = load()
        metrics.requestedCount += 1
        metrics.lastUsedAt = .now
        save(metrics)
    }

    static func recordCompleted() {
        var metrics = load()
        metrics.completedCount += 1
        metrics.lastUsedAt = .now
        save(metrics)
    }

    static func recordFailed() {
        var metrics = load()
        metrics.failedCount += 1
        metrics.lastUsedAt = .now
        save(metrics)
    }

    private static func save(_ metrics: LLMUsageMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

nonisolated struct ReadingBook: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var summary: String
    var tags: [String]
    var publisher: String?
    var publishedDate: String?
    var isbn: String?
    var coverURLString: String?
    var metadataSource: BookMetadataSource?
    var coverTheme: CoverTheme
    var highlights: [Highlight]
    var readingRecords: [ReadingRecord]

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        summary: String,
        tags: [String] = [],
        publisher: String? = nil,
        publishedDate: String? = nil,
        isbn: String? = nil,
        coverURLString: String? = nil,
        metadataSource: BookMetadataSource? = .manual,
        coverTheme: CoverTheme,
        highlights: [Highlight],
        readingRecords: [ReadingRecord] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.tags = tags
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.isbn = isbn
        self.coverURLString = coverURLString
        self.metadataSource = metadataSource
        self.coverTheme = coverTheme
        self.highlights = highlights
        self.readingRecords = readingRecords
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case summary
        case tags
        case publisher
        case publishedDate
        case isbn
        case coverURLString
        case metadataSource
        case coverTheme
        case highlights
        case readingRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        summary = try container.decode(String.self, forKey: .summary)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        publishedDate = try container.decodeIfPresent(String.self, forKey: .publishedDate)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        coverURLString = try container.decodeIfPresent(String.self, forKey: .coverURLString)
        metadataSource = try container.decodeIfPresent(BookMetadataSource.self, forKey: .metadataSource)
        coverTheme = try container.decode(CoverTheme.self, forKey: .coverTheme)
        highlights = try container.decode([Highlight].self, forKey: .highlights)
        readingRecords = try container.decodeIfPresent([ReadingRecord].self, forKey: .readingRecords) ?? []
    }
}

nonisolated struct LibraryStateSnapshot: Codable, Equatable, Sendable {
    var books: [ReadingBook]
    var insights: [LibraryInsight]
    var selectedBookID: ReadingBook.ID?

    var isEmpty: Bool {
        books.isEmpty && insights.isEmpty
    }

}

struct LibraryStorageStatus: Equatable {
    var primaryStore: String
    var fallbackStore: String
    var primarySaveSucceeded: Bool
    var fallbackSaveSucceeded: Bool
    var lastSavedAt: Date?

    var primaryLabel: String {
        "\(primaryStore) · \(primarySaveSucceeded ? "정상" : "대기")"
    }

    var fallbackLabel: String {
        "\(fallbackStore) · \(fallbackSaveSucceeded ? "정상" : "확인 필요")"
    }

    var lastSavedLabel: String {
        lastSavedAt?.overlineShortDate ?? "-"
    }

    static func initial(hasPrimaryStore: Bool, hasFallbackBackup: Bool) -> LibraryStorageStatus {
        LibraryStorageStatus(
            primaryStore: hasPrimaryStore ? "SwiftData" : "SwiftData 미사용",
            fallbackStore: "UserDefaults 백업",
            primarySaveSucceeded: hasPrimaryStore,
            fallbackSaveSucceeded: hasFallbackBackup,
            lastSavedAt: nil
        )
    }
}

@Model
final class PersistentLibrarySnapshot {
    @Attribute(.unique) var key: String
    @Attribute(.externalStorage) var data: Data
    var updatedAt: Date

    init(
        key: String = "main",
        data: Data = Data(),
        updatedAt: Date = .now
    ) {
        self.key = key
        self.data = data
        self.updatedAt = updatedAt
    }
}

@MainActor
final class LibraryPersistence {
    private let container: ModelContainer
    private let context: ModelContext
    fileprivate let writer: LibraryPersistenceWriter
    private static let recordKey = "main"

    init(inMemory: Bool = false) throws {
        let schema = Schema([PersistentLibrarySnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext
        writer = LibraryPersistenceWriter(modelContainer: container)
    }

    static func live() -> LibraryPersistence? {
        try? LibraryPersistence()
    }

    func load() -> LibraryStateSnapshot? {
        let record = try? context.fetch(FetchDescriptor<PersistentLibrarySnapshot>())
            .first(where: { $0.key == Self.recordKey })

        guard let record else {
            return nil
        }

        return try? JSONDecoder().decode(LibraryStateSnapshot.self, from: record.data)
    }

}

@ModelActor
actor LibraryPersistenceWriter {
    func save(_ data: Data) -> Bool {
        guard !Task.isCancelled else { return false }

        let records = (try? modelContext.fetch(FetchDescriptor<PersistentLibrarySnapshot>())) ?? []
        if let record = records.first(where: { $0.key == Self.recordKey }) {
            record.data = data
            record.updatedAt = .now
        } else {
            modelContext.insert(PersistentLibrarySnapshot(key: Self.recordKey, data: data))
        }

        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    private static let recordKey = "main"
}

private struct LibrarySnapshotWriteResult: Sendable {
    let primarySaveSucceeded: Bool
    let fallbackSaveSucceeded: Bool
}

private actor LibrarySnapshotWriteCoordinator {
    private let primaryWriter: LibraryPersistenceWriter?
    private var latestGeneration = 0

    init(primaryWriter: LibraryPersistenceWriter?) {
        self.primaryWriter = primaryWriter
    }

    func save(
        _ snapshot: LibraryStateSnapshot,
        generation: Int,
        fallbackKey: String
    ) async -> LibrarySnapshotWriteResult? {
        guard !Task.isCancelled, generation >= latestGeneration else { return nil }
        latestGeneration = generation

        guard let data = try? JSONEncoder().encode(snapshot), !Task.isCancelled else {
            return nil
        }

        let primarySaveSucceeded = await primaryWriter?.save(data) ?? false
        guard !Task.isCancelled, generation == latestGeneration else { return nil }

        UserDefaults.standard.set(data, forKey: fallbackKey)
        return LibrarySnapshotWriteResult(
            primarySaveSucceeded: primarySaveSucceeded,
            fallbackSaveSucceeded: true
        )
    }
}

struct SamplePageLine: Identifiable, Hashable {
    let id: Int
    let text: String
    let weight: Font.Weight
}

struct AppIntentRequest: Equatable, Identifiable {
    let id = UUID()
    let tab: AppTab
    var insightSeed: InsightSeedRequest?
}

struct InsightSeedRequest: Equatable {
    var highlightIDs: Set<Highlight.ID>
    var prompt: InsightPrompt
    var question: String?
}

private struct CapturedHighlightMetadata {
    let pageReference: String
    let tags: [String]

    init(
        memo: String,
        detectedLanguage: CaptureLanguage,
        fallbackPageReference: String,
        explicitPageReference: String = "",
        tagsText: String = ""
    ) {
        pageReference = Self.normalizedExplicitPageReference(explicitPageReference)
            ?? Self.extractedPageReference(from: memo)
            ?? fallbackPageReference

        tags = Self.deduplicated(
            Self.extractedTags(from: memo)
            + Self.normalizedTags(from: tagsText)
        )
    }

    private static func extractedTags(from memo: String) -> [String] {
        memo
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .compactMap { token -> String? in
                let trimmedToken = String(token)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}」』"))

                guard trimmedToken.hasPrefix("#"), trimmedToken.count > 1 else { return nil }
                return trimmedToken
            }
    }

    private static func extractedPageReference(from memo: String) -> String? {
        let patterns = [
            #"(?i)\b(?:p|pp|page)\.?\s*\d{1,4}(?:\s*[-–~]\s*\d{1,4})?"#,
            #"\d{1,4}(?:\s*[-–~]\s*\d{1,4})?\s*(?:쪽|페이지)"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: memo,
                    range: NSRange(memo.startIndex..<memo.endIndex, in: memo)
                ),
                let range = Range(match.range, in: memo)
            else {
                continue
            }

            return normalizedPageReference(String(memo[range]))
        }

        return nil
    }

    private static func normalizedExplicitPageReference(_ value: String) -> String? {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else { return nil }
        return normalizedPageReference(trimmedValue)
    }

    static func normalizedTags(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .compactMap { token -> String? in
                let trimmedToken = String(token)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}」』"))
                guard !trimmedToken.isEmpty else { return nil }
                return trimmedToken.hasPrefix("#") ? trimmedToken : "#\(trimmedToken)"
            }
    }

    private static func normalizedPageReference(_ value: String) -> String {
        let digitsAndRange = value
            .replacingOccurrences(of: #"[^0-9\-–~]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "~", with: "-")
            .trimmed

        guard !digitsAndRange.isEmpty else { return value.trimmed }
        return "p.\(digitsAndRange)"
    }

    static func deduplicated(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.filter { tag in
            let normalized = tag.trimmed
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }
}

struct PageReferenceLine {
    let text: String
    let boundingBox: CGRect

    nonisolated init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

enum PageReferenceInference {
    nonisolated static func inferredPageReference(
        from lines: [PageReferenceLine],
        pageBoundingBox: CGRect? = nil
    ) -> String? {
        let referenceBox = pageBoundingBox ?? inferredTextBlockBoundingBox(from: lines)
        return lines
            .compactMap { candidate(from: $0, referenceBox: referenceBox) }
            .sorted { $0.score < $1.score }
            .first?
            .pageReference
    }

    nonisolated static func isDedicatedPageReferenceLine(
        _ line: PageReferenceLine,
        pageBoundingBox: CGRect?
    ) -> Bool {
        let text = line.text.trimmed
        guard text.range(
            of: #"(?i)^\s*(?:(?:p|pp|page)\.?\s*)?\d{1,4}(?:\s*[-–~]\s*\d{1,4})?\s*(?:쪽|페이지)?\s*$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        guard let extraction = pageNumberExtraction(from: text) else { return false }
        switch extraction.position {
        case .marked, .standalone:
            return candidate(from: line, referenceBox: pageBoundingBox) != nil
        case .leading, .trailing:
            return false
        }
    }

    nonisolated private static func candidate(
        from line: PageReferenceLine,
        referenceBox: CGRect?
    ) -> PageReferenceCandidate? {
        let trimmedText = line.text.trimmed
        guard let extraction = pageNumberExtraction(from: trimmedText) else { return nil }

        let edgeDistance = pageRelativeEdgeDistance(
            for: line.boundingBox,
            referenceBox: referenceBox
        ) ?? min(line.boundingBox.midY, 1 - line.boundingBox.midY)
        guard edgeDistance <= extraction.position.maximumEdgeDistance else { return nil }
        guard line.boundingBox.height <= 0.12 else { return nil }

        let pageReference = "p.\(extraction.pageNumber)"
        let score = edgeDistance
            + min(line.boundingBox.width, 1) * 0.22
            + line.boundingBox.height * 0.45
            + extraction.position.scoreAdjustment
            + (extraction.hasPageMarker ? -0.18 : 0)
        return PageReferenceCandidate(pageReference: pageReference, score: score)
    }

    nonisolated private static func pageNumberExtraction(from text: String) -> PageNumberExtraction? {
        let markedPatterns = [
            #"(?i)(?:^|\b)(?:p|pp|page)\.?\s*(\d{1,4})(?:\s*[-–~]\s*(\d{1,4}))?(?:\b|$)"#,
            #"(?<!\d)(\d{1,4})(?:\s*[-–~]\s*(\d{1,4}))?\s*(?:쪽|페이지)"#
        ]

        for pattern in markedPatterns {
            if let pageNumber = pageNumber(from: text, matching: pattern) {
                return PageNumberExtraction(
                    pageNumber: pageNumber,
                    position: .marked,
                    hasPageMarker: true
                )
            }
        }

        if let pageNumber = pageNumber(from: text, matching: #"^\s*(\d{1,4})(?:\s*[-–~]\s*(\d{1,4}))?\s*$"#) {
            return PageNumberExtraction(
                pageNumber: pageNumber,
                position: .standalone,
                hasPageMarker: false
            )
        }

        if
            !hasLeadingPageNumberBlocker(text),
            let pageNumber = pageNumber(from: text, matching: #"^\s*(\d{1,4})(?:\s*[-–~]\s*(\d{1,4}))?(?=\s+\S)"#),
            !isLikelyYearPageNumber(pageNumber)
        {
            return PageNumberExtraction(
                pageNumber: pageNumber,
                position: .leading,
                hasPageMarker: false
            )
        }

        if
            !hasTrailingPageNumberBlocker(text),
            let pageNumber = pageNumber(from: text, matching: #"\s(\d{1,4})(?:\s*[-–~]\s*(\d{1,4}))?\s*$"#),
            !isLikelyYearPageNumber(pageNumber)
        {
            return PageNumberExtraction(
                pageNumber: pageNumber,
                position: .trailing,
                hasPageMarker: false
            )
        }

        return nil
    }

    nonisolated private static func inferredTextBlockBoundingBox(from lines: [PageReferenceLine]) -> CGRect? {
        let bodyBoxes = lines
            .map(\.boundingBox)
            .filter { box in
                box.width >= 0.14 && box.height >= 0.004
            }

        guard let firstBox = bodyBoxes.first else { return nil }

        return bodyBoxes.dropFirst().reduce(firstBox) { partialResult, box in
            partialResult.union(box)
        }
    }

    nonisolated private static func pageRelativeEdgeDistance(
        for lineBox: CGRect,
        referenceBox: CGRect?
    ) -> CGFloat? {
        guard
            let referenceBox,
            referenceBox.height > 0.001,
            !referenceBox.isNull,
            !referenceBox.isEmpty
        else {
            return nil
        }

        let relativeY = (lineBox.midY - referenceBox.minY) / referenceBox.height
        if relativeY < 0 {
            return abs(relativeY)
        }
        if relativeY > 1 {
            return relativeY - 1
        }
        return min(relativeY, 1 - relativeY)
    }

    nonisolated private static func pageNumber(from text: String, matching pattern: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            ),
            match.numberOfRanges > 1,
            let firstRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        let firstPage = String(text[firstRange])
        guard let pageValue = Int(firstPage), (1...3000).contains(pageValue) else {
            return nil
        }

        if
            match.numberOfRanges > 2,
            let secondRange = Range(match.range(at: 2), in: text)
        {
            let secondPage = String(text[secondRange])
            if let secondValue = Int(secondPage), (1...3000).contains(secondValue) {
                return "\(pageValue)-\(secondValue)"
            }
        }

        return "\(pageValue)"
    }

    nonisolated private static func hasLeadingPageNumberBlocker(_ text: String) -> Bool {
        text.range(
            of: #"^\s*\d{1,4}(?:\s*[-–~]\s*\d{1,4})?\s*(?:년|월|일|장|챕터|부|억|만|개|명|배|%)"#,
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func hasTrailingPageNumberBlocker(_ text: String) -> Bool {
        text.range(
            of: #"(?i)(?:chapter|chap\.?|ch\.|part)\s+\d{1,4}\s*$"#,
            options: .regularExpression
        ) != nil
            || text.range(
                of: #"\d{1,4}\s*(?:장|챕터|부)\s*$"#,
                options: .regularExpression
            ) != nil
    }

    nonisolated private static func isLikelyYearPageNumber(_ pageNumber: String) -> Bool {
        guard
            !pageNumber.contains("-"),
            let value = Int(pageNumber)
        else {
            return false
        }

        return (1800...2100).contains(value)
    }
}

private struct PageReferenceCandidate {
    let pageReference: String
    let score: CGFloat
}

private struct PageNumberExtraction {
    let pageNumber: String
    let position: PageNumberPosition
    let hasPageMarker: Bool
}

private enum PageNumberPosition {
    case marked
    case standalone
    case leading
    case trailing

    nonisolated var maximumEdgeDistance: CGFloat {
        switch self {
        case .marked:
            return 0.30
        case .standalone:
            return 0.26
        case .leading, .trailing:
            return 0.22
        }
    }

    nonisolated var scoreAdjustment: CGFloat {
        switch self {
        case .marked:
            return -0.12
        case .standalone:
            return -0.08
        case .leading, .trailing:
            return 0.08
        }
    }
}

@MainActor
@Observable
final class AppIntentRouter {
    static let shared = AppIntentRouter()

    var request: AppIntentRequest?

    func open(_ tab: AppTab, insightSeed: InsightSeedRequest? = nil) {
        request = AppIntentRequest(tab: tab, insightSeed: insightSeed)
    }
}

@MainActor
@Observable
final class ReadingLibrary {
    static let shared = ReadingLibrary(persistence: LibraryPersistence.live())

    var books: [ReadingBook]
    var savedInsights: [LibraryInsight]
    var selectedBookID: ReadingBook.ID?
    private(set) var recentHighlights: [Highlight] = []
    private(set) var highlightCount = 0
    private(set) var storageStatus: LibraryStorageStatus
    private(set) var resetBackupAvailable: Bool

    private let persistence: LibraryPersistence?
    @ObservationIgnored private let snapshotWriter: LibrarySnapshotWriteCoordinator
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceGeneration = 0
    @ObservationIgnored private var pendingResetBackupCleanupData: Data?
    @ObservationIgnored private var bookIndexByID: [ReadingBook.ID: Int] = [:]
    @ObservationIgnored private var highlightLocationByID: [Highlight.ID: (bookIndex: Int, highlightIndex: Int)] = [:]
    private let legacyHighlightsKey = "overline.userHighlights.v1"
    private static let snapshotBackupKey = "overline.librarySnapshot.backup.v1"
    private static let resetBackupKey = "overline.librarySnapshot.resetBackup.v1"

    init(
        books: [ReadingBook] = [],
        insights: [LibraryInsight] = [],
        includePersistedHighlights: Bool = true,
        persistence: LibraryPersistence? = nil
    ) {
        self.persistence = persistence
        self.snapshotWriter = LibrarySnapshotWriteCoordinator(primaryWriter: persistence?.writer)
        self.storageStatus = LibraryStorageStatus.initial(
            hasPrimaryStore: persistence != nil,
            hasFallbackBackup: Self.hasSnapshotBackup(key: Self.snapshotBackupKey)
        )
        self.resetBackupAvailable = Self.hasSnapshotBackup(key: Self.resetBackupKey)

        if let snapshot = persistence?.load() ?? Self.loadSnapshotBackup(key: Self.snapshotBackupKey) {
            if !Self.isUntouchedDemoSnapshot(snapshot) {
                let sanitizedSnapshot = Self.removingDemoContent(from: snapshot)
                self.books = sanitizedSnapshot.books
                self.savedInsights = sanitizedSnapshot.insights
                self.selectedBookID = sanitizedSnapshot.books.contains(where: { $0.id == sanitizedSnapshot.selectedBookID })
                    ? sanitizedSnapshot.selectedBookID
                    : sanitizedSnapshot.books.first?.id
                refreshDerivedState()
                if sanitizedSnapshot != snapshot {
                    persist()
                }
                cleanupSnapshotFilesIfNeeded()
                return
            }
        }

        self.books = books
        self.savedInsights = insights
        self.selectedBookID = books.first?.id

        guard includePersistedHighlights else {
            persist()
            cleanupSnapshotFilesIfNeeded()
            return
        }

        for highlight in Self.loadPersistedHighlights(key: legacyHighlightsKey) {
            append(highlight, to: selectedBookID)
        }
        persist()
        cleanupSnapshotFilesIfNeeded()
    }

    var selectedBook: ReadingBook? {
        guard let selectedBookID else { return books.first }
        return book(with: selectedBookID) ?? books.first
    }

    func book(with id: ReadingBook.ID) -> ReadingBook? {
        guard let index = bookIndexByID[id], books.indices.contains(index) else { return nil }
        return books[index]
    }

    func highlight(with id: Highlight.ID) -> Highlight? {
        guard
            let location = highlightLocationByID[id],
            books.indices.contains(location.bookIndex),
            books[location.bookIndex].highlights.indices.contains(location.highlightIndex)
        else {
            return nil
        }
        return books[location.bookIndex].highlights[location.highlightIndex]
    }

    func bookID(containing highlightID: Highlight.ID) -> ReadingBook.ID? {
        guard
            let location = highlightLocationByID[highlightID],
            books.indices.contains(location.bookIndex)
        else {
            return nil
        }
        return books[location.bookIndex].id
    }

    func suggestedTagsForSelectedBook() -> [String] {
        suggestedTags(for: selectedBookID)
    }

    func suggestedTags(for bookID: ReadingBook.ID?, recurringLimit: Int = 4) -> [String] {
        guard
            let bookID,
            let book = books.first(where: { $0.id == bookID })
        else {
            return []
        }

        let baseTags = CapturedHighlightMetadata.deduplicated(book.tags)
        let baseTagSet = Set(baseTags)
        var usage: [String: (count: Int, latest: Date)] = [:]

        for highlight in book.highlights {
            for tag in CapturedHighlightMetadata.deduplicated(highlight.tags) {
                let normalizedTag = CapturedHighlightMetadata.normalizedTags(from: tag).first ?? tag.trimmed
                guard !normalizedTag.isEmpty, !baseTagSet.contains(normalizedTag) else { continue }

                let current = usage[normalizedTag] ?? (count: 0, latest: .distantPast)
                let latest = current.latest > highlight.createdAt ? current.latest : highlight.createdAt
                usage[normalizedTag] = (count: current.count + 1, latest: latest)
            }
        }

        let recurringTags = usage
            .filter { $0.value.count >= 2 }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.value.latest > rhs.value.latest
            }
            .prefix(recurringLimit)
            .map(\.key)

        return CapturedHighlightMetadata.deduplicated(baseTags + recurringTags)
    }

    @discardableResult
    func appendTags(_ tags: [String], to highlightID: Highlight.ID, limit: Int = 6) -> Bool {
        guard
            let location = highlightLocationByID[highlightID],
            books.indices.contains(location.bookIndex),
            books[location.bookIndex].highlights.indices.contains(location.highlightIndex)
        else {
            return false
        }

        let bookIndex = location.bookIndex
        let highlightIndex = location.highlightIndex

        let existingTags = CapturedHighlightMetadata.deduplicated(books[bookIndex].highlights[highlightIndex].tags)
        guard existingTags.count < limit else { return false }

        let normalizedTags = CapturedHighlightMetadata.deduplicated(
            CapturedHighlightMetadata.normalizedTags(from: tags.joined(separator: " "))
        )
        let additions = Array(normalizedTags
            .filter { !existingTags.contains($0) }
            .prefix(max(limit - existingTags.count, 0)))

        guard !additions.isEmpty else { return false }

        books[bookIndex].highlights[highlightIndex].tags = existingTags + additions
        persist()
        return true
    }

    func selectBook(_ bookID: ReadingBook.ID) {
        guard books.contains(where: { $0.id == bookID }) else { return }
        selectedBookID = bookID
        persist()
    }

    @discardableResult
    func addBook(
        title: String,
        author: String,
        summary: String,
        tagsText: String = "",
        publisher: String = "",
        publishedDate: String = "",
        isbn: String = "",
        coverURLString: String = "",
        metadataSource: BookMetadataSource = .manual
    ) -> ReadingBook {
        let book = ReadingBook(
            title: title.trimmed.isEmpty ? "새 책" : title.trimmed,
            author: author.trimmed.isEmpty ? "Unknown" : author.trimmed,
            summary: summary.trimmed.isEmpty ? "직접 추가한 책입니다." : summary.trimmed,
            tags: CapturedHighlightMetadata.deduplicated(CapturedHighlightMetadata.normalizedTags(from: tagsText)),
            publisher: publisher.trimmed.nilIfEmpty,
            publishedDate: publishedDate.trimmed.nilIfEmpty,
            isbn: isbn.trimmed.nilIfEmpty,
            coverURLString: coverURLString.trimmed.nilIfEmpty,
            metadataSource: metadataSource,
            coverTheme: CoverTheme.allCases[books.count % CoverTheme.allCases.count],
            highlights: []
        )

        books.insert(book, at: 0)
        selectedBookID = book.id
        persist()
        return book
    }

    func updateBook(
        _ bookID: ReadingBook.ID,
        title: String,
        author: String,
        summary: String,
        tagsText: String = "",
        publisher: String = "",
        publishedDate: String = "",
        isbn: String = "",
        coverURLString: String = "",
        metadataSource: BookMetadataSource = .manual
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }

        books[index].title = title.trimmed.isEmpty ? books[index].title : title.trimmed
        books[index].author = author.trimmed.isEmpty ? "Unknown" : author.trimmed
        books[index].summary = summary.trimmed.isEmpty ? "직접 추가한 책입니다." : summary.trimmed
        books[index].tags = CapturedHighlightMetadata.deduplicated(CapturedHighlightMetadata.normalizedTags(from: tagsText))
        books[index].publisher = publisher.trimmed.nilIfEmpty
        books[index].publishedDate = publishedDate.trimmed.nilIfEmpty
        books[index].isbn = isbn.trimmed.nilIfEmpty
        books[index].coverURLString = coverURLString.trimmed.nilIfEmpty
        books[index].metadataSource = metadataSource
        persist()
    }

    func deleteBook(_ bookID: ReadingBook.ID) {
        let removedHighlightIDs = books.first(where: { $0.id == bookID })?.highlights.map(\.id) ?? []
        books.removeAll { $0.id == bookID }

        if selectedBookID == bookID {
            selectedBookID = books.first?.id
        }

        persist()
        postRemovedHighlights(removedHighlightIDs)
    }

    @discardableResult
    func addReadingRecord(
        to bookID: ReadingBook.ID,
        startedAt: Date,
        endedAt: Date?,
        status: ReadingStatus,
        rating: Double?,
        review: String
    ) -> ReadingRecord? {
        guard let bookIndex = books.firstIndex(where: { $0.id == bookID }) else { return nil }

        let record = ReadingRecord(
            startedAt: Self.normalizedReadingDate(startedAt),
            endedAt: Self.normalizedReadingEndDate(endedAt, startedAt: startedAt),
            status: status,
            rating: Self.normalizedReadingRating(rating),
            review: String(review.normalizedQuotesForStorage.trimmed.prefix(3_000))
        )
        books[bookIndex].readingRecords.insert(record, at: 0)
        persist()
        return record
    }

    func updateReadingRecord(
        _ recordID: ReadingRecord.ID,
        in bookID: ReadingBook.ID,
        startedAt: Date,
        endedAt: Date?,
        status: ReadingStatus,
        rating: Double?,
        review: String
    ) {
        guard
            let bookIndex = books.firstIndex(where: { $0.id == bookID }),
            let recordIndex = books[bookIndex].readingRecords.firstIndex(where: { $0.id == recordID })
        else {
            return
        }

        books[bookIndex].readingRecords[recordIndex].startedAt = Self.normalizedReadingDate(startedAt)
        books[bookIndex].readingRecords[recordIndex].endedAt = Self.normalizedReadingEndDate(
            endedAt,
            startedAt: startedAt
        )
        books[bookIndex].readingRecords[recordIndex].status = status
        books[bookIndex].readingRecords[recordIndex].rating = Self.normalizedReadingRating(rating)
        books[bookIndex].readingRecords[recordIndex].review = String(
            review.normalizedQuotesForStorage.trimmed.prefix(3_000)
        )
        books[bookIndex].readingRecords[recordIndex].updatedAt = .now
        persist()
    }

    func deleteReadingRecord(_ recordID: ReadingRecord.ID, in bookID: ReadingBook.ID) {
        guard let bookIndex = books.firstIndex(where: { $0.id == bookID }) else { return }
        let originalCount = books[bookIndex].readingRecords.count
        books[bookIndex].readingRecords.removeAll { $0.id == recordID }
        guard books[bookIndex].readingRecords.count != originalCount else { return }
        persist()
    }

    @discardableResult
    func addCapturedHighlight(
        text: String,
        memo: String,
        language: CaptureLanguage,
        pageReference: String = "p.42",
        explicitPageReference: String = "",
        tagsText: String = "",
        bookID: ReadingBook.ID? = nil,
        stickyTone: StickyTone? = nil
    ) -> Highlight {
        let metadata = CapturedHighlightMetadata(
            memo: memo,
            detectedLanguage: language,
            fallbackPageReference: pageReference,
            explicitPageReference: explicitPageReference,
            tagsText: tagsText
        )

        let targetBookID = bookID ?? selectedBookID
        let normalizedText = text.normalizedQuotesForStorage.trimmed
        let normalizedMemo = memo.normalizedQuotesForStorage.trimmed
        let highlightTags = CapturedHighlightMetadata.deduplicated(defaultTags(for: targetBookID) + metadata.tags)

        let highlight = Highlight(
            text: normalizedText,
            memo: normalizedMemo,
            pageReference: metadata.pageReference,
            language: language,
            tags: highlightTags,
            stickyTone: stickyTone ?? StickyTone.allCases[recentHighlights.count % StickyTone.allCases.count],
            source: .capture
        )

        append(highlight, to: targetBookID)
        persist()
        return highlight
    }

    @discardableResult
    func applyCaptureContinuation(
        firstPageText: String,
        secondPageText: String,
        to highlightID: Highlight.ID,
        expectedOriginalText: String
    ) -> Highlight? {
        guard
            let location = highlightLocationByID[highlightID],
            books.indices.contains(location.bookIndex),
            books[location.bookIndex].highlights.indices.contains(location.highlightIndex)
        else {
            return nil
        }

        let currentText = books[location.bookIndex].highlights[location.highlightIndex].text
            .normalizedQuotesForStorage
            .trimmed
        let expectedText = expectedOriginalText.normalizedQuotesForStorage.trimmed
        guard currentText == expectedText else { return nil }

        let firstPageText = firstPageText.normalizedQuotesForStorage.trimmed
        let secondPageText = secondPageText.normalizedQuotesForStorage.trimmed
        guard !firstPageText.isEmpty, !secondPageText.isEmpty else { return nil }

        let separator = OCRLineJoiner.inlineSeparator(between: firstPageText, and: secondPageText)
        let combinedText = "\(firstPageText)\(separator)\(secondPageText)".trimmed

        books[location.bookIndex].highlights[location.highlightIndex].text = combinedText
        books[location.bookIndex].highlights[location.highlightIndex].language = CaptureLanguage.detect(from: combinedText)
        persist()
        return books[location.bookIndex].highlights[location.highlightIndex]
    }

    @discardableResult
    func applyAutomaticOCRCorrection(
        _ correctedText: String,
        to highlightID: Highlight.ID,
        expectedHighlight: Highlight
    ) -> Highlight? {
        guard
            let location = highlightLocationByID[highlightID],
            books.indices.contains(location.bookIndex),
            books[location.bookIndex].highlights.indices.contains(location.highlightIndex)
        else {
            return nil
        }

        let currentHighlight = books[location.bookIndex].highlights[location.highlightIndex]
        guard currentHighlight == expectedHighlight else { return nil }

        let currentText = currentHighlight.text.normalizedQuotesForStorage.trimmed
        let correctedText = correctedText.normalizedQuotesForStorage.trimmed
        guard !correctedText.isEmpty, correctedText != currentText else {
            return nil
        }

        books[location.bookIndex].highlights[location.highlightIndex].text = correctedText
        books[location.bookIndex].highlights[location.highlightIndex].language = CaptureLanguage.detect(from: correctedText)
        persist()
        return books[location.bookIndex].highlights[location.highlightIndex]
    }

    @discardableResult
    func addQuickThought(
        _ thought: String,
        pageReference: String = "",
        tagsText: String = "",
        bookID: ReadingBook.ID? = nil,
        stickyTone: StickyTone = .mint
    ) -> Highlight {
        let normalizedThought = thought.normalizedQuotesForStorage
        let detectedLanguage = CaptureLanguage.detect(from: normalizedThought)
        let metadata = CapturedHighlightMetadata(
            memo: normalizedThought,
            detectedLanguage: detectedLanguage,
            fallbackPageReference: "Inbox",
            explicitPageReference: pageReference,
            tagsText: tagsText
        )
        let targetBookID = bookID ?? selectedBookID
        let highlightTags = CapturedHighlightMetadata.deduplicated(defaultTags(for: targetBookID) + metadata.tags)
        let highlight = Highlight(
            text: normalizedThought.trimmed,
            memo: "Shortcut",
            pageReference: metadata.pageReference,
            language: detectedLanguage,
            tags: highlightTags,
            stickyTone: stickyTone,
            source: .shortcut
        )
        append(highlight, to: targetBookID)
        persist()
        return highlight
    }

    @discardableResult
    func addInsight(
        categoryRaw: String,
        prompt: String,
        body: String,
        sourceCount: Int,
        sourceHighlightIDs: [Highlight.ID] = []
    ) -> LibraryInsight {
        let insight = LibraryInsight(
            categoryRaw: categoryRaw,
            prompt: prompt,
            body: body,
            sourceCount: sourceCount,
            sourceHighlightIDs: sourceHighlightIDs
        )
        savedInsights.insert(insight, at: 0)
        persist()
        return insight
    }

    func deleteInsight(_ insightID: LibraryInsight.ID) {
        _ = deleteInsightForUndo(insightID)
    }

    @discardableResult
    func deleteInsightForUndo(_ insightID: LibraryInsight.ID) -> DeletedInsightSnapshot? {
        guard let index = savedInsights.firstIndex(where: { $0.id == insightID }) else { return nil }

        let insight = savedInsights.remove(at: index)
        persist()
        return DeletedInsightSnapshot(insight: insight, index: index)
    }

    func restoreDeletedInsight(_ deletion: DeletedInsightSnapshot) {
        guard !savedInsights.contains(where: { $0.id == deletion.insight.id }) else { return }

        let index = min(max(deletion.index, 0), savedInsights.count)
        savedInsights.insert(deletion.insight, at: index)
        persist()
    }

    func resetLibrary() {
        let removedHighlightIDs = books.flatMap { $0.highlights.map(\.id) }
        let snapshot = currentSnapshot
        pendingResetBackupCleanupData = nil
        if !snapshot.isEmpty {
            resetBackupAvailable = Self.saveSnapshotBackup(snapshot, key: Self.resetBackupKey)
        }

        books = []
        savedInsights = []
        selectedBookID = nil
        persist()
        postRemovedHighlights(removedHighlightIDs)
        cleanupSnapshotFilesIfNeeded()
    }

    @discardableResult
    func restoreLastResetBackup() -> Bool {
        guard
            let backupData = UserDefaults.standard.data(forKey: Self.resetBackupKey),
            let snapshot = try? JSONDecoder().decode(LibraryStateSnapshot.self, from: backupData),
            !snapshot.isEmpty
        else {
            pendingResetBackupCleanupData = nil
            resetBackupAvailable = false
            return false
        }

        let restoredHighlightIDs = Set(snapshot.books.flatMap { $0.highlights.map(\.id) })
        let removedHighlightIDs = books
            .flatMap { $0.highlights.map(\.id) }
            .filter { !restoredHighlightIDs.contains($0) }

        books = snapshot.books
        savedInsights = snapshot.insights
        selectedBookID = snapshot.books.contains(where: { $0.id == snapshot.selectedBookID })
            ? snapshot.selectedBookID
            : snapshot.books.first?.id
        pendingResetBackupCleanupData = backupData
        persist()
        postRemovedHighlights(removedHighlightIDs)
        cleanupSnapshotFilesIfNeeded()
        return true
    }

    func updateHighlight(
        _ highlightID: Highlight.ID,
        text: String,
        memo: String,
        pageReference: String,
        tagsText: String,
        bookID: ReadingBook.ID? = nil,
        stickyTone: StickyTone? = nil,
        isReviewed: Bool = false
    ) {
        guard
            let location = highlightLocationByID[highlightID],
            books.indices.contains(location.bookIndex),
            books[location.bookIndex].highlights.indices.contains(location.highlightIndex)
        else {
            return
        }


        let bookIndex = location.bookIndex
        let highlightIndex = location.highlightIndex

        let trimmedText = text.normalizedQuotesForStorage.trimmed
        guard !trimmedText.isEmpty else { return }

        let tags = tagsText
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("#") ? $0 : "#\($0)" }

        let detectedLanguage = CaptureLanguage.detect(from: trimmedText)
        let targetBookID = bookID ?? books[bookIndex].id
        let targetBookIndex = books.firstIndex { $0.id == targetBookID } ?? bookIndex

        var updatedHighlight = books[bookIndex].highlights[highlightIndex]
        updatedHighlight.text = trimmedText
        updatedHighlight.memo = memo.normalizedQuotesForStorage.trimmed
        updatedHighlight.pageReference = pageReference.trimmed.isEmpty ? "p.?" : pageReference.trimmed
        updatedHighlight.language = detectedLanguage
        updatedHighlight.tags = CapturedHighlightMetadata.deduplicated(tags)
        updatedHighlight.stickyTone = stickyTone ?? updatedHighlight.stickyTone
        updatedHighlight.reviewedAt = isReviewed ? (updatedHighlight.reviewedAt ?? .now) : nil

        if targetBookIndex == bookIndex {
            books[bookIndex].highlights[highlightIndex] = updatedHighlight
        } else {
            books[bookIndex].highlights.remove(at: highlightIndex)
            books[targetBookIndex].highlights.insert(updatedHighlight, at: 0)
            selectedBookID = books[targetBookIndex].id
        }

        persist()
    }

    func deleteHighlight(_ highlightID: Highlight.ID) {
        _ = deleteHighlightForUndo(highlightID)
    }

    @discardableResult
    func deleteHighlightForUndo(_ highlightID: Highlight.ID) -> DeletedHighlightSnapshot? {
        guard
            let location = highlightLocationByID[highlightID],
            books.indices.contains(location.bookIndex),
            books[location.bookIndex].highlights.indices.contains(location.highlightIndex)
        else {
            return nil
        }


        let bookIndex = location.bookIndex
        let highlightIndex = location.highlightIndex

        let highlight = books[bookIndex].highlights.remove(at: highlightIndex)
        persist()
        postRemovedHighlights([highlight.id])
        return DeletedHighlightSnapshot(
            highlight: highlight,
            bookID: books[bookIndex].id,
            index: highlightIndex
        )
    }

    func restoreDeletedHighlight(_ deletion: DeletedHighlightSnapshot) {
        guard highlightLocationByID[deletion.highlight.id] == nil else { return }
        guard let bookIndex = books.firstIndex(where: { $0.id == deletion.bookID }) else { return }

        let index = min(max(deletion.index, 0), books[bookIndex].highlights.count)
        books[bookIndex].highlights.insert(deletion.highlight, at: index)
        selectedBookID = books[bookIndex].id
        persist()
    }

    private func append(_ highlight: Highlight, to bookID: ReadingBook.ID?) {
        guard !highlight.text.isEmpty else { return }

        if books.isEmpty {
            let inbox = ReadingBook(
                title: "Inbox",
                author: "BZOGAK",
                summary: "캡처한 글조각이 임시로 모이는 개인 보관함.",
                coverTheme: .cobalt,
                highlights: [highlight]
            )
            books = [inbox]
            selectedBookID = inbox.id
            return
        }

        let targetID = bookID ?? selectedBookID ?? books[0].id
        let targetIndex = books.firstIndex { $0.id == targetID } ?? 0
        books[targetIndex].highlights.insert(highlight, at: 0)
        selectedBookID = books[targetIndex].id
    }

    private func defaultTags(for bookID: ReadingBook.ID?) -> [String] {
        suggestedTags(for: bookID)
    }

    private static func normalizedReadingDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func normalizedReadingEndDate(_ endDate: Date?, startedAt: Date) -> Date? {
        guard let endDate else { return nil }
        let normalizedStart = normalizedReadingDate(startedAt)
        let normalizedEnd = normalizedReadingDate(endDate)
        return max(normalizedStart, normalizedEnd)
    }

    private static func normalizedReadingRating(_ rating: Double?) -> Double? {
        guard let rating, rating > 0 else { return nil }
        return min(max((rating * 2).rounded() / 2, 0.5), 5)
    }

    private func persist() {
        refreshDerivedState()
        let snapshot = currentSnapshot
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let snapshotWriter = snapshotWriter
        let hasPrimaryStore = persistence != nil

        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            let result = await snapshotWriter.save(
                snapshot,
                generation: generation,
                fallbackKey: Self.snapshotBackupKey
            )
            guard
                let self,
                self.persistenceGeneration == generation,
                let result
            else {
                return
            }

            self.storageStatus = LibraryStorageStatus(
                primaryStore: hasPrimaryStore ? "SwiftData" : "SwiftData 미사용",
                fallbackStore: "UserDefaults 백업",
                primarySaveSucceeded: result.primarySaveSucceeded,
                fallbackSaveSucceeded: result.fallbackSaveSucceeded,
                lastSavedAt: result.fallbackSaveSucceeded || result.primarySaveSucceeded ? .now : nil
            )

            if result.primarySaveSucceeded || result.fallbackSaveSucceeded {
                self.clearPendingResetBackupIfUnchanged()
            }
        }
    }

    private func clearPendingResetBackupIfUnchanged() {
        guard
            let pendingResetBackupCleanupData,
            UserDefaults.standard.data(forKey: Self.resetBackupKey) == pendingResetBackupCleanupData
        else {
            return
        }

        Self.deleteSnapshotBackup(key: Self.resetBackupKey)
        HighlightSnapshotStore.clearResetBackup()
        self.pendingResetBackupCleanupData = nil
        resetBackupAvailable = false
    }

    private func refreshDerivedState() {
        var nextBookIndexByID: [ReadingBook.ID: Int] = [:]
        var nextHighlightLocationByID: [Highlight.ID: (bookIndex: Int, highlightIndex: Int)] = [:]
        var highlights: [Highlight] = []
        highlights.reserveCapacity(books.reduce(into: 0) { $0 += $1.highlights.count })

        for (bookIndex, book) in books.enumerated() {
            nextBookIndexByID[book.id] = bookIndex
            for (highlightIndex, highlight) in book.highlights.enumerated() {
                nextHighlightLocationByID[highlight.id] = (bookIndex, highlightIndex)
                highlights.append(highlight)
            }
        }

        highlights.sort { $0.createdAt > $1.createdAt }
        bookIndexByID = nextBookIndexByID
        highlightLocationByID = nextHighlightLocationByID
        recentHighlights = highlights
        highlightCount = highlights.count
    }

    private func postRemovedHighlights(_ highlightIDs: [Highlight.ID]) {
        guard !highlightIDs.isEmpty else { return }
        NotificationCenter.default.post(
            name: .overlineHighlightsRemoved,
            object: nil,
            userInfo: [OverlineNotificationUserInfoKey.highlightIDs: highlightIDs]
        )
    }

    func flushPendingPersistence() async {
        await persistenceTask?.value
    }

    private func cleanupSnapshotFilesIfNeeded() {
        HighlightSnapshotStore.cleanup()
        HighlightSnapshotStore.clearResetBackup()
    }

    private var currentSnapshot: LibraryStateSnapshot {
        LibraryStateSnapshot(
            books: books,
            insights: savedInsights,
            selectedBookID: selectedBookID
        )
    }

    private static func loadPersistedHighlights(key: String) -> [Highlight] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let highlights = try? JSONDecoder().decode([Highlight].self, from: data)
        else {
            return []
        }
        return highlights
    }

    private static func loadSnapshotBackup(key: String) -> LibraryStateSnapshot? {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let snapshot = try? JSONDecoder().decode(LibraryStateSnapshot.self, from: data)
        else {
            return nil
        }

        return snapshot
    }

    private static func hasSnapshotBackup(key: String) -> Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    private static func deleteSnapshotBackup(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func saveSnapshotBackup(_ snapshot: LibraryStateSnapshot, key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    private static func isUntouchedDemoSnapshot(_ snapshot: LibraryStateSnapshot) -> Bool {
        let demoTitles = Set(SampleData.books.map(\.title))
        let demoInsightPrompts = Set(SampleData.insights.map(\.prompt))
        let snapshotTitles = Set(snapshot.books.map(\.title))
        let hasUserBookContent = snapshot.books.contains { book in
            !book.readingRecords.isEmpty || book.highlights.contains { $0.source != .sample }
        }
        let hasUserInsights = snapshot.insights.contains { insight in
            !demoInsightPrompts.contains(insight.prompt)
        }

        return !snapshot.books.isEmpty
            && snapshotTitles.isSubset(of: demoTitles)
            && !hasUserBookContent
            && !hasUserInsights
    }

    private static func removingDemoContent(from snapshot: LibraryStateSnapshot) -> LibraryStateSnapshot {
        let demoBookTitles = Set(SampleData.books.map(\.title))
        let demoInsightPrompts = Set(SampleData.insights.map(\.prompt))

        let books = snapshot.books.compactMap { book -> ReadingBook? in
            let nonDemoHighlights = book.highlights.filter { $0.source != .sample }
            let hasUserBookContent = !nonDemoHighlights.isEmpty || !book.readingRecords.isEmpty

            if demoBookTitles.contains(book.title) {
                guard hasUserBookContent else { return nil }
            }

            var sanitizedBook = book
            sanitizedBook.highlights = nonDemoHighlights
            return sanitizedBook
        }

        let insights = snapshot.insights.filter { insight in
            !demoInsightPrompts.contains(insight.prompt)
        }

        let selectedBookID = books.contains { $0.id == snapshot.selectedBookID }
            ? snapshot.selectedBookID
            : books.first?.id

        return LibraryStateSnapshot(
            books: books,
            insights: insights,
            selectedBookID: selectedBookID
        )
    }

    static var preview: ReadingLibrary {
        ReadingLibrary(
            books: SampleData.books,
            insights: SampleData.insights,
            includePersistedHighlights: false
        )
    }
}

enum SampleData {
    nonisolated static let pageLines: [SamplePageLine] = [
        SamplePageLine(id: 0, text: "BZOGAK AI", weight: .semibold),
        SamplePageLine(id: 1, text: "도서관 책에는 아무 표시도 남길 수 없었다.", weight: .regular),
        SamplePageLine(id: 2, text: "그래서 그는 손가락으로만 문장을 건넜다.", weight: .regular),
        SamplePageLine(id: 3, text: "The line did not belong to the page alone.", weight: .regular),
        SamplePageLine(id: 4, text: "그 순간의 생각까지 함께 저장되어야 했다.", weight: .regular),
        SamplePageLine(id: 5, text: "紙の余白は静かに記憶を待っていた。", weight: .regular)
    ]

    nonisolated static let books: [ReadingBook] = [
        ReadingBook(
            title: "빌린 책의 여백",
            author: "Han Seowoo",
            summary: "빌린 책에 남기지 못한 밑줄과 독자의 생각을 조용히 모아가는 에세이.",
            coverTheme: .forest,
            highlights: [
                Highlight(
                    text: "책에 직접 선을 긋지 않아도, 문장은 이미 나를 통과하고 있었다.",
                    memo: "빌린 책이라는 제약이 오히려 기록 방식을 바꾼다.",
                    pageReference: "p.18",
                    createdAt: .now.addingTimeInterval(-1800),
                    language: .korean,
                    tags: ["#철학", "#인용"],
                    stickyTone: .yellow,
                    source: .sample
                ),
                Highlight(
                    text: "A note is not a copy of reading. It is the shape reading leaves behind.",
                    memo: "Socratic Mode 첫 질문 후보.",
                    pageReference: "p.31",
                    createdAt: .now.addingTimeInterval(-3600),
                    language: .english,
                    tags: ["#아이디어"],
                    stickyTone: .blue,
                    source: .sample
                )
            ]
        ),
        ReadingBook(
            title: "Margin Atlas",
            author: "Mina Cole",
            summary: "문장, 여백, 메모가 서로 이어지는 방식을 지도처럼 따라가는 노트.",
            coverTheme: .cobalt,
            highlights: [
                Highlight(
                    text: "Every underline is a coordinate for returning.",
                    memo: "Cross-book 연결: 회귀, 좌표, 기억.",
                    pageReference: "p.7",
                    createdAt: .now.addingTimeInterval(-86400),
                    language: .english,
                    tags: ["#theme"],
                    stickyTone: .rose,
                    source: .sample
                )
            ]
        ),
        ReadingBook(
            title: "페이지의 온도",
            author: "Ishikawa Rei",
            summary: "읽는 순간의 감각과 시간이 페이지 위에 남기는 작은 온도에 관한 기록.",
            coverTheme: .vermilion,
            highlights: []
        )
    ]

    nonisolated static let insights: [LibraryInsight] = [
        LibraryInsight(
            categoryRaw: "connect",
            prompt: "서로 다른 문장 사이의 공통 패턴은?",
            body: "직접 선을 긋지 못하는 제약이 오히려 기록 방식을 바꿉니다. 메모는 원문 복사가 아니라, 다시 돌아올 위치를 만드는 독자의 표시입니다.",
            sourceCount: 3,
            createdAt: .now.addingTimeInterval(-900)
        )
    ]
}

extension Date {
    private static let overlineShortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M월d일(E) HH:mm"
        return formatter
    }()

    var overlineShortDate: String {
        Self.overlineShortDateFormatter.string(from: self)
    }
}

extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var normalizedQuotesForStorage: String {
        replacingOccurrences(of: "[“”„‟«»＂]", with: "\"", options: .regularExpression)
    }

    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
