//
//  Stock_ChatTests.swift
//  Stock ChatTests
//

import Foundation
import Testing
@testable import Stock_Chat

struct FormatterTests {
    @Test func missingValuesShowDash() {
        #expect(Fmt.price(nil) == "—")
        #expect(Fmt.percent(nil) == "—")
        #expect(Fmt.compact(0) == "—")
        #expect(Fmt.signed(nil) == "—")
    }

    @Test func percentIsSignedForGains() {
        #expect(Fmt.percent(1.5).hasPrefix("+"))
        #expect(!Fmt.percent(-1.5).hasPrefix("+"))
        #expect(!Fmt.percent(1.5, signed: false).hasPrefix("+"))
    }

    @Test func signedNumbers() {
        #expect(Fmt.signed(2).hasPrefix("+"))
        #expect(Fmt.signed(-2).hasPrefix("-"))
    }
}

struct MarketSessionTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // 2026-11-02 is a Monday; 2026-11-01 a Sunday.
    @Test func weekdaySessions() {
        #expect(Market.us.session(at: date(2026, 11, 2, 3, 59)) == .closed)
        #expect(Market.us.session(at: date(2026, 11, 2, 4, 0)) == .preMarket)
        #expect(Market.us.session(at: date(2026, 11, 2, 9, 30)) == .open)
        #expect(Market.us.session(at: date(2026, 11, 2, 15, 59)) == .open)
        #expect(Market.us.session(at: date(2026, 11, 2, 16, 0)) == .afterHours)
        #expect(Market.us.session(at: date(2026, 11, 2, 20, 0)) == .closed)
    }

    @Test func weekendIsClosed() {
        #expect(Market.us.session(at: date(2026, 11, 1, 12, 0)) == .closed)
    }
}

struct DecodingTests {
    @Test func priceChangeDecodesFMPKeys() throws {
        let json = #"[{"symbol":"AAPL","1D":1.2,"5D":-0.5,"1M":3,"3M":4,"6M":5,"ytd":6,"1Y":7,"5Y":8}]"#
        let changes = try JSONDecoder().decode([PriceChange].self, from: Data(json.utf8))
        let aapl = try #require(changes.first)
        #expect(aapl.symbol == "AAPL")
        #expect(aapl.oneDay == 1.2)
        #expect(aapl.fiveYear == 8)
        #expect(aapl.entries.map(\.label) == ["1D", "5D", "1M", "3M", "6M", "YTD", "1Y", "5Y"])
    }
}
