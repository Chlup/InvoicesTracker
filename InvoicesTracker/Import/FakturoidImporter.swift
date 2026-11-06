import Foundation

// MARK: - Errors

/// Why a file is not imported. The messages are the copy of the Import screen.
nonisolated enum ImportError: Error, Hashable, LocalizedError {
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

    /// The file is not an ISDOC invoice: it is damaged XML, or its root is not an `Invoice` of the ISDOC namespace.
    case notAnIsdocInvoice

    /// The ISDOC invoice has no `ID`, the number of the invoice.
    case isdocWithoutNumber

    /// The ISDOC invoice has no `InvoiceLine`.
    case isdocWithoutLines

    /// The file is neither a CSV nor an ISDOC file, going by its name.
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .notAFakturoidExport: "Nevypadá to jako export faktur z Fakturoidu."
        case .emptyFile: "Soubor je prázdný."
        case .damagedFile(let line): "Soubor je poškozený (řádek \(line))."
        case .unreadableFile: "Soubor se nepodařilo přečíst."
        case .notAnIsdocInvoice: "Nevypadá to jako faktura ve formátu ISDOC."
        case .isdocWithoutNumber: "V souboru ISDOC chybí číslo faktury."
        case .isdocWithoutLines: "Ve faktuře ISDOC nejsou žádné položky."
        case .unsupportedFile: "Tento soubor není CSV ani ISDOC."
        }
    }
}

/// An `ImportError` and the file it is about, for a screen that stops an import at a file that cannot be used.
nonisolated struct FileImportError: Error, Equatable, LocalizedError {
    let file: String
    let reason: ImportError

    var errorDescription: String? {
        "\(file): \(reason.errorDescription ?? "")"
    }
}

// MARK: - Importer

