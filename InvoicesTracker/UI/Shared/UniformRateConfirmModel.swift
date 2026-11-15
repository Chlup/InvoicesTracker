import Foundation
import Observation

/// The words of the sheet that asks the person to confirm the uniform rates the app found.
nonisolated enum UniformRateConfirmText {
    /// What the table of a year has more and less than the table of the year before: the currencies that are gone from
    /// it, which the reader of the PDF cannot tell from a row it did not see, and the ones that are new.
    struct Differences: Equatable, Sendable {
        /// What the sheet says of them, one line each.
        var lines: [String] = []

        /// Whether a currency of the year before is missing, which the person is asked to check before they use the
        /// table.
        var warns = false
    }

    /// "Vyšel jednotný kurz za rok 2025 (pokyn GFŘ-D-75): 1 USD = 21,84 Kč, 1 EUR = 24,66 Kč": what was found, with the
    /// rates of dollars and euros that the tax of a person who invoices in them rests on. A table without one of them
    /// leaves it out.
    static func headline(for finding: GFRFinding) -> String {
        var text = "Vyšel jednotný kurz za rok \(finding.year) (pokyn \(finding.instruction))"
        let rates = [CurrencyCode.usd, CurrencyCode.eur].compactMap { currency in
            finding.rates.first { $0.currency == currency }.map { entry in
                BuilderText.uniformRate(
                    UniformRate(
                        year: finding.year, currency: entry.currency, amount: entry.amount, rate: entry.rate,
                        instruction: finding.instruction, sourceURL: nil, confirmedAt: nil, origin: .fetched))
            }
        }
        if !rates.isEmpty {
            text += ": " + rates.joined(separator: ", ")
        }
        return text
    }

    /// "Tabulka má 31 měn.": how many currencies the table has, all of which are stored.
    static func currencyCount(_ count: Int) -> String {
        let currencies = CzechCount.counted(
            count, one: "měnu", few: "měny", many: "měn", separator: CzechFormat.noBreakSpace)
        return "Tabulka má " + currencies + "."
    }

    /// What `found` has more and less than `previous`, the currencies of the table of `previousYear`.
    static func differences(
        found: Set<CurrencyCode>, previous: Set<CurrencyCode>, previousYear: Int
    ) -> Differences {
        let missing = previous.subtracting(found).map(\.code).sorted()
        let added = found.subtracting(previous).map(\.code).sorted()
        var differences = Differences()
        if !missing.isEmpty {
            differences.lines.append(
                "Oproti roku \(previousYear) v tabulce chybí: \(missing.joined(separator: ", ")). Zkontrolujte ji ve"
                    + " Finančním zpravodaji, než ji použijete.")
            differences.warns = true
        }
        if !added.isEmpty {
            differences.lines.append("Nově je v tabulce: \(added.joined(separator: ", ")).")
        }
        return differences
    }

    // MARK: The rate the app computed

    /// "1 USD 21,32 → 21,33 Kč": the rates of dollars and euros of `finding` that differ from `computed`, the rates of
    /// its year that the app computed, each from the computed one to the official one, for one unit, dollars first.
    /// Empty when they agree, and nil when they have no currency of the two in common.
    static func changes(from computed: [UniformRate], to finding: GFRFinding) -> [String]? {
        var compared = false
        var changes: [String] = []
        for currency in UniformRate.currenciesEnteredByHand {
            guard let preliminary = computed.first(where: { $0.currency == currency }),
                let official = finding.rates.first(where: { $0.currency == currency })
            else {
                continue
            }
            compared = true
            let before = preliminary.rate / Decimal(preliminary.amount)
            let after = official.rate / Decimal(official.amount)
            guard before != after else { continue }
            changes.append(
                "1\u{00A0}\(currency.code) \(CzechFormat.rate(before, fractionDigits: 2)) → "
                    + CzechFormat.rate(after, fractionDigits: 2) + "\u{00A0}Kč")
        }
        return compared ? changes : nil
    }

    /// What the sheet says of `computed`, the rates of the year of `finding` that the app computed and that the table
    /// replaces: "Shoduje se s předběžným kurzem, který aplikace spočítala.", or "Od předběžného kurzu se liší: 1 USD
    /// 21,32 → 21,33 Kč." (`changes(from:to:)`), followed by "Platby roku 2026 se přepočtou." for a year set to the
    /// uniform rate (`convertsAtIt`), whose payments the table converts; a year set to the daily ČNB rates keeps them.
    /// Nil when the year has no computed rate of dollars or euros that the table has.
    static func computedComparison(
        of finding: GFRFinding, with computed: [UniformRate], convertsAtIt: Bool
    ) -> String? {
        guard let changes = changes(from: computed, to: finding) else { return nil }
        guard !changes.isEmpty else { return "Shoduje se s předběžným kurzem, který aplikace spočítala." }
        return "Od předběžného kurzu se liší: " + changes.joined(separator: ", ") + "."
            + (convertsAtIt ? " Platby roku \(finding.year) se přepočtou." : "")
    }

    /// The green banner once `finding` is confirmed in place of `computed`, the rates of its year that the app had
    /// computed: "Jednotný kurz 2026 z pokynu GFŘ-D-75 je potvrzený. Shoduje se s předběžným kurzem, částky se
    /// nezměnily.", or "… Od předběžného se liší (1 USD 21,32 → 21,33 Kč), platby roku 2026 jsou jím přepočtené."
    /// (`changes(from:to:)`) for a year that converts at the uniform rate (`convertsAtIt`); for a year on the daily ČNB
    /// rates the sentence ends with the differences, as its payments stay. Nil when the year had no computed rate of
    /// dollars or euros that the table has.
    static func confirmedBanner(
        for finding: GFRFinding, replacing computed: [UniformRate], convertsAtIt: Bool
    ) -> String? {
        guard let changes = changes(from: computed, to: finding) else { return nil }
        let confirmed = "Jednotný kurz \(finding.year) z pokynu \(finding.instruction) je potvrzený. "
        guard !changes.isEmpty else { return confirmed + "Shoduje se s předběžným kurzem, částky se nezměnily." }
        return confirmed + "Od předběžného se liší (" + changes.joined(separator: ", ") + ")"
            + (convertsAtIt ? ", platby roku \(finding.year) jsou jím přepočtené." : ".")
    }
}

