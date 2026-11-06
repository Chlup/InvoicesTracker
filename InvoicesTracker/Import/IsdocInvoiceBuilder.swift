import Foundation

/// Turns an `IsdocInvoice` into the parts of an invoice of the app that need a rule: the items, the VAT mode, the
/// stored rate and the payment method.
nonisolated enum IsdocInvoiceBuilder {
    /// The items of the invoice, in the order of the file, and a note for every line that could not be taken as it is.
    ///
    /// A line becomes an item with its quantity and unit. The unit price is the `UnitPrice` of the file for an invoice
    /// in crowns, and the amount of the line divided by the quantity for one in a foreign currency, because the file
    /// writes the price of a foreign invoice in crowns. A line whose price times quantity does not give its amount
    /// exactly, by the rule of `InvoiceMath`, or whose quantity is 0, becomes one item of quantity 1 without a unit at
    /// the amount of the line, and the notes say so.
    static func items(of isdoc: IsdocInvoice) -> (items: [InvoiceItem], notes: [String]) {
        var items: [InvoiceItem] = []
        var notes: [String] = []
        for line in isdoc.lines {
            if let price = unitPrice(of: line, inCrowns: isdoc.currency == "CZK") {
                items.append(
                    InvoiceItem(
                        description: line.description, quantity: line.quantity, unit: line.unit,
                        unitPriceMinor: price
                    )
                )
            } else {
                items.append(
                    InvoiceItem(
                        description: line.description, quantity: 1, unit: "", unitPriceMinor: line.lineAmountMinor
                    )
                )
                notes.append("\(isdoc.number) — položka „\(line.description)“ převzata jako 1 × částka řádku")
            }
        }
        return (items, notes)
    }

    /// The price of one unit of `line` in minor units of the invoice currency, or nil when no whole price times the
    /// quantity gives the amount of the line exactly.
    private static func unitPrice(of line: IsdocLine, inCrowns: Bool) -> Int64? {
        guard line.quantity != 0 else { return nil }
        let price: Int64
        if inCrowns {
            guard let given = line.unitPriceCZKMinor else { return nil }
            price = given
        } else {
            let divided = Decimal(line.lineAmountMinor) / line.quantity
            let whole = DecimalMath.halfUp(divided)
            guard Decimal(whole) == divided else { return nil }
            price = whole
        }
        let amount = InvoiceMath.itemAmount(quantity: line.quantity, unitPriceMinor: price)
        return amount == line.lineAmountMinor ? price : nil
    }

    /// The VAT mode of the invoice from the rates of its lines, or nil when the lines have different rates or one the
    /// app has no mode for.
    ///
    /// 21 % is `.domestic21` and 12 % is `.domestic12`. At 0 %, an `existing` mode without VAT is kept. Otherwise 0 %
    /// is `.outsideCountry` for a known country outside the EU, and no VAT for any other.
    static func vatMode(of isdoc: IsdocInvoice, existing: VatMode?, clientCountry: String) -> VatMode? {
        let rates = Set(isdoc.lines.map(\.vatPercent))
        guard rates.count == 1, let rate = rates.first else { return nil }
        switch rate {
        case 21:
            return .domestic21
        case 12:
            return .domestic12
        case 0:
            if let existing, existing.ratePercent == 0 {
                return existing
            }
            if clientCountry.count == 2, !ImportPlanner.euCountries.contains(clientCountry) {
                return .outsideCountry
            }
            return VatMode.none
        default:
            return nil
        }
    }

    /// The rate the invoice is converted at: the crowns for one unit of its currency, declared on the declaration day
    /// of the DUZP. Nil for an invoice in crowns and for one the file gives no rate.
    static func invoiceRate(of isdoc: IsdocInvoice, duzp: CivilDate) -> StoredRate? {
        guard let rate = isdoc.rate, let currency = CurrencyCode(isdoc.currency), !currency.isCZK else {
            return nil
        }
        return StoredRate(
            rate: ExchangeRate(currency: currency, amount: 1, rate: rate),
            declaredOn: CzechCalendar.rateDeclarationDay(for: duzp)
        )
    }

    /// The payment method an invoice in `language` prints for the `PaymentMeansCode` of the file: 42, a payment to a
    /// bank account, is a transfer. Nil for any other code.
    static func paymentMethod(code: String, language: InvoiceLanguage) -> String? {
        guard code == "42" else { return nil }
        switch language {
        case .cs: return "Převodem"
        case .en: return "Bank transfer"
        }
    }
}
