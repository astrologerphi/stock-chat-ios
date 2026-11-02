import Foundation

/// Financial Modeling Prep (https://financialmodelingprep.com) client for US market data.
actor FMPClient: MarketDataProvider {
    nonisolated let market: Market = .us

    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://financialmodelingprep.com/stable/")!
    private var cache: [String: (expires: Date, data: Data)] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]
    private var etfSymbols: Set<String>?

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    // MARK: - Quotes & fundamentals

    func quote(_ symbol: String) async throws -> Quote {
        let quotes: [Quote] = try await get("quote", ["symbol": symbol], ttl: 30)
        guard let quote = quotes.first else { throw MarketDataError.notFound }
        return quote
    }

    /// The batch endpoint is not available on every plan, so quotes are fetched concurrently.
    func quotes(_ symbols: [String]) async throws -> [Quote] {
        try await withThrowingTaskGroup(of: (Int, Quote?).self) { group in
            for (index, symbol) in symbols.enumerated() {
                group.addTask { (index, try? await self.quote(symbol)) }
            }
            var results: [(Int, Quote)] = []
            for try await (index, quote) in group {
                if let quote { results.append((index, quote)) }
            }
            if results.isEmpty, !symbols.isEmpty {
                // Surface the underlying error (e.g. invalid key) instead of an empty list.
                _ = try await quote(symbols[0])
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func profile(_ symbol: String) async throws -> CompanyProfile? {
        let profiles: [CompanyProfile] = try await get("profile", ["symbol": symbol], ttl: 3600)
        return profiles.first
    }

    func etfInfo(_ symbol: String) async throws -> ETFInfo? {
        let infos: [ETFInfo] = try await get("etf/info", ["symbol": symbol], ttl: 3600)
        return infos.first
    }

    func ratios(_ symbol: String) async throws -> RatiosTTM? {
        let ratios: [RatiosTTM] = try await get("ratios-ttm", ["symbol": symbol], ttl: 3600)
        return ratios.first
    }

    func priceChange(_ symbol: String) async throws -> PriceChange? {
        let changes: [PriceChange] = try await get("stock-price-change", ["symbol": symbol], ttl: 300)
        return changes.first
    }

    // MARK: - Charts

    func history(_ symbol: String, range: ChartRange) async throws -> [PricePoint] {
        let calendar = Self.calendar
        let now = Date.now
        switch range {
        case .day, .week:
            let interval = range == .day ? "5min" : "30min"
            let from = calendar.date(byAdding: .day, value: range == .day ? -6 : -12, to: now)!
            let bars: [IntradayBar] = try await get(
                "historical-chart/\(interval)",
                ["symbol": symbol, "from": Self.dayFormatter.string(from: from)],
                ttl: 120
            )
            let points = bars.compactMap { bar -> PricePoint? in
                guard let date = Self.timestampFormatter.date(from: bar.date) else { return nil }
                return PricePoint(date: date, price: bar.close, volume: bar.volume)
            }.sorted { $0.date < $1.date }
            let days = Array(Set(points.map { calendar.startOfDay(for: $0.date) })).sorted()
            let keep = Set(days.suffix(range == .day ? 1 : 5))
            return points.filter { keep.contains(calendar.startOfDay(for: $0.date)) }
        case .month, .sixMonths, .year, .fiveYears:
            let component: (Calendar.Component, Int) = switch range {
            case .month: (.month, -1)
            case .sixMonths: (.month, -6)
            case .year: (.year, -1)
            default: (.year, -5)
            }
            let from = calendar.date(byAdding: component.0, value: component.1, to: now)!
            let bars: [EODBar] = try await get(
                "historical-price-eod/light",
                ["symbol": symbol, "from": Self.dayFormatter.string(from: from)],
                ttl: 900
            )
            let points = bars.compactMap { bar -> PricePoint? in
                guard let date = Self.dayFormatter.date(from: bar.date) else { return nil }
                return PricePoint(date: date, price: bar.price, volume: bar.volume)
            }.sorted { $0.date < $1.date }
            guard range == .fiveYears, points.count > 400 else { return points }
            // Thin out long series to keep the chart light.
            let stride = points.count / 300 + 1
            return points.enumerated().filter { $0.offset % stride == 0 || $0.offset == points.count - 1 }.map(\.element)
        }
    }

    // MARK: - News

    func news(for symbols: [String], limit: Int) async throws -> [NewsArticle] {
        guard !symbols.isEmpty else { return [] }
        let raw: [RawNews] = try await get(
            "news/stock",
            ["symbols": symbols.joined(separator: ","), "limit": String(limit), "page": "0"],
            ttl: 300
        )
        var seen = Set<URL>()
        return raw.compactMap { item -> NewsArticle? in
            guard let url = URL(string: item.url), seen.insert(url).inserted,
                  let date = Self.timestampFormatter.date(from: item.publishedDate) else { return nil }
            return NewsArticle(
                symbol: item.symbol,
                publishedDate: date,
                publisher: item.publisher,
                title: item.title,
                image: item.image.flatMap(URL.init(string:)),
                site: item.site,
                text: item.text,
                url: url
            )
        }
        .sorted { $0.publishedDate > $1.publishedDate }
    }

    // MARK: - Lists & search

    /// The screener does not support offsets, so callers page by requesting a larger `limit`.
    func stocks(sector: String?, limit: Int) async throws -> [SecuritySummary] {
        var params = screenerBase
        params["isEtf"] = "false"
        params["isFund"] = "false"
        params["limit"] = String(limit)
        if let sector { params["sector"] = sector }
        let rows: [ScreenerRow] = try await get("company-screener", params, ttl: 600)
        return rows.map { $0.summary(kind: .stock) }
    }

    func etfs(limit: Int) async throws -> [SecuritySummary] {
        var params = screenerBase
        params["isEtf"] = "true"
        params["limit"] = String(limit)
        let rows: [ScreenerRow] = try await get("company-screener", params, ttl: 600)
        return rows.map { $0.summary(kind: .etf) }
    }

    func search(_ query: String) async throws -> [SecuritySummary] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        async let bySymbol: [SearchRow] = get("search-symbol", ["query": query, "limit": "50"], ttl: 3600)
        async let byName: [SearchRow] = get("search-name", ["query": query, "limit": "50"], ttl: 3600)
        let etfs = await etfDirectory()
        let symbolRows = (try? await bySymbol) ?? []
        let nameRows = try await byName

        var seen = Set<String>()
        let upper = query.uppercased()
        return (symbolRows + nameRows)
            .filter { market.exchanges.contains($0.exchange ?? "") && seen.insert($0.symbol).inserted }
            .map { row in
                SecuritySummary(
                    symbol: row.symbol,
                    name: row.name ?? row.symbol,
                    kind: etfs.contains(row.symbol) || Self.looksLikeFund(row.name) ? .etf : .stock,
                    exchange: row.exchange
                )
            }
            .sorted { lhs, rhs in
                let l = Self.searchRank(lhs, upper), r = Self.searchRank(rhs, upper)
                return l == r ? lhs.symbol < rhs.symbol : l < r
            }
    }

    nonisolated func logoURL(for symbol: String) -> URL? {
        guard !symbol.hasPrefix("^") else { return nil }
        return URL(string: "https://images.financialmodelingprep.com/symbol/\(symbol).png")
    }

    // MARK: - ETF directory

    /// Full list of ETF symbols, cached on disk for a week, used to classify search results.
    private func etfDirectory() async -> Set<String> {
        if let etfSymbols { return etfSymbols }
        let file = URL.cachesDirectory.appending(path: "fmp-etf-symbols.json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path()),
           let modified = attrs[.modificationDate] as? Date,
           modified.timeIntervalSinceNow > -7 * 86_400,
           let data = try? Data(contentsOf: file),
           let symbols = try? JSONDecoder().decode(Set<String>.self, from: data) {
            etfSymbols = symbols
            return symbols
        }
        do {
            let rows: [SearchRow] = try await get("etf-list", [:], ttl: 86_400)
            let symbols = Set(rows.map(\.symbol))
            etfSymbols = symbols
            try? JSONEncoder().encode(symbols).write(to: file)
            return symbols
        } catch {
            return []
        }
    }

    // MARK: - Networking

    private var screenerBase: [String: String] {
        [
            "country": "US",
            "isActivelyTrading": "true",
            "exchange": market.exchanges.sorted().joined(separator: ","),
        ]
    }

    private func get<T: Decodable>(_ path: String, _ params: [String: String], ttl: TimeInterval) async throws -> T {
        let data = try await data(path, params, ttl: ttl)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let message = Self.errorMessage(in: data) { throw MarketDataError.restricted(message) }
            throw error
        }
    }

    private func data(_ path: String, _ params: [String: String], ttl: TimeInterval) async throws -> Data {
        guard !apiKey.isEmpty else { throw MarketDataError.missingAPIKey }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        let cacheKey = components.url!.absoluteString
        components.queryItems = items + [URLQueryItem(name: "apikey", value: apiKey)]
        let url = components.url!

        if let entry = cache[cacheKey], entry.expires > .now { return entry.data }
        if let task = inFlight[cacheKey] { return try await task.value }

        let session = self.session
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            switch status {
            case 200..<300: return data
            case 401: throw MarketDataError.invalidAPIKey
            case 402, 403:
                throw MarketDataError.restricted(
                    Self.errorMessage(in: data) ?? "This data isn't included in the current FMP plan."
                )
            default: throw MarketDataError.http(status)
            }
        }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }
        let data = try await task.value
        cache[cacheKey] = (Date.now.addingTimeInterval(ttl), data)
        return data
    }

    // MARK: - Helpers

    nonisolated private static func errorMessage(in data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["Error Message"] as? String {
            return message
        }
        guard let text = String(data: data, encoding: .utf8), !text.hasPrefix("[") else { return nil }
        if text.contains("Restricted Endpoint") || text.contains("Premium") {
            return "This data isn't included in the current FMP plan."
        }
        return nil
    }

    nonisolated private static func looksLikeFund(_ name: String?) -> Bool {
        guard let name = name?.uppercased() else { return false }
        return name.contains(" ETF") || name.hasSuffix("ETF") || name.contains(" ETN")
    }

    nonisolated private static func searchRank(_ item: SecuritySummary, _ query: String) -> Int {
        if item.symbol == query { return 0 }
        if item.symbol.hasPrefix(query) { return 1 }
        if item.name.uppercased().hasPrefix(query) { return 2 }
        return 3
    }

    nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        return calendar
    }()

    nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.us.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.us.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Wire types

nonisolated private struct IntradayBar: Decodable {
    var date: String
    var close: Double
    var volume: Double?
}

nonisolated private struct EODBar: Decodable {
    var date: String
    var price: Double
    var volume: Double?
}

nonisolated private struct RawNews: Decodable {
    var symbol: String?
    var publishedDate: String
    var publisher: String?
    var title: String
    var image: String?
    var site: String?
    var text: String?
    var url: String
}

nonisolated private struct SearchRow: Decodable {
    var symbol: String
    var name: String?
    var exchange: String?

    enum CodingKeys: String, CodingKey { case symbol, name, exchange, companyName }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .companyName)
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange)
    }
}

nonisolated private struct ScreenerRow: Decodable {
    var symbol: String
    var companyName: String?
    var marketCap: Double?
    var sector: String?
    var industry: String?
    var price: Double?
    var volume: Double?
    var exchangeShortName: String?

    func summary(kind: SecurityKind) -> SecuritySummary {
        SecuritySummary(
            symbol: symbol,
            name: companyName ?? symbol,
            kind: kind,
            exchange: exchangeShortName,
            price: price,
            marketCap: marketCap,
            sector: sector,
            industry: industry,
            volume: volume
        )
    }
}
