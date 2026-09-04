import Foundation

// Isolate the production settings store from the rest of the app's networking helpers.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum LLMInsightError: Error {
    case requestFailed(Int, String)
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

@main
@MainActor
struct LegacyCredentialCleanupTests {
    static func main() {
        do {
            try runChecks()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func runChecks() throws {
        let suiteName = "bzogak-credential-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let subscriptionServices = [
            "aib.Overline.llm.subscription",
            "vote.aib.bzogak.llm.subscription",
        ]
        let apiKeyServices = ["aib.Overline.llm", "vote.aib.bzogak.llm"]
        let accounts = LLMProvider.allCases.map(\.rawValue)
        var items: [String: [String: String]] = [:]
        for service in subscriptionServices + apiKeyServices {
            items[service] = Dictionary(uniqueKeysWithValues: accounts.map { ($0, "test-only-value") })
            items[service]?["unrelated-account"] = "keep"
        }
        let expectedAPIKeys = apiKeyServices.map { items[$0] }
        var deletions: [(String, String)] = []

        for account in accounts {
            defaults.set("subscription", forKey: "overline.llm.authMode.\(account)")
            defaults.set(true, forKey: "overline.llm.credentialRejected.\(account).subscription")
            defaults.set(true, forKey: "overline.llm.credentialRejected.\(account).apiKey")
            defaults.set("custom-model", forKey: "overline.llm.model.\(account)")
        }
        defaults.set("openai", forKey: "overline.llm.provider")
        defaults.set(true, forKey: "overline.llm.externalAIDataSharingAllowed")
        defaults.set("keep-reading-records", forKey: "unrelated-library-setting")

        // Inject in-memory deletion so these tests never read or change the real Keychain.
        let deleteCredential: @MainActor (KeychainStringStore, String) -> Void = { store, account in
            deletions.append((store.service, account))
            items[store.service]?.removeValue(forKey: account)
        }
        LLMSettingsStore.purgeLegacySubscriptionCredentials(
            defaults: defaults, deleteCredential: deleteCredential
        )

        for service in subscriptionServices {
            for account in accounts {
                try require(items[service]?[account] == nil, "Subscription credential was not removed: \(service)/\(account)")
            }
            try require(items[service]?["unrelated-account"] == "keep", "Unrelated account was removed")
        }
        try require(deletions.count == accounts.count * subscriptionServices.count, "Unexpected deletion count")
        try require(apiKeyServices.map { items[$0] } == expectedAPIKeys, "API keys changed")
        print("PASS: both subscription namespaces are cleared; API keys and unrelated accounts are preserved")

        for account in accounts {
            try require(defaults.object(forKey: "overline.llm.authMode.\(account)") == nil, "Legacy auth mode remains")
            try require(defaults.object(forKey: "overline.llm.credentialRejected.\(account).subscription") == nil, "Legacy rejection remains")
            try require(defaults.bool(forKey: "overline.llm.credentialRejected.\(account).apiKey"), "API key rejection changed")
            try require(defaults.string(forKey: "overline.llm.model.\(account)") == "custom-model", "Model selection changed")
        }
        try require(defaults.string(forKey: "overline.llm.provider") == "openai", "Provider changed")
        try require(defaults.bool(forKey: "overline.llm.externalAIDataSharingAllowed"), "Consent changed")
        try require(defaults.string(forKey: "unrelated-library-setting") == "keep-reading-records", "Unrelated setting changed")
        print("PASS: only obsolete subscription preferences are removed")

        let afterFirstCleanup = items
        LLMSettingsStore.purgeLegacySubscriptionCredentials(
            defaults: defaults, deleteCredential: deleteCredential
        )
        try require(items == afterFirstCleanup, "Repeated cleanup changed remaining items")
        print("PASS: repeated cleanup is safe when obsolete credentials are absent")
        print("All 3 legacy credential cleanup checks passed")
    }
}
