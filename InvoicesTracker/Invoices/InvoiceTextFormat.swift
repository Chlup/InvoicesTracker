import Foundation

/// The words of the invoice layout in one language: the headings, the labels of the blocks and the heads of the
/// columns. They are those of the layout, word for word. The label of the QR code comes with the code itself
/// (`QRPayloadResult`).
nonisolated struct InvoiceLabels: Sendable, Hashable {
    /// "Faktura" or "Invoice", in front of the number, and the line under it.
    var document: String
    var subtitle: String

    /// The heads of the two blocks of the parties.
    var supplier: String
    var customer: String

    /// The company registration number (IČO) and the VAT number (DIČ).
    var registrationNumber: String
    var vatID: String

    /// The rows of the bank account: the number, the IBAN and BIC, and the routing number of an account in dollars.
    var bankAccount: String
    var iban: String
    var bic: String
    var routingNumber: String

    /// The variable symbol on a Czech invoice, the reference on an English one.
    var reference: String
    var paymentMethod: String
    var issueDate: String
    var dueDate: String

    /// The date of the taxable supply (DUZP).
    var taxableSupplyDate: String

    /// The heads of the columns of the items, and of the summary under them.
    var vat: String
    var unitPrice: String
    var totalWithoutVAT: String
    var vatRate: String
    var vatBase: String

    /// What the first three columns of the items hold. The layout leaves their heads empty and gives them to assistive
    /// technology.
    var quantityHeader: String
    var unitHeader: String
    var descriptionHeader: String
}

/// The text an invoice prints, in the language of the invoice: Czech with its no-break spaces and decimal comma,
/// English with a point for the decimals and commas between thousands. Numbers and dates are built by hand rather than
/// with `NumberFormatter` or `DateFormatter`, so they read the same on every Mac, whatever its settings.
nonisolated enum InvoiceTextFormat {
    private static let noBreakSpace = "\u{00A0}"
    private static let minus = "\u{2212}"

    private static let englishMonths = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// The symbols an English invoice puts before an amount. Any other currency has its code after it.
    private static let englishSymbols = ["USD": "$", "EUR": "€", "GBP": "£"]

    // MARK: Dates

    /// `30. 09. 2026` in Czech, with two digits for the day and the month and a no-break space after each dot, and
    /// `Sep 30, 2026` in English.
    static func date(_ d: CivilDate, language: InvoiceLanguage) -> String {
        switch language {
        case .cs: "\(twoDigits(d.day)).\(noBreakSpace)\(twoDigits(d.month)).\(noBreakSpace)\(d.year)"
        case .en: "\(englishMonths[d.month - 1]) \(d.day), \(d.year)"
        }
    }

    // MARK: Amounts

    /// An amount in minor units with its currency. Czech: `4 500,00 Kč` for crowns and `14 350,00 USD` for any other
    /// currency, the minus sign U+2212. English: the symbol of the currency and a no-break space before the amount
    /// (`$ 14,350.00`, `€ 1,210.00`, `£ 2,500.00`) and for any other currency, crowns included, its code after it
    /// (`4,500.00 CZK`). A negative amount is written with a hyphen before all of it (`-$ 5.00`).
    static func amount(_ minor: Int64, currency: CurrencyCode, language: InvoiceLanguage) -> String {
        switch language {
        case .cs:
            return CzechFormat.money(Money(minor: minor, currency: currency))
        case .en:
            let number = englishNumber(minor.magnitude)
            let sign = minor < 0 ? "-" : ""
            guard let symbol = englishSymbols[currency.code] else {
                return sign + number + noBreakSpace + currency.code
            }
            return sign + symbol + noBreakSpace + number
        }
    }

    /// An amount in haléře as crowns, such as the equivalent of an amount in a foreign currency: `306 501,65 Kč` in
    /// Czech and `306,501.65 CZK` in English.
    static func czkAmount(_ halere: Int64, language: InvoiceLanguage) -> String {
        amount(halere, currency: .czk, language: language)
    }

    /// A quantity as it is, without grouping and without trailing zeros: `6,5` in Czech and `6.5` in English, `218` in
    /// both.
    static func quantity(_ q: Decimal, language: InvoiceLanguage) -> String {
        let text = DecimalMath.canonical(q)
        switch language {
        case .cs: return text.replacing("-", with: minus).replacing(".", with: ",")
        case .en: return text
        }
    }

    /// A VAT rate in whole percent: `21 %`, with a no-break space before the sign.
    static func vatRate(_ percent: Int) -> String {
        "\(percent)\(noBreakSpace)%"
    }

    /// The reference to pay with: the variable symbol, which is the digits of the number, on a Czech invoice, and the
    /// number as it is on an English one.
    static func reference(ofNumber number: String, language: InvoiceLanguage) -> String {
        switch language {
        case .cs: InvoiceNumbering.variableSymbol(of: number)
        case .en: number
        }
    }

    // MARK: Countries

    /// The name of a country, from its ISO 3166-1 alpha-2 code, in the language of the invoice: `Czech Republic` and
    /// `United States of America` in English, `Česko` in Czech, and so on. `Countries` has the names.
    static func countryName(_ code: String, language: InvoiceLanguage) -> String {
        Countries.name(code, language: language)
    }

    // MARK: Labels

    /// The words of the layout in `language`.
    static func labels(_ language: InvoiceLanguage) -> InvoiceLabels {
        switch language {
        case .cs:
            InvoiceLabels(
                document: "Faktura", subtitle: "DAŇOVÝ DOKLAD", supplier: "DODAVATEL", customer: "ODBĚRATEL",
                registrationNumber: "IČO", vatID: "DIČ", bankAccount: "Bankovní účet", iban: "IBAN", bic: "BIC",
                routingNumber: "Routing number", reference: "Variabilní symbol", paymentMethod: "Způsob platby",
                issueDate: "Datum vystavení", dueDate: "Datum splatnosti", taxableSupplyDate: "Datum zdan. plnění",
                vat: "DPH", unitPrice: "CENA ZA MJ", totalWithoutVAT: "CELKEM BEZ DPH", vatRate: "SAZBA",
                vatBase: "ZÁKLAD", quantityHeader: "Počet", unitHeader: "Jednotka", descriptionHeader: "Popis")
        case .en:
            InvoiceLabels(
                document: "Invoice", subtitle: "TAX DOCUMENT", supplier: "SUPPLIER", customer: "CUSTOMER",
                registrationNumber: "Reg. no.", vatID: "VAT ID", bankAccount: "Bank account", iban: "IBAN", bic: "BIC",
                routingNumber: "Routing number", reference: "Reference", paymentMethod: "Payment method",
                issueDate: "Issued on", dueDate: "Due on", taxableSupplyDate: "Date of taxable supply", vat: "VAT",
                unitPrice: "UNIT PRICE", totalWithoutVAT: "TOTAL W/O VAT", vatRate: "VAT RATE", vatBase: "VAT BASE",
                quantityHeader: "Quantity", unitHeader: "Unit", descriptionHeader: "Description")
        }
    }

    // MARK: Helpers

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }

    /// An amount in minor units without its sign: `14,350.00`.
    private static func englishNumber(_ magnitude: UInt64) -> String {
        let fraction = magnitude % 100
        return groupedByThousands(String(magnitude / 100)) + "." + (fraction < 10 ? "0" : "") + String(fraction)
    }

    /// `1,234,567` for the digits `1234567`.
    private static func groupedByThousands(_ digits: String) -> String {
        var result = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 {
                result += ","
            }
            result.append(digit)
        }
        return result
    }
}
