import Foundation
import Observation
import Security

struct LLMModelOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum LLMProvider: String, CaseIterable, Codable, Identifiable {
    case openrouter
    case anthropic
    case openai
    case gemini

    var id: String { rawValue }

    static let settingsOrder: [LLMProvider] = [
        .openai,
        .anthropic,
        .gemini,
        .openrouter
    ]

    var title: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .gemini: "Google"
        }
    }

    var shortTitle: String {
        switch self {
        case .openrouter: "OR"
        case .anthropic: "AN"
        case .openai: "OA"
        case .gemini: "GO"
        }
    }

    var assetName: String {
        switch self {
        case .openrouter: "LLMOpenRouter"
        case .anthropic: "LLMAnthropic"
        case .openai: "LLMOpenAI"
        case .gemini: "LLMGemini"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openrouter: "sk-or-..."
        case .anthropic: "sk-ant-..."
        case .openai: "sk-..."
        case .gemini: "AIza..."
        }
    }

    var defaultModelID: String {
        modelOptions.first?.id ?? ""
    }

    var modelOptions: [LLMModelOption] {
        switch self {
        case .openrouter:
            [
                LLMModelOption(id: "openrouter/auto", title: "Auto Router"),
                LLMModelOption(id: "deepseek/deepseek-v4-pro", title: "DeepSeek V4 Pro"),
                LLMModelOption(id: "arcee-ai/trinity-large-thinking", title: "Trinity Large Thinking"),
                LLMModelOption(id: "minimax/minimax-m3", title: "MiniMax M3"),
                LLMModelOption(id: "nvidia/nemotron-3-ultra-550b-a55b", title: "Nemotron 3 Ultra")
            ]
        case .anthropic:
            [
                LLMModelOption(id: "claude-haiku-4-5-20251001", title: "Claude Haiku 4.5"),
                LLMModelOption(id: "claude-sonnet-5", title: "Claude Sonnet 5"),
                LLMModelOption(id: "claude-opus-5", title: "Claude Opus 5")
            ]
        case .openai:
            [
                LLMModelOption(id: "gpt-5.6-luna", title: "GPT-5.6 Luna"),
                LLMModelOption(id: "gpt-5.6-terra", title: "GPT-5.6 Terra"),
                LLMModelOption(id: "gpt-5.6-sol", title: "GPT-5.6 Sol")
            ]
        case .gemini:
            [
                LLMModelOption(id: "gemini-3.5-flash-lite", title: "Gemini 3.5 Flash-Lite"),
                LLMModelOption(id: "gemini-3.7-flash", title: "Gemini 3.7 Flash"),
                LLMModelOption(id: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro")
            ]
        }
    }
}

enum LLMAuthMode: String, CaseIterable, Codable, Identifiable {
    case apiKey

    var id: String { rawValue }

    var title: String {
        "API 키 사용"
    }

    var systemImage: String {
        "key"
    }
}

enum LLMAuthCredential: Equatable {
    case apiKey(String)

    var mode: LLMAuthMode {
        .apiKey
    }
}

struct LLMTagProviderConfiguration: Equatable {
    let provider: LLMProvider
    let modelID: String
    let credential: LLMAuthCredential
}

@MainActor
@Observable
final class LLMSettingsStore {
    var provider: LLMProvider {
        didSet {
            guard provider != oldValue else { return }
            saveProvider()
            setAllowsExternalAIDataSharing(false)
        }
    }

    private(set) var apiKeys: [LLMProvider: String]
    private(set) var allowsExternalAIDataSharing: Bool
    private var selectedModelIDs: [LLMProvider: String]
    private var rejectedCredentialKeys: Set<String>
    @ObservationIgnored private var loadedAPIKeyProviders: Set<LLMProvider> = []

