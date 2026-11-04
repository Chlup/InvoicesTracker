import Foundation

/// An invoice a budget can be made from, with the figures the budget divides.
nonisolated struct BudgetInvoice: Sendable, Hashable {
    /// The invoice, with its items and payment.
    var invoice: Invoice

    /// What the invoice leaves after its levies, or nil when that cannot be worked out, for instance because a rate
    /// could not be looked up.
    var net: InvoiceNetIncome?

    /// The income of the invoice without VAT in whole Kč, or nil without a net.
    var incomeKc: Int64? {
        net.map { DecimalMath.halfUp(Decimal($0.incomeHalere) / 100) }
    }

    /// The VAT of the invoice in whole Kč, 0 without a net.
    var vatKc: Int64 {
        guard let net else { return 0 }
        return DecimalMath.halfUp(Decimal(net.effect.receipt.czkVatHalere) / 100)
    }

    /// The levies the income adds, in whole Kč (`ReceiptEffect.total`), or nil without a net.
    var leviesKc: Int64? {
        net?.effect.total
    }
}

extension AppModel {
    /// The invoices a budget of the selected year can be made from: the paid ones up to `receivedThrough` and the
    /// unpaid ones issued in the year (`Database.budgetInvoices(year:asOf:)`), each with its net as of
    /// `receivedThrough` (`invoiceNetIncomes(of:asOf:)`). An invoice whose net cannot be worked out is listed without
    /// one. Throws `VaultError.locked` while the data is locked.
    func budgetInvoices() async throws -> [BudgetInvoice] {
        guard let database else { throw VaultError.locked }
        let day = receivedThrough
        let invoices = try await database.budgetInvoices(year: asOf.year, asOf: day)
        let nets = await invoiceNetIncomes(of: invoices, asOf: day)
        return invoices.map { BudgetInvoice(invoice: $0, net: nets[$0.id]) }
    }
}
