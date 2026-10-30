import Foundation

/// How VAT is charged on an invoice. The database stores the raw value, so a case is never renamed.
nonisolated enum VatMode: String, CaseIterable, Sendable, Hashable, Codable {
    /// Supply in the Czech Republic at 21 %.
    case domestic21

    /// Supply in the Czech Republic at 12 %.
    case domestic12

    /// Supply outside the country (§ 9 odst. 1 zákona o DPH): no Czech VAT is charged.
    case outsideCountry

    /// Supply to a customer in another EU country who accounts for the VAT (přenesená daňová povinnost).
    case euReverseCharge

    /// No VAT, for example because the supplier is not a VAT payer.
    case none

    /// The VAT rate in percent: 21 or 12 for a domestic supply, otherwise 0.
    var ratePercent: Int {
        switch self {
        case .domestic21: 21
        case .domestic12: 12
        case .outsideCountry, .euReverseCharge, .none: 0
        }
    }

    /// The name shown in the app.
    var label: String {
        switch self {
        case .domestic21: "Tuzemsko 21 %"
        case .domestic12: "Tuzemsko 12 %"
        case .outsideCountry: "Mimo tuzemsko – § 9 odst. 1 (bez DPH)"
        case .euReverseCharge: "Přenesená povinnost – EU"
        case .none: "Bez DPH"
        }
    }
}
