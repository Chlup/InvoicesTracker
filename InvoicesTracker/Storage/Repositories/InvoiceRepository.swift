import Foundation

/// Which invoices a list shows for a year.
nonisolated enum InvoiceScope: String, Sendable {
    /// The invoices issued in the year, drafts included.
    case issued

    /// The invoices with a payment dated in the year, up to the as-of day.
    case paid
}

/// An invoice as the chart of the overview needs it: what it is worth, when it was issued and what was paid on it,
/// without its items.
nonisolated struct InvoiceChartRow: Sendable, Hashable {
    var id: Int64

    /// The day of issue. The invoice is a bar of the chart in the year and the month of it.
    var issueDate: CivilDate
    var isDraft: Bool

    /// Whether the invoice has a review flag.
    var inReview: Bool
    var currency: CurrencyCode

    /// The amount without VAT and the VAT, in the minor units of `currency`.
    var netMinor: Int64
    var vatMinor: Int64

    /// The day the money arrived. The payment is a point of the line of the chart in the year and the month of it,
    /// whatever the year of issue.
    var paymentDate: CivilDate?

    /// The net and the VAT of the payment, converted to crowns, in haléře.
    var paymentNetHalere: Int64?
    var paymentVatHalere: Int64?

    /// The ČNB rate valid on the day of issue, which turns an invoice in a foreign currency that has not been paid
    /// into an estimate in crowns. Nil for an invoice in crowns, which needs no rate, when the ČNB does not quote the
    /// currency, and when it has not declared the rate yet and no earlier rate of the currency is stored either. While
    /// the rate of the day is not declared yet, because the day is today or still to come, it is the latest declared
    /// rate on or before real today, and `issueDayRateIsProvisional` says so.
    var issueDayRate: ExchangeRate?

    /// Whether `issueDayRate` is only the latest rate declared before the day of issue, which stands in until the ČNB
    /// declares the rate of that day. Presentation data of the charts: nothing stored changes with it.
    var issueDayRateIsProvisional = false
}

/// What the invoice repository refuses to do.
nonisolated enum InvoiceError: Error, Equatable {
    /// Another invoice has the digits of this number. The value is the number that was to be saved, as written.
    case duplicateNumber(String)

    /// No invoice has the id that was to be saved.
    case notFound
}