    init() {
        let defaults = UserDefaults.standard
        Self.purgeLegacySubscriptionCredentials(defaults: defaults)
        if
            let rawProvider = defaults.string(forKey: Self.providerKey),
            let storedProvider = LLMProvider(rawValue: rawProvider)
        {
            provider = storedProvider
        } else {
            provider = .openai
        }

        apiKeys = [:]
        allowsExternalAIDataSharing = defaults.bool(forKey: Self.externalAIDataSharingKey)

        selectedModelIDs = Dictionary(
            uniqueKeysWithValues: LLMProvider.allCases.map { provider in
                let stored = defaults.string(forKey: Self.modelKey(for: provider))
                if let stored, !stored.trimmed.isEmpty {
                    let normalized = Self.normalizedModelID(stored, for: provider)
                    if normalized != stored {
                        defaults.set(normalized, forKey: Self.modelKey(for: provider))
                    }
                    return (provider, normalized)
                }
                return (provider, provider.defaultModelID)
            }
        )

        rejectedCredentialKeys = Set(
            LLMProvider.allCases.compactMap { provider in
                let key = Self.rejectedCredentialKey(for: provider, mode: .apiKey)
                return defaults.bool(forKey: key) ? key : nil
            }
        )
    }

    var selectedModelID: String {
        selectedModelIDs[provider] ?? provider.defaultModelID
    }

    var selectedModelTitle: String {
        provider.modelOptions.first { $0.id == selectedModelID }?.title ?? selectedModelID
    }

    var activeConfiguration: LLMTagProviderConfiguration? {
        guard isReady(for: provider) else { return nil }
        return LLMTagProviderConfiguration(
            provider: provider,
            modelID: selectedModelID,
            credential: credential(for: provider)
        )
    }

    func setSelectedModelID(_ modelID: String) {
        let trimmedModelID = modelID.trimmed
        guard !trimmedModelID.isEmpty else {
            selectedModelIDs[provider] = provider.defaultModelID
            UserDefaults.standard.set(provider.defaultModelID, forKey: Self.modelKey(for: provider))
            clearCredentialRejection(for: provider, mode: .apiKey)
            return
        }

        selectedModelIDs[provider] = trimmedModelID
        UserDefaults.standard.set(trimmedModelID, forKey: Self.modelKey(for: provider))
        clearCredentialRejection(for: provider, mode: .apiKey)
    }

    func apiKey(for provider: LLMProvider) -> String {
        ensureAPIKeyLoaded(for: provider)
        return apiKeys[provider] ?? ""
    }

    func setAPIKey(_ apiKey: String, for provider: LLMProvider) {
        loadedAPIKeyProviders.insert(provider)
        apiKeys[provider] = apiKey
        Self.keychain.set(apiKey.trimmed, account: provider.rawValue)
        clearCredentialRejection(for: provider, mode: .apiKey)
    }

    func hasAPIKey(for provider: LLMProvider) -> Bool {
        !apiKey(for: provider).trimmed.isEmpty
    }

    func authMode(for provider: LLMProvider) -> LLMAuthMode {
        .apiKey
    }

    func setAllowsExternalAIDataSharing(_ isAllowed: Bool) {
        allowsExternalAIDataSharing = isAllowed
        UserDefaults.standard.set(isAllowed, forKey: Self.externalAIDataSharingKey)
    }

    func hasCredential(for provider: LLMProvider) -> Bool {
        hasAPIKey(for: provider)
    }

    func isReady(for provider: LLMProvider) -> Bool {
        allowsExternalAIDataSharing
            && hasCredential(for: provider)
            && !isCredentialRejected(for: provider)
    }

    func credential(for provider: LLMProvider) -> LLMAuthCredential {
        .apiKey(apiKey(for: provider))
    }

    func isCredentialRejected(for provider: LLMProvider) -> Bool {
        rejectedCredentialKeys.contains(
            Self.rejectedCredentialKey(for: provider, mode: .apiKey)
        )
    }

    func handleRequestError(
        _ error: Error,
        configuration: LLMTagProviderConfiguration
    ) {
        guard
            case .requestFailed(let statusCode, _) = error as? LLMInsightError,
            [401, 403].contains(statusCode),
            isCurrent(configuration)
        else {
            return
        }

        let provider = configuration.provider
        let mode = configuration.credential.mode
        let key = Self.rejectedCredentialKey(for: provider, mode: mode)
        rejectedCredentialKeys.insert(key)
        UserDefaults.standard.set(true, forKey: key)
    }