/// The model of the sheet that asks the person to confirm the uniform rates the refresh found: the table is compared
/// with the one of the year before, and with the rates of its year that the app computed, which it replaces, and the
/// person stores it (Použít), enters the rates by hand (Zadat ručně) or puts the decision off (Později), when the rates
/// stay as they are and come again with the next search.
@MainActor
@Observable
final class UniformRateConfirmModel {
    /// What the sheet says when the rates could not be stored.
    nonisolated static let saveFailureText = "Kurz se nepodařilo uložit."

    /// What the sheet says when the year has rates stored already: typed by hand, say, while the sheet was open.
    nonisolated static func alreadyStoredText(year: Int) -> String {
        "Jednotný kurz za rok \(year) už je uložený."
    }

    let finding: GFRFinding

    /// What the table has more and less than the one of the year before, one line each. Empty while the tables are not
    /// compared, and when they do not differ.
    private(set) var differenceLines: [String] = []

    /// Whether a currency of the year before is missing from the table.
    private(set) var warnsOfMissingCurrencies = false

    /// What the sheet says of the rates of the year that the app computed from the ČNB month-end rates, which the
    /// table replaces: that they agree, or how they differ
    /// (`UniformRateConfirmText.computedComparison(of:with:convertsAtIt:)`). Nil while the year has none, and until
    /// they are read.
    private(set) var computedComparison: String?

    /// Why the rates are not stored, or that their payments are not converted, in Czech; nil otherwise. A failure is
    /// said to VoiceOver as it comes, also one that is the same as the one before: it answers what the person did. One
    /// that comes while the app is locked after inactivity is said once it is unlocked (`announceWhenUnlocked(_:)`).
    private(set) var failure: String? {
        didSet {
            if let failure {
                app.announceWhenUnlocked(failure)
            }
        }
    }