/// The statements the queries of the invoice repository run, so that a test can ask SQLite how each finds its rows.
/// Every statement about a year finds its rows in an index of `invoice`, `payment` or `income_adjustment`, so it costs
/// the same with one year of invoices stored and with ten. The ones that look at all years say so.
nonisolated enum InvoiceQueries {
    // MARK: Which invoices

    // The conditions below select the invoices that `invoices(where:)` and `items(where:)` read.

    /// Every invoice. No arguments.
    static let all = "1 = 1"

    /// The invoice with an id. Arguments: the id.
    static let byID = "invoice.id = ?"

    /// The invoice with the digits of a number in a currency. Arguments: the digits, the currency.
    static let byNumber = "invoice.number_digits = ? AND invoice.currency = ?"

    /// The invoices issued between two days, both included. Arguments: the first day, the last day.
    static let issuedBetween = "invoice.issue_date BETWEEN ? AND ?"

    /// The invoices with a payment dated between two days, both included. Arguments: the first day, the last day.
    static let paidBetween = "payment.date BETWEEN ? AND ?"

    /// The invoices with a payment that waits for its rate. It looks at all years. No arguments.
    static let provisional = "payment.provisional = 1"

    /// The day and the currency of each provisional payment of an invoice in a foreign currency, each pair once, by
    /// day. It looks at all years. No arguments.
    static let provisionalForeignPayments = """
        SELECT DISTINCT payment.date, invoice.currency FROM payment JOIN invoice ON invoice.id = payment.invoice_id
        WHERE payment.provisional = 1 AND invoice.currency <> '\(CurrencyCode.czk.code)'
        ORDER BY payment.date, invoice.currency
        """

    /// The invoices that a condition (over `invoice` and its payment, which may be missing) selects, newest first by
    /// the day of issue, then by the digits of the number. A row is read by `Invoice(row:items:)`.
    static func invoices(where condition: String) -> String {
        """
        SELECT \(Invoice.columns) FROM invoice LEFT JOIN payment ON payment.invoice_id = invoice.id
        WHERE \(condition) ORDER BY invoice.issue_date DESC, invoice.number_digits DESC
        """
    }

    /// The items of the same invoices, in the order of the invoices and their positions. Needs the same arguments.
    static func items(where condition: String) -> String {
        """
        SELECT invoice_id, description, quantity, unit, unit_price_minor FROM invoice_item
        WHERE invoice_id IN (
            SELECT invoice.id FROM invoice LEFT JOIN payment ON payment.invoice_id = invoice.id WHERE \(condition))
        ORDER BY invoice_id, position
        """
    }

    // MARK: Sums and lists of a year

    /// The receipts of a period: payments of issued invoices without a review flag, and income adjustments, by day,
    /// then payments before adjustments, then by id. Columns: the day, the net, the VAT (0 for an adjustment), 0 for a
    /// payment and 1 for an adjustment, the id of the invoice or the adjustment. Arguments: the first and the last
    /// day for the payments, the same for the adjustments.
    static let receipts = """
        SELECT payment.date AS day, payment.czk_net_halere AS net, payment.czk_vat_halere AS vat,
               0 AS kind, payment.invoice_id AS source
        FROM payment JOIN invoice ON invoice.id = payment.invoice_id
        WHERE payment.date BETWEEN ? AND ?
          AND invoice.status = '\(InvoiceStatus.issued.rawValue)' AND invoice.review_reason IS NULL
        UNION ALL
        SELECT date, amount_halere, 0, 1, id FROM income_adjustment WHERE date BETWEEN ? AND ?
        ORDER BY day, kind, source
        """

    /// A row when a receipt of a period is provisional: a payment dated in it of an issued invoice without a review
    /// flag, converted at a rate that stands in for the one it waits for. Arguments: the first and the last day.
    static let provisionalReceipt = """
        SELECT 1 FROM payment JOIN invoice ON invoice.id = payment.invoice_id
        WHERE payment.date BETWEEN ? AND ? AND payment.provisional = 1
          AND invoice.status = '\(InvoiceStatus.issued.rawValue)' AND invoice.review_reason IS NULL
        LIMIT 1
        """

    /// The rows of the chart for a period: the invoices issued in it, and the invoices issued outside it that have a
    /// payment dated in it, so that none is twice. By the day of issue, then the id. Read by
    /// `InvoiceChartRow(row:)`. Arguments: the first and the last day for the issue day, the same for the payment
    /// day, and the same once more to leave out of those the invoices issued in the period.
    static let chartRows = """
        SELECT invoice.id, invoice.issue_date, invoice.status, invoice.review_reason, invoice.currency,
               invoice.net_minor, invoice.vat_minor, payment.date, payment.czk_net_halere, payment.czk_vat_halere
        FROM invoice LEFT JOIN payment ON payment.invoice_id = invoice.id
        WHERE invoice.issue_date BETWEEN ? AND ?
        UNION ALL
        SELECT invoice.id, invoice.issue_date, invoice.status, invoice.review_reason, invoice.currency,
               invoice.net_minor, invoice.vat_minor, payment.date, payment.czk_net_halere, payment.czk_vat_halere
        FROM payment JOIN invoice ON invoice.id = payment.invoice_id
        WHERE payment.date BETWEEN ? AND ? AND invoice.issue_date NOT BETWEEN ? AND ?
        ORDER BY 2, 1
        """

    /// The VAT of the invoices that are not drafts and are not to be checked (no review flag), with their DUZP in a
    /// period, and the rate fixed on them. Columns: the DUZP, the currency, the VAT, then the four columns of the rate.
    /// Arguments: the first day, the last day.
    static let vatByDUZP = """
        SELECT duzp, currency, vat_minor, rate_currency, rate_amount, rate_value, rate_declared_on FROM invoice
        WHERE status <> '\(InvoiceStatus.draft.rawValue)' AND vat_minor <> 0 AND review_reason IS NULL
          AND duzp BETWEEN ? AND ?
        """

    /// The DUZP of the invoices to check (with a review flag) that are not drafts and have VAT, with their DUZP in a
    /// period. Columns: the DUZP. Arguments: the first day, the last day.
    static let vatToCheckByDUZP = """
        SELECT duzp FROM invoice
        WHERE status <> '\(InvoiceStatus.draft.rawValue)' AND vat_minor <> 0 AND review_reason IS NOT NULL
          AND duzp BETWEEN ? AND ?
        """

    /// The foreign currencies of the invoices that are not drafts and were issued in a period or have a payment
    /// dated in it, each once and in the order of the codes. Arguments: the first and the last day for the issue
    /// day, the same for the payment day.
    static let foreignCurrencies = """
        SELECT currency FROM invoice
        WHERE status <> '\(InvoiceStatus.draft.rawValue)' AND currency <> '\(CurrencyCode.czk.code)'
          AND issue_date BETWEEN ? AND ?
        UNION
        SELECT invoice.currency FROM payment JOIN invoice ON invoice.id = payment.invoice_id
        WHERE invoice.status <> '\(InvoiceStatus.draft.rawValue)' AND invoice.currency <> '\(CurrencyCode.czk.code)'
          AND payment.date BETWEEN ? AND ?
        ORDER BY 1
        """

    /// How many drafts were issued between two days, both included. Arguments: the first day, the last day.
    static let draftsIssuedBetween = """
        SELECT count(*) FROM invoice WHERE issue_date BETWEEN ? AND ? AND status = '\(InvoiceStatus.draft.rawValue)'
        """

    /// The numbers, as written, of the invoices whose digits start with a prefix, in the order of the digits. The
    /// digits of a number are the characters 0 to 9, which all sort before ":", so the numbers that start with the
    /// prefix are those from the prefix up to, and not including, the prefix and a colon. Arguments: the prefix, the
    /// prefix and a colon.
    static let numbersWithDigitsPrefix = """
        SELECT number FROM invoice WHERE number_digits >= ? AND number_digits < ? ORDER BY number_digits
        """

    /// The years in which invoices that are not drafts were issued, and the years in which payments were made, each as
    /// the first four characters of the dates. These two look at all years, because they say which years there are.
    /// No arguments.
    static let issueYears = """
        SELECT DISTINCT substr(issue_date, 1, 4) FROM invoice WHERE status <> '\(InvoiceStatus.draft.rawValue)'
        """
    static let paymentYears = "SELECT DISTINCT substr(date, 1, 4) FROM payment"
}

