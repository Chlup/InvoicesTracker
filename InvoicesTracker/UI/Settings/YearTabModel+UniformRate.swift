import Foundation

/// The card Jednotný kurz of Nastavení › Rok beyond its form (`YearTabModel`): what it says of the rates of the year —
/// where they are from, what rates entered by hand stand in for, how a rate the app computed came about with the ČNB
/// rates of the month ends it averages, and what a year without a rate waits for — whether rates saved by hand change
/// anything, and the removal of rates entered by hand with the question before it. The state of the card is the
/// model's.
extension YearTabModel {
    // MARK: Texts of the card

    /// The question of the card before the rates entered by hand are removed, and the answer that removes them.
    nonisolated static let removalTitle = "Odstranit ručně zadaný kurz?"
    nonisolated static let removalConfirmTitle = "Odstranit kurz"

    /// Whether the rates the card shows were entered by hand, so that Odstranit… removes them and the card says what
    /// they stand in for.
    var isManual: Bool {
        shownRates.contains { $0.origin == .manual }
    }

    /// Whether the rates the card shows are the preliminary ones the app computed from the ČNB month-end rates: the
    /// card says so (Předběžný), says how they came about and what replaces them, shows the ČNB rates of the month ends
    /// they average, and offers Zadat ručně in place of Upravit.
    var isComputed: Bool {
        shownRates.contains(where: \.isComputed)
    }

    /// Upravit of the rates the card shows, or Zadat ručně of rates the app computed, which the form replaces rather
    /// than edits.
    var editRatesTitle: String {
        isComputed ? "Zadat ručně" : "Upravit"
    }

    /// The number of months, from January, that the computed rates the card shows average, or nil for other rates.
    private var computedMonths: Int? {
        guard isComputed, let months = shownRates.compactMap(\.computedMonths).max(), (1...12).contains(months) else {
            return nil
        }
        return months
    }

    /// Where the rates shown are from, as every screen says it (`BuilderText.uniformSource(of:)`): "pokyn GFŘ-D-75 ·
    /// v aplikaci od vydání" for the rates shipped with the app, "pokyn GFŘ-D-99" for rates fetched and confirmed, and
    /// for rates entered by hand "pokyn GFŘ-D-80, zadáno ručně", or "zadáno ručně" without an instruction. Rates the
    /// app computed say from which ČNB rates and months (`computedSource(year:months:)`).
    var rateSource: String {
        let shown = shownRates
        if let months = computedMonths {
            return Self.computedSource(year: year, months: months)
        }
        let source = BuilderText.uniformSource(of: shown) ?? ""
        guard !shown.isEmpty, shown.allSatisfy({ $0.origin == .builtIn }) else { return source }
        return source + " · v aplikaci od vydání"
    }

    /// "Spočítáno podle § 38 odst. 7 ZDP z kurzů ČNB k posledním dnům měsíců leden–září 2026 (9 z 12)": where the rate
    /// of `year` that the app computed is from, over `months` months from January, 1 to 12; "… k posledním dnům měsíců
    /// roku 2026 (všech 12)" over the whole year. The count in parentheses is kept on one line with no-break spaces,
    /// so that the line never ends with "(9" or the preposition "z".
    nonisolated static func computedSource(year: Int, months: Int) -> String {
        let source = "Spočítáno podle § 38 odst. 7 ZDP z kurzů ČNB k posledním dnům měsíců "
        guard months < 12 else { return source + "roku \(year) (všech\u{00A0}12)" }
        return source + "\(BuilderText.monthSpan(months)) \(year) (\(months)\u{00A0}z\u{00A0}12)"
    }

    /// The grey note under rates the app computed, on the day of the app (`computedNote(year:months:today:)`); nil for
    /// any other rates.
    var computedNote: String? {
        computedMonths.map { Self.computedNote(year: year, months: $0, today: app.today) }
    }

    /// What comes of the rate of `year` that the app computed over `months` months, said on `today`: that it is
    /// computed again with each month that ends, while not all twelve have, and that the app finds the official rate
    /// the GFŘ publishes in January of the next year and replaces it with that once the person confirms it. Once the
    /// search of the app for the official rate is over (`UniformRateSearch`), that the app did not find it, and that
    /// the year keeps the computed rate until the official one is entered by hand.
    nonisolated static func computedNote(year: Int, months: Int, today: CivilDate) -> String {
        guard UniformRateSearch(year: year, today: today) != .over else {
            return "Aplikace kurz GFŘ nenašla. Zadejte ho podle pokynu GFŘ tlačítkem Zadat ručně; do té doby rok"
                + " používá tento předběžný kurz."
        }
        return (months < 12 ? "Po každém skončeném měsíci se kurz přepočítá i s ním. " : "")
            + "Oficiální kurz vyhlásí GFŘ v lednu \(year + 1). Aplikace ho pak sama najde, dá vám ho potvrdit a"
            + " předběžný kurz jím nahradí."
    }

