import Foundation

// MARK: - Errors

/// Why a file is not imported. The messages are the copy of the Import screen.
nonisolated enum ImportError: Error, Equatable, LocalizedError {
    /// The file is a CSV, but not an export of invoices from Fakturoid: it has no `Number` or no `Issued on` column.
    case notAFakturoidExport

    /// The file has nothing in it.
    case emptyFile

    /// The file cannot be read as the table it should be: a quote is never closed, text follows a closing quote, or a
    /// row has another number of fields than the header, so that its values may be in the wrong columns. The number
    /// is the line (a row with a line break in a field makes it a guess for the rows after it).
    case damagedFile(line: Int)

    /// The file cannot be opened, or it is not text in UTF-8.
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .notAFakturoidExport: "Nevypadá to jako export faktur z Fakturoidu."
        case .emptyFile: "Soubor je prázdný."
        case .damagedFile(let line): "Soubor je poškozený (řádek \(line))."
        case .unreadableFile: "Soubor se nepodařilo přečíst."
        }
    }
}

/// An `ImportError` and the file it is about: nothing of the files is imported then.
nonisolated struct FileImportError: Error, Equatable, LocalizedError {
    let file: String
    let reason: ImportError

    var errorDescription: String? {
        "\(file): \(reason.errorDescription ?? "")"
    }
}

// MARK: - Progress

/// How far the reading of the files of an import is, as the importer reports it after each file is read.
nonisolated struct ImportProgress: Equatable, Sendable {
    /// The rows of each file read so far, in the order of the files: the lines under the header of the export.
    var rowCounts: [Int]

    /// How many files the import has.
    var fileCount: Int

    /// How many files are read.
    var filesRead: Int {
        rowCounts.count
    }

    /// How many rows the files read so far have.
    var rowsRead: Int {
        rowCounts.reduce(0, +)
    }
}

// MARK: - Importer

/// Imports the invoices of Fakturoid exports into the database.
///
/// All the files are read first, so a file that cannot be read stops the import before anything is changed. The ČNB
/// rates of the years the invoices were paid in are fetched when they are not there (an invoice that is not paid needs
/// no rate), the rows are converted to invoices and clients, and the whole plan is applied in one transaction with the
/// import log. A paid invoice in a foreign currency whose row has no rate gets the latest rate in the database at its
/// DUZP, and is held for review when there is none.
@MainActor
final class FakturoidImporter {
    private let database: Database
    private let fetcher: CNBFetcher?
    private let clock: any AppClock

    /// The years of the days of the payments the last import added, changed or took away, the days they have and the
    /// days they had: the years whose method of converting income may have changed with them, which the app converts
    /// again (`AppModel.recomputePaymentsAfterChanges(inYears:)`). Empty before an import, and after one that failed.
    private(set) var yearsOfChangedPayments: Set<Int> = []

    /// - Parameters:
    ///   - database: The database the invoices go to.
    ///   - fetcher: Where the yearly files of the ČNB come from, or nil when the app is offline. A payment whose rate
    ///     the database does not have (no fetcher, or a file that could not be fetched) is converted at the rate of
    ///     its invoice and marked provisional. The refresh of the app then fetches the yearly file of its year at its
    ///     next run once the ČNB has declared the rate of its day (under the back-off after failed requests), and the
    ///     payment is converted again when the rates are stored (`AppModel.ratesUpdated()`).
    ///   - clock: The time of the import log and of the fetch log.
    init(database: Database, fetcher: CNBFetcher?, clock: any AppClock = SystemClock()) {
        self.database = database
        self.fetcher = fetcher
        self.clock = clock
    }

