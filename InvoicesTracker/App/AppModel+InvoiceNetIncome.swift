import Foundation

/// A currency on the day an invoice is expected to be paid: what a rate is looked up for. Many invoices are expected on
/// the same day, so each is looked up once.
private nonisolated struct ExpectedRateKey: Hashable {
    let currency: CurrencyCode
    let day: CivilDate
}

/// The net income of invoices, loaded from what the data holds.
extension AppModel {
    /// The net of each of `invoices` that has one, by invoice id, as of `asOf` ("K datu"): what the invoice leaves
    /// after the levies its payment adds, or would add (`InvoiceNetIncome`). The work is done away from the main actor
    /// (`invoiceNetIncomes(of:asOf:in:)`), which this waits for once.
    ///
    /// An invoice that is not paid and not in crowns is worth the latest ČNB rate of its currency declared on or before
    /// the day its money is expected (`InvoiceNetIncome.expectedDay(of:asOf:)`), or, when there is none, the rate fixed
    /// on the invoice. Each currency and day is looked up once. Each year the nets are worked out in
    /// (`InvoiceNetIncome.yearOfLevies(of:asOf:)`) is read once (`yearInput(for:in:)`) and checked (`validate(_:)`).
    ///
    /// Nothing is thrown. A rate that cannot be looked up and a year that cannot be read or computed are logged, and
    /// the invoices that need them have no net, while the others keep theirs. Locked data has no net at all.
    func invoiceNetIncomes(of invoices: [Invoice], asOf: CivilDate) async -> [Int64: InvoiceNetIncome] {
        guard let database else { return [:] }
        let worked = await Self.invoiceNetIncomes(of: invoices, asOf: asOf, in: database)
        for failure in worked.failures {
            Self.log("Working out the net income of invoices", failedWith: failure)
        }
        return worked.nets
    }

    /// The nets of `invoices` as `invoiceNetIncomes(of:asOf:)` works them out, read from `database`, and the errors of
    /// what could not be read. All of it is done away from the main actor: the lookups of the rates, the reading and
    /// the checking of the years, and the levies of each invoice, which can take a while for a long list.
    ///
    /// It logs nothing. Each lookup of a rate that fails and each year that cannot be read or computed gives one error
    /// in `failures`, the rates first and then the years oldest first, and the invoices that need them have no net,
    /// while the others keep theirs.
    @concurrent
    nonisolated static func invoiceNetIncomes(
        of invoices: [Invoice], asOf: CivilDate, in database: Database
    ) async -> (nets: [Int64: InvoiceNetIncome], failures: [any Error]) {
        let rates = await expectedRates(of: invoices, asOf: asOf, in: database)
        let years = await yearInputs(of: invoices, asOf: asOf, in: database)
        let nets = InvoiceNetIncome.make(for: invoices, asOf: asOf, rates: rates.byInvoice, years: years.byYear)
        return (nets, rates.failures + years.failures)
    }

    /// The rate that each invoice of `invoices` that needs one (`InvoiceNetIncome.needsRate(_:)`) is converted at, by
    /// invoice id: the latest ČNB rate of its currency declared on or before the day its money is expected, otherwise
    /// the rate fixed on the invoice, which may be none. A lookup that fails gives one error in `failures`, and the
    /// invoices that need it have no rate: the rate of the invoice is no stand-in for one that could not be looked up.
    private nonisolated static func expectedRates(
        of invoices: [Invoice], asOf: CivilDate, in database: Database
    ) async -> (byInvoice: [Int64: ExchangeRate], failures: [any Error]) {
        var lookups: [ExpectedRateKey: Result<ExchangeRate?, any Error>] = [:]
        var rates: [Int64: ExchangeRate] = [:]
        var failures: [any Error] = []
        for invoice in invoices where InvoiceNetIncome.needsRate(invoice) {
            let key = ExpectedRateKey(
                currency: invoice.currency, day: InvoiceNetIncome.expectedDay(of: invoice, asOf: asOf))
            let lookup: Result<ExchangeRate?, any Error>
            if let known = lookups[key] {
                lookup = known
            } else {
                do {
                    lookup = .success(try await database.latestCNBRate(key.currency, onOrBefore: key.day)?.rate)
                } catch {
                    failures.append(error)
                    lookup = .failure(error)
                }
                lookups[key] = lookup
            }
            if case .success(let latest) = lookup, let rate = latest ?? invoice.invoiceRate?.rate {
                rates[invoice.id] = rate
            }
        }
        return (rates, failures)
    }

    /// The input of the engine for each year that the nets of `invoices` are worked out in, by year: read once for all
    /// the invoices (`yearInput(for:in:)`) and checked (`validate(_:)`). A year that cannot be read or that the engine
    /// does not take gives one error in `failures` and is left out, and so are the invoices of that year.
    private nonisolated static func yearInputs(
        of invoices: [Invoice], asOf: CivilDate, in database: Database
    ) async -> (byYear: [Int: YearInput], failures: [any Error]) {
        let years = Set(invoices.compactMap { InvoiceNetIncome.yearOfLevies(of: $0, asOf: asOf) })
        var inputs: [Int: YearInput] = [:]
        var failures: [any Error] = []
        for year in years.sorted() {
            do {
                let input = try await yearInput(for: year, in: database).input
                try validate(input)
                inputs[year] = input
            } catch {
                failures.append(error)
            }
        }
        return (inputs, failures)
    }
}
