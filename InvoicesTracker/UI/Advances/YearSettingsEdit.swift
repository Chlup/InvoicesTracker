import Foundation

/// The three columns of the plan of advances, in the order of the table.
nonisolated enum AdvanceColumn: Int, CaseIterable, Sendable, Hashable {
    /// Sociální pojištění.
    case social = 0

    /// Zdravotní pojištění.
    case health = 1

    /// Daň z příjmů.
    case tax = 2
}

/// A field of the deductions that is typed: an amount in whole Kč, or the number of months of mortgage interest.
nonisolated enum DeductionField: CaseIterable, Sendable, Hashable {
    case mortgageInterest
    case mortgageMonths
    case lifeInsurance
    case pensionSavings
    case dip
    case longTermCare
    case gifts

    /// Whether the field counts months (0 to 12) and not crowns.
    var isMonthCount: Bool {
        self == .mortgageMonths
    }

    /// The value of the field in `deductions`: crowns, or months.
    func amount(in deductions: Deductions) -> Int64 {
        switch self {
        case .mortgageInterest: deductions.mortgageInterestPaid
        case .mortgageMonths: Int64(deductions.mortgageMonths)
        case .lifeInsurance: deductions.lifeInsurance
        case .pensionSavings: deductions.pensionSavings
        case .dip: deductions.dip
        case .longTermCare: deductions.longTermCare
        case .gifts: deductions.gifts
        }
    }

    /// Sets the field in `deductions` to `value`: crowns, or months.
    func set(_ value: Int64, in deductions: inout Deductions) {
        switch self {
        case .mortgageInterest: deductions.mortgageInterestPaid = value
        case .mortgageMonths: deductions.mortgageMonths = Int(clamping: value)
        case .lifeInsurance: deductions.lifeInsurance = value
        case .pensionSavings: deductions.pensionSavings = value
        case .dip: deductions.dip = value
        case .longTermCare: deductions.longTermCare = value
        case .gifts: deductions.gifts = value
        }
    }

    /// What the text typed in the field stands for: crowns, or the months of interest. Nothing at all is zero. Nil for
    /// a text that is neither.
    func value(of text: String) -> Int64? {
        if isMonthCount {
            return Self.months(in: text)
        }
        switch TypedKc(text) {
        case .blank: return 0
        case .value(let kc): return kc
        case .refused: return nil
        }
    }

    /// The months of interest in `text`: 0 to 12, or 0 for nothing; nil for anything else.
    private static func months(in text: String) -> Int64? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 0
        }
        guard let number = AmountParser.decimal(text, maxFractionDigits: 0), (0...12).contains(number) else {
            return nil
        }
        return Int64(NSDecimalNumber(decimal: number).intValue)
    }
}

/// One change of the settings of a year that the screen of advances and deductions makes: it sets one field to a value
/// and touches nothing else. The screen saves the changes it has made with the stored settings read in the same
/// transaction (`Database.updateYearSettings`), so that what another part of the app changed meanwhile is kept.
///
/// An edit sets a value, it does not add to one, so applying it twice or after another edit of the same field is
/// harmless: the last one wins. Months are 1 to 12; an edit of a month outside the year changes nothing.
nonisolated enum YearSettingsEdit: Sendable, Hashable {
    /// The advance of `column` for `month`, in whole Kč.
    case advance(AdvanceColumn, month: Int, kc: Int64)

    /// Whether the activity of `month` was a secondary one.
    case secondary(month: Int, on: Bool)

    case expensePercent(Int)
    case reducedSocialBase(Bool)
    case taxpayerCredit(Bool)

    /// A typed deduction field: crowns, or months of mortgage interest.
    case deduction(DeductionField, value: Int64)
    case mortgageCap(MortgageCap)

    /// The spouse of the year, nil for none: what the card of the spouse chooses.
    case spouse(SpouseYear?)

    /// The spouse's own income for the year, in whole Kč: the typed field of the card. A year without a spouse has no
    /// income to set.
    case spouseIncome(Int64)

    /// What an edit sets, without the value: an edit replaces an earlier one that has the same target.
    enum Target: Sendable, Hashable {
        case advance(AdvanceColumn, month: Int)
        case secondary(month: Int)
        case expensePercent
        case reducedSocialBase
        case taxpayerCredit
        case deduction(DeductionField)
        case mortgageCap
        case spouse
        case spouseIncome
    }

    var target: Target {
        switch self {
        case .advance(let column, let month, _): .advance(column, month: month)
        case .secondary(let month, _): .secondary(month: month)
        case .expensePercent: .expensePercent
        case .reducedSocialBase: .reducedSocialBase
        case .taxpayerCredit: .taxpayerCredit
        case .deduction(let field, _): .deduction(field)
        case .mortgageCap: .mortgageCap
        case .spouse: .spouse
        case .spouseIncome: .spouseIncome
        }
    }

    /// Sets the field in `settings`.
    func apply(to settings: inout YearSettings) {
        switch self {
        case .advance(let column, let month, let kc):
            guard (1...12).contains(month) else { return }
            switch column {
            case .social: settings.advances.social[month - 1] = kc
            case .health: settings.advances.health[month - 1] = kc
            case .tax: settings.advances.tax[month - 1] = kc
            }
        case .secondary(let month, let on):
            guard (1...12).contains(month) else { return }
            if on {
                settings.secondaryMonths.insert(month)
            } else {
                settings.secondaryMonths.remove(month)
            }
        case .expensePercent(let percent):
            settings.expensePercent = percent
        case .reducedSocialBase(let on):
            settings.reducedSocialBase = on
        case .taxpayerCredit(let on):
            settings.taxpayerCredit = on
        case .deduction(let field, let value):
            field.set(value, in: &settings.deductions)
        case .mortgageCap(let cap):
            settings.deductions.mortgageCap = cap
        case .spouse(let spouse):
            settings.spouse = spouse
        case .spouseIncome(let kc):
            settings.spouse?.ownIncomeKc = kc
        }
    }
}