    /// What the card says while the year has no rate, on the day of the app (`missingRateText(year:today:)`).
    var missingRateText: String {
        Self.missingRateText(year: year, today: app.today)
    }

    /// What the card says on `today` while `year` has no rate. The current year does not wait for the GFŘ: the app
    /// computes its rate from the ČNB rates of the month ends (`AppModel.updateComputedUniformRates()`), so in January
    /// the card says that no month has ended yet and from when the app computes it, and in a later month that the app
    /// lacks some of the ČNB rates of the month ends, the reason the current year is then without a rate
    /// (`BuilderText.uniformRateMissing(_:year:today:)` tells the two apart the same way, by the month of `today`).
    /// Another year follows where the search of the app for it stands
    /// (`UniformRateSearch`), so that the card never promises a January that has passed: until 2 January of the next
    /// year when the GFŘ publishes it, then until 31 March that the app looks for it, and after that that the app does
    /// not have it.
    nonisolated static func missingRateText(year: Int, today: CivilDate) -> String {
        if year == today.year, let february = CivilDate(year: year, month: 2, day: 1) {
            guard today.month == 1 else {
                return "Zatím ho nejde spočítat – aplikaci chybí kurzy ČNB ke konci některých měsíců. Spočítá ho, až"
                    + " je stáhne."
            }
            return "Zatím ho nejde ani předběžně spočítat – leden \(year) ještě neskončil. Od"
                + " \(CzechFormat.date(february)) ho aplikace spočítá z kurzů ČNB ke konci měsíců; oficiální kurz"
                + " vyhlásí GFŘ v lednu \(year + 1)."
        }
        switch UniformRateSearch(year: year, today: today) {
        case .notStarted:
            return "Zatím nevyšel. GFŘ ho zveřejní v lednu \(year + 1); aplikace ho pak sama najde a požádá vás o"
                + " potvrzení."
        case .looking:
            return "Zatím nevyšel. Aplikace ho jednou denně hledá a dá vám ho potvrdit."
        case .over:
            return "Pro rok \(year) kurz v aplikaci není. Zadejte ho podle pokynu GFŘ."
        }
    }

    /// The instruction of the table that ships with the app for `year` (`BuiltInUniformRates`), or nil for a year
    /// without one: the official rate that rates entered by hand replace, and that removing them brings back.
    private nonisolated static func shippedInstruction(of year: Int) -> String? {
        guard !BuiltInUniformRates.rates(year: year).isEmpty else { return nil }
        return BuiltInUniformRates.instructions[year]
    }

    /// "pokynu GFŘ-D-75 (1 USD = 21,84 Kč · 1 EUR = 24,66 Kč)": the table that ships with the app for `year` with its
    /// rates of dollars and euros, as the texts of rates entered by hand name it; nil for a year without one.
    private nonisolated static func shippedTableText(of year: Int) -> String? {
        guard let instruction = shippedInstruction(of: year) else { return nil }
        let rates = dollarAndEuroRates(BuiltInUniformRates.uniformRates(year: year))
        return "pokynu \(instruction) (" + rates.map(BuilderText.uniformRate).joined(separator: " · ") + ")"
    }

    /// The grey note under rates entered by hand, while the card does not ask whether to remove them
    /// (`manualNote(year:today:)`); nil for official rates.
    var manualNote: String? {
        guard isManual else { return nil }
        return Self.manualNote(year: year, today: app.today)
    }

    /// What rates entered by hand for `year` stand in for, said on `today`: the table that ships with the app, which
    /// they replace; for another year, that the app does not look for the official rate while they are stored, and once
    /// its search is over (`UniformRateSearch`), that the app does not have the official rate.
    nonisolated static func manualNote(year: Int, today: CivilDate) -> String {
        if let table = shippedTableText(of: year) {
            return "Nahrazuje kurz z \(table), který má aplikace od vydání."
        }
        if UniformRateSearch(year: year, today: today) == .over {
            return "Oficiální kurz pro rok \(year) aplikace nemá."
        }
        return "Dokud je kurz zadaný ručně, aplikace oficiální kurz nehledá. Po odstranění ho začne hledat znovu."
    }