// MARK: - Invoices

extension Database {
    /// The invoice with `id`, with its items and its payment, or nil if there is none.
    func invoice(id: Int64) throws -> Invoice? {
        try read { connection in
            try Invoice.load(where: InvoiceQueries.byID, [.integer(id)], in: connection).first
        }
    }

    /// The invoice that has the digits `numberDigits` in its number (`20260501` for `2026-05-01`) and is in `currency`,
    /// or nil if there is none. The digits are searched for as given: the number as written is not the digits.
    func invoice(numberDigits: String, currency: CurrencyCode) throws -> Invoice? {
        try read { connection in
            try Invoice.load(
                where: InvoiceQueries.byNumber, [.text(numberDigits), .currency(currency)], in: connection
            ).first
        }
    }

    /// Saves `invoice` with its items and its payment and returns its id. An invoice with `id == 0` is inserted and
    /// gets a new id. Any other is updated in place, and its items and its payment are replaced by the ones given: a
    /// payment of nil removes the stored one. The net, the VAT and the total are stored with the row, worked out from
    /// the items and the VAT mode, and so are the digits of the number.
    ///
    /// All of it, with the search document, is one transaction: when anything fails, nothing is changed.
    ///
    /// Throws `InvoiceError.duplicateNumber` when another invoice has the same digits in its number (`2026-05-01` and
    /// `20260501` are the same number), and `InvoiceError.notFound` when the id is not 0 and no invoice has it, so a
    /// form that was open while the invoice was deleted does not bring it back. A client that the invoice links to
    /// must exist.
    @discardableResult
    func saveInvoice(_ invoice: Invoice) throws -> Int64 {
        try write { connection in
            let id = try invoice.store(in: connection)
            try rebuildSearchDocument(invoiceID: id, in: connection)
            return id
        }
    }

    /// Deletes the invoice with its items, its payment and its search row. An invoice that is not there is not an
    /// error.
    func deleteInvoice(id: Int64) throws {
        try write { connection in
            // A full-text table cannot have a foreign key, so deleting the invoice does not delete its row. The plain
            // table would cascade, and deleting the row first is harmless there.
            try connection.run("DELETE FROM invoice_search WHERE rowid = ?", [.integer(id)])
            try connection.run("DELETE FROM invoice WHERE id = ?", [.integer(id)])
        }
    }

    /// Deletes the invoice with `id` when `typed` confirms its number (`DeleteConfirmation`: the number or its digits),
    /// and returns the number of the invoice, as written, for the message that says so. Returns nil when nothing was
    /// deleted: no invoice has the id, or the text typed is not its number.
    ///
    /// The number is checked and the invoice deleted in one call on the database, so the invoice that is deleted is the
    /// one whose number was typed, however the screen got there, and a call that deletes nothing writes nothing.
    func deleteInvoice(id: Int64, confirmedBy typed: String) throws -> String? {
        let number = try read { connection in
            try connection.query("SELECT number FROM invoice WHERE id = ?", [.integer(id)]).first?.text(0)
        }
        guard let number, DeleteConfirmation.matches(typed: typed, number: number) else {
            return nil
        }
        try deleteInvoice(id: id)
        return number
    }

