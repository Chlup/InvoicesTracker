import Foundation

/// Works out what the payment of an invoice is worth as income in crowns, the net and the VAT apart.
///
/// The amounts are in haléře. A payment that has to be converted with a ČNB rate which is not known yet (not declared,
/// or not stored) is provisional: it is worked out with a stand-in and again when the rate arrives. A uniform rate that
/// is not there is no reason to wait: a year without it is converted at the ČNB rates of the days (`YearFXState`).
nonisolated enum PaymentConverter {
    /// The payment of `invoice` that was received on `date`.
    ///
    /// - An invoice in crowns is worth its own net and VAT, whatever method is asked for: the payment is `.czk`.
    /// - `.bankCZK`: `bankCZKTotalHalere`, the amount in crowns the bank credited for the whole invoice, is split into
    ///   the net and the VAT in the proportion of the invoice (all of it is net when the invoice has no VAT). Without
    ///   an amount the payment is worth nothing yet, and the caller must not save it.
    /// - `.cnbDaily`: the net and the VAT are converted with the rate in `cnbRate`. When it is not available (not
    ///   declared yet, or not published for the currency) the rate fixed on the invoice stands in and the payment is
    ///   provisional. Without that, the payment is worth nothing and provisional.
    /// - `.uniform`: the net and the VAT are converted with `uniformRate`, which counts as declared on 31 December of
    ///   the year of the payment. Without it the payment is what `.cnbDaily` gives: a year that does not have its
    ///   uniform rate for the currency is converted at the ČNB rates of the days, and so is the payment.
    /// - `.czk` for an invoice in a foreign currency is converted like `.cnbDaily`, because money in another currency
    ///   cannot be worth its own amounts.
    ///
    /// - Parameters:
    ///   - invoice: The invoice that was paid.
    ///   - date: The day the money was received. The year of it is the year of the income.
    ///   - requested: The method to convert with.
    ///   - bankCZKTotalHalere: The amount in crowns the bank credited, if it was entered.
    ///   - cnbRate: The ČNB rate valid on `date` for the currency of the invoice.
    ///   - uniformRate: The uniform annual rate of the year of `date` for the currency of the invoice, if it is known.
    static func convert(
        invoice: Invoice, date: CivilDate, requested: PaymentConversion, bankCZKTotalHalere: Int64?,
        cnbRate: RateLookupResult, uniformRate: ExchangeRate?
    ) -> Payment {
        guard !invoice.currency.isCZK else {
            return Payment(date: date, conversion: .czk, czkNetHalere: invoice.netMinor, czkVatHalere: invoice.vatMinor)
        }
        switch requested {
        case .bankCZK:
            let parts = split(bankCZKTotalHalere ?? 0, of: invoice)
            return Payment(
                date: date, conversion: .bankCZK, czkNetHalere: parts.net, czkVatHalere: parts.vat,
                bankCZKTotalHalere: bankCZKTotalHalere
            )
        case .uniform:
            guard let uniformRate else {
                return convertedByCNB(invoice: invoice, date: date, cnbRate: cnbRate)
            }
            let rate = StoredRate(rate: uniformRate, declaredOn: lastDay(of: date.year))
            return converted(invoice: invoice, date: date, conversion: .uniform, rate: rate, provisional: false)
        case .cnbDaily, .czk:
            return convertedByCNB(invoice: invoice, date: date, cnbRate: cnbRate)
        }
    }

    /// `payment` worked out again for `invoice`, after the invoice was edited: the day and the method stay, and so do
    /// the rate and whether it is provisional.
    ///
    /// - `.cnbDaily` and `.uniform`: the stored rate is applied to the new net and VAT.
    /// - `.bankCZK`: the amount the bank credited stays and is split in the proportion of the new net and VAT.
    /// - `.czk`: the payment takes the new net and VAT of the invoice.
    ///
    /// A payment is not reapplied when it has no rate to apply or no bank amount to split: that is a payment worth
    /// nothing yet, which is converted afresh and not reapplied. If it is reapplied anyway, it is returned as it is.
    static func reapply(_ payment: Payment, to invoice: Invoice) -> Payment {
        var result = payment
        switch payment.conversion {
        case .czk:
            result.czkNetHalere = invoice.netMinor
            result.czkVatHalere = invoice.vatMinor
        case .cnbDaily, .uniform:
            guard let stored = payment.rate else { return payment }
            result.czkNetHalere = stored.rate.czkHalere(fromMinor: invoice.netMinor)
            result.czkVatHalere = stored.rate.czkHalere(fromMinor: invoice.vatMinor)
        case .bankCZK:
            guard let bank = payment.bankCZKTotalHalere else { return payment }
            let parts = split(bank, of: invoice)
            result.czkNetHalere = parts.net
            result.czkVatHalere = parts.vat
        }
        return result
    }

    // MARK: Helpers

    /// The conversion at the ČNB rate of the day, or at the rate of the invoice until that is known.
    private static func convertedByCNB(invoice: Invoice, date: CivilDate, cnbRate: RateLookupResult) -> Payment {
        if case .declared(let rate, let declaredOn) = cnbRate {
            let stored = StoredRate(rate: rate, declaredOn: declaredOn)
            return converted(invoice: invoice, date: date, conversion: .cnbDaily, rate: stored, provisional: false)
        }
        if let invoiceRate = invoice.invoiceRate {
            return converted(invoice: invoice, date: date, conversion: .cnbDaily, rate: invoiceRate, provisional: true)
        }
        return Payment(date: date, conversion: .cnbDaily, czkNetHalere: 0, czkVatHalere: 0, provisional: true)
    }

    private static func converted(
        invoice: Invoice, date: CivilDate, conversion: PaymentConversion, rate: StoredRate, provisional: Bool
    ) -> Payment {
        Payment(
            date: date, conversion: conversion, czkNetHalere: rate.rate.czkHalere(fromMinor: invoice.netMinor),
            czkVatHalere: rate.rate.czkHalere(fromMinor: invoice.vatMinor), rate: rate, provisional: provisional
        )
    }

    /// `bank` haléře for the whole invoice, divided into the net, rounded half up, and the VAT, which is the rest. An
    /// invoice without VAT is all net.
    private static func split(_ bank: Int64, of invoice: Invoice) -> (net: Int64, vat: Int64) {
        let invoiceNet = invoice.netMinor
        let invoiceVat = InvoiceMath.vat(netMinor: invoiceNet, mode: invoice.vatMode)
        guard invoiceVat != 0 else { return (net: bank, vat: 0) }
        // A VAT that is not 0 has the sign of the net, so the total is not 0 either.
        let net = DecimalMath.halfUp(Decimal(bank) * Decimal(invoiceNet) / Decimal(invoiceNet + invoiceVat))
        return (net: net, vat: bank - net)
    }

    private static func lastDay(of year: Int) -> CivilDate {
        guard let day = CivilDate(year: year, month: 12, day: 31) else {
            preconditionFailure("31 December \(year) is not a date in the years 1 to 9999.")
        }
        return day
    }
}