    /// What the form says above its fields when what is saved replaces a rate the app computed (Zadat ručně of that
    /// rate) or the table that ships with the app (Upravit of that rate), and how to bring it back; nil otherwise.
    var formHint: String? {
        guard editsRates, !isManual else { return nil }
        if isComputed {
            return "Ručně zadaný kurz nahradí předběžný kurz, který aplikace spočítala z kurzů ČNB. Vrátíte ho"
                + " tlačítkem Odstranit."
        }
        guard let instruction = Self.shippedInstruction(of: year) else { return nil }
        return "Ručně zadaný kurz nahradí kurz z pokynu \(instruction). Vrátíte ho tlačítkem Odstranit."
    }

    // MARK: Kurzy ke konci měsíců

    /// A month of the table of the ČNB rates of the month ends that a computed rate averages: its name, the day of the
    /// ČNB rate valid on its last day and the rates of 1 USD and 1 EUR, or, for a month that has not ended, the day it
    /// ends and dashes.
    nonisolated struct MonthEndRow: Equatable, Sendable {
        /// "Leden".
        let month: String

        /// "30. 1. (platí i 31. 1.)", "31. 3.", or "měsíc skončí 31. 10." for a month that has not ended.
        let day: String

        /// "20,413", the rate of one dollar to three places, or "—" without one.
        let usd: String

        /// "24,330", the rate of one euro to three places, or "—" without one.
        let eur: String

        /// Whether the month has ended, so that its rates count in the average.
        let hasEnded: Bool
    }

    /// The titles of the columns of the table of the month ends.
    nonisolated static let monthEndColumns = ["Měsíc", "Kurz ČNB ze dne", "1\u{00A0}USD", "1\u{00A0}EUR"]

    /// What the table of the month ends says under it: which ČNB rate a month takes, and from when it counts.
    nonisolated static let monthEndsCaption =
        "Kurz ČNB platný k poslednímu dni měsíce; o víkendu a ve svátek ten z posledního pracovního dne před ním. Měsíc"
        + " se započítá den po svém konci."

    /// The link that shows the table of the month ends under a computed rate, or hides it.
    var monthEndsTitle: String {
        showsMonthEnds ? "Skrýt kurzy ke konci měsíců" : "Kurzy ke konci měsíců"
    }

    /// Kurzy ke konci měsíců, and Skrýt kurzy ke konci měsíců: shows the table of the month ends, or hides it.
    func toggleMonthEnds() {
        showsMonthEnds.toggle()
    }

    /// The computation of the year shown, while the card shows a rate the app computed; nil otherwise.
    private var shownComputation: PreliminaryUniformRates.Computation? {
        guard isComputed, let computation, computation.year == year else { return nil }
        return computation
    }

    /// The twelve rows of the table of the month ends of the year (`monthEndRows(of:)`), empty unless the card shows a
    /// rate the app computed.
    var monthEndRows: [MonthEndRow] {
        shownComputation.map(Self.monthEndRows(of:)) ?? []
    }

    /// The rows of the table of the month ends of `computation`, January first. A month that has ended has the day the
    /// ČNB declared the rate valid on its last day, followed by "(platí i 31. 1.)" when that is a day before, as on a
    /// weekend, and the rates of one dollar and one euro to three places, "—" for a currency without one; a month that
    /// has not ended has the day it ends, "měsíc skončí 31. 10.", and dashes.
    nonisolated static func monthEndRows(of computation: PreliminaryUniformRates.Computation) -> [MonthEndRow] {
        computation.months.map { month in
            let name = BuilderText.capitalized(CzechFormat.monthNames[month.month - 1])
            let lastDay = CzechFormat.dayMonth(month.lastDay)
            guard month.hasEnded else {
                return MonthEndRow(month: name, day: "měsíc skončí " + lastDay, usd: "—", eur: "—", hasEnded: false)
            }
            let declaredOn = PreliminaryUniformRates.currencies.lazy.compactMap { currency -> CivilDate? in
                guard case .declared(_, let day)? = month.rates[currency] else { return nil }
                return day
            }.first
            let day = declaredOn.map { declared in
                declared == month.lastDay ? lastDay : CzechFormat.dayMonth(declared) + " (platí i \(lastDay))"
            }
            return MonthEndRow(
                month: name, day: day ?? "—", usd: monthEndRate(month.rates[.usd]),
                eur: monthEndRate(month.rates[.eur]), hasEnded: true)
        }
    }