    /// Removes the payment of the invoice with `id` when `typed` confirms its number (`DeleteConfirmation`: the number
    /// or its digits): the invoice is issued and unpaid again, as it was before the payment, and its search document no
    /// longer holds the payment. An invoice imported from Fakturoid is marked as changed in the app, as any change made
    /// in the app marks it, so that the next import of the same export keeps it unpaid. Returns the invoice as it was,
    /// with the payment that was removed, for its number and the year of the payment; nil when nothing was removed: no
    /// invoice has the id, it has no payment, or the text typed is not its number.
    ///
    /// The number is checked and the payment removed in one call on the database, the search document in the same
    /// transaction as the invoice (`saveInvoice(_:)`), so the payment that is removed is the one of the invoice whose
    /// number was typed, however the screen got there, and a call that removes nothing writes nothing.
    func removePayment(ofInvoice id: Int64, confirmedBy typed: String) throws -> Invoice? {
        guard let invoice = try invoice(id: id), invoice.payment != nil,
            DeleteConfirmation.matches(typed: typed, number: invoice.number)
        else {
            return nil
        }
        var unpaid = invoice
        unpaid.payment = nil
        if case .imported(let fakturoidID, let fingerprint, _) = unpaid.source {
            unpaid.source = .imported(fakturoidID: fakturoidID, fingerprint: fingerprint, changedInApp: true)
        }
        try saveInvoice(unpaid)
        return invoice
    }

    /// How many drafts were issued in `year`, by the day of issue: what the Koncepty chip of Faktury counts, for its
    /// badge in the sidebar. A year outside the calendar has none.
    func draftCount(year: Int) throws -> Int {
        guard let period = Period(year: year) else { return 0 }
        return try read { connection in
            let counted = try connection.scalar(InvoiceQueries.draftsIssuedBetween, period.arguments)
            guard case .integer(let count)? = counted else {
                throw SQLiteError.step("count(*) returned no number.")
            }
            return Int(count)
        }
    }

    /// How many invoices are stored, drafts included.
    func invoiceCount() throws -> Int {
        try read { connection in
            guard case .integer(let count)? = try connection.scalar("SELECT count(*) FROM invoice") else {
                throw SQLiteError.step("count(*) returned no number.")
            }
            return Int(count)
        }
    }

    /// The numbers, as written, of the invoices whose digits start with `prefix`, in the order of the digits. Drafts
    /// count. With the year and the month as the prefix (`202609`) these are the numbers that the next number of the
    /// month has to follow.
    func invoiceNumbers(withDigitsPrefix prefix: String) throws -> [String] {
        try read { connection in
            try connection.query(InvoiceQueries.numbersWithDigitsPrefix, [.text(prefix), .text(prefix + ":")])
                .map { $0.text(0) }
        }
    }

    // MARK: Lists

    /// The invoices of `year` in `scope`, with their items and payments, newest first by the day of issue, then by the
    /// digits of the number. A year outside the calendar has none.
    ///
    /// - `.issued`: issued in the year, drafts included. The as-of day does not matter.
    /// - `.paid`: with a payment dated in the year and on or before `asOf`, whatever the state of the invoice. A
    ///   payment after the as-of day has not been made yet.
    func invoices(scope: InvoiceScope, year: Int, asOf: CivilDate) throws -> [Invoice] {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            switch scope {
            case .issued:
                return try Invoice.load(where: InvoiceQueries.issuedBetween, period.arguments, in: connection)
            case .paid:
                // BETWEEN finds nothing when the as-of day is before the year.
                let paidByAsOf = [SQLValue.day(period.first), .day(min(period.last, asOf))]
                return try Invoice.load(where: InvoiceQueries.paidBetween, paidByAsOf, in: connection)
            }
        }
    }

    /// Every invoice with a payment dated in `year`, in the order of the lists. Unlike the paid list this is not cut at
    /// an as-of day, and no invoice is left out for its state: one in review and a draft come too.
    func paidInvoices(year: Int) throws -> [Invoice] {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            try Invoice.load(where: InvoiceQueries.paidBetween, period.arguments, in: connection)
        }
    }

    /// The invoices whose payment is provisional, because it was converted with the rate fixed on the invoice until
    /// the right rate is published, whatever the year. They are in the order of the lists.
    func provisionalPayments() throws -> [Invoice] {
        try read { connection in
            try Invoice.load(where: InvoiceQueries.provisional, [], in: connection)
        }
    }
}

// MARK: - Sums and rows for the screens

