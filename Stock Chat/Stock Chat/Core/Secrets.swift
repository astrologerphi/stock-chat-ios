import Foundation

/// API keys injected at build time by the "Embed API Secrets" build phase, which reads
/// `.secrets` at the repository root and writes `Secrets.plist` into the app bundle.
nonisolated enum Secrets {
    static var fmpAPIKey: String {
        if let key = ProcessInfo.processInfo.environment["FMP_API_KEY"], !key.isEmpty { return key }
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["FMPAPIKey"] as? String else { return "" }
        return key
    }
}