    /// "20,413": the ČNB rate of one unit that a month end takes, to three places, or "—" without one.
    private nonisolated static func monthEndRate(_ result: RateLookupResult?) -> String {
        guard case .declared(let rate, _)? = result else { return "—" }
        return CzechFormat.rate(rate.rate / Decimal(rate.amount), fractionDigits: 3)
    }

    /// The last row of the table of the month ends of the year (`monthEndAverage(of:)`), nil unless the card shows a
    /// rate the app computed.
    var monthEndAverage: (label: String, usd: String, eur: String)? {
        shownComputation.flatMap(Self.monthEndAverage(of:))
    }

    /// The last row of the table of the month ends of `computation`: "Průměr 9 měsíců, na haléře", or "Průměr 1
    /// měsíce, na haléře" for one, with the rates of one dollar and one euro that the months give, to two places, "—"
    /// for a currency they give none of. Nil while they give no rate: no month has ended, or the ČNB rate of a month
    /// end is not there yet.
    nonisolated static func monthEndAverage(
        of computation: PreliminaryUniformRates.Computation
    ) -> (label: String, usd: String, eur: String)? {
        guard case .rates(let rates) = computation.outcome else { return nil }
        func average(_ currency: CurrencyCode) -> String {
            rates.first { $0.currency == currency }
                .map { CzechFormat.rate($0.rate / Decimal($0.amount), fractionDigits: 2) } ?? "—"
        }
        let months = CzechCount.counted(
            computation.endedMonths, one: "měsíce", few: "měsíců", many: "měsíců", separator: CzechFormat.noBreakSpace)
        return ("Průměr \(months), na haléře", average(.usd), average(.eur))
    }

    // MARK: Saving

    /// Whether `typed`, the rates of the form, are the rates of dollars and euros the year has, `stored`: the same
    /// currencies, each the same for one unit and with the same instruction, so that saving them would change nothing.
    nonisolated static func areStored(_ typed: [UniformRate], among stored: [UniformRate]) -> Bool {
        typed.count == stored.count
            && typed.allSatisfy { rate in
                stored.contains { old in
                    old.currency == rate.currency && old.rate / Decimal(old.amount) == rate.rate
                        && old.instruction.trimmingCharacters(in: .whitespacesAndNewlines) == rate.instruction
                }
            }
    }

    /// "Jednotný kurz 2025 se nezměnil.": the form was saved with the rates the year has.
    nonisolated static func unchangedRateText(year: Int) -> String {
        "Jednotný kurz \(year) se nezměnil."
    }

    /// What the banner says once rates of `year` entered by hand are saved: that its payments are converted at them,
    /// when the year converts at the uniform rate now (`convertsAtIt`), otherwise where the year is switched to it.
    nonisolated static func savedRateText(year: Int, convertsAtIt: Bool) -> String {
        "Jednotný kurz \(year) je uložený. "
            + (convertsAtIt
                ? "Platby roku \(year) jsou jím přepočtené."
                : "Rok \(year) na něj přepnete v liště nahoře nebo tady v Profilu.")
    }

    /// What the banner says once rates of `year` are saved that lack the rate of `currency`, in which the year has
    /// payments (`UniformAvailability.missingCurrency`): the year is computed at the daily ČNB rates, whatever it is
    /// set to, until the rate is added. For a currency whose rate Nastavení › Rok does not take
    /// (`UniformRate.currenciesEnteredByHand`), the banner says that the rate cannot be typed instead.
    nonisolated static func lacksPaidCurrencyText(year: Int, currency: CurrencyCode) -> String {
        "Jednotný kurz \(year) je uložený, ale chybí v něm kurz \(currency.code), ve kterém máte v roce \(year) platby."
            + (UniformRate.currenciesEnteredByHand.contains(currency)
                ? " Dokud ho nedoplníte, počítá se rok \(year) denními kurzy ČNB."
                : " Ten ručně zadat nelze, takže se rok \(year) počítá denními kurzy ČNB.")
    }

    // MARK: Odstranit

    /// Odstranit…: the card asks whether to remove the rates entered by hand, in place of its note, and says what
    /// follows (`removalQuestion`). Official rates have nothing to remove.
    func askToRemoveRates() {
        guard isManual, !editsRates else { return }
        asksToRemove = true
    }

