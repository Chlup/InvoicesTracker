import Foundation

/// Why the levies of a year were not computed.
nonisolated enum ComputationError: Error, Equatable {
    /// What is stored for the year has a value that no form saves and the computation does not take: the database was
    /// changed outside the app, or it is damaged. The number is the year.
    case invalidYear(Int)
}

/// The computation of the levies of a year from what the data holds.
extension AppModel {
    /// What the computation of `year` needs: its receipts, its settings and its family, with the settings themselves
    /// for what the input does not hold (the conversion of income). The family is the one of `Database.family(year:)`,
    /// its children in its order and its spouse. Throws `VaultError.locked` while the data is locked.
    ///
    /// In the current year the receipts dated after the real today are left out: the reporting cutoff reaches the end
    /// of the month, but a payment or an income adjustment that is dated later is not income yet, whatever day the
    /// levies are worked out as of. The prediction reads the year without this (`predictionOutcome(year:)`).
    func yearInput(for year: Int) async throws -> (input: YearInput, settings: YearSettings) {
        guard let database else { throw VaultError.locked }
        var read = try await Self.yearInput(for: year, in: database)
        if year == today.year {
            let today = self.today
            read.input.receipts.removeAll { $0.day > today }
        }
        return read
    }

    /// What the computation of `year` needs, read from `database` as `yearInput(for:)` reads it: it runs on the actor
    /// of the caller and needs none of the model, so work away from the main actor can read a year too.
    nonisolated static func yearInput(
        for year: Int, in database: Database
    ) async throws -> (input: YearInput, settings: YearSettings) {
        let settings = try await database.yearSettings(year)
        let receipts = try await database.receipts(year: year)
        let family = try await database.family(year: year)
        return (yearInput(settings, receipts: receipts, family: FamilyFacts(family)), settings)
    }

    /// The levies of the selected year as of the day its money is received by (`receivedThrough`). A year without
    /// rules of its own is computed with the rules of the nearest year that has them, as an estimate. Throws
    /// `ComputationError.invalidYear` for stored values the computation does not take, and `VaultError.locked` while
    /// the data is locked.
    func computeSelectedYear() async throws -> TaxResult {
        let shown = asOf
        let day = receivedThrough
        let input = try await yearInput(for: shown.year).input
        return try Self.compute(input, asOf: day)
    }

    /// The input of the computation of a year with `settings`, `receipts` and `family`. The family is taken whole, its
    /// children as `Database.family(year:)` lists them together with its spouse; the spouse of `settings` is not read,
    /// so a caller can give the spouse being edited. A year without a family is given an empty one (`FamilyFacts()`).
    nonisolated static func yearInput(
        _ settings: YearSettings, receipts: [Receipt], family: FamilyFacts
    ) -> YearInput {
        YearInput(
            year: settings.year, receipts: receipts, expensePercent: settings.expensePercent,
            months: settings.monthActivities(), healthExemptMonths: settings.healthExemptMonths,
            deductions: settings.deductions, taxpayerCredit: settings.taxpayerCredit, advances: settings.advances,
            family: family)
    }

    /// What `receipt` adds to the levies of its year on its own day, by authority: the levies with the receipts of the
    /// year up to that day, with and without it. The year is read as it is stored, with its settings, and the minimum
    /// bases count its active months through the month of the receipt. A receipt of an invoice replaces the receipt
    /// stored for the same invoice, so a payment that is edited is never counted twice; a receipt of another source is
    /// added to the stored ones. Throws `ComputationError.invalidYear` for stored values the computation does not
    /// take, and `VaultError.locked` while the data is locked.
    func effect(of receipt: Receipt) async throws -> ReceiptEffect {
        let input = try await yearInput(for: receipt.day.year).input
        try Self.validate(input)
        return TaxEngine.effect(of: receipt, in: input)
    }

    /// `TaxEngine.compute`, once it is checked that the engine takes `input` as of `asOf`: an as-of day in the year and
    /// what `validate(_:)` checks. Throws `ComputationError.invalidYear` otherwise, where the engine would stop the app.
    nonisolated static func compute(_ input: YearInput, asOf: CivilDate) throws -> TaxResult {
        guard asOf.year == input.year else {
            throw ComputationError.invalidYear(input.year)
        }
        try validate(input)
        return TaxEngine.compute(input, asOf: asOf)
    }

    /// Checks that the engine takes `input`: a flat-rate percentage of 80, 60, 40 or 30, twelve months of activity and
    /// of each advance, months 1 to 12, no negative advance or claim, 0 to 12 months of mortgage interest, and a family
    /// whose ranges of months are ranges, whose orders are 1 or more and whose spouse's income is not negative. Throws
    /// `ComputationError.invalidYear` otherwise, where the engine would stop the app.
    nonisolated static func validate(_ input: YearInput) throws {
        let claims = input.deductions
        let amounts = [
            claims.mortgageInterestPaid, claims.lifeInsurance, claims.pensionSavings, claims.dip, claims.longTermCare,
            claims.gifts,
        ]
        let plans = [input.advances.social, input.advances.health, input.advances.tax]
        guard
            TaxRules.expenseCap(percent: input.expensePercent) != nil,
            input.months.count == 12,
            input.healthExemptMonths.allSatisfy({ (1...12).contains($0) }),
            plans.allSatisfy({ $0.count == 12 && $0.allSatisfy { $0 >= 0 } }),
            (0...12).contains(claims.mortgageMonths),
            amounts.allSatisfy({ $0 >= 0 }),
            input.family.isValid
        else {
            throw ComputationError.invalidYear(input.year)
        }
    }
}

nonisolated extension ChildFacts {
    /// What the engine takes of `member`: its name as the label, its date of birth and what its year says about it.
    init(_ member: FamilyChild) {
        self.init(
            label: member.child.name, birthDate: member.child.birthDate, household: member.year.household,
            claimant: member.year.claimant, order: member.year.order, ztpp: member.year.ztpp,
            studies: member.year.studies)
    }
}

nonisolated extension FamilyFacts {
    /// What the engine takes of `family`: its children in its order, and its spouse.
    init(_ family: FamilyYear) {
        self.init(children: family.children.map { ChildFacts($0) }, spouse: family.spouse)
    }
}