extension Database {
    /// The money received in `year`, for the tax computation: the payments dated in the year of the invoices that are
    /// issued and have no review flag (a draft and an invoice in review are not income), and the income adjustments
    /// of the year. A payment carries the id of its invoice, an adjustment its own id, and the amounts are those
    /// stored with them, in crowns. They are sorted by day. Of one day the payments come first, then the adjustments,
    /// each by id.
    ///
    /// The year of the invoice does not matter: money that arrives on 2 January for an invoice of December is income
    /// of the new year.
    func receipts(year: Int) throws -> [Receipt] {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            try connection.query(InvoiceQueries.receipts, period.arguments + period.arguments).map { row in
                let id = row.int64(4)
                return Receipt(
                    day: try row.day(0), czkNetHalere: row.int64(1), czkVatHalere: row.int64(2),
                    source: row.int64(3) == 0 ? .invoice(id) : .adjustment(id)
                )
            }
        }
    }

    /// Whether a receipt of `year` dated on or before `asOf` is provisional: a payment of an issued invoice without a
    /// review flag, converted at a rate that stands in for the one it waits for. Such a year's income is not final.
    func hasProvisionalReceipt(year: Int, through asOf: CivilDate) throws -> Bool {
        guard let period = Period(year: year), asOf >= period.first else { return false }
        return try read { connection in
            try connection.scalar(InvoiceQueries.provisionalReceipt, [.day(period.first), .day(min(period.last, asOf))])
                != nil
        }
    }

    /// The rows of the chart for the years `fromYear` to `throughYear`: the invoices issued in them, which are the
    /// bars, and those issued in other years that have a payment dated in them, which are points of the line. Each
    /// invoice is there once. They come by the day of issue, then by id.
    ///
    /// Drafts and invoices in review are in the list and say so, and it is for the builder of the chart to leave them
    /// out. Future issue dates use the latest currency rate declared on or before the injected real `today`, marked
    /// provisional, even when later declarations are stored. The rate of a past or present day of issue is looked up
    /// in the stored ČNB rates by the same rule as `cnbRate`. When the day is after the newest stored declaration
    /// (today before the ČNB publishes, or a historical day whose declaration is not stored yet), the row gets the
    /// latest rate declared before the day instead,
    /// marked provisional (`InvoiceChartRow.issueDayRateIsProvisional`); it has none when the currency has no earlier
    /// rate at all. A rate that is missing for an older day stays missing.
    func chartRows(fromYear: Int, throughYear: Int, today: CivilDate) throws -> [InvoiceChartRow] {
        guard let period = Period(fromYear: fromYear, throughYear: throughYear) else { return [] }
        return try read { connection in
            let arguments = period.arguments + period.arguments + period.arguments
            var rows = try connection.query(InvoiceQueries.chartRows, arguments).map { try InvoiceChartRow(row: $0) }
            // Many invoices are issued on the same day, so each rate is looked up once.
            var lookups: [RateKey: RateLookupResult] = [:]
            var futureRates: [CurrencyCode: ExchangeRate?] = [:]
            var newestDeclaration: CivilDate?
            var newestDeclarationRead = false
            for index in rows.indices where !rows[index].currency.isCZK {
                let key = RateKey(currency: rows[index].currency, day: rows[index].issueDate)
                if key.day > today {
                    let rate: ExchangeRate?
                    if let known = futureRates[key.currency] {
                        rate = known
                    } else {
                        rate = try latestCNBRate(key.currency, onOrBefore: today)?.rate
                        futureRates.updateValue(rate, forKey: key.currency)
                    }
                    rows[index].issueDayRate = rate
                    rows[index].issueDayRateIsProvisional = rate != nil
                    continue
                }
                let lookup: RateLookupResult
                if let known = lookups[key] {
                    lookup = known
                } else {
                    lookup = try cnbRate(key.currency, on: key.day)
                    lookups[key] = lookup
                }
                switch lookup {
                case .declared(let rate, _):
                    rows[index].issueDayRate = rate
                case .notYetAvailable:
                    if !newestDeclarationRead {
                        newestDeclaration = try newestCNBDeclaration()
                        newestDeclarationRead = true
                    }
                    guard let newest = newestDeclaration, key.day > newest,
                        let latest = try latestCNBRate(key.currency, onOrBefore: key.day)
                    else {
                        break
                    }
                    rows[index].issueDayRate = latest.rate
                    rows[index].issueDayRateIsProvisional = true
                case .notPublished:
                    break
                }
            }
            return rows
        }
    }

    /// The years that have data, the oldest first, each once: the years of issue of the invoices that are not drafts,
    /// the years of all payments, and the years with stored settings.
    func yearsWithData() throws -> [Int] {
        var years = Set(try storedSettingsYears())
        try read { connection in
            for statement in [InvoiceQueries.issueYears, InvoiceQueries.paymentYears] {
                for row in try connection.query(statement) {
                    years.insert(try row.yearOfStoredDate(0))
                }
            }
        }
        return years.sorted()
    }

    /// The currencies other than crowns of the invoices that are not drafts and were issued in `year` or have a
    /// payment dated in it, each once, in the order of the codes.
    func foreignCurrencies(year: Int) throws -> [CurrencyCode] {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            try connection.query(InvoiceQueries.foreignCurrencies, period.arguments + period.arguments)
                .map { try $0.currency(0) }
        }
    }

    /// The VAT of the invoices that are not drafts, in haléře, by the month of their DUZP in `year`: twelve sums,
    /// January first. An invoice in crowns adds its VAT as it is, an invoice in a foreign currency adds its VAT
    /// converted at the rate fixed on the invoice, each invoice on its own. A foreign invoice that has no rate adds
    /// nothing, because its VAT has no value in crowns, and an invoice to check (with a review flag, such as one
    /// cancelled in Fakturoid) adds nothing until it is resolved (`monthsWithVATToCheck(year:)`).
    func vatByDUZPMonth(year: Int) throws -> [Int64] {
        var months = [Int64](repeating: 0, count: 12)
        guard let period = Period(year: year) else { return months }
        try read { connection in
            for row in try connection.query(InvoiceQueries.vatByDUZP, period.arguments) {
                let month = try row.day(0).month
                if try row.currency(1).isCZK {
                    months[month - 1] += row.int64(2)
                } else if let fixed = try row.optionalStoredRate(3) {
                    months[month - 1] += fixed.rate.czkHalere(fromMinor: row.int64(2))
                }
            }
        }
        return months
    }

    /// The months (1 to 12) of `year` whose VAT (`vatByDUZPMonth(year:)`) leaves out an invoice to check: one that is
    /// not a draft, has a review flag and VAT, and has its DUZP in the month.
    func monthsWithVATToCheck(year: Int) throws -> Set<Int> {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            Set(try connection.query(InvoiceQueries.vatToCheckByDUZP, period.arguments).map { try $0.day(0).month })
        }
    }
}

