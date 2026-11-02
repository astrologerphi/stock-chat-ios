import Foundation

/// A stock market the app can display. Only the US is supported today; new markets
/// are added by extending this enum and registering a `MarketDataProvider` for them.
nonisolated enum Market: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case us = "US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: "United States"
        }
    }

    var flag: String {
        switch self {
        case .us: "🇺🇸"
        }
    }

    var currencyCode: String {
        switch self {
        case .us: "USD"
        }
    }

    var timeZone: TimeZone {
        switch self {
        case .us: TimeZone(identifier: "America/New_York")!
        }
    }

    /// Exchange short codes (as reported by the data provider) that belong to this market.
    var exchanges: Set<String> {
        switch self {
        case .us: ["NASDAQ", "NYSE", "AMEX", "CBOE"]
        }
    }

    /// Benchmark indices shown on the home screen.
    var benchmarkIndices: [String] {
        switch self {
        case .us: ["^GSPC", "^IXIC", "^DJI", "^RUT", "^VIX"]
        }
    }

    /// Regular trading session state (ignores exchange holidays).
    func session(at date: Date = .now) -> MarketSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekday = calendar.component(.weekday, from: date)
        guard (2...6).contains(weekday) else { return .closed }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        switch minutes {
        case 240..<570: return .preMarket
        case 570..<960: return .open
        case 960..<1200: return .afterHours
        default: return .closed
        }
    }
}

nonisolated enum MarketSession: Sendable {
    case preMarket, open, afterHours, closed

    var title: String {
        switch self {
        case .preMarket: "Pre-Market"
        case .open: "Market Open"
        case .afterHours: "After Hours"
        case .closed: "Market Closed"
        }
    }

    var isLive: Bool { self == .open }
}
