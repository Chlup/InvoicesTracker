import Foundation

/// What the person did in one month of the year, as far as the levies are concerned.
nonisolated enum MonthActivity: String, Sendable, Codable, Hashable {
    /// No self-employment in the month: it is outside the months in which the activity was carried on.
    case inactive

    /// The self-employment was the main activity (hlavní samostatná výdělečná činnost).
    case main

    /// The self-employment was a secondary activity (vedlejší samostatná výdělečná činnost, § 9 zákona
    /// č. 155/1995 Sb.), for example next to an employment.
    case secondary
}

/// When the housing paid for with the mortgage was acquired, which decides the yearly limit on the deductible interest.
nonisolated enum MortgageCap: String, Sendable, Codable, Hashable {
    /// Acquired before 1 January 2021.
    case before2021

    /// Acquired on 1 January 2021 or later.
    case after2021

    /// The household's yearly limit on deductible mortgage interest, in Kč: 300 000 for housing acquired before
    /// 1 January 2021, otherwise 150 000 (§ 15 odst. 3 and 4 zákona č. 586/1992 Sb.; zákon č. 386/2020 Sb., Čl. IV
    /// body 3 and 4).
    var annualCap: Int64 {
        switch self {
        case .before2021: 300_000
        case .after2021: 150_000
        }
    }
}

/// What the person claims to take off the tax base (nezdanitelné části základu daně), in whole Kč. These are amounts
/// of the whole year: they are not prorated to the as-of day. None of them may be negative.
nonisolated struct Deductions: Sendable, Hashable, Codable {
    /// Mortgage interest paid in the year.
    var mortgageInterestPaid: Int64 = 0

    /// The months of the year in which the interest was paid, 0 to 12. Each of them allows a twelfth of the yearly cap.
    var mortgageMonths = 12

    /// Which yearly cap applies to the interest.
    var mortgageCap = MortgageCap.after2021

    /// Private life insurance premiums paid.
    var lifeInsurance: Int64 = 0

    /// Pension savings: the deductible amount the pension company certifies, not the contributions themselves.
    var pensionSavings: Int64 = 0

    /// Contributions to a long-term investment product (DIP). Deductible from 2024.
    var dip: Int64 = 0

    /// Long-term care insurance premiums. Deductible from 2024.
    var longTermCare: Int64 = 0

    /// Gifts (donations) given in the year.
    var gifts: Int64 = 0
}

/// The advances of the year by month, in whole Kč: twelve entries in each list, index 0 is January, none negative. An
/// advance counts as paid in its own month.
nonisolated struct AdvancePlan: Sendable, Hashable, Codable {
    /// Social insurance advances.
    var social: [Int64]

    /// Health insurance advances.
    var health: [Int64]

    /// Income tax advances.
    var tax: [Int64]

    /// No advance in any month.
    static let empty: AdvancePlan = AdvancePlan(
        social: [Int64](repeating: 0, count: 12),
        health: [Int64](repeating: 0, count: 12),
        tax: [Int64](repeating: 0, count: 12)
    )
}

/// Where a receipt comes from.
nonisolated enum ReceiptSource: Sendable, Hashable {
    /// The payment of the invoice with this id.
    case invoice(Int64)

    /// The income adjustment with this id: a credit note, a refund or money received outside the invoices.
    case adjustment(Int64)

    /// Made up by the caller for a receipt that is not stored, such as a preview.
    case synthetic
}

/// Money received that counts as income: a payment or an income adjustment, in CZK.
nonisolated struct Receipt: Sendable, Hashable {
    /// The day the money was received. It decides the year the income belongs to and whether an as-of day counts it.
    var day: CivilDate

    /// The amount without VAT in haléře, already converted to CZK. An adjustment may be negative.
    var czkNetHalere: Int64

    /// The VAT in haléře. It is tracked on its own and is never income.
    var czkVatHalere: Int64

    var source: ReceiptSource
}

/// Everything the engine needs to know about one year.
nonisolated struct YearInput: Sendable, Hashable {
    var year: Int

    /// The receipts. Those of other years are ignored, so a caller may pass more than the year's.
    var receipts: [Receipt]

    /// The flat-rate expense percentage: 80, 60, 40 or 30.
    var expensePercent: Int

    /// The activity of each month: twelve entries, index 0 is January.
    var months: [MonthActivity]

    /// The months, 1 to 12, in which the health insurance minimum does not apply because for the whole month the person
    /// was, for example, insured by the state or an employee paying from at least the minimum base (§ 3a odst. 3 and 4
    /// zákona č. 592/1992 Sb.).
    var healthExemptMonths: Set<Int>

    var deductions: Deductions

    /// Whether the taxpayer credit (sleva na poplatníka) is claimed.
    var taxpayerCredit: Bool

    var advances: AdvancePlan

    /// The children and the spouse, for the spouse credit and the child tax benefit. None by default.
    var family = FamilyFacts()
}
