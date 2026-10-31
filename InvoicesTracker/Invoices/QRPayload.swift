import Foundation

/// What an invoice prints as its payment code.
nonisolated enum QRPayloadResult: Sendable, Hashable {
    /// The text of the code, and the label printed beside it: "QR Platba" on a Czech invoice and "QR payment" on an
    /// English one.
    case payload(String, label: String)

    /// There is no code, and this is why, as the editor shows it.
    case unavailable(String)
}

/// The texts of the payment codes: the QR Platba of the Czech banks for an invoice in crowns (SPAYD 1.0, qr-platba.cz)
/// and the EPC code of the SEPA credit transfer for an invoice in euros (version 002, UTF-8). `QRImage` draws them.
///
/// What goes into a code is cleaned first, so that no text a person typed can break the shape of the code: no value of
/// a QR Platba holds the `*` that separates its fields or a `%` that a reader could take for an escape, and no text of
/// an EPC code holds a line break.
nonisolated enum QRPayload {
    private static let czechLabel = "QR Platba"
    private static let englishLabel = "QR payment"

    private static let missingCzkIBAN = "Doplňte IBAN účtu v Kč v Nastavení › Moje údaje."
    private static let missingEurIBAN = "Doplňte IBAN účtu v eurech v Nastavení › Moje údaje."
    private static let missingSupplierName = "Doplňte jméno dodavatele v Nastavení › Moje údaje."
    private static let amountNotPositive = "Faktura nemá kladnou částku."
    private static let amountTooHigh = "Částka je pro QR kód příliš vysoká."
    private static let tooMuchData = "Údaje platby se do QR kódu nevejdou."

    /// A QR Platba has ten characters for the amount (`9999999.99`), so 9 999 999,99 Kč at most. An EPC code takes
    /// 0,01 to 999 999 999,99 euros. An amount of zero or below is allowed by neither.
    private static let largestSpaydAmountMinor: Int64 = 999_999_999
    private static let largestEpcAmountMinor: Int64 = 99_999_999_999

    /// An EPC code carries 331 bytes at most: what a QR code of version 13 holds at error correction level M.
    private static let largestEpcBytes = 331

    /// A variable symbol is at most ten digits.
    private static let variableSymbolLength = 10

    /// A message of a QR Platba is at most sixty characters.
    private static let messageLength = 60

    /// The name of the beneficiary of an EPC code is at most seventy characters, and the unstructured remittance at
    /// most a hundred and forty.
    private static let nameLength = 70
    private static let remittanceLength = 140

    // MARK: Invoice

    /// The code of `invoice`, or the reason why it has none.
    ///
    /// An invoice in crowns gets a QR Platba and one in euros an EPC code, each from the account of the invoice's
    /// currency in `accounts`; the supplier's name is the beneficiary of the EPC code. The amount is the total with
    /// VAT, and the message "Faktura <number>" on a Czech invoice and "Invoice <number>" on an English one. The
    /// variable symbol of a QR Platba is the digits of the number.
    ///
    /// There is no code, and the first of these reasons that applies is given, in this order:
    /// - the currency is another than crowns or euros;
    /// - there is no IBAN of the invoice's currency (the IBAN of another account is never used);
    /// - an invoice in euros has a supplier without a name, which an EPC code requires;
    /// - the total is not positive (an invoice whose items are not priced yet has none), or more than the code can
    ///   carry: 9 999 999,99 Kč in a QR Platba, 999 999 999,99 EUR in an EPC code;
    /// - an EPC code would be more than 331 bytes long.
    ///
    /// Whether the invoice wants its code (`qrEnabled`) is not decided here.
    static func payload(for invoice: Invoice, supplier: Supplier, accounts: [BankAccount]) -> QRPayloadResult {
        let currency = invoice.currency
        guard currency == .czk || currency == .eur else {
            return .unavailable("Pro platby v \(currency.code) QR standard není, faktura bude bez QR kódu.")
        }
        guard let account = accounts.first(where: { $0.currency == currency }), !compact(account.iban).isEmpty else {
            return .unavailable(currency == .czk ? missingCzkIBAN : missingEurIBAN)
        }
        if currency == .eur, epcText(supplier.name, limit: nameLength).isEmpty {
            return .unavailable(missingSupplierName)
        }
        let total = invoice.totalMinor
        guard total >= 1 else {
            return .unavailable(amountNotPositive)
        }
        guard total <= (currency == .czk ? largestSpaydAmountMinor : largestEpcAmountMinor) else {
            return .unavailable(amountTooHigh)
        }
        let isCzech = invoice.language == .cs
        let label = isCzech ? czechLabel : englishLabel
        let message = (isCzech ? "Faktura " : "Invoice ") + invoice.number
        if currency == .czk {
            let text = spayd(
                iban: account.iban, bic: account.bic, amountMinor: total,
                variableSymbol: InvoiceNumbering.variableSymbol(of: invoice.number), due: invoice.dueDate,
                message: message
            )
            return .payload(text, label: label)
        }
        let text = epc(
            name: supplier.name, iban: account.iban, bic: account.bic, amountMinor: total, remittance: message
        )
        guard text.utf8.count <= largestEpcBytes else {
            return .unavailable(tooMuchData)
        }
        return .payload(text, label: label)
    }

    // MARK: QR Platba

    /// A QR Platba: `SPD*1.0*ACC:<IBAN>+<BIC>*AM:<amount>*CC:CZK*X-VS:<symbol>*DT:<due date>*MSG:<message>`.
    ///
    /// - The IBAN and the BIC are written without spaces and in upper case; `+<BIC>` is left out when there is no BIC.
    /// - The amount has a point and exactly two decimals (`5445.00`) and no grouping.
    /// - The variable symbol is the digits of `variableSymbol`. A symbol is at most ten digits, so a longer one is left
    ///   out and never cut, which would pay another invoice; a symbol without digits is left out too.
    /// - The due date is written as `YYYYMMDD`.
    /// - The message is upper case, without diacritics and with ASCII characters only, at most sixty of them. A `*`
    ///   or a `%` becomes a space, and so does every character that has no ASCII form. The field is left out when
    ///   nothing is left of the message.
    ///
    /// The function writes whatever amount it is given (`payload(for:supplier:accounts:)` keeps to the range the code
    /// allows), and `iban` is not empty (`payload(for:supplier:accounts:)` makes sure of that).
    static func spayd(
        iban: String, bic: String, amountMinor: Int64, variableSymbol: String, due: CivilDate, message: String
    ) -> String {
        let bic = compact(bic)
        var fields = [
            "SPD", "1.0", "ACC:" + compact(iban) + (bic.isEmpty ? "" : "+" + bic), "AM:" + amountText(amountMinor),
            "CC:CZK",
        ]
        let symbol = InvoiceNumbering.digits(of: variableSymbol)
        if (1...variableSymbolLength).contains(symbol.utf8.count) {
            fields.append("X-VS:" + symbol)
        }
        fields.append("DT:" + due.iso.replacing("-", with: ""))
        let text = spaydMessage(message)
        if !text.isEmpty {
            fields.append("MSG:" + text)
        }
        return fields.joined(separator: "*")
    }

    /// The message of a QR Platba. The folding is the one of the search (Czech diacritics removed), and the rest is
    /// made of printable ASCII.
    private static func spaydMessage(_ message: String) -> String {
        let folded = SearchFolding.fold(message).uppercased()
        var allowed = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            allowed.append(isAllowedInMessage(scalar) ? scalar : " ")
        }
        let text = SearchFolding.collapsingWhitespace(String(allowed))
        return String(text.prefix(messageLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Printable ASCII, except the `*` that separates the fields and the `%` that starts an escape: a value writes a
    /// `*` as `%2A`, so a reader that decodes values would misread a `%` of the message.
    private static func isAllowedInMessage(_ scalar: Unicode.Scalar) -> Bool {
        (0x20...0x7E).contains(scalar.value) && scalar != "*" && scalar != "%"
    }

    // MARK: EPC

    /// An EPC code (version 002, character set UTF-8) for a transfer in euros: the lines `BCD`, `002`, `1`, `SCT`, the
    /// BIC (empty without one), the name of the beneficiary, the IBAN, `EUR<amount>`, an empty purpose, an empty
    /// structured reference and the remittance, joined with line breaks.
    ///
    /// - The IBAN and the BIC are written without spaces and in upper case.
    /// - The amount has a point and exactly two decimals (`EUR1210.00`) and no grouping.
    /// - The name is cut at 70 characters and the remittance at 140. A cut falls between two characters as a person
    ///   sees them, so a letter never loses its accent and a symbol is never torn apart, and it never leaves a space
    ///   at the end. A run of white space, a line break included, is one space.
    ///
    /// The function writes whatever amount and name it is given, and its text may be longer than an EPC code can be
    /// (`payload(for:supplier:accounts:)` keeps to the amount range, requires a name and checks the length).
    static func epc(name: String, iban: String, bic: String, amountMinor: Int64, remittance: String) -> String {
        [
            "BCD", "002", "1", "SCT", compact(bic), epcText(name, limit: nameLength), compact(iban),
            "EUR" + amountText(amountMinor), "", "", epcText(remittance, limit: remittanceLength),
        ].joined(separator: "\n")
    }

    /// `text` on one line, cut after as many characters as fit in `limit` Unicode scalars.
    private static func epcText(_ text: String, limit: Int) -> String {
        var kept = ""
        var scalars = 0
        for character in SearchFolding.collapsingWhitespace(text) {
            scalars += character.unicodeScalars.count
            guard scalars <= limit else { break }
            kept.append(character)
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Both

    /// An IBAN or a BIC as the codes carry it: the ASCII letters and digits of `code`, in upper case. The IBAN a
    /// person copies from a bank has spaces in it (`CZ65 0800 0000 1920 0014 5399`).
    private static func compact(_ code: String) -> String {
        String(String.UnicodeScalarView(code.unicodeScalars.filter(isASCIILetterOrDigit))).uppercased()
    }

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "0"..."9", "A"..."Z", "a"..."z": true
        default: false
        }
    }

    /// An amount in minor units with a point and exactly two decimals and no grouping: `5445.00`, `0.05`.
    private static func amountText(_ minor: Int64) -> String {
        let magnitude = minor.magnitude
        let fraction = magnitude % 100
        return (minor < 0 ? "-" : "") + String(magnitude / 100) + "." + (fraction < 10 ? "0" : "") + String(fraction)
    }
}