// MARK: - Rows

/// The first and the last day of a run of years.
nonisolated struct Period {
    let first: CivilDate
    let last: CivilDate

    /// The days of the years `fromYear` to `throughYear`. Nil for a year outside the calendar and for no years.
    init?(fromYear: Int, throughYear: Int) {
        guard fromYear <= throughYear,
            let first = CivilDate(year: fromYear, month: 1, day: 1),
            let last = CivilDate(year: throughYear, month: 12, day: 31)
        else {
            return nil
        }
        self.first = first
        self.last = last
    }

    init?(year: Int) {
        self.init(fromYear: year, throughYear: year)
    }

    /// The arguments of one `BETWEEN ? AND ?`.
    var arguments: [SQLValue] {
        [.day(first), .day(last)]
    }
}

/// A currency on a day: what a rate is looked up for.
private nonisolated struct RateKey: Hashable {
    let currency: CurrencyCode
    let day: CivilDate
}

nonisolated extension Invoice {
    /// The invoices that `condition` selects (one of `InvoiceQueries`, with its `arguments`), in the order of the
    /// lists, with their items. The items of the selected invoices only are read, in one statement.
    static func load(
        where condition: String, _ arguments: [SQLValue], in connection: SQLiteConnection
    ) throws -> [Invoice] {
        let rows = try connection.query(InvoiceQueries.invoices(where: condition), arguments)
        var itemsByInvoice: [Int64: [InvoiceItem]] = [:]
        for row in try connection.query(InvoiceQueries.items(where: condition), arguments) {
            itemsByInvoice[row.int64(0), default: []].append(try InvoiceItem(row: row))
        }
        return try rows.map { row in
            try Invoice(row: row, items: itemsByInvoice[row.int64(0)] ?? [])
        }
    }

    /// Writes the invoice row, its items and its payment, and returns its id. This is the part of a save that the
    /// search document follows, and it must run in the transaction of one.
    func store(in connection: SQLiteConnection) throws -> Int64 {
        if id != 0, try connection.scalar("SELECT 1 FROM invoice WHERE id = ?", [.integer(id)]) == nil {
            throw InvoiceError.notFound
        }
        let sameDigits = try connection.scalar(
            "SELECT 1 FROM invoice WHERE number_digits = ? AND id <> ?", [.text(numberDigits), .integer(id)]
        )
        if sameDigits != nil {
            throw InvoiceError.duplicateNumber(number)
        }
        let values = rowValues()
        let storedID: Int64
        if id == 0 {
            let columns = values.map(\.column).joined(separator: ", ")
            let placeholders = values.map { _ in "?" }.joined(separator: ", ")
            try connection.run("INSERT INTO invoice(\(columns)) VALUES (\(placeholders))", values.map(\.value))
            storedID = connection.lastInsertRowID
        } else {
            // The row is updated in place: replacing it would delete the rows that refer to it along with it, such
            // as its search row.
            let assignments = values.map { "\($0.column) = ?" }.joined(separator: ", ")
            try connection.run("UPDATE invoice SET \(assignments) WHERE id = ?", values.map(\.value) + [.integer(id)])
            try connection.run("DELETE FROM invoice_item WHERE invoice_id = ?", [.integer(id)])
            try connection.run("DELETE FROM payment WHERE invoice_id = ?", [.integer(id)])
            storedID = id
        }
        for (position, item) in items.enumerated() {
            try connection.run(
                """
                INSERT INTO invoice_item(invoice_id, position, description, quantity, unit, unit_price_minor)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .integer(storedID), .int(position), .text(item.description), .decimal(item.quantity),
                    .text(item.unit), .integer(item.unitPriceMinor),
                ]
            )
        }
        if let payment {
            var arguments: [SQLValue] = [
                .integer(storedID), .day(payment.date), .choice(payment.conversion), .integer(payment.czkNetHalere),
                .integer(payment.czkVatHalere),
            ]
            arguments += SQLValue.rateColumns(payment.rate)
            arguments += [.flag(payment.provisional), payment.bankCZKTotalHalere.map { SQLValue.integer($0) } ?? .null]
            try connection.run(
                """
                INSERT INTO payment(
                    invoice_id, date, conversion, czk_net_halere, czk_vat_halere, rate_currency, rate_amount,
                    rate_value, rate_declared_on, provisional, bank_czk_total_halere)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments
            )
        }
        return storedID
    }
}