    func handleRequestSuccess(configuration: LLMTagProviderConfiguration) {
        guard isCurrent(configuration) else { return }
        clearCredentialRejection(
            for: configuration.provider,
            mode: configuration.credential.mode
        )
    }

    private func saveProvider() {
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
    }

    private func ensureAPIKeyLoaded(for provider: LLMProvider) {
        guard loadedAPIKeyProviders.insert(provider).inserted else { return }
        apiKeys[provider] = Self.keychain.string(account: provider.rawValue) ?? ""
    }

    private static let providerKey = "overline.llm.provider"
    private static let externalAIDataSharingKey = "overline.llm.externalAIDataSharingAllowed"

    private static func modelKey(for provider: LLMProvider) -> String {
        "overline.llm.model.\(provider.rawValue)"
    }

    private func clearCredentialRejection(for provider: LLMProvider, mode: LLMAuthMode) {
        let key = Self.rejectedCredentialKey(for: provider, mode: mode)
        rejectedCredentialKeys.remove(key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func isCurrent(_ configuration: LLMTagProviderConfiguration) -> Bool {
        let currentModelID = selectedModelIDs[configuration.provider]
            ?? configuration.provider.defaultModelID
        return currentModelID == configuration.modelID
            && credential(for: configuration.provider) == configuration.credential
    }

    private static func rejectedCredentialKey(for provider: LLMProvider, mode: LLMAuthMode) -> String {
        "overline.llm.credentialRejected.\(provider.rawValue).\(mode.rawValue)"
    }

    static func purgeLegacySubscriptionCredentials(
        defaults: UserDefaults,
        deleteCredential: @MainActor (KeychainStringStore, String) -> Void = { store, account in
            store.delete(account: account)
        }
    ) {
        // Cleanup is limited to this app's accessible Keychain groups, not other app identities.
        for provider in LLMProvider.allCases {
            deleteCredential(legacySubscriptionKeychain, provider.rawValue)
            deleteCredential(subscriptionKeychain, provider.rawValue)
            defaults.removeObject(forKey: "overline.llm.authMode.\(provider.rawValue)")
            defaults.removeObject(
                forKey: "overline.llm.credentialRejected.\(provider.rawValue).subscription"
            )
        }
    }

    private static func normalizedModelID(_ modelID: String, for provider: LLMProvider) -> String {
        let trimmedModelID = modelID.trimmed

        switch provider {
        case .openrouter:
            switch trimmedModelID {
            case "~openai/gpt-mini-latest",
                 "~anthropic/claude-haiku-latest",
                 "openai/gpt-5.4-nano",
                 "openai/gpt-5.4-mini",
                 "anthropic/claude-haiku-4.5",
                 "google/gemini-3.1-flash-lite":
                return "openrouter/auto"
            default:
                return trimmedModelID
            }
        case .gemini:
            if trimmedModelID == "gemini-2.5-flash-lite" {
                return "gemini-3.1-pro-preview"
            }
            return trimmedModelID
        case .anthropic, .openai:
            return trimmedModelID
        }
    }

    private static let keychain = KeychainStringStore(service: "vote.aib.bzogak.llm")
    // Earlier service namespace; a different app/team's private Keychain remains inaccessible.
    private static let legacySubscriptionKeychain = KeychainStringStore(service: "aib.Overline.llm.subscription")
    private static let subscriptionKeychain = KeychainStringStore(service: "vote.aib.bzogak.llm.subscription")
}

struct KeychainStringStore {
    let service: String

    static var storagePolicyLabel: String {
        "Keychain · 이 기기 전용"
    }

    func string(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, account: String) {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }

        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecSuccess else { return }

        if status != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = Self.accessibility
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static var accessibility: CFString {
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
}
