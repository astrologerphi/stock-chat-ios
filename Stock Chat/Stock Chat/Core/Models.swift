import Foundation

nonisolated enum SecurityKind: String, Codable, Hashable, Sendable, CaseIterable {
    case stock
    case etf
    case index

    var title: String {
        switch self {
        case .stock: "Stock"
        case .etf: "ETF"
        case .index: "Index"
        }
    }
}

/// A lightweight reference used for navigation and starring.
nonisolated struct SecurityRef: Hashable, Codable, Sendable, Identifiable {
    var symbol: String
    var name: String
    var kind: SecurityKind
    var market: Market = .us

    var id: String { "\(market.rawValue):\(symbol)" }
}

/// A row in a list / search result.
nonisolated struct SecuritySummary: Hashable, Sendable, Identifiable {
    var symbol: String
    var name: String
    var kind: SecurityKind
    var exchange: String?
    var price: Double?
    var marketCap: Double?
    var sector: String?
    var industry: String?
    var volume: Double?
    var market: Market = .us

    var id: String { "\(market.rawValue):\(symbol)" }

    var ref: SecurityRef { SecurityRef(symbol: symbol, name: name, kind: kind, market: market) }
}

nonisolated struct Quote: Decodable, Hashable, Sendable {
    var symbol: String
    var name: String?
    var price: Double
    var changePercentage: Double?
    var change: Double?
    var volume: Double?
    var dayLow: Double?
    var dayHigh: Double?
    var yearHigh: Double?
    var yearLow: Double?
    var marketCap: Double?
    var priceAvg50: Double?
    var priceAvg200: Double?
    var exchange: String?
    var open: Double?
    var previousClose: Double?
    var timestamp: TimeInterval?

    var date: Date? { timestamp.map { Date(timeIntervalSince1970: $0) } }
    var isUp: Bool { (change ?? 0) >= 0 }
}

nonisolated struct CompanyProfile: Decodable, Hashable, Sendable {
    var symbol: String
    var companyName: String?
    var currency: String?
    var exchange: String?
    var exchangeFullName: String?
    var industry: String?
    var sector: String?
    var website: String?
    var description: String?
    var ceo: String?
    var country: String?
    var fullTimeEmployees: String?
    var city: String?
    var state: String?
    var image: String?
    var ipoDate: String?
    var beta: Double?
    var lastDividend: Double?
    var averageVolume: Double?
    var marketCap: Double?
    var range: String?
    var isEtf: Bool?
    var isFund: Bool?
}

nonisolated struct ETFInfo: Decodable, Hashable, Sendable {
    var symbol: String
    var name: String?
    var description: String?
    var assetClass: String?
    var domicile: String?
    var website: String?
    var etfCompany: String?
    var expenseRatio: Double?
    var assetsUnderManagement: Double?
    var avgVolume: Double?
    var inceptionDate: String?
    var nav: Double?
    var navCurrency: String?
    var holdingsCount: Int?
    var sectorsList: [SectorExposure]?

    nonisolated struct SectorExposure: Decodable, Hashable, Sendable {
        var industry: String
        var exposure: Double
    }
}

nonisolated struct RatiosTTM: Decodable, Hashable, Sendable {
    var priceToEarningsRatioTTM: Double?
    var priceToBookRatioTTM: Double?
    var dividendYieldTTM: Double?
    var netProfitMarginTTM: Double?
    var grossProfitMarginTTM: Double?
}

nonisolated struct PriceChange: Decodable, Hashable, Sendable {
    var symbol: String
    var oneDay: Double?
    var fiveDay: Double?
    var oneMonth: Double?
    var threeMonth: Double?
    var sixMonth: Double?
    var ytd: Double?
    var oneYear: Double?
    var fiveYear: Double?

    enum CodingKeys: String, CodingKey {
        case symbol
        case oneDay = "1D"
        case fiveDay = "5D"
        case oneMonth = "1M"
        case threeMonth = "3M"
        case sixMonth = "6M"
        case ytd
        case oneYear = "1Y"
        case fiveYear = "5Y"
    }

    var entries: [(label: String, value: Double?)] {
        [("1D", oneDay), ("5D", fiveDay), ("1M", oneMonth), ("3M", threeMonth),
         ("6M", sixMonth), ("YTD", ytd), ("1Y", oneYear), ("5Y", fiveYear)]
    }
}

nonisolated struct PricePoint: Hashable, Sendable, Identifiable {
    var date: Date
    var price: Double
    var volume: Double?

    var id: Date { date }
}

nonisolated struct NewsArticle: Hashable, Sendable, Identifiable {
    var symbol: String?
    var publishedDate: Date
    var publisher: String?
    var title: String
    var image: URL?
    var site: String?
    var text: String?
    var url: URL

    var id: URL { url }
}

nonisolated enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1D"
    case week = "5D"
    case month = "1M"
    case sixMonths = "6M"
    case year = "1Y"
    case fiveYears = "5Y"

    var id: String { rawValue }

    var isIntraday: Bool { self == .day || self == .week }
}
