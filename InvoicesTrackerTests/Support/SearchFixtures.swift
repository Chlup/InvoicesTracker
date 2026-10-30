import Foundation
@testable import InvoicesTracker

/// The kinds of search table this SQLCipher build can create: the plain table always, and the full-text table when the
/// trigram tokenizer is there. The tests of the search run over all of them.
let availableSearchIndexKinds: [SearchIndexKind] = {
    supportsFTS5TrigramInThisBuild() ? [.fts5, .plain] : [.plain]
}()

private func supportsFTS5TrigramInThisBuild() -> Bool {
    do {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let path = directory.appending(path: "Probe.sqlite").path(percentEncoded: false)
        return try SQLiteConnection(path: path, key: randomKey()).supportsFTS5Trigram()
    } catch {
        preconditionFailure("The probe database could not be opened: \(error)")
    }
}

/// Invented clients and invoices for the tests of the search: a crown invoice and a dollar invoice of September 2026,
/// and a crown invoice of September 2025 for the client of the first.
enum SearchFixtures {
    /// Written like the client of `Invoice.fixture`.
    static let alfa = Client(
        name: "Alfa Systems s.r.o.", street: "Hlavní 1", postcode: "261 01", city: "Příbram", country: "CZ",
        ico: "12345678", dic: "CZ12345678", email: "ucetni@example.com"
    )

    static let bravo = Client(
        name: "Bravo Labs, Inc.", street: "100 Congress Avenue", postcode: "78701", city: "Austin, TX", country: "US",
        email: "billing@example.org", currency: .usd, vatMode: .outsideCountry, language: .en
    )

    /// 7,5 hours at 600,00 Kč and 21 % VAT: 4 500,00 Kč and 945,00 Kč VAT, 5 445,00 Kč in all. Supplied and issued on
    /// 30. 9. 2026, due on 14. 10. 2026, paid on 15. 10. 2026.
    static func crownInvoice(clientID: Int64? = nil) -> Invoice {
        var invoice = Invoice.fixture(number: "20260901", payment: .fixture(on: "2026-10-15"))
        invoice.clientID = clientID
        invoice.client = ClientSnapshot(client: alfa)
        return invoice
    }

    /// 205 hours at 70,00 USD without VAT: 14 350,00 USD, fixed at 21,359 on the day of supply, 30. 9. 2026, and paid
    /// on 2. 10. 2026 at 21,305, which is 305 726,75 Kč. The note has a placeholder for the routing number.
    static func dollarInvoice(clientID: Int64? = nil) -> Invoice {
        var invoice = Invoice.fixture(
            number: "20260902", currency: .usd, duzp: "2026-09-30", dueDate: "2026-10-30",
            items: [
                InvoiceItem(
                    description: "Software development", quantity: decimal("205"), unit: "hod", unitPriceMinor: 7_000)
            ],
            vatMode: .outsideCountry, invoiceRate: storedRate("USD", "21.359", declaredOn: "2026-09-30"),
            payment: Payment.fixture(
                on: "2026-10-02", conversion: .cnbDaily, net: 30_572_675, vat: 0,
                rate: storedRate("USD", "21.305", declaredOn: "2026-10-02"))
        )
        invoice.clientID = clientID
        invoice.client = ClientSnapshot(client: bravo)
        invoice.language = .en
        invoice.paymentMethod = "ACH transfer"
        invoice.note = "Routing number: [ROUTING NUMBER]"
        return invoice
    }

    /// The crown invoice of a year earlier: supplied and issued on 30. 9. 2025, due on 14. 10. 2025, paid on
    /// 10. 10. 2025.
    static func earlierCrownInvoice(clientID: Int64? = nil) -> Invoice {
        var invoice = Invoice.fixture(
            number: "20250901", duzp: "2025-09-30", dueDate: "2025-10-14", payment: .fixture(on: "2025-10-10"))
        invoice.clientID = clientID
        invoice.client = ClientSnapshot(client: alfa)
        return invoice
    }
}
