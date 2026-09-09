import Foundation

@main struct Runner {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RankingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var date = Date(timeIntervalSince1970: 1_000_000)
        let model = CommunityViewModel(
            client: OverlineAPIClient(session: session, baseURL: URL(string: "https://test.invalid")!),
            now: { date }
        )

        await model.loadRankings()
        let bestseller = model.rankings
        model.selectRankingKind(.loans)
        await model.loadRankings()
        let loans = model.rankings
        model.selectRankingKind(.bestseller)
        await model.loadRankings()
        precondition(RankingURLProtocol.requestCount == 2 && model.rankings == bestseller)
        model.selectRankingKind(.loans)
        await model.loadRankings()
        precondition(RankingURLProtocol.requestCount == 2 && model.rankings == loans)
        print("PASS: kind cache reuse")

        await model.loadRankings(force: true)
        precondition(RankingURLProtocol.requestCount == 3)
        print("PASS: force refresh")

        date = date.addingTimeInterval(8 * 60 * 60 - 1)
        await model.loadRankings()
        precondition(RankingURLProtocol.requestCount == 3)
        print("PASS: cache retained until eight hours")

        date = date.addingTimeInterval(1)
        await model.loadRankings()
        precondition(RankingURLProtocol.requestCount == 4)
        print("PASS: cache expiry")

        RankingURLProtocol.holdNext()
        model.rankingCategory = .philosophy
        let pending = Task { await model.loadRankings() }
        try await waitForRequest(5)
        precondition(model.isLoadingRankings && model.rankings.isEmpty)
        model.rankingCategory = .all
        await model.loadRankings()
        precondition(!model.isLoadingRankings && model.rankings == loans)
        RankingURLProtocol.release()
        await pending.value
        precondition(model.rankings == loans && model.rankingError == nil)
        print("PASS: loading state and stale request after cache hit")

        RankingURLProtocol.holdNext()
        model.rankingCategory = .philosophy
        let failure = Task { await model.loadRankings() }
        try await waitForRequest(6)
        RankingURLProtocol.release(status: 502)
        await failure.value
        precondition(model.rankingError != nil && !model.isLoadingRankings)
        await model.loadRankings()
        precondition(RankingURLProtocol.requestCount == 7 && model.rankingError == nil)
        print("PASS: failed requests are not cached")
    }

    static func waitForRequest(_ count: Int) async throws {
        for _ in 0..<200 {
            if RankingURLProtocol.requestCount >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Request did not start")
    }
}
