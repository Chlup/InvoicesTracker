import Foundation

/// The arithmetic of an invoice, in the minor units of its currency (hundredths, haléře for crowns).
nonisolated enum InvoiceMath {
    /// The amount of an item: the quantity times the price of one unit, rounded half up to a minor unit.
    /// Traps if the result does not fit in `Int64`.
    static func itemAmount(quantity: Decimal, unitPriceMinor: Int64) -> Int64 {
        DecimalMath.halfUp(quantity * Decimal(unitPriceMinor))
    }

    /// The VAT on an invoice whose items add up to `netMinor`: the rate of `mode` in percent of the net, rounded half
    /// up to a minor unit. It is worked out once for the invoice, not for each item.
    static func vat(netMinor: Int64, mode: VatMode) -> Int64 {
        DecimalMath.halfUp(Decimal(netMinor) * Decimal(mode.ratePercent) / 100)
    }
}

nonisolated extension Invoice {
    /// The amount without VAT: the sum of the items, each rounded to a minor unit on its own.
    var netMinor: Int64 {
        items.reduce(0) { sum, item in
            sum + InvoiceMath.itemAmount(quantity: item.quantity, unitPriceMinor: item.unitPriceMinor)
        }
    }

    /// The VAT, on the net of the whole invoice.
    var vatMinor: Int64 {
        InvoiceMath.vat(netMinor: netMinor, mode: vatMode)
    }

    /// The amount to pay: the net and the VAT.
    var totalMinor: Int64 {
        let net = netMinor
        return net + InvoiceMath.vat(netMinor: net, mode: vatMode)
    }

    /// The digits of the number, which is what numbers are unique by and what the variable symbol is.
    var numberDigits: String {
        InvoiceNumbering.digits(of: number)
    }

    /// Whether the invoice is in a currency other than crowns, so that it has a CZK equivalent to work out.
    var isForeignCurrency: Bool {
        !currency.isCZK
    }
}
