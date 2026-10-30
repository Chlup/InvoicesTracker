import Foundation

/// The card Jednotný kurz of Nastavení › Rok beyond its form (`YearTabModel`): what it says of the rates of the year —
/// where they are from, what rates entered by hand stand in for, and what a year without a rate waits for — whether
/// rates saved by hand change anything, and the removal of rates entered by hand with the question before it. The
/// state of the card is the model's.
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

    /// Where the rates shown are from, as every screen says it (`BuilderText.uniformSource(of:)`): "pokyn GFŘ-D-75 ·
    /// v aplikaci od vydání" for the rates shipped with the app, "pokyn GFŘ-D-99" for rates fetched and confirmed, and
    /// for rates entered by hand "pokyn GFŘ-D-80, zadáno ručně", or "zadáno ručně" without an instruction.
    var rateSource: String {
        let shown = shownRates
        let source = BuilderText.uniformSource(of: shown) ?? ""
        guard !shown.isEmpty, shown.allSatisfy({ $0.origin == .builtIn }) else { return source }
        return source + " · v aplikaci od vydání"
    }

    /// What the card says while the year has no rate, on the day of the app (`missingRateText(year:today:)`).
    var missingRateText: String {
        Self.missingRateText(year: year, today: app.today)
    }

    /// What the card says on `today` while `year` has no rate, by where the search of the app for it stands
    /// (`UniformRateSearch`), so that it never promises a January that has passed: until 2 January of the next year
    /// when the GFŘ publishes it, then until 31 March that the app looks for it, and after that that the app does not
    /// have it.
    nonisolated static func missingRateText(year: Int, today: CivilDate) -> String {
        switch UniformRateSearch(year: year, today: today) {
        case .notStarted:
            "Zatím nevyšel. GFŘ ho zveřejní v lednu \(year + 1); aplikace ho pak sama najde a požádá vás o potvrzení."
        case .looking:
            "Zatím nevyšel. Aplikace ho jednou denně hledá a dá vám ho potvrdit."
        case .over:
            "Pro rok \(year) kurz v aplikaci není. Zadejte ho podle pokynu GFŘ."
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

    /// What the form says above its fields when what is saved replaces the table that ships with the app (Upravit of
    /// that rate), and how to bring the table back; nil otherwise.
    var formHint: String? {
        guard editsRates, !isManual, let instruction = Self.shippedInstruction(of: year) else { return nil }
        return "Ručně zadaný kurz nahradí kurz z pokynu \(instruction). Vrátíte ho tlačítkem Odstranit."
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

    /// What removing the rates entered by hand leads to, as the card asks it
    /// (`removalQuestion(year:today:choseUniform:)`).
    var removalQuestion: String {
        Self.removalQuestion(year: year, today: app.today, choseUniform: settings?.incomeFXMethod == .uniform)
    }

    /// What removing the rates entered by hand for `year` leads to, said on `today`, for a year set to the uniform rate
    /// (`choseUniform`), whose payments the removal converts again:
    /// - a year whose table ships with the app uses the table again, and the payments of a year set to the uniform rate
    ///   are converted at it;
    /// - another year has no uniform rate until the app finds the official one and it is confirmed, and a year set to
    ///   the uniform rate is computed at the daily ČNB rates meanwhile. The January in which the GFŘ publishes the rate
    ///   is named only before the app starts looking for it (`UniformRateSearch`), never once it has passed;
    /// - once the search is over, the year has no uniform rate in the app.
    nonisolated static func removalQuestion(year: Int, today: CivilDate, choseUniform: Bool) -> String {
        if let table = shippedTableText(of: year) {
            return "Rok \(year) pak použije kurz z \(table)."
                + (choseUniform ? " Platby roku \(year) se jím přepočtou." : "")
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
    /// uniform rate (`choseUniform`): the table of the GFŘ that the year uses again; otherwise that the app looks for
    /// the official rate again, or once its search is over that the year has no uniform rate, with the daily rates a
    /// year set to the uniform rate is computed at meanwhile.
    nonisolated static func removalBanner(year: Int, today: CivilDate, choseUniform: Bool) -> String {
        let removed = "Ručně zadaný jednotný kurz \(year) je odstraněný. "
        if let instruction = shippedInstruction(of: year) {
            return removed + "Rok \(year) teď používá kurz z pokynu \(instruction)."
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
    /// app then converts the payments of the year again by the method it uses then (`convertPaymentsAgain(of:)`): a
    /// year set to the uniform rate at the table, or at the daily ČNB rates while it has no rate. The banner says what
    /// the year uses now (`removalBanner(year:today:choseUniform:)`), from the choice the year has once its payments
    /// are converted, whatever the tab last loaded of it (`showRemovalBanner(year:)`), and the refresh is told. What
    /// cannot be removed or converted is logged and said in `saveFailure`, and a choice that cannot be read is logged
    /// and leaves the banner out.
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
    /// now, from the choice it has (`AppModel.fxState(year:)`), read anew rather than taken from what the tab last
    /// loaded, which may be of another year, or older when the choice was changed since (the menu of the toolbar). A
    /// choice that cannot be read is logged and shows no banner: the tab says itself what it cannot load.
    private func showRemovalBanner(year: Int) async {
        let state: YearFXState
        do {
            state = try await app.fxState(year: year)
        } catch {
            AppModel.log("Reading the conversion of a year whose uniform rate was removed", failedWith: error)
            return
        }
        app.showBanner(Self.removalBanner(year: year, today: app.today, choseUniform: state.chosen == .uniform))
    }
}