    /// Zrušit of the question: nothing is removed.
    func cancelRemovingRates() {
        asksToRemove = false
    }

    /// Whether the app computes a preliminary rate of `year` on `today` (`AppModel.updateComputedUniformRates()`): for
    /// the current and the finished year, of which it also looks for the official rate again once rates entered by hand
    /// are removed.
    nonisolated static func computesRate(of year: Int, today: CivilDate) -> Bool {
        ((today.year - 1)...today.year).contains(year)
    }

    /// The preliminary rates of dollars and euros that the year falls back to once its rates entered by hand are
    /// removed: those the app computes for it (`computation`), for a year it computes a rate of
    /// (`computesRate(of:today:)`) that has no table shipping with the app, which comes back instead. Empty otherwise,
    /// and while the ČNB rate of a month end is missing, when the year is left without a rate.
    private var fallbackRates: [UniformRate] {
        guard Self.shippedInstruction(of: year) == nil, Self.computesRate(of: year, today: app.today),
            let computation, computation.year == year, case .rates(let rates) = computation.outcome
        else {
            return []
        }
        return Self.dollarAndEuroRates(rates)
    }

    /// What removing the rates entered by hand leads to, as the card asks it
    /// (`removalQuestion(year:today:choseUniform:computed:)`).
    var removalQuestion: String {
        Self.removalQuestion(
            year: year, today: app.today, choseUniform: settings?.incomeFXMethod == .uniform, computed: fallbackRates)
    }

    /// What removing the rates entered by hand for `year` leads to, said on `today`, for a year set to the uniform rate
    /// (`choseUniform`), whose payments the removal converts again, and that falls back to `computed`, the preliminary
    /// rates the app computes for it (`fallbackRates`):
    /// - a year whose table ships with the app uses the table again, and the payments of a year set to the uniform rate
    ///   are converted at it;
    /// - a year with computed rates uses them, written with "≈", and the payments of a year set to the uniform rate
    ///   are converted at them. For the current and the finished year the app looks for the official rate again
    ///   (`computesRate(of:today:)`);
    /// - another year has no uniform rate until the app finds the official one and it is confirmed, and a year set to
    ///   the uniform rate is computed at the daily ČNB rates meanwhile. The January in which the GFŘ publishes the rate
    ///   is named only before the app starts looking for it (`UniformRateSearch`), never once it has passed;
    /// - once the search is over, the year has no uniform rate in the app.
    nonisolated static func removalQuestion(
        year: Int, today: CivilDate, choseUniform: Bool, computed: [UniformRate] = []
    ) -> String {
        if let table = shippedTableText(of: year) {
            return "Rok \(year) pak použije kurz z \(table)."
                + (choseUniform ? " Platby roku \(year) se jím přepočtou." : "")
        }
        let fallback = dollarAndEuroRates(computed)
        if !fallback.isEmpty {
            return "Rok \(year) pak použije předběžný kurz, který aplikace spočítá z kurzů ČNB ("
                + fallback.map(BuilderText.uniformRate).joined(separator: " · ") + ")."
                + (choseUniform ? " Platby roku \(year) se jím přepočtou." : "")
                + (computesRate(of: year, today: today)
                    ? " Oficiální kurz začne aplikace znovu hledat a dá vám ho potvrdit." : "")
        }
        let meanwhile =
            choseUniform
            ? " Do té doby se rok \(year) počítá denními kurzy ČNB; jednotným kurzem se přepočte, až kurz potvrdíte."
            : ""
        switch UniformRateSearch(year: year, today: today) {
        case .notStarted:
            return "Jednotný kurz \(year) pak nebude k dispozici, dokud ho GFŘ nezveřejní (v lednu \(year + 1))."
                + " Aplikace ho začne znovu hledat a dá vám ho potvrdit." + meanwhile
        case .looking:
            return "Jednotný kurz \(year) pak nebude k dispozici, dokud ho GFŘ nezveřejní. Aplikace ho začne znovu"
                + " hledat a dá vám ho potvrdit." + meanwhile
        case .over:
            return "Jednotný kurz \(year) pak v aplikaci nebude."
                + (choseUniform ? " Rok \(year) se bude počítat denními kurzy ČNB." : "")
        }
    }

