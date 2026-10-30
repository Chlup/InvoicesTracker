import Foundation
@testable import InvoicesTracker

/// The twelve invoices of a sample year 2026, numbered 1 to 12 in the order they were written, with their payments
/// and rates as of 17 October 2026. The amounts, dates and rates are those of the sample year; the clients, their
/// addresses and their numbers are invented (Alfa Systems, Bravo Labs and Cetus Data). The payments are the eleven of
/// the engine's regression year (`TaxEngineRegressionTests.sampleYear2026`), which have the same ids. The last invoice
/// is a draft in dollars that is not paid. The tests that use it expect figures and texts that were worked out for the
/// same data by a separate implementation, so they check the builders against something other than themselves.
enum SampleYear2026 {
    /// The invented clients of the sample year. Alfa and Bravo are those of the search fixtures.
    static let alfa = ClientSnapshot(client: SearchFixtures.alfa)
    static let bravo = ClientSnapshot(client: SearchFixtures.bravo)
    static let cetus = ClientSnapshot(
        name: "Cetus Data s.r.o.", street: "Zahradní 5", postcode: "602 00", city: "Brno", country: "CZ",
        ico: "87654321", dic: "CZ87654321", email: "fakturace@example.com")

    /// One invoice of the sample: `rates` are the ČNB rates of the day it was issued and, once it is paid, of the day
    /// the money arrived; they only exist for an invoice in dollars.
    private struct Entry {
        var number: String
        var client: ClientSnapshot
        var currency: CurrencyCode
        var quantity: String
        var unit: String
        var unitPriceMinor: Int64
        var issueDate: String
        var dueDate: String
        var paidOn: String?
        var issueDayRate: String?
        var paymentDayRate: String?
    }

    /// 1 250,00 Kč an hour for Alfa Systems, 600,00 Kč for Cetus Data, 70,00 USD for Bravo Labs.
    private static let entries: [Entry] = [
        Entry(
            number: "2026-01-01", client: alfa, currency: .czk, quantity: "176", unit: "hod",
            unitPriceMinor: 125_000, issueDate: "2026-01-31", dueDate: "2026-02-15", paidOn: "2026-02-03"),
        Entry(
            number: "2026-02-01", client: alfa, currency: .czk, quantity: "152", unit: "hod",
            unitPriceMinor: 125_000, issueDate: "2026-02-28", dueDate: "2026-03-14", paidOn: "2026-03-03"),
        Entry(
            number: "2026-03-01", client: alfa, currency: .czk, quantity: "168", unit: "hod",
            unitPriceMinor: 125_000, issueDate: "2026-03-31", dueDate: "2026-04-15", paidOn: "2026-04-07"),
        Entry(
            number: "2026-04-01", client: alfa, currency: .czk, quantity: "168", unit: "hod",
            unitPriceMinor: 125_000, issueDate: "2026-04-30", dueDate: "2026-05-15", paidOn: "2026-04-10"),
        Entry(
            number: "2026-05-01", client: alfa, currency: .czk, quantity: "168", unit: "hod",
            unitPriceMinor: 125_000, issueDate: "2026-05-29", dueDate: "2026-06-15", paidOn: "2026-05-05"),
        Entry(
            number: "20260601", client: bravo, currency: .usd, quantity: "196", unit: "h",
            unitPriceMinor: 7_000, issueDate: "2026-06-30", dueDate: "2026-07-30", paidOn: "2026-07-07",
            issueDayRate: "21.287", paymentDayRate: "21.050"),
        Entry(
            number: "20260701", client: bravo, currency: .usd, quantity: "184", unit: "h",
            unitPriceMinor: 7_000, issueDate: "2026-07-31", dueDate: "2026-08-30", paidOn: "2026-08-07",
            issueDayRate: "21.076", paymentDayRate: "20.870"),
        Entry(
            number: "20260801", client: cetus, currency: .czk, quantity: "7.5", unit: "hod",
            unitPriceMinor: 60_000, issueDate: "2026-08-18", dueDate: "2026-09-17", paidOn: "2026-08-26"),
        Entry(
            number: "20260802", client: bravo, currency: .usd, quantity: "190", unit: "h",
            unitPriceMinor: 7_000, issueDate: "2026-08-31", dueDate: "2026-09-30", paidOn: "2026-09-09",
            issueDayRate: "20.800", paymentDayRate: "21.010"),
        Entry(
            number: "20260901", client: bravo, currency: .usd, quantity: "205", unit: "h",
            unitPriceMinor: 7_000, issueDate: "2026-09-30", dueDate: "2026-10-30", paidOn: "2026-10-02",
            issueDayRate: "21.359", paymentDayRate: "21.305"),
        Entry(
            number: "20260902", client: cetus, currency: .czk, quantity: "7.5", unit: "hod",
            unitPriceMinor: 60_000, issueDate: "2026-09-30", dueDate: "2026-10-30", paidOn: "2026-10-15"),
        Entry(
            number: "20261001", client: bravo, currency: .usd, quantity: "172", unit: "h",
            unitPriceMinor: 7_000, issueDate: "2026-10-31", dueDate: "2026-11-30", issueDayRate: "21.622"),
    ]

