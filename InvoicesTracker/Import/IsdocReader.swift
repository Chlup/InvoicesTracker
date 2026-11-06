import Foundation

/// Reads one ISDOC invoice, in the shape Fakturoid writes it (ISDOC 6.0.2, namespace `http://isdoc.cz/namespace/2013`).
///
/// The elements are found by their path from the root and matched by local name. The declared encoding of the file
/// (such as windows-1250) is honoured and a byte order mark is skipped. Numbers are read exactly (`AmountParser`):
/// an amount, quantity or rate that is not an exact number makes the file unreadable rather than a guess. A date that
/// is not a plausible ISO date is nil.
nonisolated enum IsdocReader {
    /// The namespace of ISDOC invoices.
    fileprivate static let namespace = "http://isdoc.cz/namespace/2013"

    /// Dates this far out are not taken for dates.
    fileprivate static let plausibleYears = 1990...2100

    /// The invoice in the data.
    ///
    /// - Throws: `ImportError.notAnIsdocInvoice` for data that is not well-formed XML, whose root is not an `Invoice`
    ///   of the ISDOC namespace, or that has an amount, quantity or percentage that is not an exact number;
    ///   `ImportError.isdocWithoutNumber` when there is no `ID`; `ImportError.isdocWithoutLines` when there is no
    ///   `InvoiceLine`.
    static func read(_ data: Data) throws(ImportError) -> IsdocInvoice {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        guard parser.parse(), collector.rootIsInvoice else { throw ImportError.notAnIsdocInvoice }
        return try collector.invoice()
    }
}

// MARK: - Collecting the elements

/// Collects the text of the elements of a document by their path, and builds the invoice from them.
nonisolated private final class Collector: NSObject, XMLParserDelegate {
    /// The path of the element being read, from the root, as local names.
    private var path: [String] = []
    private var text = ""
    private(set) var rootIsInvoice = false

    /// The first text of each element outside the lines, by its path below the root, such as `IssueDate` or
    /// `AccountingCustomerParty/Party/PartyName/Name`.
    private var values: [String: String] = [:]

    /// The elements of each line by their path below the `InvoiceLine`, in the order of the lines.
    private var lines: [[String: String]] = []
    private var inLine = false

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if path.isEmpty {
            guard elementName == "Invoice", namespaceURI == IsdocReader.namespace else {
                parser.abortParsing()
                return
            }
            rootIsInvoice = true
        }
        path.append(elementName)
        text = ""
        if path == ["Invoice", "InvoiceLines", "InvoiceLine"] {
            inLine = true
            lines.append([:])
        }
        if inLine, elementName == "InvoicedQuantity", let unit = attributeDict["unitCode"] {
            store(path.dropFirst(3).joined(separator: "/") + "@unitCode", unit)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    /// A CDATA block is text of its element like any other text, such as a note written as `<![CDATA[…]]>`. The
    /// parser hands its bytes over in UTF-8 whatever the encoding of the file, and it hands them only here once this
    /// method is there, not to `parser(_:foundCharacters:)` as well.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        if inLine {
            if path.count > 3 {
                store(path.dropFirst(3).joined(separator: "/"), text)
            } else {
                inLine = false
            }
        } else if path.count > 1 {
            store(path.dropFirst().joined(separator: "/"), text)
        }
        path.removeLast()
        text = ""
    }

    /// Keeps the first value of a path: the next one is from a repeated element.
    private func store(_ key: String, _ value: String) {
        if inLine {
            if lines[lines.count - 1][key] == nil {
                lines[lines.count - 1][key] = value
            }
        } else if values[key] == nil {
            values[key] = value
        }
    }

    // MARK: Building the invoice

    /// The trimmed text of an element outside the lines, empty when there is none.
    private func value(_ key: String) -> String {
        (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func date(_ key: String) -> CivilDate? {
        guard let date = CivilDate(iso: value(key)), IsdocReader.plausibleYears.contains(date.year) else { return nil }
        return date
    }

    private func party(_ element: String) -> IsdocParty {
        let base = "\(element)/Party/"
        let street = [value(base + "PostalAddress/StreetName"), value(base + "PostalAddress/BuildingNumber")]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return IsdocParty(
            name: value(base + "PartyName/Name"), street: street, postcode: value(base + "PostalAddress/PostalZone"),
            city: value(base + "PostalAddress/CityName"),
            country: value(base + "PostalAddress/Country/IdentificationCode").uppercased(),
            ico: value(base + "PartyIdentification/ID"), dic: value(base + "PartyTaxScheme/CompanyID"),
            email: value(base + "Contact/ElectronicMail"))
    }

    /// The invoice the collected elements make.
    func invoice() throws(ImportError) -> IsdocInvoice {
        let number = value("ID")
        guard !number.isEmpty else { throw ImportError.isdocWithoutNumber }
        guard !lines.isEmpty else { throw ImportError.isdocWithoutLines }

        let foreign = value("ForeignCurrencyCode").uppercased()
        let local = value("LocalCurrencyCode").uppercased()
        var rate: Decimal?
        if !foreign.isEmpty, let current = AmountParser.decimal(value("CurrRate"), maxFractionDigits: 8),
            let reference = AmountParser.decimal(value("RefCurrRate"), maxFractionDigits: 8),
            current > 0, reference > 0
        {
            rate = current / reference
        }
        var readLines: [IsdocLine] = []
        for line in lines {
            readLines.append(try self.line(line, foreign: !foreign.isEmpty))
        }
        let hasSupplier = values.keys.contains { $0.hasPrefix("AccountingSupplierParty/") }
        return IsdocInvoice(
            documentType: Int(value("DocumentType")) ?? 1, number: number, uuid: value("UUID"),
            issueDate: date("IssueDate"), taxPointDate: date("TaxPointDate"),
            dueDate: date("PaymentMeans/Payment/Details/PaymentDueDate"), note: value("Note"),
            currency: foreign.isEmpty ? (local.isEmpty ? "CZK" : local) : foreign, rate: rate,
            customer: party("AccountingCustomerParty"), supplier: hasSupplier ? party("AccountingSupplierParty") : nil,
            lines: readLines, paymentMeansCode: value("PaymentMeans/Payment/PaymentMeansCode"))
    }

    /// One line. The quantity, the amount and the percentage must be exact numbers.
    private func line(_ elements: [String: String], foreign: Bool) throws(ImportError) -> IsdocLine {
        func text(_ key: String) -> String {
            (elements[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let amountKey = foreign ? "LineExtensionAmountCurr" : "LineExtensionAmount"
        guard let quantity = AmountParser.decimal(text("InvoicedQuantity"), maxFractionDigits: 8),
            let amount = AmountParser.minor(text(amountKey)),
            let percent = AmountParser.decimal(text("ClassifiedTaxCategory/Percent"), maxFractionDigits: 8)
        else {
            throw ImportError.notAnIsdocInvoice
        }
        return IsdocLine(
            description: text("Item/Description"), quantity: quantity, unit: text("InvoicedQuantity@unitCode"),
            lineAmountMinor: amount, unitPriceCZKMinor: AmountParser.minor(text("UnitPrice")), vatPercent: percent)
    }
}