    /// Imports the invoices in `urls`, and keeps the years whose payments it changed (`yearsOfChangedPayments`).
    ///
    /// - Parameter progress: Called after each file is read, with the rows of the files read so far and the number of
    ///   files (`ImportProgress`).
    /// - Returns: What was done. Without files nothing is done and the summary is empty.
    /// - Throws: `FileImportError` for a file that cannot be read as an export (and nothing is imported), and the
    ///   errors of the database, which leave it as it was.
    func importFiles(_ urls: [URL], progress: @MainActor (ImportProgress) -> Void) async throws -> ImportSummary {
        yearsOfChangedPayments = []
        guard !urls.isEmpty else { return ImportSummary() }
        var rows: [FakturoidRow] = []
        var names: [String] = []
        var rowCounts: [Int] = []
        for url in urls {
            let name = url.lastPathComponent
            do {
                let read = try await Self.rows(of: url)
                rows += read
                rowCounts.append(read.count)
            } catch let error as ImportError {
                throw FileImportError(file: name, reason: error)
            }
            names.append(name)
            progress(ImportProgress(rowCounts: rowCounts, fileCount: urls.count))
        }
        try await fetchMissingRates(for: rows)
        let knownCurrencies = ImportPlanner.quotedCurrencies(cached: try await database.cnbCurrencies())
        let invoiceRates = try await invoiceRatesOfRowsWithoutOne(in: rows)
        let payments = try await convertedPayments(
            of: rows, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
        // After this the plan is made and applied in one go, which cannot be taken back.
        try Task.checkCancellation()
        let applied = try await database.applyFakturoidImport(
            FakturoidImportJob(
                rows: rows, payments: payments, invoiceRates: invoiceRates, knownCurrencies: knownCurrencies,
                files: names, exportSupplier: rows.first.flatMap { Self.supplier(of: $0) }, at: clock.now()
            )
        )
        yearsOfChangedPayments = applied.paymentYears
        return applied.summary
    }

    // MARK: Reading

    /// The rows of the file, read away from the main actor.
    @concurrent
    private nonisolated static func rows(of url: URL) async throws -> [FakturoidRow] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile
        }
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.unreadableFile }
        return try FakturoidRow.rows(from: CSVTable.parse(text))
    }

    /// The supplier the row prints, or nil when its "Your …" columns are all empty.
    private nonisolated static func supplier(of row: FakturoidRow) -> Supplier? {
        let street = [row.yourStreet, row.yourStreet2].filter { !$0.isEmpty }.joined(separator: ", ")
        let texts = [
            row.yourName, street, row.yourCity, row.yourZip, row.yourCountry, row.yourRegistrationNo, row.yourVatNo,
        ]
        guard texts.contains(where: { !$0.isEmpty }) else { return nil }
        var supplier = Supplier()
        supplier.name = row.yourName
        supplier.street = street
        supplier.postcode = row.yourZip
        supplier.city = row.yourCity
        let country = ImportPlanner.countryCode(of: row.yourCountry)
        if !country.isEmpty {
            supplier.country = country
        }
        supplier.ico = row.yourRegistrationNo
        supplier.dic = row.yourVatNo
        return supplier
    }

    // MARK: Rates

    /// The rows that are payments in a foreign currency, which need the ČNB rate of the day of the payment.
    private func needsRate(_ row: FakturoidRow) -> (currency: CurrencyCode, day: CivilDate)? {
        guard !row.proforma, !row.cancelled, row.status == "paid", let day = row.paidOn,
            let currency = CurrencyCode(row.currency), !currency.isCZK
        else {
            return nil
        }
        return (currency, day)
    }

    /// Fetches the yearly file of the ČNB for each payment whose rate is not there yet: the year of the payment, and
    /// the year before when the payment is in January (the rate of 1 and 2 January may be the last of the year
    /// before). A year is asked for once however many payments need it, and a year that cannot be fetched is not asked
    /// for again by this import: its payments are converted provisionally, and the refresh of the app fetches the year
    /// later (see `init(database:fetcher:clock:)`).
    private func fetchMissingRates(for rows: [FakturoidRow]) async throws {
        var asked: Set<Int> = []
        for row in rows {
            guard let payment = needsRate(row) else { continue }
            let years = payment.day.month == 1 ? [payment.day.year, payment.day.year - 1] : [payment.day.year]
            // Another request would not help a payment whose years were asked for already.
            guard years.contains(where: { !asked.contains($0) }) else { continue }
            let lookup = try await database.cnbRate(payment.currency, on: payment.day)
            guard case .notYetAvailable = lookup else { continue }
            for year in years where asked.insert(year).inserted {
                try await fetchRates(of: year)
            }
        }
    }

    /// Fetches and stores the rates of `year`, and logs the request. A request that fails is logged and is not an
    /// error of the import; cancelling the import is.
    private func fetchRates(of year: Int) async throws {
        guard let fetcher else { return }
        let fetched: [CNBRateRow]
        do {
            fetched = try await fetcher.fetchYear(year)
        } catch {
            try Task.checkCancellation()
            try await log(year: year, ok: false, message: Self.reason(of: error))
            return
        }
        try await database.insertCNBRates(fetched)
        try await log(year: year, ok: true, message: "")
    }

    private func log(year: Int, ok: Bool, message: String) async throws {
        try await database.appendFetchLog(
            FetchLogEntry(at: clock.now(), kind: .cnbYearly, target: String(year), ok: ok, message: message))
    }

    /// A few words for the fetch log about why a request failed. Never more than the kind of failure.
    private nonisolated static func reason(of error: any Error) -> String {
        switch error {
        case HTTPError.offline: "offline"
        case HTTPError.status(let status): "status \(status)"
        case HTTPError.hostNotAllowed: "address not allowed"
        case is CNBParseError: "file not readable"
        default: "request failed"
        }
    }

    // MARK: Invoice rates

    /// The rate of the invoice of each row that is paid in a foreign currency and has none of its own, by the
    /// fingerprint of the row: the latest ČNB rate in the database declared on or before the DUZP of the row, with the
    /// day it was declared on. A row there is no such rate for is not in the result: its invoice is held for review.
    /// This comes after the rates of the payments are fetched, so that a rate fetched for a payment is found.
    private func invoiceRatesOfRowsWithoutOne(in rows: [FakturoidRow]) async throws -> [String: StoredRate] {
        var rates: [String: StoredRate] = [:]
        for row in rows {
            guard let needed = ImportPlanner.invoiceRateNeeded(by: row), rates[row.fingerprint] == nil else { continue }
            rates[row.fingerprint] = try await database.latestCNBRate(needed.currency, onOrBefore: needed.duzp)
        }
        return rates
    }

    // MARK: Payments

    /// The payment of each row that is paid and is not held for review, by the fingerprint of the row: converted by the
    /// method the year of the payment uses (`YearFXState.effective`), so at the ČNB rate of the day in a year without
    /// the uniform rate of the currency. An invoice in crowns is worth its own amounts. The ČNB rate of the day is the
    /// one in the database; without it (not fetched, or not declared) the payment is provisional (see
    /// `PaymentConverter`). A payment that changes what a year has the uniform rate for is converted again with its
    /// year after the import (`yearsOfChangedPayments`).
    private func convertedPayments(
        of rows: [FakturoidRow], knownCurrencies: Set<CurrencyCode>, invoiceRates: [String: StoredRate]
    ) async throws -> [String: Payment] {
        var payments: [String: Payment] = [:]
        var methods: [Int: IncomeFXMethod] = [:]
        for row in rows {
            guard
                ImportPlanner.classify(row, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
                    == .invoice(reviewReason: nil),
                row.status == "paid", let day = row.paidOn,
                let invoice = ImportPlanner.invoice(
                    from: row, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
            else {
                continue
            }
            let method: IncomeFXMethod
            if let known = methods[day.year] {
                method = known
            } else {
                method = try await database.effectiveFXMethod(year: day.year)
                methods[day.year] = method
            }
            let requested: PaymentConversion
            if invoice.currency.isCZK {
                requested = .czk
            } else {
                requested = method == .uniform ? .uniform : .cnbDaily
            }
            var uniformRate: ExchangeRate?
            if requested == .uniform {
                uniformRate = try await database.uniformRate(invoice.currency, year: day.year)?.exchangeRate
            }
            payments[row.fingerprint] = PaymentConverter.convert(
                invoice: invoice, date: day, requested: requested, bankCZKTotalHalere: nil,
                cnbRate: try await database.cnbRate(invoice.currency, on: day), uniformRate: uniformRate
            )
        }
        return payments
    }
}

// MARK: - Applying the import

/// What applying an import did: its summary, and the years of the days of the payments it added, changed or took away,
/// those they have and those they had.
nonisolated struct FakturoidImportResult: Sendable {
    let summary: ImportSummary
    let paymentYears: Set<Int>
}

/// Everything the database needs to make an import: the rows, and what is worked out from outside of it.
nonisolated struct FakturoidImportJob: Sendable {
    let rows: [FakturoidRow]

    /// The payment of each row that has one, by the fingerprint of the row.
    let payments: [String: Payment]

    /// The rate of the invoice of each paid row in a foreign currency whose export has none, by the fingerprint of the
    /// row, where the database has one.
    let invoiceRates: [String: StoredRate]

    /// The currencies the ČNB has rates of in the database, crowns among them.
    let knownCurrencies: Set<CurrencyCode>
    let files: [String]
    let exportSupplier: Supplier?

    /// The time of the import, for the import log.
    let at: Date
}

/// The statements that find the invoices the rows of an import may be. They are conditions of `InvoiceQueries`, so a
/// test can ask SQLite how each finds its rows: by the unique index of the digits of the number, and by the index of
/// the Fakturoid id.
nonisolated enum ImportQueries {
    /// The invoices with one of `count` numbers (by digits). Arguments: the digits.
    static func byNumberDigits(count: Int) -> String {
        "invoice.number_digits IN (\(placeholders(count)))"
    }

    /// The invoices imported with one of `count` Fakturoid ids. Arguments: the ids.
    static func byFakturoidIDs(count: Int) -> String {
        "invoice.fakturoid_id IN (\(placeholders(count)))"
    }

    /// How many values one statement is given. SQLite takes far more; this keeps the statements short.
    static let chunkSize = 400

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}

extension Database {
    /// Makes the import of `job`: the rows are planned against what the database holds, the plan is applied and the
    /// summary is put in the import log, all in one transaction. When anything fails, nothing is changed. Returns the
    /// summary, and the years of the payments the import added, changed or took away.
    ///
    /// The planning is in the transaction too, so what the plan was made from is what it is applied to: an invoice
    /// cannot change between the two.
    func applyFakturoidImport(_ job: FakturoidImportJob) throws -> FakturoidImportResult {
        try write { connection in
            let existing = try invoicesOfRows(job.rows, in: connection)
            let plan = ImportPlanner.plan(
                rows: job.rows,
                existingInvoices: existing,
                clients: try clients(),
                knownCurrencies: job.knownCurrencies,
                payments: job.payments,
                invoiceRates: job.invoiceRates
            )
            try apply(plan, in: connection)
            let summary = ImportSummary(plan: plan, files: job.files, exportSupplier: job.exportSupplier)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try Database.insertImportLog(try encoder.encode(summary), at: job.at, in: connection)
            return FakturoidImportResult(summary: summary, paymentYears: Self.paymentYears(of: plan, over: existing))
        }
    }

    /// The years of the days of the payments that `plan` adds, changes or takes away from `existing`, the invoices it
    /// was made from: those the payments have and those they had.
    private nonisolated static func paymentYears(of plan: ImportPlan, over existing: [Invoice]) -> Set<Int> {
        let paymentsBefore = Dictionary(existing.map { ($0.id, $0.payment) }, uniquingKeysWith: { first, _ in first })
        var years: Set<Int> = []
        for invoice in plan.inserts + plan.updates + plan.flaggedCancelled {
            // An invoice to add has no id yet, and had no payment.
            let before = paymentsBefore[invoice.id] ?? nil
            guard invoice.payment != before else { continue }
            for payment in [invoice.payment, before].compactMap({ $0 }) {
                years.insert(payment.date.year)
            }
        }
        return years
    }

    /// The invoices that have the digits of the number of one of `rows` (the invoice with no digit in its number, if a
    /// row has none), and those imported with the Fakturoid id of one.
    private func invoicesOfRows(_ rows: [FakturoidRow], in connection: SQLiteConnection) throws -> [Invoice] {
        let digits = Set(rows.map { InvoiceNumbering.digits(of: $0.number) })
        let ids = Set(rows.map(\.fakturoidID).filter { !$0.isEmpty })
        let found =
            try invoices(whereIn: ImportQueries.byNumberDigits, values: Array(digits), in: connection)
            + invoices(whereIn: ImportQueries.byFakturoidIDs, values: Array(ids), in: connection)
        // An invoice that has both is there once.
        return Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
            .sorted { $0.id < $1.id }
    }

    /// The invoices that `condition` selects for `values`, a few of them in each statement. `condition` is one of
    /// `ImportQueries`, given the number of values of its statement.
    private func invoices(
        whereIn condition: (Int) -> String, values: [String], in connection: SQLiteConnection
    ) throws -> [Invoice] {
        var found: [Invoice] = []
        for start in stride(from: 0, to: values.count, by: ImportQueries.chunkSize) {
            let chunk = values[start..<min(start + ImportQueries.chunkSize, values.count)]
            found += try Invoice.load(where: condition(chunk.count), chunk.map { SQLValue.text($0) }, in: connection)
        }
        return found
    }

    /// Saves what `plan` holds: the clients, then the invoices (with the search documents), in the transaction of
    /// `connection`. An invoice of a new client gets the id the client was given.
    private func apply(_ plan: ImportPlan, in connection: SQLiteConnection) throws {
        var newClientIDs: [Int64] = []
        for client in plan.newClients {
            newClientIDs.append(try client.store(in: connection))
        }
        for client in plan.clientUpdates {
            let id = try client.store(in: connection)
            try rebuildSearchDocuments(ofClient: id, in: connection)
        }
        for var invoice in plan.inserts + plan.updates {
            if let index = plan.newClientIndexByDigits[invoice.numberDigits] {
                invoice.clientID = newClientIDs[index]
            }
            let id = try invoice.store(in: connection)
            try rebuildSearchDocument(invoiceID: id, in: connection)
        }
        for invoice in plan.flaggedCancelled {
            let id = try invoice.store(in: connection)
            try rebuildSearchDocument(invoiceID: id, in: connection)
        }
    }
}
