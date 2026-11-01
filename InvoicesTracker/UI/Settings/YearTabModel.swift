import Foundation
import Observation

/// The model of Nastavení › Rok Y, the settings of the selected year: the profile (the conversion of the income in
/// other currencies), the months of the activity and those without the health minimum, the uniform rate of the year
/// with the form to enter it by hand and the question before a rate entered by hand is removed, the rules the year is
/// computed with, and the income adjustments.
///
/// - The tab loads again whenever what the data depends on changes (`AppModel.reloadKey`), for the year selected then.
/// - Every choice is saved at once, through the year's one-transaction update (`Database.updateYearSettings`), and the
///   app is told (`didWrite()`); a value the computation would refuse is never saved. The conversion of the income is
///   chosen through the app (`AppModel.setFXMethod(_:year:)`), which converts the year's payments again, and a uniform
///   rate entered by hand, edited or removed has the app convert them too, by the method the year uses then
///   (`AppModel.convertPaymentsAfterUniformRatesChanged(year:)`). The uniform rate can be chosen only while the year
///   has it (`YearFXState`).
/// - The form of the uniform rate and the one of an adjustment are saved by their buttons: what is typed is read then,
///   with `AmountParser`, and a text that is not a rate or an amount is refused with a message.
/// - What the card says of a year without an official rate follows the search of the app for it (`UniformRateSearch`)
///   on the day of the app, as the toolbar does (`UniformAvailability`), so that the two never disagree.
@MainActor
@Observable
final class YearTabModel {
    /// A row of the card Pravidla výpočtu.
    struct RuleRow: Hashable, Sendable {
        var label: String
        var value: String
    }

    // MARK: Texts

    nonisolated static let loadFailureText = "Nastavení roku se nepodařilo načíst."
    nonisolated static let saveFailureText = "Změnu se nepodařilo uložit."
    nonisolated static let noRateText = "Zadejte aspoň jeden kurz, například 21,84."
    nonisolated static let rateFormatText = "Zadejte kurz ve tvaru 21,84."
    nonisolated static let noAmountText = "Zadejte částku v Kč – kladnou, když příjem přibyl, zápornou, když ubyl."
    nonisolated static let amountFormatText = "Zadejte částku ve tvaru 13 340 nebo 13 340,50."

    /// The example in the field of the amount of a new adjustment, before anything is typed: a negative amount, with
    /// the minus sign and a no-break space in the thousands.
    nonisolated static let adjustmentAmountPrompt = "\u{2212}5\u{00A0}200"

    /// What the card of the rules says under them.
    nonisolated static let rulesNote =
        "Každý rok má vlastní verzi pravidel, takže starší výpočty se dají zopakovat se stejnými vstupy."

    // MARK: State

    /// The settings of the year as stored, with a choice that is being saved on top of it. Nil until the first load.
    private(set) var settings: YearSettings?

    /// The uniform rates stored for the year, of every currency.
    private(set) var uniformRates: [UniformRate] = []

    /// How the year converts its income in other currencies: the method chosen, the one it uses and whether it has
    /// the uniform rate. Nil until the first load.
    private(set) var fxState: YearFXState?

    /// The page or the PDF of the Finanční zpravodaj that the search for the year's uniform rate could not read, while
    /// the year has no rate. The form to enter it by hand is open then.
    private(set) var unreadablePage: URL?

    /// The income adjustments of the year, by date.
    private(set) var adjustments: [IncomeAdjustment] = []

    /// What the tab says in place of its content when the last load failed, and next to the profile when the last
    /// choice could not be saved; otherwise nil. The removal of rates entered by hand says its failures too
    /// (`YearTabModel+UniformRate.swift`).
    private(set) var errorText: String?
    var saveFailure: String?

    /// Whether the form of the uniform rate is open, its texts, and what is wrong with them.
    private(set) var editsRates = false
    var usdText = ""
    var eurText = ""
    var instructionText = ""
    private(set) var rateError: String?

    /// Whether the card asks whether to remove the rates entered by hand (Odstranit…), in place of its note. The
    /// question and the removal are in `YearTabModel+UniformRate.swift`.
    var asksToRemove = false

    /// Whether the rates entered by hand are being removed: another Odstranit kurz meanwhile does nothing.
    @ObservationIgnored var removesRates = false