    /// The invoices, as of 17 October 2026: all paid except the last, which is a draft.
    static let invoices: [Invoice] = entries.enumerated().map { index, entry in
        var invoice = Invoice.fixture(
            number: entry.number, currency: entry.currency, issued: entry.issueDate, duzp: entry.issueDate,
            dueDate: entry.dueDate,
            items: [
                InvoiceItem(
                    description: "Služby", quantity: decimal(entry.quantity), unit: entry.unit,
                    unitPriceMinor: entry.unitPriceMinor)
            ],
            vatMode: entry.currency.isCZK ? .domestic21 : .outsideCountry,
            status: entry.paidOn == nil ? .draft : .issued)
        invoice.id = Int64(index + 1)
        invoice.client = entry.client
        if let paidOn = entry.paidOn {
            let lookup = entry.paymentDayRate.map { declaredLookup("USD", $0, on: paidOn) } ?? .notYetAvailable
            invoice.payment = PaymentConverter.convert(
                invoice: invoice, date: civilDate(paidOn), requested: .cnbDaily, bankCZKTotalHalere: nil,
                cnbRate: lookup, uniformRate: nil)
        }
        return invoice
    }

    /// By invoice id, the ČNB rate of the day the money arrived, for the paid invoices in dollars.
    static let paymentDayRates: [Int64: ExchangeRate] = rates { $0.paymentDayRate }

    /// By invoice id, the ČNB rate of the day of issue, for the invoices in dollars.
    static let issueDayRates: [Int64: ExchangeRate] = rates { $0.issueDayRate }

    private static func rates(_ rate: (Entry) -> String?) -> [Int64: ExchangeRate] {
        var result: [Int64: ExchangeRate] = [:]
        for (index, entry) in entries.enumerated() {
            if let text = rate(entry) {
                result[Int64(index + 1)] = ExchangeRate(currency: .usd, amount: 1, rate: decimal(text))
            }
        }
        return result
    }

    /// The rows the chart of the overview is made of.
    static let chartRows: [InvoiceChartRow] = invoices.map { invoice in
        InvoiceChartRow(
            id: invoice.id, issueDate: invoice.issueDate, isDraft: invoice.status == .draft, inReview: false,
            currency: invoice.currency, netMinor: invoice.netMinor, vatMinor: invoice.vatMinor,
            paymentDate: invoice.payment?.date, paymentNetHalere: invoice.payment?.czkNetHalere,
            paymentVatHalere: invoice.payment?.czkVatHalere, issueDayRate: issueDayRates[invoice.id]
        )
    }
}

// MARK: - In a database

/// Why the sample year could not be stored as it is numbered.
enum SampleYearError: Error {
    /// The database numbered an invoice differently from `SampleYear2026.invoices`, because it was not empty.
    case idsDiffer(expected: Int64, stored: Int64)
}

extension SampleYear2026 {
    /// The settings of the sample year, as the engine's regression year has them: 60 % flat-rate expenses, main
    /// activity all year, mortgage interest of 219 000 Kč (above the limit), life insurance of 6 480 Kč, the taxpayer
    /// credit and the advance plan that drops from May.
    static let yearSettings: YearSettings = {
        let regression = TaxEngineRegressionTests.sampleYear2026
        var settings = YearSettings(year: 2026)
        settings.expensePercent = regression.expensePercent
        settings.deductions = regression.deductions
        settings.advances = regression.advances
        return settings
    }()

    /// Stores the sample year in `database`, which must be empty: its settings, the ČNB rates of the fixtures for
    /// dollars and euros and the twelve invoices, which the database numbers 1 to 12 as `invoices` does. Throws
    /// `SampleYearError.idsDiffer` when it does not.
    static func store(in database: Database) async throws {
        try await database.saveYearSettings(yearSettings)
        let rates = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rates)
        for sample in invoices {
            var invoice = sample
            invoice.id = 0
            let stored = try await database.saveInvoice(invoice)
            guard stored == sample.id else {
                throw SampleYearError.idsDiffer(expected: sample.id, stored: stored)
            }
        }
    }
}
