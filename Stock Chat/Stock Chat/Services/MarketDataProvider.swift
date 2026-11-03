import Foundation

/// Abstraction over a market data source. Each `Market` is served by one provider,
/// so adding a new market means adding a provider and registering it in `MarketData`.
protocol MarketDataProvider: Sendable {
    nonisolated var market: Market { get }

    func quote(_ symbol: String) async throws -> Quote
    func quotes(_ symbols: [String]) async throws -> [Quote]
    func profile(_ symbol: String) async throws -> CompanyProfile?
    func etfInfo(_ symbol: String) async throws -> ETFInfo?
    func ratios(_ symbol: String) async throws -> RatiosTTM?
    func priceChange(_ symbol: String) async throws -> PriceChange?
    func history(_ symbol: String, range: ChartRange) async throws -> [PricePoint]
    func news(for symbols: [String], limit: Int) async throws -> [NewsArticle]
    func stocks(sector: String?, limit: Int) async throws -> [SecuritySummary]
    func etfs(limit: Int) async throws -> [SecuritySummary]
    func search(_ query: String) async throws -> [SecuritySummary]
    nonisolated func logoURL(for symbol: String) -> URL?
}

nonisolated enum MarketDataError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case restricted(String)
    case http(Int)
    case notFound

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No FMP API key. Add one in Settings."
        case .invalidAPIKey: "The FMP API key was rejected. Update it in Settings."
        case .restricted(let message): message
        case .http(let code): "The server returned an error (\(code))."
        case .notFound: "No data available."
        }
    }
}

/// Entry point used by views. Resolves the provider for a market.
@Observable
final class MarketData {
    private var providers: [Market: any MarketDataProvider] = [:]
    private let makeProviders: () -> [any MarketDataProvider]
    /// Incremented whenever providers are rebuilt (e.g. after an API key change) so views can reload.
    private(set) var revision = 0

    init(makeProviders: @escaping () -> [any MarketDataProvider]) {
        self.makeProviders = makeProviders
        providers = Self.index(makeProviders())
    }

    static func live() -> MarketData {
        MarketData { [FMPClient(apiKey: Secrets.fmpAPIKey)] }
    }

    /// Recreates providers with the current API keys and clears their caches.
    func reloadProviders() {
        providers = Self.index(makeProviders())
        revision += 1
    }

    private static func index(_ providers: [any MarketDataProvider]) -> [Market: any MarketDataProvider] {
        Dictionary(uniqueKeysWithValues: providers.map { ($0.market, $0) })
    }

    func provider(for market: Market) -> any MarketDataProvider {
        guard let provider = providers[market] else {
            preconditionFailure("No data provider registered for \(market)")
        }
        return provider
    }

    var availableMarkets: [Market] { Market.allCases.filter { providers[$0] != nil } }
}
