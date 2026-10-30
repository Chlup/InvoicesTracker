import Foundation

nonisolated extension ReceiptEffect {
    /// What the receipt leaves of its income after the levies it adds, in haléře: its amount without VAT less the
    /// levies, which are whole Kč. It is more than the income when the levies are negative, because the receipt brings
    /// a tax bonus, and it is negative when the levies are more than the income, as the insurance has a minimum.
    var netHalere: Int64 {
        receipt.czkNetHalere - total * 100
    }
}

/// What an invoice leaves of the money it brings ("čistý příjem") after the levies that money adds, or would add: the
/// income of its payment, or of the payment expected for an invoice that is not paid, less what that income adds to the
/// tax, the social insurance and the health insurance of its year on its day (`TaxEngine.effect(of:in:)`, the effect
/// the detail of an invoice shows as "Dopad na odvody"). Each invoice is worked out on its own, as if its payment were
/// the last receipt of its day.
nonisolated struct InvoiceNetIncome: Sendable, Hashable {
    /// What the income adds to the levies of its year on its day, with the receipt it was worked out for.
    let effect: ReceiptEffect

    /// Whether the invoice is not paid, so that the figures are those of a payment expected, not of one received.
    let isEstimate: Bool

    /// Whether the payment is converted at a rate that stands in for the one it waits for, so that its figures change
    /// once the right rate is published (`Payment.provisional`). An estimate is not.
    let isProvisional: Bool

    /// The income in haléře: the amount without VAT, in crowns, of the payment or of the payment expected.
    var incomeHalere: Int64 {
        effect.receipt.czkNetHalere
    }

    /// The day the money came, or is expected. The year of it is the year of the levies.
    var day: CivilDate {
        effect.receipt.day
    }

    /// What the income leaves after the levies, in haléře (`ReceiptEffect.netHalere`).
    var netHalere: Int64 {
        effect.netHalere
    }
}

nonisolated extension InvoiceNetIncome {
    /// The day the money for `invoice` is expected when it is not paid: its due date, or `asOf` when that is later, as
    /// an invoice past its due date is awaited from the day shown on.
    static func expectedDay(of invoice: Invoice, asOf: CivilDate) -> CivilDate {
        max(invoice.dueDate, asOf)
    }

    /// The year the net of `invoice` is worked out in, or nil when it has none.
    ///
    /// For an invoice that is paid and counts as income (`InvoiceDetailBuilder.countsAsIncome`) it is the year of the
    /// payment, whatever the year of the invoice: money that comes in January for an invoice of December is income of
    /// the new year. For one that is not paid and not in review it is the year of `expectedDay(of:asOf:)`. An invoice
    /// that does not count as income has none.
    static func yearOfLevies(of invoice: Invoice, asOf: CivilDate) -> Int? {
        dayOfIncome(of: invoice, asOf: asOf)?.year
    }

    /// Whether the net of `invoice` needs a rate to be worked out: it is not paid, not in review, and not in crowns, so
    /// the amount expected has to be converted. The amount of a payment is in crowns already.
    static func needsRate(_ invoice: Invoice) -> Bool {
        invoice.payment == nil && invoice.review == nil && !invoice.currency.isCZK
    }

    /// The net of each of `invoices` that has one, by invoice id, as of `asOf`.
    ///
    /// A paid invoice that counts as income gets the receipt of its payment, on the day the money came: a payment dated
    /// after `asOf` has its net too. An invoice that is not paid and not in review gets a receipt dated on
    /// `expectedDay(of:asOf:)`. Its amounts are its net and its VAT as they are for an invoice in crowns, and converted
    /// at the rate in `rates` for its id for any other currency: without that rate it has no net. An invoice that does
    /// not count as income has none.
    ///
    /// The effect is `TaxEngine.effect(of:in:)` of the receipt in the year of its day in `years`, and a receipt of a
    /// year that `years` does not hold has no net either. The engine stops the app on an input it does not take, so the
    /// years must have been checked already (`AppModel.validate(_:)`).
    static func make(
        for invoices: [Invoice], asOf: CivilDate, rates: [Int64: ExchangeRate], years: [Int: YearInput]
    ) -> [Int64: InvoiceNetIncome] {
        var nets: [Int64: InvoiceNetIncome] = [:]
        for invoice in invoices {
            guard let receipt = receipt(of: invoice, asOf: asOf, rate: rates[invoice.id]),
                let input = years[receipt.day.year]
            else {
                continue
            }
            nets[invoice.id] = InvoiceNetIncome(
                effect: TaxEngine.effect(of: receipt, in: input), isEstimate: invoice.payment == nil,
                isProvisional: invoice.payment?.provisional ?? false)
        }
        return nets
    }

    /// The day the income of `invoice` counts on: the day of its payment when it is paid and counts as income, the day
    /// its money is expected when it is not paid and not in review, and nil otherwise.
    private static func dayOfIncome(of invoice: Invoice, asOf: CivilDate) -> CivilDate? {
        if let payment = invoice.payment {
            return InvoiceDetailBuilder.countsAsIncome(invoice) ? payment.date : nil
        }
        return invoice.review == nil ? expectedDay(of: invoice, asOf: asOf) : nil
    }

    /// The money `invoice` brings, as a receipt on its day of income (`dayOfIncome(of:asOf:)`): the amounts of its
    /// payment, or, when it is not paid, its own amounts, converted at `rate` unless they are in crowns. Nil when it
    /// has no day of income, and when it is not paid, in another currency and `rate` is nil.
    private static func receipt(of invoice: Invoice, asOf: CivilDate, rate: ExchangeRate?) -> Receipt? {
        guard let day = dayOfIncome(of: invoice, asOf: asOf) else { return nil }
        let net: Int64
        let vat: Int64
        if let payment = invoice.payment {
            net = payment.czkNetHalere
            vat = payment.czkVatHalere
        } else if invoice.currency.isCZK {
            net = invoice.netMinor
            vat = invoice.vatMinor
        } else if let rate {
            net = rate.czkHalere(fromMinor: invoice.netMinor)
            vat = rate.czkHalere(fromMinor: invoice.vatMinor)
        } else {
            return nil
        }
        return Receipt(day: day, czkNetHalere: net, czkVatHalere: vat, source: .invoice(invoice.id))
    }
}
