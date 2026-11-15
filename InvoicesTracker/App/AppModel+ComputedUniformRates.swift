import Foundation

/// The preliminary uniform rate (jednotný kurz) of the current and of the finished year, which the app computes from
/// the ČNB rates of the month ends (`PreliminaryUniformRates`) and stores as computed rates, kept current: when the
/// data opens, on a new day, after new ČNB rates and once the rates entered by hand are removed. A year set to the
/// uniform rate whose computed rate changed has its payments converted at the new one, and a green banner says so.
extension AppModel {
    /// Computes the preliminary uniform rates of the current year and of the finished year, in that order, from the ČNB
    /// rates stored (`Database.preliminaryUniformRates(year:today:)`), and stores them in place of the computed rates
    /// each year has (`Database.storeComputedUniformRates(_:year:)`):
    /// - none while no month of the year has ended, nor while neither dollars nor euros have a ČNB rate on every month
    ///   end that has, which deletes the computed rates the year has;
    /// - nothing for a year whose month-end rates are not all stored yet, which keeps what it has until they are;
    /// - nothing for a year with an official rate or one entered by hand, which a computed one never replaces.
    ///
    /// A year whose computed rates changed and that is set to the uniform rate has its payments converted again by the
    /// method it uses then (`recomputePayments(year:in:)`). When that is the uniform rate, the green banner says what
    /// they are converted at now (`ComputedRateBanner`), naming the currencies the year was paid in. A change is told
    /// (`didWrite()`) so that the screens load again; a rate computed as it is stored writes nothing and shows nothing.
    ///
    /// It is a conversion in its turn (`convertPaymentsInTurn(_:)`), so it never overlaps itself or another conversion,
    /// and it does nothing while the data is locked, or once other data has been opened. A failure is logged and leaves
    /// the year as it is until the next run.
    func updateComputedUniformRates() async {
        await convertPaymentsInTurn { database in
            await self.updateComputedUniformRates(in: database)
        }
    }

    /// `updateComputedUniformRates()` in its turn, on `database`, as of the day of the app.
    private func updateComputedUniformRates(in database: Database) async {
        let today = self.today
        var changed = false
        for year in [today.year, today.year - 1] {
            // The data was let go or replaced meanwhile: what is left to do is about data that is not open any more.
            guard self.database === database else { return }
            guard
                case .changed(let before, let after) = await storeComputedUniformRates(
                    year: year, today: today, in: database)
            else {
                continue
            }
            changed = true
            await convertPayments(ofYear: year, from: before, to: after, today: today, in: database)
        }
        if changed, self.database === database {
            await didWrite()
        }
    }

    /// Computes the preliminary uniform rates of `year` as of `today` from the ČNB rates in `database` and stores them
    /// there, as `updateComputedUniformRates()` says. Returns what storing them did, or nil when nothing was stored:
    /// a month-end rate of the year is not stored yet, or the computation or the storing failed, which is logged.
    private func storeComputedUniformRates(
        year: Int, today: CivilDate, in database: Database
    ) async -> ComputedRatesChange? {
        do {
            let rates: [UniformRate]
            switch try await database.preliminaryUniformRates(year: year, today: today).outcome {
            case .none:
                rates = []
            case .rates(let computed):
                // Empty when neither currency has a ČNB rate on every month end: no rate, as for a year in January.
                rates = computed
            case .incomplete:
                return nil
            }
            return try await database.storeComputedUniformRates(rates, year: year)
        } catch {
            Self.log("Storing the preliminary uniform rates of a year", failedWith: error)
            return nil
        }
    }