    /// Whether the rates are being stored.
    private(set) var isWorking = false

    /// Whether nothing is left to choose, and the sheet only says why: the rates are stored, but their payments could
    /// not be converted, or the year has rates stored already, which a table that was found does not replace.
    private(set) var isSettled = false

    private let app: AppModel

    init(app: AppModel, finding: GFRFinding) {
        self.app = app
        self.finding = finding
    }

    /// The sentence the sheet is about.
    var headline: String {
        UniformRateConfirmText.headline(for: finding)
    }

    /// How many currencies the table has.
    var tableNote: String {
        UniformRateConfirmText.currencyCount(finding.rates.count)
    }

    /// Compares the table with the one stored for the year before, when there is one, and with the rates of its year
    /// that the app computed, when there are any (`compareWithComputedRates(in:)`). A failure is logged and leaves that
    /// comparison out.
    func load() async {
        guard let database = app.database else { return }
        await compareWithTheYearBefore(in: database)
        await compareWithComputedRates(in: database)
    }

    /// Compares the table with the one stored in `database` for the year before, when there is one. A failure is
    /// logged and leaves the table uncompared.
    private func compareWithTheYearBefore(in database: Database) async {
        do {
            let previous = try await database.uniformRates(year: finding.year - 1)
            guard !previous.isEmpty else { return }
            let differences = UniformRateConfirmText.differences(
                found: Set(finding.rates.map(\.currency)), previous: Set(previous.map(\.currency)),
                previousYear: finding.year - 1)
            differenceLines = differences.lines
            warnsOfMissingCurrencies = differences.warns
        } catch {
            AppModel.log("Comparing the uniform rates with the year before", failedWith: error)
        }
    }

    /// Compares the table with the rates of its year that the app computed, stored in `database`, when there are any,
    /// and says whether the payments of the year are converted at it: they are for a year set to the uniform rate. A
    /// failure is logged and leaves the rates uncompared.
    private func compareWithComputedRates(in database: Database) async {
        do {
            let computed = try await database.uniformRates(year: finding.year).filter(\.isComputed)
            guard !computed.isEmpty else { return }
            let chosen = try await database.yearSettings(finding.year).incomeFXMethod
            computedComparison = UniformRateConfirmText.computedComparison(
                of: finding, with: computed, convertsAtIt: chosen == .uniform)
        } catch {
            AppModel.log("Comparing the uniform rates with the ones the app computed", failedWith: error)
        }
    }

    /// Použít: stores the table (`AppModel.confirmUniformRate(_:)`) and closes the sheet. When that cannot be done, the
    /// sheet stays and says why (`failure`); when the rates are stored but their payments are not converted, it says
    /// so and only closes.
    func use() async {
        guard !isWorking, !isSettled else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await app.confirmUniformRate(finding)
            app.uniformRateOffer = nil
        } catch UniformRateConfirmationError.paymentsNotConverted(let year) {
            failure = FXMethodChange.paymentsNotConvertedText(year: year)
            isSettled = true
        } catch UniformRateConfirmationError.alreadyStored(let year) {
            failure = Self.alreadyStoredText(year: year)
            isSettled = true
        } catch UniformRateConfirmationError.emptyTable {
            failure = Self.saveFailureText
        } catch let error as VaultError {
            failure = WelcomeTexts.vaultErrorText(error)
        } catch {
            AppModel.log("Storing the uniform rates", failedWith: error)
            failure = Self.saveFailureText
        }
    }

    /// Zadat ručně: closes the sheet and shows the form of the rates in Nastavení › Rok for the year of the table.
    func enterManually() {
        app.enterUniformRateManually(year: finding.year)
    }

    /// Později, and Zavřít: closes the sheet. A finding that is not stored waits for the person, and the sheet comes
    /// again when the refresh finds it anew.
    func later() {
        app.uniformRateOffer = nil
    }
}
