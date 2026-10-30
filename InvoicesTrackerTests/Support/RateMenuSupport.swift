import Foundation
import Testing
@testable import InvoicesTracker

/// Stores the income of 2025 that the tests of the rate menu compare the conversions of, with the ČNB rates of dollars
/// and euros of 2025 it is converted with, and returns the invoices as stored, in this order:
/// - 1 500 000,00 Kč without VAT, paid on 10. 6. 2025, enough income for a conversion to move the levies;
/// - 10 000,00 USD, paid on 2. 10. 2025 at the ČNB rate of that day, 20,618 Kč (the uniform rate is 21,84 Kč);
/// - 4 000,00 EUR, paid on 14. 11. 2025 at the ČNB rate of that day (the uniform rate is 24,66 Kč);
/// - 3 000,00 EUR that the bank credited as 73 123,45 Kč on 10. 11. 2025, which no conversion changes.
@MainActor
@discardableResult
func storeForeignIncomeOf2025(in app: AppModel) async throws -> [Invoice] {
    let database = try #require(app.database)
    try await database.insertCNBRates(try cnbYearlyRows([2025]).filter { $0.currency == .usd || $0.currency == .eur })
    let paidAtTheirDays = [
        (invoice: incomeInvoice("20250601", .czk, 150_000_000, issued: "2025-06-01"), day: "2025-06-10"),
        (invoice: incomeInvoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), day: "2025-10-02"),
        (invoice: incomeInvoice("20251101", .eur, 400_000, issued: "2025-10-31"), day: "2025-11-14"),
    ]
    var stored: [Invoice] = []
    for (invoice, day) in paidAtTheirDays {
        var paid = invoice
        paid.payment = try await app.convert(invoice, paidOn: civilDate(day), method: .cnbDaily, in: database)
        paid.id = try await database.saveInvoice(paid)
        stored.append(paid)
    }
    var bank = incomeInvoice("20251102", .eur, 300_000, issued: "2025-11-03")
    bank.payment = Payment(
        date: civilDate("2025-11-10"), conversion: .bankCZK, czkNetHalere: 7_312_345, czkVatHalere: 0,
        bankCZKTotalHalere: 7_312_345)
    bank.id = try await database.saveInvoice(bank)
    stored.append(bank)
    await app.didWrite()
    return stored
}

/// An issued invoice of `amountMinor` hundredths of `currency` without VAT, supplied, issued and due on `issued`.
private func incomeInvoice(
    _ number: String, _ currency: CurrencyCode, _ amountMinor: Int64, issued: String
) -> Invoice {
    Invoice.fixture(
        number: number, currency: currency, duzp: issued, dueDate: issued, items: [.fixture("1", at: amountMinor)],
        vatMode: .outsideCountry)
}