    /// The form of a new adjustment, and what is wrong with it.
    var adjustmentDate: CivilDate
    var adjustmentAmount = ""
    var adjustmentDescription = ""
    private(set) var adjustmentError: String?

    /// The app, also used by the card of the uniform rate (`YearTabModel+UniformRate.swift`).
    let app: AppModel

    /// How many loads have started. Only the latest may show its result.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
        adjustmentDate = app.receivedThrough
    }

    /// The year shown.
    var year: Int {
        settings?.year ?? app.asOf.year
    }

    // MARK: Loading

    /// Loads the selected year. A failure is logged and shows `errorText`.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        let shown = app.asOf
        let received = app.receivedThrough
        do {
            guard let database = app.database else { throw VaultError.locked }
            let readSettings = try await database.yearSettings(shown.year)
            let readRates = try await database.uniformRates(year: shown.year)
            let readFXState = try await app.fxState(year: shown.year)
            let readAdjustments = try await database.adjustments(year: shown.year)
            let unreadable = readRates.isEmpty ? await unreadablePage(of: shown.year, in: database) : nil
            guard thisLoad == loadsStarted else { return }
            if settings?.year != shown.year {
                // The forms and the question belong to the year they were opened for.
                editsRates = false
                rateError = nil
                asksToRemove = false
                adjustmentError = nil
                adjustmentDate = received
            }
            settings = readSettings
            uniformRates = readRates
            fxState = readFXState
            adjustments = readAdjustments
            unreadablePage = unreadable
            if !isManual {
                // The rates entered by hand are gone: there is nothing to ask about.
                asksToRemove = false
            }
            if unreadable != nil, !editsRates {
                startEditingRates()
            }
            errorText = nil
            openRequestedForm()
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading the settings of the year", failedWith: error)
            errorText = Self.loadFailureText
        }
    }

    /// The page of the Finanční zpravodaj that the refresh could not read for `year`, as its state keeps it. A state
    /// that cannot be read is logged: it is the refresh's own bookkeeping.
    private func unreadablePage(of year: Int, in database: Database) async -> URL? {
        do {
            return try await database.refreshState()?.unreadableUniformPages[year]
        } catch {
            AppModel.log("Reading the state of the refresh", failedWith: error)
            return nil
        }
    }

    // MARK: Profil

    /// "paušál 60 % (strop 1 200 000 Kč)": the flat-rate expenses of the year, which Zálohy a odpočty sets.
    var expenseText: String {
        let percent = settings?.expensePercent ?? YearSettings(year: year).expensePercent
        let cap = TaxRules.expenseCap(percent: percent).map { " (strop \(CzechFormat.wholeKc($0)))" } ?? ""
        return "paušál " + CzechFormat.percent(Decimal(percent) / 100, fractionDigits: 0) + cap
    }

    /// Whether the uniform rate can be chosen for the year: once it has the rate of every currency it was paid in
    /// (`UniformAvailability.isReady`).
    var canChooseUniform: Bool {
        fxState?.uniform.isReady ?? false
    }

    /// "jednotný kurz za rok", the uniform rate in the menu of Příjmy v cizí měně, and while it cannot be chosen, why.
    /// While the app waits for the GFŘ to publish the rate the menu says only that it is not out, as the design does:
    /// "jednotný kurz za rok – zatím nevyšel". A closed menu is as wide as its longest item, and the reason that the
    /// menu of the rate capsule adds there, when the GFŘ publishes it, would make it that wide for most of the year.
    /// The states the design does not draw give the reason that every screen gives on the day of the app
    /// (`BuilderText.uniformRateMissing(_:year:)`): "jednotný kurz za rok – v aplikaci není – zadáte ho v Nastavení ›
    /// Rok 2024".
    var uniformOptionLabel: String {
        guard let fxState, let reason = BuilderText.uniformRateMissing(fxState.uniform, year: fxState.year) else {
            return "jednotný kurz za rok"
        }
        if case .notPublishedYet = fxState.uniform {
            return "jednotný kurz za rok – zatím nevyšel"
        }
        return "jednotný kurz za rok – " + reason
    }

    /// The conversion the menu of Příjmy v cizí měně shows: the one the year uses. A year set to the uniform rate that
    /// does not have it is computed at the ČNB rates of the days meanwhile, so they are what it shows; the choice is
    /// kept for when the year has the rate.
    var shownFXMethod: IncomeFXMethod {
        settings?.incomeFXMethod == .uniform && canChooseUniform ? .uniform : .cnbDaily
    }

    /// How the income in other currencies is converted: at the ČNB rate of the day it came, or at the uniform rate of
    /// the year, which can be chosen only while the year has it (`canChooseUniform`). The choice is shown at once and
    /// made by the app (`AppModel.setFXMethod(_:year:)`), which stores it and converts the year's payments again; then
    /// the tab loads again. A choice that cannot be saved, or is not taken, is taken back, and what failed is said in
    /// `saveFailure`.
    func setFXMethod(_ method: IncomeFXMethod) async {
        guard let shown = settings, shown.incomeFXMethod != method else { return }
        var changed = shown
        changed.incomeFXMethod = method
        settings = changed
        let change = await app.setFXMethod(method, year: shown.year)
        if change == .notSaved || change == .unchanged, settings == changed {
            // Not stored: the choice shown is taken back.
            settings = shown
        }
        if change != .unchanged {
            saveFailure = change.failureText
        }
        await load()
    }

    // MARK: Činnost

    /// The first and the last month of the activity, 1 to 12. A range that is not one (`from` after `to`, a month
    /// outside the year) is not saved.
    func setActivity(from: Int, to: Int) async {
        guard (1...12).contains(from), (1...12).contains(to), from <= to else { return }
        guard settings?.activityFrom != from || settings?.activityTo != to else { return }
        await update { settings in
            settings.activityFrom = from
            settings.activityTo = to
        }
    }

    /// Whether the health minimum does not apply in `month`, 1 to 12.
    func setHealthExempt(month: Int, _ exempt: Bool) async {
        guard (1...12).contains(month), settings?.healthExemptMonths.contains(month) != exempt else { return }
        await update { settings in
            if exempt {
                settings.healthExemptMonths.insert(month)
            } else {
                settings.healthExemptMonths.remove(month)
            }
        }
    }

    /// Označit i tady: the months of secondary activity become months without the health minimum as well.
    func markSecondaryAsExempt() async {
        guard let settings, !settings.secondaryMonths.isSubset(of: settings.healthExemptMonths) else { return }
        await update { $0.healthExemptMonths.formUnion($0.secondaryMonths) }
    }

    /// "celý rok", or "5 měsíců činnosti · ostatní měsíce se do minim nepočítají".
    var activityText: String {
        Self.activityText(from: settings?.activityFrom ?? 1, to: settings?.activityTo ?? 12)
    }

    nonisolated static func activityText(from: Int, to: Int) -> String {
        // A range that runs backwards, which only damaged data can hold, has no month.
        let count = max(0, to - from + 1)
        guard count != 12 else { return "celý rok" }
        return ComputationBuilder.months(count) + " činnosti · ostatní měsíce se do minim nepočítají"
    }

    /// Whether the activity was carried on in `month` by `settings`. A range that runs backwards has no month; it is
    /// compared bound by bound, as it cannot be made a range.
    nonisolated static func isActiveMonth(_ month: Int, in settings: YearSettings) -> Bool {
        month >= settings.activityFrom && month <= settings.activityTo
    }

    /// The hint about the months of secondary activity that are not marked as months without the health minimum, or
    /// nil when there are none.
    var secondaryHint: String? {
        guard let settings else { return nil }
        let months = settings.secondaryMonths.subtracting(settings.healthExemptMonths).sorted()
        guard !months.isEmpty else { return nil }
        let names = months.map { CzechFormat.monthNames[$0 - 1] }.joined(separator: ", ")
        return "V Zálohách máte vedlejší činnost v měsících \(names). Byli jste v nich zároveň zaměstnaní nebo"
            + " studovali? Pak se za ně minimum zdravotního nepočítá."
    }

    // MARK: Jednotný kurz

    /// The uniform rates of dollars and euros of `rates`, dollars first (`UniformRate.currenciesEnteredByHand`): the
    /// currencies the card and the form are about.
    nonisolated static func dollarAndEuroRates(_ rates: [UniformRate]) -> [UniformRate] {
        UniformRate.currenciesEnteredByHand.compactMap { currency in
            rates.first { $0.currency == currency && $0.rate > 0 }
        }
    }

    /// The rates the card shows: those of dollars and euros stored for the year.
    var shownRates: [UniformRate] {
        Self.dollarAndEuroRates(uniformRates)
    }

    /// "21,84 Kč": a rate of the card, with two decimals as the GFŘ publishes it.
    nonisolated static func rateText(_ rate: UniformRate) -> String {
        CzechFormat.rate(rate.rate, fractionDigits: 2) + "\u{00A0}Kč"
    }

    /// "1 USD": what a rate of the card is for.
    nonisolated static func rateUnit(_ rate: UniformRate) -> String {
        "\(rate.amount)\u{00A0}\(rate.currency.code)"
    }

    /// Zadat ručně, or Upravit: opens the form with the rates and the instruction that are stored, in place of the
    /// question whether to remove them.
    func startEditingRates() {
        let shown = shownRates
        usdText = shown.first { $0.currency == .usd }.map { CzechFormat.rate($0.rate, fractionDigits: 2) } ?? ""
        eurText = shown.first { $0.currency == .eur }.map { CzechFormat.rate($0.rate, fractionDigits: 2) } ?? ""
        instructionText = shown.first?.instruction ?? ""
        rateError = nil
        asksToRemove = false
        editsRates = true
    }

    /// Zadat ručně on the sheet of a uniform rate that was found, or on the reminder of Přehled: opens the form of the
    /// rates when the app asked for it (`SettingsAction.enterUniformRate`) and the selected year is loaded. While it is
    /// not (the tab is not loaded yet, or still shows the year before), the request waits for the load; a request that
    /// is for another tab is left for it.
    func openRequestedForm() {
        guard app.settingsAction == .enterUniformRate, settings?.year == app.asOf.year else { return }
        app.settingsAction = nil
        if !editsRates {
            startEditingRates()
        }
    }

    /// Why `rate`, typed by hand as the uniform rate of one unit of `currency` in `year`, does not fit the year, or nil
    /// when it does. The uniform rate is the mean of the twelve ČNB rates of the ends of the months, so a correct one
    /// is near the ČNB rates of the year, and a rate typed without its decimal comma ("2184" for "21,84") is a hundred
    /// times too big:
    /// - a rate more than 20 % away from `cnbMean`, the mean of the ČNB rates of the year that the app has (for one
    ///   unit), does not fit;
    /// - without them, a rate more than 50 % away from `previousUniform`, the uniform rate of the year before (for one
    ///   unit), does not fit;
    /// - with neither, any rate fits.
    nonisolated static func implausibility(
        of rate: Decimal, currency: CurrencyCode, year: Int, cnbMean: Decimal?, previousUniform: Decimal?
    ) -> String? {
        let typed = CzechFormat.rate(rate, fractionDigits: 2)
        if let mean = cnbMean {
            guard isFar(rate, from: mean, percent: 20) else { return nil }
            return "Kurz \(currency.code) \(typed) neodpovídá kurzům ČNB za rok \(year) (průměr "
                + "\(CzechFormat.rate(mean, fractionDigits: 2))). Zkontrolujte desetinnou čárku."
        }
        if let previous = previousUniform {
            guard isFar(rate, from: previous, percent: 50) else { return nil }
            return "Kurz \(currency.code) \(typed) se příliš liší od jednotného kurzu za rok \(year - 1) "
                + "(\(CzechFormat.rate(previous, fractionDigits: 2))). Zkontrolujte desetinnou čárku."
        }
        return nil
    }

    /// Whether `rate` is more than `percent` % away from `reference`, up or down.
    private nonisolated static func isFar(_ rate: Decimal, from reference: Decimal, percent: Int) -> Bool {
        let difference = rate > reference ? rate - reference : reference - rate
        return difference * Decimal(100) > reference * Decimal(percent)
    }

    /// Zrušit: the form closes, and nothing is saved.
    func cancelEditingRates() {
        editsRates = false
        rateError = nil
    }

    /// Uložit kurz: saves the rates of 1 USD and 1 EUR in crowns typed in `usd` and `eur` (either may be left empty,
    /// not both) with the GFŘ instruction, as rates entered by hand. They replace the year's rates of dollars and
    /// euros, official or entered by hand before; those of other currencies stay. What the year has is what the
    /// database holds for it (`Database.uniformRates(year:)`), read once the rates are checked and not taken from what
    /// the tab last loaded (`uniformRates`), which another path may have changed since: the currencies that stay are
    /// those stored then, and rates that only the tab still shows are saved. Rates that are the ones the year has
    /// stored, with the same instruction, are not saved again: an official rate stays official, and the banner says
    /// that nothing changed. The app then converts the payments of the year again, by the method it uses with these
    /// rates (`convertPaymentsAgain(of:)`), whatever the tab last read of it: a year set to the uniform rate that
    /// lacked the rate of a currency it was paid in takes the uniform rate again once it has it. The banner then says,
    /// from what the year uses then (`showSavedRateBanner(year:)`), that the payments are converted at the rate, or
    /// where the year is switched to it (`savedRateText(year:convertsAtIt:)`), and the refresh is told, which stops
    /// looking for the rate. Returns whether the year has the rates of the form now, saved or unchanged; a text that is
    /// not a rate above zero with at most two decimals is refused with `rateError`, and so is a rate that does not fit
    /// the year (`implausibility(of:currency:year:cnbMean:previousUniform:)`).
    @discardableResult
    func saveManualUniformRates(usd: String, eur: String, instruction: String) async -> Bool {
        let typed: [(CurrencyCode, String)] = [(.usd, usd), (.eur, eur)]
        var rates: [UniformRate] = []
        for (currency, text) in typed where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let rate = AmountParser.decimal(text, maxFractionDigits: 2), rate > 0 else {
                rateError = Self.rateFormatText
                return false
            }
            rates.append(
                UniformRate(
                    year: year, currency: currency, amount: 1, rate: rate,
                    instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines), origin: .manual))
        }
        guard !rates.isEmpty else {
            rateError = Self.noRateText
            return false
        }
        guard let database = app.database else {
            rateError = Self.saveFailureText
            return false
        }
        let year = self.year
        let stored: [UniformRate]
        do {
            for rate in rates {
                let previous = try await database.uniformRate(rate.currency, year: year - 1)
                if let problem = Self.implausibility(
                    of: rate.rate, currency: rate.currency, year: year,
                    cnbMean: try await database.meanCNBRate(rate.currency, year: year),
                    previousUniform: previous.map { $0.rate / Decimal($0.amount) })
                {
                    rateError = problem
                    return false
                }
            }
            // What the year has stored, read as late as possible: just before it is compared and saved over.
            stored = try await database.uniformRates(year: year)
        } catch {
            AppModel.log("Reading the rates a uniform rate is checked against", failedWith: error)
            rateError = Self.saveFailureText
            return false
        }
        guard !Self.areStored(rates, among: Self.dollarAndEuroRates(stored)) else {
            rateError = nil
            editsRates = false
            app.showBanner(Self.unchangedRateText(year: year))
            return true
        }
        let others = stored.filter { $0.currency != .usd && $0.currency != .eur }
        do {
            try await database.saveUniformRates(others + rates, year: year)
        } catch {
            AppModel.log("Saving the uniform rates", failedWith: error)
            rateError = Self.saveFailureText
            return false
        }
        rateError = nil
        editsRates = false
        saveFailure = nil
        app.noteUniformRatesStored(forYear: year)
        await app.didWrite()
        let converted = await convertPaymentsAgain(of: year)
        await load()
        if converted {
            // A year that could not be converted says so in `saveFailure` instead.
            await showSavedRateBanner(year: year)
        }
        if app.dependencies.startsRefresh, let refresh = app.refresh {
            Task { await refresh.refresh(.settingsChanged) }
        }
        return true
    }

    /// The banner once rates of `year` are saved and its payments converted: what the year uses now
    /// (`AppModel.fxState(year:)`), read anew rather than taken from what the tab last loaded, which may be of another
    /// year, or older when a load since took the place of the tab's own. A state that cannot be read is logged and
    /// shows no banner: the tab says itself what it cannot load.
    private func showSavedRateBanner(year: Int) async {
        let state: YearFXState
        do {
            state = try await app.fxState(year: year)
        } catch {
            AppModel.log("Reading the conversion of a year whose uniform rate was saved", failedWith: error)
            return
        }
        if case .missingCurrency(let currency) = state.uniform {
            app.showBanner(Self.lacksPaidCurrencyText(year: year, currency: currency))
        } else {
            app.showBanner(Self.savedRateText(year: year, convertsAtIt: state.effective == .uniform))
        }
    }

    // MARK: Pravidla

    /// The rules the year is computed with: its own, or those of the nearest year that has rules.
    private var rules: (rules: TaxRules, isEstimate: Bool) {
        TaxRules.forYear(year)
    }

    /// "verze 2026.1 · ověřeno 20. 10. 2026".
    var rulesVersion: String {
        Screen.rulesText(year: year)
    }

    /// The values of the rules of the year, as the card lists them: those of the levies, then the amounts of the
    /// family — the spouse credit, the child benefit of the first, the second and the third and every further child for
    /// a year, and the income from which the tax bonus is paid.
    var ruleRows: [RuleRow] {
        let rules = rules.rules
        let percent = settings?.expensePercent ?? YearSettings(year: year).expensePercent
        func share(_ value: Decimal, digits: Int = 0) -> String {
            CzechFormat.percent(value, fractionDigits: digits)
        }
        let healthMinimum = DecimalMath.halfUp(rules.healthMinimumMonthlyBase * 100)
        // "15 204 / 22 320 / 27 840 Kč": the child benefit of each rate for a year, with the currency once, at the end.
        let childAmounts =
            rules.childMonthly.map { CzechFormat.grouped($0 * 12) }.joined(separator: " / ") + "\u{00A0}Kč"
        return [
            RuleRow(
                label: "Daň \(share(TaxRules.taxRateLow)), \(share(TaxRules.taxRateHigh)) ze základu nad",
                value: CzechFormat.wholeKc(rules.taxBandThreshold)),
            RuleRow(label: "Sleva na poplatníka", value: CzechFormat.wholeKc(rules.taxpayerCredit)),
            RuleRow(
                label: "Sociální \(share(rules.socialAssessmentPercent)) zisku × \(share(TaxRules.socialRate, digits: 1)),"
                    + " min. VZ / měsíc",
                value: CzechFormat.wholeKc(rules.socialMinimumMonthlyMain)),
            RuleRow(label: "Sociální – maximální VZ za rok", value: CzechFormat.wholeKc(rules.socialMaximumAnnualBase)),
            RuleRow(
                label: "Zdravotní \(share(TaxRules.healthAssessmentPercent)) zisku × \(share(TaxRules.healthRate, digits: 1)),"
                    + " min. VZ / měsíc",
                value: CzechFormat.halere(healthMinimum)),
            RuleRow(
                label: "Strop paušálu \(share(Decimal(percent) / 100))",
                value: TaxRules.expenseCap(percent: percent).map { CzechFormat.wholeKc($0) } ?? "—"),
            RuleRow(
                label: "Sleva na manžela/ku" + (rules.spouseNeedsYoungChild ? " – jen s vaším dítětem do 3 let" : ""),
                value: CzechFormat.wholeKc(rules.spouseCreditMonthly * 12)),
            RuleRow(label: "Daňové zvýhodnění na 1. / 2. / 3. a další dítě", value: childAmounts),
            RuleRow(
                label: "Daňový bonus od příjmů (6× minimální mzda \(CzechFormat.wholeKc(rules.minimumWage)))",
                value: CzechFormat.wholeKc(rules.bonusIncomeThreshold)),
        ]
    }

    /// The conventions of the app that the law leaves open, in the words of Výpočet: how the income and the expenses
    /// are rounded, and how the months after the day shown count in the reduced decisive amount.
    var conventions: [String] {
        [
            // As the row of the income of Výpočet says it.
            BuilderText.capitalized(ComputationBuilder.incomeRoundingNote),
            BuilderText.capitalized(ComputationBuilder.notReachedMonthsConvention),
        ]
    }

    /// The warning that the year is computed with the rules of another year, or nil.
    var rulesWarning: String? {
        let rules = rules
        return rules.isEstimate ? RulesWarning.message(year: year, rulesYear: rules.rules.year) : nil
    }

    // MARK: Úpravy příjmů

    /// "celkem −1 000,00 Kč": the sum of the adjustments, or nil when there are none.
    var adjustmentsTotal: String? {
        guard !adjustments.isEmpty else { return nil }
        let sum = adjustments.reduce(Int64(0)) { $0 + $1.amountHalere }
        return "celkem " + Self.adjustmentAmountText(sum)
    }

    /// "+4 500,00 Kč", "−1 000,00 Kč": an adjustment with its sign.
    nonisolated static func adjustmentAmountText(_ halere: Int64) -> String {
        (halere > 0 ? "+" : "") + CzechFormat.halere(halere)
    }

    /// Přidat: saves an adjustment of the year on `date`, of the amount in crowns typed in `amount` (negative when the
    /// income went down) and `description`. Returns whether it was saved, and then the form is emptied. A date outside
    /// the year, an amount that is not one, and zero are refused with `adjustmentError`.
    @discardableResult
    func addAdjustment(date: CivilDate, amount: String, description: String) async -> Bool {
        let year = self.year
        guard date.year == year else {
            adjustmentError = "Zadejte datum v roce \(year)."
            return false
        }
        let typed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            adjustmentError = Self.noAmountText
            return false
        }
        guard let halere = Self.signedAmount(typed) else {
            adjustmentError = Self.amountFormatText
            return false
        }
        guard halere != 0 else {
            adjustmentError = Self.noAmountText
            return false
        }
        guard let database = app.database else {
            adjustmentError = Self.saveFailureText
            return false
        }
        let adjustment = IncomeAdjustment(
            date: date, amountHalere: halere,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await database.saveAdjustment(adjustment)
        } catch {
            AppModel.log("Saving an income adjustment", failedWith: error)
            adjustmentError = Self.saveFailureText
            return false
        }
        adjustmentError = nil
        adjustmentAmount = ""
        adjustmentDescription = ""
        app.showBanner("Úprava příjmů je přidaná a počítá se do roku \(year).")
        await app.didWrite()
        await load()
        return true
    }

    /// An amount in haléře typed with its sign, as the field of an adjustment asks for it: "−1 000" or "-1 000" when the
    /// income went down, "4 500" or "+4 500" when it went up (`AmountParser.minor` reads all but the plus). Nil for a
    /// text that is not an amount.
    nonisolated static func signedAmount(_ text: String) -> Int64? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.hasPrefix("+") else { return AmountParser.minor(typed) }
        let rest = typed.dropFirst()
        // A plus is a sign only before the number itself.
        guard let first = rest.first, ("0"..."9").contains(first) else { return nil }
        return AmountParser.minor(String(rest))
    }

    /// Smazat: deletes the adjustment.
    func deleteAdjustment(id: Int64) async {
        guard let database = app.database else { return }
        do {
            try await database.deleteAdjustment(id: id)
        } catch {
            AppModel.log("Deleting an income adjustment", failedWith: error)
            saveFailure = Self.saveFailureText
            return
        }
        saveFailure = nil
        await app.didWrite()
        await load()
    }

    // MARK: Saving

    /// Changes the settings of the year shown with `change`, in one transaction, and tells the app. The change is shown
    /// at once, and taken back when it cannot be saved, which `saveFailure` says. Returns whether it was saved.
    @discardableResult
    private func update(_ change: @Sendable (inout YearSettings) -> Void) async -> Bool {
        guard let database = app.database, let shown = settings else {
            saveFailure = Self.saveFailureText
            return false
        }
        var changed = shown
        change(&changed)
        settings = changed
        do {
            let saved = try await database.updateYearSettings(shown.year, change)
            if settings?.year == saved.year {
                settings = saved
            }
        } catch {
            AppModel.log("Saving the settings of the year", failedWith: error)
            if settings == changed {
                settings = shown
            }
            saveFailure = Self.saveFailureText
            return false
        }
        saveFailure = nil
        await app.didWrite()
        return true
    }

    /// Has the app convert the payments of `year` again, after its uniform rate was saved or removed, by the method the
    /// year uses then (`AppModel.convertPaymentsAfterUniformRatesChanged(year:)`). Returns whether they were. A failure
    /// is said in `saveFailure`: the change is saved, its payments are not converted.
    func convertPaymentsAgain(of year: Int) async -> Bool {
        guard await app.convertPaymentsAfterUniformRatesChanged(year: year) else {
            saveFailure = FXMethodChange.paymentsNotConvertedText(year: year)
            return false
        }
        return true
    }
}
