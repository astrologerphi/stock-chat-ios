import Foundation
import SwiftData

/// A security the user starred. Attributes have defaults so the model stays CloudKit-compatible.
@Model
final class StarredSymbol {
    var symbol: String = ""
    var name: String = ""
    var kindRaw: String = SecurityKind.stock.rawValue
    var marketRaw: String = Market.us.rawValue
    var starredAt: Date = Date.now

    init(ref: SecurityRef, starredAt: Date = .now) {
        self.symbol = ref.symbol
        self.name = ref.name
        self.kindRaw = ref.kind.rawValue
        self.marketRaw = ref.market.rawValue
        self.starredAt = starredAt
    }

    var kind: SecurityKind { SecurityKind(rawValue: kindRaw) ?? .stock }
    var market: Market { Market(rawValue: marketRaw) ?? .us }
    var ref: SecurityRef { SecurityRef(symbol: symbol, name: name, kind: kind, market: market) }
}

enum Stars {
    static func isStarred(_ ref: SecurityRef, in stars: [StarredSymbol]) -> Bool {
        stars.contains { $0.symbol == ref.symbol && $0.marketRaw == ref.market.rawValue }
    }

    static func toggle(_ ref: SecurityRef, in context: ModelContext) {
        let symbol = ref.symbol
        let market = ref.market.rawValue
        let descriptor = FetchDescriptor<StarredSymbol>(
            predicate: #Predicate { $0.symbol == symbol && $0.marketRaw == market }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.isEmpty {
            context.insert(StarredSymbol(ref: ref))
        } else {
            existing.forEach(context.delete)
        }
        try? context.save()
    }

    /// Stars a few symbols on first launch of debug builds so the home feed has content.
    static func seedForLocalTestingIfNeeded(in context: ModelContext) {
        #if DEBUG
        let key = "didSeedLocalTestingStars"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let seeds = [
            SecurityRef(symbol: "AAPL", name: "Apple Inc.", kind: .stock),
            SecurityRef(symbol: "NVDA", name: "NVIDIA Corporation", kind: .stock),
            SecurityRef(symbol: "SOXX", name: "iShares Semiconductor ETF", kind: .etf),
        ]
        let existing = (try? context.fetch(FetchDescriptor<StarredSymbol>())) ?? []
        for (offset, ref) in seeds.enumerated() where !isStarred(ref, in: existing) {
            context.insert(StarredSymbol(ref: ref, starredAt: .now.addingTimeInterval(Double(offset))))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
        #endif
    }
}
