import Foundation

/// The prediction of a year's income, loaded from what the data holds.
extension AppModel {
    /// The prediction of the whole income of `year` and the levies the engine works out from it, as of 31 December. It
    /// is made from today's data, whatever the reporting cutoff is (`asOf` is never read): "now" is today in the
    /// current year, and 31 December in any other (`PredictionInput.now(year:today:)`).
    ///
    /// Its input is the clients, the issued invoices of every year and the drafts of the year
    /// (`Database.predictionInvoices(year:)`), the templates, the person's choices of months for the year, and the
    /// receipts of the year. The receipts are those of the year's input of the engine (`yearInput(for:in:)`), loaded
    /// once and kept whole, also those dated after today, so the money the prediction counts as received is the money
    /// the engine counts.
    ///
    /// Drafts, unpaid invoices and empty-history template fallbacks in foreign currencies use the year's uniform
    /// rate when the year converts its income with the uniform rates
    /// (`YearFXState.effective`) and has one for the currency, otherwise at the latest ČNB rate of the currency on or
    /// before "now". The amounts of a currency with neither are unknown. With the uniform rates the prediction names no
    /// day of the rates. Otherwise it names the newest day the ČNB rates it used were declared on, or, when it used
    /// none (no currency but crowns, or no rate on or before "now"), "now", or the business day before it on a weekend
    /// or a holiday (`CzechCalendar.rateDeclarationDay(for:)`), so that the page always has a day to name.
    ///
    /// The annual mean separately converts each original net invoice amount with its daily ČNB rate: the actual
    /// payment day when received in the selected year, otherwise its issue day when expected in that year. Future
    /// issue lookup dates cap at real today. Missing conversions keep the mean unavailable. Stored payment
    /// conversions remain the authoritative actual receipts, including bank and uniform conversions.
    ///
    /// Throws `CancellationError` if the real day or open database changes during loading.
    /// Throws `VaultError.locked` while the data is locked, `ComputationError.invalidYear` for a year outside the
    /// calendar and for stored values the computation does not take, and what the database throws.
    func predictionOutcome(year: Int) async throws -> PredictionOutcome {
        guard let database else { throw VaultError.locked }
        guard CivilDate(year: year, month: 12, day: 31) != nil else { throw ComputationError.invalidYear(year) }
        let refresh = self.refresh
        let today = self.today
        let now = PredictionInput.now(year: year, today: today)
        let taxInput = try await Self.yearInput(for: year, in: database).input
        let clients = try await database.clients()
        let invoices = try await database.predictionInvoices(year: year)
        let templates = try await database.templates()
        let changes = try await database.expectedInvoiceMonths(year: year)
        var input = PredictionInput(
            year: year, today: today, clients: clients, invoices: invoices, templates: templates, changes: changes,
            receipts: taxInput.receipts, rates: [:], usesUniformRate: false, rateDay: nil)
        try Task.checkCancellation()
        guard self.database === database, self.today == today else { throw CancellationError() }
        input.averageRates = try await predictionRateLoader.load(
            keys: IncomePrediction.averageRateKeys(in: input), database: database, today: today,
            fetchYears: { years in
                guard let refresh else { return false }
                return await refresh.fetchYears(years)
            })
        // A fetched yearly file can also add a newer ordinary quote; use it in this outcome's drafts and waiting.
        let conversion = try await predictionRates(
            year: year, now: now, today: today, clients: clients, invoices: invoices, in: database)
        input.rates = conversion.rates
        input.usesUniformRate = conversion.usesUniformRate
        input.rateDay = conversion.rateDay
        try Task.checkCancellation()
        guard self.database === database, self.today == today else { throw CancellationError() }
        return try PredictionOutcome.make(prediction: IncomePrediction.make(input), yearInput: taxInput)
    }

    /// The rate of each foreign currency of `clients` and `invoices` that the prediction of `year` as of `now` converts
    /// with, whether the year converts with its uniform rates, and the day of the rates the page names, as
    /// `predictionOutcome(year:)` describes.
    private func predictionRates(
        year: Int, now: CivilDate, today: CivilDate, clients: [Client], invoices: [Invoice], in database: Database
    ) async throws -> (rates: [CurrencyCode: ExchangeRate], usesUniformRate: Bool, rateDay: CivilDate?) {
        let usesUniformRate = try await database.fxState(year: year, today: today).effective == .uniform
        var uniform: [CurrencyCode: ExchangeRate] = [:]
        if usesUniformRate {
            let uniformRates = try await database.uniformRates(year: year)
            uniform = Dictionary(uniqueKeysWithValues: uniformRates.map { ($0.currency, $0.exchangeRate) })
        }
        var rates: [CurrencyCode: ExchangeRate] = [:]
        var newest: CivilDate?
        let foreign = Set(clients.map(\.currency)).union(invoices.map(\.currency)).filter { !$0.isCZK }
        for currency in foreign.sorted() {
            if let rate = uniform[currency] {
                rates[currency] = rate
            } else if let latest = try await database.latestCNBRate(currency, onOrBefore: now) {
                rates[currency] = latest.rate
                newest = max(newest ?? latest.declaredOn, latest.declaredOn)
            }
        }
        let rateDay: CivilDate? = usesUniformRate ? nil : (newest ?? CzechCalendar.rateDeclarationDay(for: now))
        return (rates, usesUniformRate, rateDay)
    }
}