private nonisolated extension Invoice {
    /// The columns of an invoice row followed by those of its payment, in the order `init(row:items:)` reads them. The
    /// totals and the digits of the number are not read: they follow from the items and the number.
    static let columns = """
        invoice.id, invoice.number, invoice.client_id, invoice.client_name, invoice.client_street, \
        invoice.client_postcode, invoice.client_city, invoice.client_country, invoice.client_ico, \
        invoice.client_dic, invoice.client_email, invoice.currency, invoice.issue_date, invoice.duzp, \
        invoice.due_date, invoice.vat_mode, invoice.rate_currency, invoice.rate_amount, invoice.rate_value, \
        invoice.rate_declared_on, invoice.qr_enabled, invoice.note, invoice.language, invoice.payment_method, \
        invoice.status, invoice.review_reason, invoice.fakturoid_id, invoice.import_fingerprint, \
        invoice.changed_in_app, \
        payment.date, payment.conversion, payment.czk_net_halere, payment.czk_vat_halere, payment.rate_currency, \
        payment.rate_amount, payment.rate_value, payment.rate_declared_on, payment.provisional, \
        payment.bank_czk_total_halere
        """

    /// The column of a row of `columns` where the payment starts.
    static let firstPaymentColumn = 29

    /// A row of `columns` with the items of the invoice.
    init(row: SQLRow, items: [InvoiceItem]) throws {
        let source: InvoiceSource
        if let fakturoidID = row.optionalText(26) {
            source = .imported(
                fakturoidID: fakturoidID, fingerprint: row.text(27), changedInApp: row.bool(28)
            )
        } else {
            source = .app
        }
        self.init(
            id: row.int64(0), number: row.text(1), clientID: row.optionalInt64(2),
            client: ClientSnapshot(
                name: row.text(3), street: row.text(4), postcode: row.text(5), city: row.text(6),
                country: row.text(7), ico: row.text(8), dic: row.text(9), email: row.text(10)
            ),
            currency: try row.currency(11), issueDate: try row.day(12), duzp: try row.day(13),
            dueDate: try row.day(14), items: items, vatMode: try row.choice(15),
            invoiceRate: try row.optionalStoredRate(16), qrEnabled: row.bool(20), note: row.text(21),
            language: try row.choice(22), paymentMethod: row.text(23), status: try row.choice(24),
            review: row.optionalText(25).map { ReviewFlag(reason: $0) },
            payment: try Payment(row: row, from: Self.firstPaymentColumn), source: source
        )
    }

    /// The columns of the invoice row except `id`, each with its value. The net, the VAT and the total are worked out
    /// from the items here, once.
    private func rowValues() -> [(column: String, value: SQLValue)] {
        let net = netMinor
        let vat = InvoiceMath.vat(netMinor: net, mode: vatMode)
        let rate = SQLValue.rateColumns(invoiceRate)
        let fakturoidID: SQLValue
        let fingerprint: SQLValue
        let changedInApp: Bool
        switch source {
        case .app:
            (fakturoidID, fingerprint, changedInApp) = (.null, .null, false)
        case .imported(let importedID, let importedFingerprint, let changed):
            (fakturoidID, fingerprint, changedInApp) = (.text(importedID), .text(importedFingerprint), changed)
        }
        return [
            ("number", .text(number)),
            ("number_digits", .text(numberDigits)),
            ("client_id", clientID.map { SQLValue.integer($0) } ?? .null),
            ("client_name", .text(client.name)),
            ("client_street", .text(client.street)),
            ("client_postcode", .text(client.postcode)),
            ("client_city", .text(client.city)),
            ("client_country", .text(client.country)),
            ("client_ico", .text(client.ico)),
            ("client_dic", .text(client.dic)),
            ("client_email", .text(client.email)),
            ("currency", .currency(currency)),
            ("issue_date", .day(issueDate)),
            ("duzp", .day(duzp)),
            ("due_date", .day(dueDate)),
            ("vat_mode", .choice(vatMode)),
            ("rate_currency", rate[0]),
            ("rate_amount", rate[1]),
            ("rate_value", rate[2]),
            ("rate_declared_on", rate[3]),
            ("qr_enabled", .flag(qrEnabled)),
            ("note", .text(note)),
            ("language", .choice(language)),
            ("payment_method", .text(paymentMethod)),
            ("status", .choice(status)),
            ("review_reason", .optionalText(review?.reason)),
            ("fakturoid_id", fakturoidID),
            ("import_fingerprint", fingerprint),
            ("changed_in_app", .flag(changedInApp)),
            ("net_minor", .integer(net)),
            ("vat_minor", .integer(vat)),
            ("total_minor", .integer(net + vat)),
        ]
    }
}

