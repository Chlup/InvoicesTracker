import Foundation
@testable import InvoicesTracker

extension InvoiceItem {
    /// An item of invented text. `quantity` is plain POSIX decimal text such as `"6.5"`.
    static func fixture(_ quantity: String, at unitPriceMinor: Int64) -> InvoiceItem {
        InvoiceItem(description: "Vývoj", quantity: decimal(quantity), unit: "hod", unitPriceMinor: unitPriceMinor)
    }
}

extension Payment {
    /// The payment of the CZK invoice fixture (4 500,00 Kč and 945,00 Kč VAT) received on `day`, written as
    /// `YYYY-MM-DD`. Unless a test says otherwise it is a payment in crowns without a rate.
    static func fixture(
        on day: String,
        conversion: PaymentConversion = .czk,
        net: Int64 = 450_000,
        vat: Int64 = 94_500,
        rate: StoredRate? = nil,
        provisional: Bool = false,
        bankCZKTotalHalere: Int64? = nil
    ) -> Payment {
        Payment(
            date: civilDate(day), conversion: conversion, czkNetHalere: net, czkVatHalere: vat, rate: rate,
            provisional: provisional, bankCZKTotalHalere: bankCZKTotalHalere
        )
    }
}

extension Invoice {
    /// An issued invoice of invented data. Unless a test says otherwise it is for 7,5 hours at 600,00 Kč with 21 % VAT
    /// (4 500,00 Kč and 945,00 Kč VAT), supplied on 30 September 2026, issued the same day and due on 14 October
    /// 2026. Dates are written as `YYYY-MM-DD`. `issued` is the issue date, which is the `duzp` unless given.
    static func fixture(
        number: String = "20260901",
        currency: CurrencyCode = .czk,
        issued: String? = nil,
        duzp: String = "2026-09-30",
        dueDate: String = "2026-10-14",
        items: [InvoiceItem] = [.fixture("7.5", at: 60_000)],
        vatMode: VatMode = .domestic21,
        invoiceRate: StoredRate? = nil,
        status: InvoiceStatus = .issued,
        review: ReviewFlag? = nil,
        payment: Payment? = nil
    ) -> Invoice {
        Invoice(
            number: number, clientID: nil,
            client: ClientSnapshot(
                name: "Alfa Systems s.r.o.", street: "Hlavní 1", postcode: "261 01", city: "Příbram", country: "CZ",
                ico: "12345678", dic: "CZ12345678", email: "ucetni@example.com"
            ),
            currency: currency, issueDate: civilDate(issued ?? duzp), duzp: civilDate(duzp),
            dueDate: civilDate(dueDate), items: items, vatMode: vatMode, invoiceRate: invoiceRate, qrEnabled: false,
            note: "", language: .cs, paymentMethod: "Převodem", status: status, review: review, payment: payment,
            source: .app
        )
    }
}

extension Database {
    /// Marks the payment of the stored invoice `id` provisional, as a payment converted at the rate of its invoice
    /// while the rate of its day is not there, and returns the invoice as stored. The invoice must have a payment.
    @discardableResult
    func markPaymentProvisional(ofInvoice id: Int64) throws -> Invoice {
        guard var invoice = try invoice(id: id), invoice.payment != nil else { throw InvoiceError.notFound }
        invoice.payment?.provisional = true
        try saveInvoice(invoice)
        return invoice
    }

    /// Stores an invoice of no client that is issued and paid on `day` (`YYYY-MM-DD`), with a payment converted at a
    /// provisional rate, as one is while the rate of its day is not there, and returns its id.
    @discardableResult
    func saveInvoiceWithProvisionalPayment(on day: String) throws -> Int64 {
        let invoice = Invoice.fixture(
            number: "P" + day.replacingOccurrences(of: "-", with: ""), issued: day, duzp: day, dueDate: day,
            payment: Payment.fixture(on: day, provisional: true))
        return try saveInvoice(invoice)
    }
}

/// `amount` units of `code` cost `rate` crowns (plain POSIX decimal text), as the ČNB declared it on `day`.
func storedRate(_ code: String, _ rate: String, declaredOn day: String, amount: Int = 1) -> StoredRate {
    StoredRate(
        rate: ExchangeRate(currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate)),
        declaredOn: civilDate(day)
    )
}

/// The answer of a ČNB rate lookup for a rate of `amount` units of `code` that cost `rate` crowns and were declared on
/// `day`.
func declaredLookup(_ code: String, _ rate: String, on day: String, amount: Int = 1) -> RateLookupResult {
    let fixed = storedRate(code, rate, declaredOn: day, amount: amount)
    return .declared(fixed.rate, declaredOn: fixed.declaredOn)
}