/// Imports the invoices of Fakturoid's CSV exports and ISDOC files into the database, in two steps.
///
/// - **The preview** (`preview(_:)`) plans the import against what the database holds and writes nothing: no rate is
///   fetched for it, and nothing is logged.
/// - **The import** (`importFiles(_:progress:)`) fetches the ČNB rates of the years the invoices were paid in when they
///   are not there (an invoice that is not paid needs no rate), converts the payments, and then plans the import
///   again and applies it in one transaction with the import log, so that it is applied to the data as they are then.
///   A paid invoice in a foreign currency whose row has no rate gets the latest rate in the database at its DUZP, and
///   is held for review when there is none.
///
/// A file that cannot be used is left out of both, and the other files are imported.
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

    /// The plan of an import of `files` against what the database holds now, for the Import screen to show before the
    /// person imports: the invoices that would be added, overwritten, left unchanged, skipped or not added, and the
    /// notes. The files that failed are left out.
    ///
    /// Nothing is written: no rate is fetched and nothing is logged. The plan is made without the payments of the rows
    /// and without the rates of the invoices that have none of their own, which changes only the payments and the
    /// review flags of the invoices it holds, and the preview shows neither. The import makes its own plan
    /// (`importFiles(_:progress:)`).
    func preview(_ files: [ImportFile]) async throws -> ImportPlan {
        let knownCurrencies = ImportPlanner.quotedCurrencies(cached: try await database.cnbCurrencies())
        return try await database.previewFakturoidImport(files.sources, knownCurrencies: knownCurrencies)
    }

    /// Imports the invoices of the files of `files` that did not fail, and keeps the years whose payments it changed
    /// (`yearsOfChangedPayments`).
    ///
    /// The missing ČNB rates of the days of the payments are fetched first, and the payments are converted. Then the
    /// import is planned again and applied in one transaction, on the data as they are then: when they changed since
    /// the preview, the counts of the summary are not those of the preview.
    ///
    /// - Parameters:
    ///   - files: The files of the import as they were read. A file that failed is left out, and the others import.
    ///   - progress: Called after each invoice the import saves (those it adds, those it updates and those it flags
    ///     as cancelled, in that order), with how many are saved and how many the import saves
    ///     (`ImportPlan.invoiceCount`), from 1 to the whole. It is called inside the transaction on the database's
    ///     actor, so the caller brings what it reports to its own actor. An import that then fails has saved nothing.
    /// - Returns: What was done. Without a file that did not fail nothing is done and the summary is empty.
    /// - Throws: The errors of the database, which leave it as it was, and `CancellationError` for an import cancelled
    ///   before its plan is applied.
    func importFiles(
        _ files: [ImportFile], progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void
    ) async throws -> ImportSummary {
        yearsOfChangedPayments = []
        let usable = files.filter { !Self.failed($0) }
        guard !usable.isEmpty else { return ImportSummary() }
        let sources = usable.sources
        try await fetchMissingRates(for: sources.rows)
        let knownCurrencies = ImportPlanner.quotedCurrencies(cached: try await database.cnbCurrencies())
        let invoiceRates = try await invoiceRatesOfRowsWithoutOne(in: sources.rows)
        let payments = try await convertedPayments(
            of: sources.rows, knownCurrencies: knownCurrencies, invoiceRates: invoiceRates)
        // After this the plan is made and applied in one go, which cannot be taken back.
        try Task.checkCancellation()
        let applied = try await database.applyFakturoidImport(
            FakturoidImportJob(
                sources: sources, payments: payments, invoiceRates: invoiceRates, knownCurrencies: knownCurrencies,
                files: usable.map(\.name), exportSupplier: Self.exportSupplier(of: sources), at: clock.now()
            ),
            progress: progress
        )
        yearsOfChangedPayments = applied.paymentYears
        return applied.summary
    }

    /// Whether `file` could not be used.
    private nonisolated static func failed(_ file: ImportFile) -> Bool {
        if case .failed = file.content { true } else { false }
    }

    // MARK: The supplier of the export

    /// The supplier the import offers to fill an empty profile with: the one the first row prints in its "Your …"
    /// columns, or else the supplier of the first ISDOC invoice. Nil when neither has one.
    private nonisolated static func exportSupplier(of sources: ImportSources) -> Supplier? {
        if let supplier = sources.rows.first.flatMap({ supplier(of: $0) }) {
            return supplier
        }
        return sources.isdocs.first?.supplier.flatMap { supplier(of: $0) }
    }

    /// The supplier the row prints, or nil when its "Your …" columns are all empty.
    private nonisolated static func supplier(of row: FakturoidRow) -> Supplier? {
        supplier(
            name: row.yourName,
            street: [row.yourStreet, row.yourStreet2].filter { !$0.isEmpty }.joined(separator: ", "),
            postcode: row.yourZip, city: row.yourCity, country: row.yourCountry, ico: row.yourRegistrationNo,
            dic: row.yourVatNo
        )
    }

    /// The supplier of an ISDOC invoice, or nil when the party has none of the fields a supplier takes.
    private nonisolated static func supplier(of party: IsdocParty) -> Supplier? {
        supplier(
            name: party.name, street: party.street, postcode: party.postcode, city: party.city,
            country: party.country, ico: party.ico, dic: party.dic
        )
    }

    /// A supplier of these fields, or nil when they are all empty. The country is stored as a code where the import
    /// knows it (`ImportPlanner.countryCode(of:)`), and an empty one leaves the supplier's default.
    private nonisolated static func supplier(
        name: String, street: String, postcode: String, city: String, country: String, ico: String, dic: String
    ) -> Supplier? {
        guard [name, street, city, postcode, country, ico, dic].contains(where: { !$0.isEmpty }) else { return nil }
        var supplier = Supplier()
        supplier.name = name
        supplier.street = street
        supplier.postcode = postcode
        supplier.city = city
        let code = ImportPlanner.countryCode(of: country)
        if !code.isEmpty {
            supplier.country = code
        }
        supplier.ico = ico
        supplier.dic = dic
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

/// Everything the database needs to make an import: the rows and ISDOC invoices, and what is worked out from outside
/// of it.
nonisolated struct FakturoidImportJob: Sendable {
    let sources: ImportSources

    /// The payment of each row that has one, by the fingerprint of the row.
    let payments: [String: Payment]

    /// The rate of the invoice of each paid row in a foreign currency whose export has none, by the fingerprint of the
    /// row, where the database has one.
    let invoiceRates: [String: StoredRate]

    /// The currencies the ČNB has rates of in the database, crowns among them.
    let knownCurrencies: Set<CurrencyCode>

    /// The names of the files of the import that did not fail.
    let files: [String]

    /// The supplier the import offers to fill an empty profile with (`ImportSummary.exportSupplier`).
    let exportSupplier: Supplier?

    /// The time of the import, for the import log.
    let at: Date
}

/// The statements that find the invoices the rows and ISDOC invoices of an import may be. They are conditions of
/// `InvoiceQueries`, so a test can ask SQLite how each finds its rows: by the unique index of the digits of the number,
/// and by the index of the Fakturoid id.
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
    /// The plan of an import of `sources` against what the database holds now, made without writing anything: the
    /// preview of the import (`FakturoidImporter.preview(_:)`).
    ///
    /// It is made without payments and without the rates of the invoices that have none of their own, which changes
    /// only the payments and the review flags of the invoices it holds.
    func previewFakturoidImport(_ sources: ImportSources, knownCurrencies: Set<CurrencyCode>) throws -> ImportPlan {
        try read { connection in
            ImportPlanner.plan(
                sources: sources,
                existingInvoices: try invoicesOfSources(sources, in: connection),
                clients: try clients(),
                knownCurrencies: knownCurrencies,
                payments: [:],
                invoiceRates: [:]
            )
        }
    }

    /// Makes the import of `job`: its rows and ISDOC invoices are planned against what the database holds, the plan is
    /// applied and the summary is put in the import log, all in one transaction. When anything fails, nothing is
    /// changed. Returns the summary, and the years of the payments the import added, changed or took away.
    ///
    /// The planning is in the transaction too, so what the plan was made from is what it is applied to: an invoice
    /// cannot change between the two, and whatever changed since the preview is planned as it is now.
    ///
    /// - Parameter progress: Called after each invoice is saved, in the transaction (see `apply(_:in:progress:)`).
    func applyFakturoidImport(
        _ job: FakturoidImportJob, progress: @Sendable (_ done: Int, _ total: Int) -> Void
    ) throws -> FakturoidImportResult {
        try write { connection in
            let existing = try invoicesOfSources(job.sources, in: connection)
            let plan = ImportPlanner.plan(
                sources: job.sources,
                existingInvoices: existing,
                clients: try clients(),
                knownCurrencies: job.knownCurrencies,
                payments: job.payments,
                invoiceRates: job.invoiceRates
            )
            try apply(plan, in: connection, progress: progress)
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

    /// The invoices that have the digits of the number of a row or an ISDOC invoice of `sources` (the invoice with no
    /// digit in its number, if one has none), and those imported with the Fakturoid id of a row.
    private func invoicesOfSources(_ sources: ImportSources, in connection: SQLiteConnection) throws -> [Invoice] {
        let numbers = sources.rows.map(\.number) + sources.isdocs.map(\.number)
        let digits = Set(numbers.map { InvoiceNumbering.digits(of: $0) })
        let ids = Set(sources.rows.map(\.fakturoidID).filter { !$0.isEmpty })
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
    /// `connection`. An invoice of a new client gets the id the client was given. `progress` is told after each
    /// invoice is saved: the invoices to add, then those to update, then those flagged as cancelled, with how many are
    /// saved of `plan.invoiceCount`.
    private func apply(
        _ plan: ImportPlan, in connection: SQLiteConnection, progress: @Sendable (_ done: Int, _ total: Int) -> Void
    ) throws {
        var newClientIDs: [Int64] = []
        for client in plan.newClients {
            newClientIDs.append(try client.store(in: connection))
        }
        for client in plan.clientUpdates {
            let id = try client.store(in: connection)
            try rebuildSearchDocuments(ofClient: id, in: connection)
        }
        var saved = 0
        for var invoice in plan.inserts + plan.updates {
            if let index = plan.newClientIndexByDigits[invoice.numberDigits] {
                invoice.clientID = newClientIDs[index]
            }
            let id = try invoice.store(in: connection)
            try rebuildSearchDocument(invoiceID: id, in: connection)
            saved += 1
            progress(saved, plan.invoiceCount)
        }
        for invoice in plan.flaggedCancelled {
            let id = try invoice.store(in: connection)
            try rebuildSearchDocument(invoiceID: id, in: connection)
            saved += 1
            progress(saved, plan.invoiceCount)
        }
    }
}