private nonisolated extension InvoiceItem {
    /// A row of `SELECT invoice_id, description, quantity, unit, unit_price_minor`.
    init(row: SQLRow) throws {
        self.init(
            description: row.text(1), quantity: try row.decimal(2), unit: row.text(3), unitPriceMinor: row.int64(4)
        )
    }
}

private nonisolated extension Payment {
    /// The payment in the columns of a row of `Invoice.columns` that start at `first`, or nil when the invoice has
    /// none, which shows as no date.
    init?(row: SQLRow, from first: Int) throws {
        guard row.optionalText(first) != nil else { return nil }
        self.init(
            date: try row.day(first), conversion: try row.choice(first + 1), czkNetHalere: row.int64(first + 2),
            czkVatHalere: row.int64(first + 3), rate: try row.optionalStoredRate(first + 4),
            provisional: row.bool(first + 8), bankCZKTotalHalere: row.optionalInt64(first + 9)
        )
    }
}

private nonisolated extension InvoiceChartRow {
    /// A row of `InvoiceQueries.chartRows`. The rate of the day of issue is added afterwards.
    init(row: SQLRow) throws {
        let status: InvoiceStatus = try row.choice(2)
        let paymentDate: CivilDate?
        if row.optionalText(7) != nil {
            paymentDate = try row.day(7)
        } else {
            paymentDate = nil
        }
        self.init(
            id: row.int64(0), issueDate: try row.day(1), isDraft: status == .draft,
            inReview: row.optionalText(3) != nil, currency: try row.currency(4), netMinor: row.int64(5),
            vatMinor: row.int64(6), paymentDate: paymentDate, paymentNetHalere: row.optionalInt64(8),
            paymentVatHalere: row.optionalInt64(9)
        )
    }
}

private nonisolated extension SQLValue {
    /// The four columns of a rate fixed on an invoice or used by a payment: the currency, the quoted amount, the rate
    /// and the day the ČNB declared it. All four are NULL for no rate.
    static func rateColumns(_ rate: StoredRate?) -> [SQLValue] {
        guard let rate else { return [.null, .null, .null, .null] }
        return [.currency(rate.rate.currency), .int(rate.rate.amount), .decimal(rate.rate.rate), .day(rate.declaredOn)]
    }
}

private nonisolated extension SQLRow {
    /// The rate in the four columns that start at `i`, or nil if they are NULL.
    func optionalStoredRate(_ i: Int) throws -> StoredRate? {
        guard optionalText(i) != nil else { return nil }
        return StoredRate(
            rate: ExchangeRate(currency: try currency(i), amount: int(i + 1), rate: try decimal(i + 2)),
            declaredOn: try day(i + 3)
        )
    }
}

nonisolated extension SQLRow {
    /// The year at the start of a stored date, read as `substr(date, 1, 4)`.
    func yearOfStoredDate(_ i: Int) throws -> Int {
        let digits = text(i)
        guard digits.utf8.count == 4, digits.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
            let year = Int(digits), year > 0
        else {
            throw StoredValueError.unreadable(column: i, expected: "year")
        }
        return year
    }
}