    /// The computed rates of `year` in `database` changed from `before` to `after`: a year set to the uniform rate has
    /// its payments converted again by the method it uses then, and when that is the uniform rate, the banner tells of
    /// the new rates (`ComputedRateBanner.text(year:before:after:paid:)`) while `database` is the data open. A year
    /// set to the daily rates is left as it is. A failure is logged and shows no banner.
    private func convertPayments(
        ofYear year: Int, from before: [UniformRate], to after: [UniformRate], today: CivilDate,
        in database: Database
    ) async {
        do {
            guard try await database.yearSettings(year).incomeFXMethod == .uniform else { return }
            try await recomputePayments(year: year, in: database)
            let state = try await database.fxState(year: year, today: today)
            guard state.effective == .uniform, self.database === database,
                let text = ComputedRateBanner.text(year: year, before: before, after: after, paid: state.paidCurrencies)
            else {
                return
            }
            showBanner(text)
        } catch {
            Self.log("Converting the payments of a year at its computed uniform rate", failedWith: error)
        }
    }
}

/// What the green banner says once the preliminary uniform rate of a year changed and its payments were converted at
/// it (`AppModel.updateComputedUniformRates()`).
nonisolated enum ComputedRateBanner {
    /// The banner of `year`, whose computed rates changed from `before` to `after`, both by currency, and which was
    /// paid in `paid`. It names the rate of each currency of `after` among dollars and euros that the year was paid in,
    /// dollars first, joined with ", ", and with the rate it had before, when it had one ("1 USD ≈ 21,38 Kč (dříve
    /// 21,35)"):
    /// - a first rate: "Předběžný jednotný kurz 2027 je spočítaný z kurzu za leden: 1 USD ≈ 21,40 Kč. Platby roku 2027
    ///   jsou jím přepočtené.", or "z kurzů za leden–březen" over more months;
    /// - a rate over more months: "Předběžný jednotný kurz 2026 je přepočítaný i s kurzem za říjen: …" for one month
    ///   added, "i s kurzy za září a říjen" for two, and "i s kurzy za srpen–říjen" for three or more;
    /// - a rate over as many months or fewer, as when the ČNB rates changed or the clock went back: "Předběžný jednotný
    ///   kurz 2026 je přepočítaný: 1 USD ≈ 21,35 Kč (dříve 21,38). …".
    ///
    /// Nil when the year was paid in none of the currencies of `after`, as the banner would name no rate.
    static func text(year: Int, before: [UniformRate], after: [UniformRate], paid: [CurrencyCode]) -> String? {
        let named = UniformRate.currenciesEnteredByHand.compactMap { currency in
            paid.contains(currency) ? after.first { $0.currency == currency } : nil
        }
        guard !named.isEmpty, let months = after.compactMap(\.computedMonths).max() else { return nil }
        let rates = named.map { rate in
            let pill = BuilderText.uniformRate(rate)
            guard let earlier = before.first(where: { $0.currency == rate.currency }) else { return pill }
            return pill + " (dříve \(CzechFormat.rate(earlier.rate, fractionDigits: 2)))"
        }
        return "Předběžný jednotný kurz \(year) je \(change(over: months, from: before)): "
            + rates.joined(separator: ", ") + ". Platby roku \(year) jsou jím přepočtené."
    }

    /// How the rate over `months` months came to be, after the rates `before`: "spočítaný z kurzu za leden" or
    /// "spočítaný z kurzů za leden–březen" when there were none, "přepočítaný i s kurzem za říjen", "přepočítaný i s
    /// kurzy za září a říjen" or "přepočítaný i s kurzy za srpen–říjen" with months added, and "přepočítaný" without.
    private static func change(over months: Int, from before: [UniformRate]) -> String {
        guard let earlier = before.compactMap(\.computedMonths).max() else {
            return (months == 1 ? "spočítaný z kurzu za " : "spočítaný z kurzů za ") + BuilderText.monthSpan(months)
        }
        let names = CzechFormat.monthNames
        switch months - earlier {
        case ...0:
            return "přepočítaný"
        case 1:
            return "přepočítaný i s kurzem za \(names[months - 1])"
        case 2:
            return "přepočítaný i s kurzy za \(names[months - 2]) a \(names[months - 1])"
        default:
            return "přepočítaný i s kurzy za \(names[earlier])–\(names[months - 1])"
        }
    }
}