    /// What the banner says once the rates entered by hand for `year` are removed on `today`, for a year set to the
    /// uniform rate (`choseUniform`) and one that now uses a preliminary rate the app computed (`usesComputedRate`):
    /// the table of the GFŘ that the year uses again; the computed rate, with the official one the app looks for again
    /// for the current and the finished year (`computesRate(of:today:)`); otherwise that the app looks for the
    /// official rate again, or once its search is over that the year has no uniform rate, with the daily rates a year
    /// set to the uniform rate is computed at meanwhile.
    nonisolated static func removalBanner(
        year: Int, today: CivilDate, choseUniform: Bool, usesComputedRate: Bool = false
    ) -> String {
        let removed = "Ručně zadaný jednotný kurz \(year) je odstraněný. "
        if let instruction = shippedInstruction(of: year) {
            return removed + "Rok \(year) teď používá kurz z pokynu \(instruction)."
        }
        if usesComputedRate {
            return removed + "Rok \(year) teď používá předběžný kurz spočítaný z kurzů ČNB."
                + (computesRate(of: year, today: today) ? " Aplikace oficiální kurz znovu hledá." : "")
        }
        let daily = choseUniform ? " Rok \(year) se zatím počítá denními kurzy ČNB." : ""
        if UniformRateSearch(year: year, today: today) == .over {
            return removed + "Pro rok \(year) teď jednotný kurz není." + daily
        }
        return removed + "Aplikace oficiální kurz znovu hledá." + daily
    }

    /// Odstranit kurz: removes the rates of dollars and euros entered by hand for the year shown. A year whose table
    /// ships with the app gets it back whole (`Database.restoreBuiltInUniformRates(year:)`); another year is left
    /// without uniform rates (`Database.deleteUniformRates(year:)`), and the refresh looks for the official ones again
    /// when they are due, also when its search for them gave up before (`RefreshCoordinator.searchAgain(for:)`). The
    /// app then computes the preliminary uniform rates (`AppModel.updateComputedUniformRates()`), so that the current
    /// or the finished year left without rates takes the rate the app computes from the ČNB rates at once, and converts
    /// the payments of the year again by the method it uses then (`convertPaymentsAgain(of:)`): a year set to the
    /// uniform rate at the table or at the computed rate, or at the daily ČNB rates while it has no rate. The banner
    /// says what the year uses now (`removalBanner(year:today:choseUniform:usesComputedRate:)`), from the choice and
    /// the rates the year has once its payments are converted, whatever the tab last loaded of it
    /// (`showRemovalBanner(year:)`), and the refresh is told. What cannot be removed or converted is logged and said in
    /// `saveFailure`, and a choice that cannot be read is logged and leaves the banner out.
    func removeManualUniformRates() async {
        guard isManual, !removesRates, let database = app.database else { return }
        removesRates = true
        defer { removesRates = false }
        asksToRemove = false
        let year = self.year
        let restoresTable = Self.shippedInstruction(of: year) != nil
        do {
            if restoresTable {
                try await database.restoreBuiltInUniformRates(year: year)
            } else {
                try await database.deleteUniformRates(year: year)
            }
        } catch {
            AppModel.log("Removing the uniform rates entered by hand", failedWith: error)
            saveFailure = Self.saveFailureText
            return
        }
        saveFailure = nil
        if restoresTable {
            app.noteUniformRatesStored(forYear: year)
        } else {
            await app.refresh?.searchAgain(for: year)
        }
        await app.didWrite()
        await app.updateComputedUniformRates()
        let converted = await convertPaymentsAgain(of: year)
        await load()
        if converted {
            // A year that could not be converted says so in `saveFailure` instead.
            await showRemovalBanner(year: year)
        }
        if app.dependencies.startsRefresh, let refresh = app.refresh {
            Task { await refresh.refresh(.settingsChanged) }
        }
    }

    /// The banner once the rates entered by hand for `year` are removed and its payments converted: what the year uses
    /// now, from the choice and the rates it has (`AppModel.fxState(year:)`), read anew rather than taken from what the
    /// tab last loaded, which may be of another year, or older when the choice was changed since (the menu of the
    /// toolbar). A year whose rate the app computed uses it (`UniformAvailability.computedMonths`). A choice that
    /// cannot be read is logged and shows no banner: the tab says itself what it cannot load.
    private func showRemovalBanner(year: Int) async {
        let state: YearFXState
        do {
            state = try await app.fxState(year: year)
        } catch {
            AppModel.log("Reading the conversion of a year whose uniform rate was removed", failedWith: error)
            return
        }
        app.showBanner(
            Self.removalBanner(
                year: year, today: app.today, choseUniform: state.chosen == .uniform,
                usesComputedRate: state.uniform.computedMonths != nil))
    }
}

