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

    var title: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    var shortTitle: String {
        switch self {
        case .openrouter: "OR"
        case .anthropic: "AN"
        case .openai: "OA"
        case .gemini: "GM"
        }
    }

    var systemImage: String {
        switch self {
        case .openrouter: "point.3.connected.trianglepath.dotted"
        case .anthropic: "a.circle"
        case .openai: "sparkles"
        case .gemini: "diamond"
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
                LLMModelOption(id: "claude-sonnet-4-6", title: "Claude Sonnet 4.6"),
                LLMModelOption(id: "claude-opus-4-8", title: "Claude Opus 4.8")
            ]
        case .openai:
            [
                LLMModelOption(id: "gpt-5.4-nano", title: "GPT-5.4 nano"),
                LLMModelOption(id: "gpt-5.4-mini", title: "GPT-5.4 mini"),
                LLMModelOption(id: "gpt-5.5", title: "GPT-5.5")
            ]
        case .gemini:
            [
                LLMModelOption(id: "gemini-3.1-flash-lite", title: "Gemini 3.1 Flash-Lite"),
                LLMModelOption(id: "gemini-3.5-flash", title: "Gemini 3.5 Flash"),
                LLMModelOption(id: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro")
            ]
        }
    }
}

@MainActor
@Observable
final class LLMSettingsStore {
    var provider: LLMProvider {
        didSet {
            guard provider != oldValue else { return }
            saveProvider()
        }
    }

    private(set) var apiKeys: [LLMProvider: String]
    private var selectedModelIDs: [LLMProvider: String]

    init() {
        let defaults = UserDefaults.standard
        if
            let rawProvider = defaults.string(forKey: Self.providerKey),
            let storedProvider = LLMProvider(rawValue: rawProvider)
        {
            provider = storedProvider
        } else {
            provider = .openai
        }

        apiKeys = Dictionary(
            uniqueKeysWithValues: LLMProvider.allCases.map { provider in
                let storedKey = Self.keychain.string(account: provider.rawValue) ?? ""
                if !storedKey.trimmed.isEmpty {
                    Self.keychain.set(storedKey, account: provider.rawValue)
                }
                return (provider, storedKey)
            }
        )

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
    }

    var selectedModelID: String {
        selectedModelIDs[provider] ?? provider.defaultModelID
    }

    var selectedModelTitle: String {
        provider.modelOptions.first { $0.id == selectedModelID }?.title ?? selectedModelID
    }

    func setSelectedModelID(_ modelID: String) {
        let trimmedModelID = modelID.trimmed
        guard !trimmedModelID.isEmpty else {
            selectedModelIDs[provider] = provider.defaultModelID
            UserDefaults.standard.set(provider.defaultModelID, forKey: Self.modelKey(for: provider))
            return
        }

        selectedModelIDs[provider] = trimmedModelID
        UserDefaults.standard.set(trimmedModelID, forKey: Self.modelKey(for: provider))
    }

    func apiKey(for provider: LLMProvider) -> String {
        apiKeys[provider] ?? ""
    }

    func setAPIKey(_ apiKey: String, for provider: LLMProvider) {
        apiKeys[provider] = apiKey
        Self.keychain.set(apiKey.trimmed, account: provider.rawValue)
    }

    func hasAPIKey(for provider: LLMProvider) -> Bool {
        !apiKey(for: provider).trimmed.isEmpty
    }

    private func saveProvider() {
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
    }

    private static let providerKey = "overline.llm.provider"

    private static func modelKey(for provider: LLMProvider) -> String {
        "overline.llm.model.\(provider.rawValue)"
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

    private static let keychain = KeychainStringStore(service: "aib.Overline.llm")
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
