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
}

/// The model of the sheet that asks the person to confirm the uniform rates the refresh found: the table is compared
/// with the one of the year before, and the person stores it (Použít), enters the rates by hand (Zadat ručně) or puts
/// the decision off (Později), when the rates stay as they are and come again with the next search.
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

    /// Compares the table with the one stored for the year before, when there is one. A failure is logged and leaves
    /// the table uncompared.
    func load() async {
        guard let database = app.database else { return }
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
