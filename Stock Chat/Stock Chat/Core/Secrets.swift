import Foundation
import Security

/// Third-party services that need an API key.
nonisolated enum APIService: String, CaseIterable, Identifiable, Sendable {
    case fmp
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fmp: "Financial Modeling Prep"
        case .gemini: "Google Gemini"
        }
    }

    var usage: String {
        switch self {
        case .fmp: "Market data for US stocks, ETFs and news. Get a free key at [financialmodelingprep.com](https://site.financialmodelingprep.com/developer/docs)."
        case .gemini: "For AI features. Get a key at [Google AI Studio](https://aistudio.google.com/apikey)."
        }
    }

    var environmentVariable: String {
        switch self {
        case .fmp: "FMP_API_KEY"
        case .gemini: "GEMINI_API_KEY"
        }
    }

    /// Key name in the bundled `Secrets.plist` written by the "Embed API Secrets" build phase.
    var bundledKeyName: String {
        switch self {
        case .fmp: "FMPAPIKey"
        case .gemini: "GeminiAPIKey"
        }
    }
}

nonisolated enum APIKeySource: Sendable {
    case settings, environment, bundled

    var label: String {
        switch self {
        case .settings: "Saved in Settings"
        case .environment: "From environment"
        case .bundled: "Built in (.secrets)"
        }
    }
}

nonisolated struct ResolvedAPIKey: Equatable, Sendable {
    var value: String
    var source: APIKeySource

    var masked: String { "••••" + value.suffix(4) }
}

/// Resolves API keys. A key saved in Settings (Keychain) wins over the `*_API_KEY` environment
/// variable, which wins over the key embedded from `.secrets` at build time.
nonisolated enum Secrets {
    static func key(for service: APIService) -> ResolvedAPIKey? {
        if let key = Keychain.string(for: service.rawValue)?.trimmed, !key.isEmpty {
            return ResolvedAPIKey(value: key, source: .settings)
        }
        if let key = ProcessInfo.processInfo.environment[service.environmentVariable]?.trimmed, !key.isEmpty {
            return ResolvedAPIKey(value: key, source: .environment)
        }
        if let key = (bundled[service.bundledKeyName] as? String)?.trimmed, !key.isEmpty {
            return ResolvedAPIKey(value: key, source: .bundled)
        }
        return nil
    }

    static var fmpAPIKey: String { key(for: .fmp)?.value ?? "" }
    static var geminiAPIKey: String { key(for: .gemini)?.value ?? "" }

    @discardableResult
    static func save(_ key: String, for service: APIService) -> Bool {
        Keychain.set(key.trimmed, for: service.rawValue)
    }

    static func removeSavedKey(for service: APIService) {
        Keychain.delete(service.rawValue)
    }

    private static let bundled: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()
}

/// Minimal generic-password Keychain wrapper (device-only, no iCloud sync).
nonisolated enum Keychain {
    private static let service = "com.fhh.Stock-Chat.api-keys"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func string(for account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
