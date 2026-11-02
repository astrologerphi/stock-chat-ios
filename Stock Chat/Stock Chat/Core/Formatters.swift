import Foundation
import SwiftUI

nonisolated enum Fmt {
    static func price(_ value: Double?, currency: String = "USD") -> String {
        guard let value else { return "—" }
        let digits = abs(value) < 1 ? 4 : 2
        return value.formatted(.currency(code: currency).precision(.fractionLength(digits)))
    }

    static func number(_ value: Double?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func compact(_ value: Double?) -> String {
        guard let value, value != 0 else { return "—" }
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
    }

    static func compactCurrency(_ value: Double?, currency: String = "USD") -> String {
        guard let value, value != 0 else { return "—" }
        return value.formatted(.currency(code: currency).notation(.compactName).precision(.significantDigits(3)))
    }

    static func percent(_ value: Double?, signed: Bool = true) -> String {
        guard let value else { return "—" }
        let text = (value / 100).formatted(.percent.precision(.fractionLength(2)))
        return signed && value > 0 ? "+" + text : text
    }

    static func signed(_ value: Double?) -> String {
        guard let value else { return "—" }
        let text = value.formatted(.number.precision(.fractionLength(2)))
        return value > 0 ? "+" + text : text
    }
}

extension Color {
    static let gain = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let loss = Color(red: 1.00, green: 0.27, blue: 0.33)

    static func trend(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return value >= 0 ? .gain : .loss
    }
}
