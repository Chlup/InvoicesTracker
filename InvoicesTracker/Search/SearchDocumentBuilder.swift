import Foundation

/// One text of an invoice that the search covers.
nonisolated struct SearchField: Sendable, Hashable {
    /// What the text is, as the list names it when it says why an invoice was found: "Poznámka" for the note.
    let label: String

    /// The text as the app writes it, not folded.
    let text: String

    /// Whether the table of the list shows this text. A match in it needs no explanation; a match in any other field
    /// does.
    let shownInTable: Bool
}

/// The texts of an invoice that the search covers, and the document made of them, which is what the search looks in.
/// A document comes from the invoice itself, the printed data of its client, its items, its payment and the rates
/// fixed on it, so nothing is looked up to make one. The one thing the invoice does not have, what its client is called
/// now, is added by `additionalDocument(forCurrent:besides:)`.
nonisolated enum SearchDocumentBuilder {
    /// The fields of `invoice`, in the order an excerpt looks for a match in them: the number, the client, the items,
    /// the amounts, the currency, the VAT mode, the dates, the payment method, the value in crowns and the rates, the
    /// payment, the status, the note and the source.
    ///
    /// An amount has three spellings (`14 350,00 USD`, `14350,00` and `14350.00`), a day four (`30. 9. 2026`,
    /// `30.9.2026`, `30.09.2026` and `2026-09-30`), so a person finds it however they write it. The status has
    /// words that do not depend on the day: "Koncept", "Vystavená", "uhrazená" and "ke kontrole". The value in crowns
    /// is that of a foreign invoice: what was paid when it is paid, otherwise the net at the rate fixed on the invoice.
    /// What an invoice does not have is not a field.
    static func fields(for invoice: Invoice) -> [SearchField] {
        var list = FieldList()
        list.add("Číslo", invoice.number, shownInTable: true)
        if invoice.numberDigits != invoice.number {
            list.add("Číslo", invoice.numberDigits, shownInTable: true)
        }
        list.add(clientFields(invoice.client))
        for item in invoice.items {
            list.add("Položka", item.description)
            list.add("Množství", quantityText(of: item))
            list.addAmount("Cena za jednotku", minor: item.unitPriceMinor, currency: invoice.currency)
        }
        let net = invoice.netMinor
        let vat = InvoiceMath.vat(netMinor: net, mode: invoice.vatMode)
        list.addAmount("Bez DPH", minor: net, currency: invoice.currency, shownInTable: true)
        if vat != 0 {
            list.addAmount("DPH", minor: vat, currency: invoice.currency)
            // The table has no column with the total with VAT, so a match on it is explained under the client.
            list.addAmount("S DPH", minor: net + vat, currency: invoice.currency)
        }
        list.add("Měna", invoice.currency.code, shownInTable: true)
        list.add("Režim DPH", invoice.vatMode.label)
        list.addDay("Vystaveno", invoice.issueDate, shownInTable: true)
        list.addDay("DUZP", invoice.duzp)
        list.addDay("Splatnost", invoice.dueDate)
        list.add("Měsíc DUZP", "\(CzechFormat.monthNames[invoice.duzp.month - 1]) \(invoice.duzp.year)")
        list.add("Způsob platby", invoice.paymentMethod)
        if invoice.isForeignCurrency, let crowns = valueInCrowns(of: invoice, net: net) {
            list.addAmount("V Kč", minor: crowns, currency: .czk, shownInTable: true)
        }
        if let rate = invoice.invoiceRate {
            list.add("Kurz k DUZP", CzechFormat.rate(rate.rate.rate))
        }
        if let payment = invoice.payment {
            list.addDay("Zaplaceno", payment.date, shownInTable: true)
            if let rate = payment.rate {
                list.add("Kurz platby", CzechFormat.rate(rate.rate.rate))
            }
        }
        list.add("Stav", statusText(of: invoice), shownInTable: true)
        list.add("Poznámka", invoice.note)
        if case .imported = invoice.source {
            list.add("Zdroj", "import z Fakturoidu")
        }
        return list.fields
    }

    /// The document of `invoice`: its fields folded and joined with " | ". A query finds the invoice when each of its
    /// words is somewhere in the document.
    static func document(for invoice: Invoice) -> String {
        document(of: fields(for: invoice))
    }

    /// The part of a document for a client whose printed data are not those of the snapshot an invoice took: the
    /// fields of `current` that the snapshot does not have (compared folded), folded and joined as in the document. It
    /// is empty when the client has not changed.
    ///
    /// An invoice is found by what it printed and by what its client is called now. Both are in the document of an
    /// invoice that is still linked to its client, the second after the first.
    static func additionalDocument(forCurrent current: ClientSnapshot, besides snapshot: ClientSnapshot) -> String {
        let known = Set(clientFields(snapshot).map { SearchFolding.fold($0.text) })
        let added = clientFields(current).map { SearchFolding.fold($0.text) }
        return added.filter { !$0.isEmpty && !known.contains($0) }.joined(separator: " | ")
    }

    // MARK: Pieces

    private static func document(of fields: [SearchField]) -> String {
        fields.map { SearchFolding.fold($0.text) }.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    private static func clientFields(_ client: ClientSnapshot) -> [SearchField] {
        var list = FieldList()
        list.add("Odběratel", client.name, shownInTable: true)
        list.add("Adresa", address(of: client))
        list.add("IČO", client.ico)
        list.add("DIČ", client.dic)
        list.add("E-mail", client.email)
        return list.fields
    }

    /// The street, the postcode with the city, and the country by its name in Czech (`Countries`), as far as the client
    /// has them.
    private static func address(of client: ClientSnapshot) -> String {
        let place = [client.postcode, client.city].filter { !$0.isBlank }.joined(separator: " ")
        let country = Countries.name(client.country, language: .cs)
        return [client.street, place, country].filter { !$0.isBlank }.joined(separator: ", ")
    }

    /// The quantity with a decimal comma and its unit: `6,5 hod`.
    private static func quantityText(of item: InvoiceItem) -> String {
        let quantity = DecimalMath.canonical(item.quantity).replacingOccurrences(of: ".", with: ",")
        return item.unit.isBlank ? quantity : quantity + " " + item.unit
    }

    /// What a foreign invoice is worth in haléře: what was paid, or its net at the rate fixed on it, or nothing when it
    /// is neither paid nor has a rate.
    private static func valueInCrowns(of invoice: Invoice, net: Int64) -> Int64? {
        if let payment = invoice.payment {
            return payment.czkNetHalere
        }
        return invoice.invoiceRate?.rate.czkHalere(fromMinor: net)
    }

    /// The words of the status that hold whatever the day is, so the document never goes stale as the days pass: a
    /// draft is "Koncept", an invoice that was issued is "Vystavená", with "uhrazená" when it has a payment and "ke
    /// kontrole" when it has a review flag.
    private static func statusText(of invoice: Invoice) -> String {
        if invoice.status == .draft {
            return "Koncept"
        }
        var words = ["Vystavená"]
        if invoice.payment != nil {
            words.append("uhrazená")
        }
        if invoice.review != nil {
            words.append("ke kontrole")
        }
        return words.joined(separator: ", ")
    }
}

// MARK: - The list of fields

/// The fields of an invoice as they are collected, with the spellings of amounts and days.
private nonisolated struct FieldList {
    private(set) var fields: [SearchField] = []

    private static let minus = "\u{2212}"

    /// A field, unless its text is empty.
    mutating func add(_ label: String, _ text: String, shownInTable: Bool = false) {
        guard !text.isBlank else { return }
        fields.append(SearchField(label: label, text: text, shownInTable: shownInTable))
    }

    mutating func add(_ more: [SearchField]) {
        fields += more
    }

    /// A field for each of the spellings, left out when the same spelling came before.
    private mutating func add(_ label: String, spellings: [String], shownInTable: Bool) {
        var written: [String] = []
        for spelling in spellings where !written.contains(spelling) {
            written.append(spelling)
            add(label, spelling, shownInTable: shownInTable)
        }
    }

    /// An amount as the app writes it with its currency (`14 350,00 USD`), then without the spaces and the currency
    /// (`14350,00`) and with a decimal point (`14350.00`). Without spaces the minus sign is the one on the keyboard.
    mutating func addAmount(_ label: String, minor: Int64, currency: CurrencyCode, shownInTable: Bool = false) {
        let typed = CzechFormat.amount(minor)
            .replacingOccurrences(of: CzechFormat.noBreakSpace, with: "")
            .replacingOccurrences(of: Self.minus, with: "-")
        add(
            label,
            spellings: [
                CzechFormat.money(Money(minor: minor, currency: currency)), typed,
                typed.replacingOccurrences(of: ",", with: "."),
            ],
            shownInTable: shownInTable
        )
    }

    /// A day as the app writes it (`30. 9. 2026`), without the spaces (`30.9.2026`), with two digits for the day and
    /// the month (`30.09.2026`) and as `2026-09-30`.
    mutating func addDay(_ label: String, _ day: CivilDate, shownInTable: Bool = false) {
        let twoDigits = { (number: Int) -> String in number < 10 ? "0\(number)" : "\(number)" }
        add(
            label,
            spellings: [
                CzechFormat.date(day), "\(day.day).\(day.month).\(day.year)",
                "\(twoDigits(day.day)).\(twoDigits(day.month)).\(day.year)", day.iso,
            ],
            shownInTable: shownInTable
        )
    }
}

private nonisolated extension String {
    /// Whether the text has no character other than whitespace.
    var isBlank: Bool {
        unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }
}
