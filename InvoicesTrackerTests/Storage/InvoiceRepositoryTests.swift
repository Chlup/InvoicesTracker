import Foundation
import Testing
@testable import InvoicesTracker

/// The invoice repository: saving and loading invoices with their items and payment, the lists and sums the screens
/// and the tax computation ask for, and what they cost with ten years of data. The data is invented.
struct InvoiceRepositoryTests {
    // MARK: Invented data

    /// A client of another country and currency, with Czech diacritics in its texts.
    private static func client() -> Client {
        Client(
            name: "Příbramská strojírna, s.r.o.", street: "Žižkova 12/3", postcode: "261 01",
            city: "Příbram – Orlov", country: "SK", ico: "12345679", dic: "SK2020123456",
            email: "účetní@example.com", currency: .eur, vatMode: .euReverseCharge
        )
    }

    /// Every field differs from the default: three items (one with a negative quantity), a rate fixed on the invoice,
    /// a payment with its own stored rate, an imported source and a review flag.
    private static func fullInvoice(clientID: Int64) -> Invoice {
        var invoice = Invoice.fixture(
            number: "2026-05-01", currency: .usd, issued: "2026-05-04", duzp: "2026-05-01", dueDate: "2026-05-18",
            items: [
                .fixture("7.5", at: 60_000),
                InvoiceItem(
                    description: "Hosting – květen", quantity: decimal("1"), unit: "měs", unitPriceMinor: 12_550),
                InvoiceItem(
                    description: "Sleva za zpoždění", quantity: decimal("-0.25"), unit: "hod",
                    unitPriceMinor: 60_000),
            ],
            vatMode: .euReverseCharge, invoiceRate: storedRate("USD", "21.832", declaredOn: "2026-04-30"),
            review: ReviewFlag(reason: "Částka nesedí s výpisem"),
            payment: Payment.fixture(
                on: "2026-05-20", conversion: .cnbDaily, net: 1_122_000, vat: 0,
                rate: storedRate("USD", "21.5", declaredOn: "2026-05-20"), provisional: true,
                bankCZKTotalHalere: 1_130_000)
        )
        invoice.clientID = clientID
        invoice.client = ClientSnapshot(
            name: "Příbramská strojírna, s.r.o.", street: "Žižkova 12/3", postcode: "261 01",
            city: "Příbram – Orlov", country: "SK", ico: "12345679", dic: "SK2020123456",
            email: "účetní@example.com")
        invoice.qrEnabled = true
        invoice.note = "První řádek\nDruhý řádek"
        invoice.language = .en
        invoice.paymentMethod = "Platba kartou"
        invoice.source = .imported(fakturoidID: "F-2026-0501", fingerprint: "9f2c41", changedInApp: true)
        return invoice
    }

    /// Issued on 31 December 2025 and paid on 2 January 2026: the money arrived in the year after the invoice.
    private static func yearEndInvoice() -> Invoice {
        Invoice.fixture(
            number: "20251201", duzp: "2025-12-31", dueDate: "2026-01-14", payment: .fixture(on: "2026-01-02"))
    }

    private static func adjustment(_ day: String, _ amount: Int64, _ description: String) -> IncomeAdjustment {
        IncomeAdjustment(date: civilDate(day), amountHalere: amount, description: description)
    }

    /// An invoice with one item worth `net` without VAT, issued on `issued` and due on `due` (`YYYY-MM-DD`). Unless a
    /// test says otherwise it is issued, unpaid, without a review flag and in crowns with 21 % VAT.
    private static func dueInvoice(
        _ number: String, issued: String, due: String, net: Int64 = 100_000, currency: CurrencyCode = .czk,
        vatMode: VatMode = .domestic21, status: InvoiceStatus = .issued, review: ReviewFlag? = nil,
        payment: Payment? = nil
    ) -> Invoice {
        Invoice.fixture(
            number: number, currency: currency, issued: issued, duzp: issued, dueDate: due,
            items: [.fixture("1", at: net)], vatMode: vatMode, status: status, review: review, payment: payment)
    }

    // MARK: Helpers

    /// `invoice` as it is after saving: with the id the database gave it.
    @discardableResult
    private func save(_ invoice: Invoice, in database: Database) async throws -> Invoice {
        var saved = invoice
        saved.id = try await database.saveInvoice(invoice)
        return saved
    }

    /// The ČNB rates of 2025 and 2026 for dollars and euros: the real rows of the test fixtures.
    private func loadRates(into database: Database) async throws {
        let rows = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rows)
    }

    private func row(_ database: Database, _ sql: String, _ arguments: [SQLValue] = []) async throws -> [SQLValue] {
        try await database.read { connection in
            try connection.query(sql, arguments)[0].values
        }
    }

    /// How many rows `table` (`invoice_item` or `payment`) has for the invoice with `id`.
    private func rows(of table: String, forInvoice id: Int64, in database: Database) async throws -> Int64 {
        try await database.integer("SELECT count(*) FROM \(table) WHERE invoice_id = ?", [.integer(id)])
    }

    /// How many rows the search table has for the invoice with `id`.
    private func searchRows(forInvoice id: Int64, in database: Database) async throws -> Int64 {
        try await database.integer("SELECT count(*) FROM invoice_search WHERE rowid = ?", [.integer(id)])
    }

    // MARK: Saving and loading

    @Test func anInvoiceWithThreeItemsAPaymentWithARateAnImportedSourceAndAReviewFlagRoundTrips() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        let invoice = Self.fullInvoice(clientID: clientID)

        let id = try await database.saveInvoice(invoice)

        #expect(id == 1)
        var expected = invoice
        expected.id = id
        let loaded = try #require(try await database.invoice(id: id))
        #expect(loaded == expected)
        #expect(loaded.items.map(\.description) == ["Vývoj", "Hosting – květen", "Sleva za zpoždění"])
        #expect(loaded.items.map(\.quantity) == [decimal("7.5"), decimal("1"), decimal("-0.25")])
        #expect(loaded.payment?.rate == storedRate("USD", "21.5", declaredOn: "2026-05-20"))
        #expect(loaded.source == .imported(fakturoidID: "F-2026-0501", fingerprint: "9f2c41", changedInApp: true))
        #expect(loaded.review == ReviewFlag(reason: "Částka nesedí s výpisem"))
        #expect(loaded.issueDate == civilDate("2026-05-04") && loaded.duzp == civilDate("2026-05-01"))
    }

    @Test func anInvoiceMadeInTheAppWithoutAPaymentRateOrReviewFlagRoundTrips() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let invoice = Invoice.fixture()

        let saved = try await save(invoice, in: database)

        #expect(try await database.invoice(id: saved.id) == saved)
        let loaded = try #require(try await database.invoice(id: saved.id))
        #expect(loaded.source == .app && loaded.payment == nil && loaded.review == nil && loaded.invoiceRate == nil)
        #expect(loaded.clientID == nil)
    }

    @Test func aDraftAndAnImportedInvoiceThatWasNotChangedInTheAppRoundTrip() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var imported = Invoice.fixture(number: "Z20261001", duzp: "2026-10-01")
        imported.source = .imported(fakturoidID: "F-9", fingerprint: "ab", changedInApp: false)
        let draft = Invoice.fixture(number: "20261002", duzp: "2026-10-02", items: [], status: .draft)

        let savedImported = try await save(imported, in: database)
        let savedDraft = try await save(draft, in: database)

        #expect(try await database.invoice(id: savedImported.id) == savedImported)
        #expect(try await database.invoice(id: savedDraft.id) == savedDraft)
        #expect(try await database.invoice(id: savedDraft.id)?.status == .draft)
        #expect(try await database.invoice(id: savedDraft.id)?.items.isEmpty == true)
    }

    @Test func eachNewInvoiceGetsItsOwnIdAndAnUnknownIdIsNil() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let first = try await database.saveInvoice(Invoice.fixture(number: "20260901"))
        let second = try await database.saveInvoice(Invoice.fixture(number: "20260902"))

        #expect(first == 1)
        #expect(second == 2)
        #expect(try await database.invoice(id: 99) == nil)
        #expect(try await database.invoice(id: 0) == nil)
    }

    @Test func updatingAnInvoiceKeepsItsIdAndReplacesItsItemsAndPayment() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var invoice = try await save(Self.fullInvoice(clientID: clientID), in: database)
        let other = try await save(
            Invoice.fixture(number: "20260902", payment: .fixture(on: "2026-10-05")), in: database)

        invoice.number = "2026-05-02"
        invoice.items = [.fixture("1", at: 100_000)]
        invoice.payment = nil
        invoice.review = nil
        invoice.note = "Upraveno"
        invoice.source = .app
        invoice.invoiceRate = nil
        let id = try await database.saveInvoice(invoice)

        #expect(id == invoice.id)
        #expect(try await database.invoice(id: id) == invoice)
        #expect(try await database.invoiceCount() == 2)
        // The other invoice has not been touched, and the old items and payment are gone.
        #expect(try await database.invoice(id: other.id) == other)
        #expect(try await rows(of: "invoice_item", forInvoice: id, in: database) == 1)
        #expect(try await rows(of: "payment", forInvoice: id, in: database) == 0)
        #expect(try await database.integer("SELECT count(*) FROM invoice_item") == 2)
        #expect(try await database.integer("SELECT count(*) FROM payment") == 1)
    }

    /// The invoice row is changed in place, and the search table keeps one row for it, with the document of the new
    /// data.
    @Test(arguments: [SearchIndexKind.fts5, SearchIndexKind.plain])
    func updatingAnInvoiceKeepsOneSearchRowForIt(kind: SearchIndexKind) async throws {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        defer { removeTemporaryDirectory(directory) }
        var invoice = try await save(Invoice.fixture(), in: database)
        let id = invoice.id
        #expect(try await searchRows(forInvoice: id, in: database) == 1)

        invoice.note = "Upraveno"
        try await database.saveInvoice(invoice)

        #expect(try await searchRows(forInvoice: id, in: database) == 1)
        #expect(try await database.integer("SELECT count(*) FROM invoice_search") == 1)
        #expect(try await database.invoice(id: id)?.note == "Upraveno")
    }

    @Test func aPaymentCanBeAddedLaterAndTheItemsKeepTheOrderGiven() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var invoice = try await save(Invoice.fixture(items: []), in: database)

        invoice.items = (0..<12).reversed().map { index in
            InvoiceItem(description: "Položka \(index)", quantity: decimal("1"), unit: "ks", unitPriceMinor: 100)
        }
        invoice.payment = .fixture(on: "2026-10-05")
        try await database.saveInvoice(invoice)

        let loaded = try #require(try await database.invoice(id: invoice.id))
        #expect(loaded == invoice)
        #expect(loaded.items.first?.description == "Položka 11")
        #expect(loaded.items.last?.description == "Položka 0")
    }

    @Test func savingAnIdThatIsNotThereIsRefusedAndWritesNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var invoice = Invoice.fixture(payment: .fixture(on: "2026-10-05"))
        invoice.id = 7

        await #expect(throws: InvoiceError.notFound) { try await database.saveInvoice(invoice) }

        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.integer("SELECT count(*) FROM invoice_item") == 0)
        #expect(try await database.integer("SELECT count(*) FROM payment") == 0)
        #expect(await database.writeCount == 0)
    }

    @Test func theTotalsAndTheDigitsOfTheNumberAreStoredWithTheRow() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // 7,5 h at 600,00 Kč and a rounded half-up 0,335 at 1,00 Kč: 4 500,34 Kč and 21 % VAT of 945,07 Kč.
        let invoice = Invoice.fixture(
            number: "2026-05-01", duzp: "2026-05-01", items: [.fixture("7.5", at: 60_000), .fixture("0.335", at: 100)])
        let saved = try await save(invoice, in: database)

        let columns = try await row(
            database, "SELECT number, number_digits, net_minor, vat_minor, total_minor FROM invoice WHERE id = ?",
            [.integer(saved.id)])

        #expect(
            columns
                == [.text("2026-05-01"), .text("20260501"), .integer(450_034), .integer(94_507), .integer(544_541)])
        #expect(saved.netMinor == 450_034 && saved.vatMinor == 94_507 && saved.totalMinor == 544_541)
    }

    @Test func updatingAnInvoiceStoresItsNewTotalsAndDigits() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var invoice = try await save(Invoice.fixture(number: "20260901"), in: database)

        invoice.number = "FA 2026/09-02"
        invoice.items = [.fixture("2", at: 50_000)]
        invoice.vatMode = .domestic12
        try await database.saveInvoice(invoice)

        let columns = try await row(
            database, "SELECT number_digits, net_minor, vat_minor, total_minor FROM invoice WHERE id = ?",
            [.integer(invoice.id)])
        #expect(columns == [.text("20260902"), .integer(100_000), .integer(12_000), .integer(112_000)])
    }

    // MARK: Numbers

    @Test func aNumberWithTheDigitsOfAnotherInvoiceIsRefusedAndNothingIsWritten() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try await save(Invoice.fixture(number: "2026-05-01", duzp: "2026-05-01"), in: database)
        let writesBefore = await database.writeCount
        let second = Invoice.fixture(number: "20260501", duzp: "2026-05-31", payment: .fixture(on: "2026-06-10"))

        await #expect(throws: InvoiceError.duplicateNumber("20260501")) { try await database.saveInvoice(second) }

        #expect(try await database.invoiceCount() == 1)
        #expect(try await database.invoice(id: first.id) == first)
        #expect(try await database.integer("SELECT count(*) FROM payment") == 0)
        #expect(await database.writeCount == writesBefore)
    }

    @Test func anInvoiceMayKeepItsOwnNumberOrWriteItInAnotherFormat() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var invoice = try await save(Invoice.fixture(number: "2026-05-01", duzp: "2026-05-01"), in: database)

        try await database.saveInvoice(invoice)
        invoice.number = "20260501"
        try await database.saveInvoice(invoice)

        #expect(try await database.invoice(id: invoice.id)?.number == "20260501")
        #expect(try await database.invoiceCount() == 1)
    }

    @Test func changingTheNumberOfAnInvoiceToTheNumberOfAnotherIsRefusedAndTheOldContentsStay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await save(Invoice.fixture(number: "20260901"), in: database)
        let second = try await save(
            Invoice.fixture(number: "20260902", payment: .fixture(on: "2026-10-05")), in: database)
        var changed = second
        changed.number = "2026-09-01"
        changed.items = []
        changed.payment = nil

        await #expect(throws: InvoiceError.duplicateNumber("2026-09-01")) { try await database.saveInvoice(changed) }

        #expect(try await database.invoice(id: second.id) == second)
    }

    @Test func theNumbersOfAMonthAreFoundByTheirDigitsAndComeAsPrinted() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let numbers = [
            "20260901", "2026-09-02", "Z20260903", "20260801", "20261001", "20250901", "2026091", "20260910",
        ]
        for number in numbers {
            try await save(Invoice.fixture(number: number), in: database)
        }
        try await save(Invoice.fixture(number: "20260904", status: .draft), in: database)

        // In the order of the digits as text. A draft counts, and so does a number of another shape that starts alike.
        #expect(
            try await database.invoiceNumbers(withDigitsPrefix: "202609")
                == ["20260901", "2026-09-02", "Z20260903", "20260904", "2026091", "20260910"])
        #expect(try await database.invoiceNumbers(withDigitsPrefix: "202608") == ["20260801"])
        #expect(try await database.invoiceNumbers(withDigitsPrefix: "20260902") == ["2026-09-02"])
        #expect(try await database.invoiceNumbers(withDigitsPrefix: "202612").isEmpty)
        #expect(try await database.invoiceNumbers(withDigitsPrefix: "2027").isEmpty)
        // The numbers of a month feed the proposal of the next one.
        let september = try await database.invoiceNumbers(withDigitsPrefix: "202609")
        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-09-30"), existingNumbers: september) == "20260911")
    }

    @Test func anInvoiceIsFoundByTheDigitsOfItsNumberAndItsCurrency() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let dollars = try await save(
            Invoice.fixture(number: "2026-05-01", currency: .usd, duzp: "2026-05-01", vatMode: .outsideCountry),
            in: database)
        try await save(Invoice.fixture(number: "20260502"), in: database)

        #expect(try await database.invoice(numberDigits: "20260501", currency: .usd) == dollars)
        #expect(try await database.invoice(numberDigits: "20260501", currency: .eur) == nil)
        #expect(try await database.invoice(numberDigits: "20260501", currency: .czk) == nil)
        #expect(try await database.invoice(numberDigits: "20260502", currency: .czk)?.number == "20260502")
        #expect(try await database.invoice(numberDigits: "20260503", currency: .czk) == nil)
        // The digits are searched for as they are: the number as printed is not the digits.
        #expect(try await database.invoice(numberDigits: "2026-05-01", currency: .usd) == nil)
    }

    // MARK: Deleting

    @Test(arguments: [SearchIndexKind.fts5, SearchIndexKind.plain])
    func deletingAnInvoiceDeletesItsItemsItsPaymentAndItsSearchRow(kind: SearchIndexKind) async throws {
        let (database, directory) = try makeDatabase(searchIndex: kind)
        defer { removeTemporaryDirectory(directory) }
        let first = try await save(
            Invoice.fixture(
                number: "20260901", items: [.fixture("1", at: 100), .fixture("2", at: 200)],
                payment: .fixture(on: "2026-10-05")),
            in: database)
        let second = try await save(
            Invoice.fixture(number: "20260902", payment: .fixture(on: "2026-10-06")), in: database)
        #expect(await database.searchIndexKind == kind)
        #expect(try await rows(of: "invoice_item", forInvoice: first.id, in: database) == 2)
        #expect(try await rows(of: "payment", forInvoice: first.id, in: database) == 1)
        #expect(try await searchRows(forInvoice: first.id, in: database) == 1)
        #expect(try await searchRows(forInvoice: second.id, in: database) == 1)

        try await database.deleteInvoice(id: first.id)

        #expect(try await database.invoice(id: first.id) == nil)
        for table in ["invoice_item", "payment"] {
            #expect(try await rows(of: table, forInvoice: first.id, in: database) == 0, "\(table)")
            #expect(try await rows(of: table, forInvoice: second.id, in: database) == 1, "\(table) of the other")
        }
        #expect(try await searchRows(forInvoice: first.id, in: database) == 0)
        #expect(try await searchRows(forInvoice: second.id, in: database) == 1)
        #expect(try await database.invoice(id: second.id) == second)
        #expect(try await database.invoiceCount() == 1)
    }

    @Test func deletingAnInvoiceThatIsNotThereIsNotAnError() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept = try await save(Invoice.fixture(), in: database)

        try await database.deleteInvoice(id: 99)
        try await database.deleteInvoice(id: 0)
        try await database.deleteInvoice(id: kept.id)
        try await database.deleteInvoice(id: kept.id)

        #expect(try await database.invoiceCount() == 0)
    }

    @Test func aDeletedInvoiceNumberCanBeUsedAgainButItsIdIsNot() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try await save(Invoice.fixture(number: "20260901"), in: database)

        try await database.deleteInvoice(id: first.id)
        let again = try await database.saveInvoice(Invoice.fixture(number: "2026-09-01"))

        #expect(first.id == 1)
        #expect(again == 2)
    }

    @Test func deletingAnInvoiceKeepsItsClient() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var invoice = Invoice.fixture()
        invoice.clientID = clientID
        let saved = try await save(invoice, in: database)

        try await database.deleteInvoice(id: saved.id)

        #expect(try await database.client(id: clientID) != nil)
    }

    // MARK: Lists by scope

    /// An invoice issued on 31 December 2025 and paid on 2 January 2026 is in the issued list of 2025, and in the paid
    /// list of 2026 from the day it was paid.
    @Test func aYearEndInvoiceIsIssuedInOneYearAndPaidInTheNext() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let invoice = try await save(Self.yearEndInvoice(), in: database)

        func ids(_ scope: InvoiceScope, _ year: Int, asOf day: String) async throws -> [Int64] {
            try await database.invoices(scope: scope, year: year, asOf: civilDate(day)).map(\.id)
        }

        #expect(try await ids(.issued, 2025, asOf: "2026-10-17") == [invoice.id])
        #expect(try await ids(.paid, 2026, asOf: "2026-10-17") == [invoice.id])
        #expect(try await ids(.paid, 2026, asOf: "2026-01-01").isEmpty)
        // The day of the payment counts, the day before does not.
        #expect(try await ids(.paid, 2026, asOf: "2026-01-02") == [invoice.id])
        // It is not in the other lists of those two years.
        #expect(try await ids(.issued, 2026, asOf: "2026-10-17").isEmpty)
        #expect(try await ids(.paid, 2025, asOf: "2026-10-17").isEmpty)
        #expect(try await ids(.paid, 2025, asOf: "2025-12-31").isEmpty)
        #expect(try await ids(.issued, 2025, asOf: "2025-06-30") == [invoice.id])
    }

    @Test func theIssuedListHoldsEveryInvoiceIssuedInTheYearDraftsAndUnpaidOnesIncludedAndNoOther() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try await save(Invoice.fixture(number: "20260101", duzp: "2026-01-01"), in: database)
        let last = try await save(
            Invoice.fixture(number: "20261201", duzp: "2026-12-31", payment: .fixture(on: "2027-01-05")), in: database)
        let draft = try await save(
            Invoice.fixture(number: "20260601", duzp: "2026-06-15", status: .draft), in: database)
        try await save(Invoice.fixture(number: "20251201", duzp: "2025-12-31"), in: database)
        try await save(Invoice.fixture(number: "20270101", duzp: "2027-01-01"), in: database)

        let list = try await database.invoices(scope: .issued, year: 2026, asOf: civilDate("2026-03-01"))

        // The as-of day does not matter for the issued list, and the invoices come in full.
        #expect(list == [last, draft, first])
        #expect(list[0].payment?.date == civilDate("2027-01-05"))
    }

    @Test func thePaidListHoldsTheInvoicesPaidInTheYearUpToTheAsOfDay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let january = try await save(
            Invoice.fixture(number: "20251201", duzp: "2025-12-15", payment: .fixture(on: "2026-01-01")), in: database)
        let june = try await save(
            Invoice.fixture(number: "20260501", duzp: "2026-05-31", payment: .fixture(on: "2026-06-30")), in: database)
        let december = try await save(
            Invoice.fixture(number: "20261101", duzp: "2026-11-30", payment: .fixture(on: "2026-12-31")), in: database)
        try await save(
            Invoice.fixture(number: "20251101", duzp: "2025-11-30", payment: .fixture(on: "2025-12-31")), in: database)
        try await save(
            Invoice.fixture(number: "20261201", duzp: "2026-12-01", payment: .fixture(on: "2027-01-01")), in: database)
        try await save(Invoice.fixture(number: "20260901", duzp: "2026-09-01"), in: database)

        func paid(asOf day: String) async throws -> [Invoice] {
            try await database.invoices(scope: .paid, year: 2026, asOf: civilDate(day))
        }

        // Newest first by the date of issue.
        #expect(try await paid(asOf: "2026-12-31") == [december, june, january])
        #expect(try await paid(asOf: "2026-10-17") == [june, january])
        #expect(try await paid(asOf: "2026-06-30") == [june, january])
        #expect(try await paid(asOf: "2026-06-29") == [january])
        #expect(try await paid(asOf: "2026-01-01") == [january])
        #expect(try await paid(asOf: "2025-12-31").isEmpty)
        #expect(try await paid(asOf: "2030-01-01") == [december, june, january])
    }

    @Test func aPaidInvoiceInReviewIsStillInThePaidListOfTheYearOfItsPayment() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let review = try await save(
            Invoice.fixture(review: ReviewFlag(reason: "Zkontrolovat"), payment: .fixture(on: "2026-10-05")),
            in: database)

        let list = try await database.invoices(scope: .paid, year: 2026, asOf: civilDate("2026-10-17"))

        #expect(list == [review])
    }

    @Test func listsAreNewestFirstByIssueDateThenNumberAndNumbersCompareByTheirDigits() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let invoices = [
            ("20260901", "2026-09-30"), ("20260902", "2026-09-30"), ("2026-09-03", "2026-09-30"),
            ("20261001", "2026-08-01"), ("20260801", "2026-10-02"),
        ]
        for (number, issued) in invoices {
            try await save(Invoice.fixture(number: number, issued: issued, duzp: "2026-09-30"), in: database)
        }

        let list = try await database.invoices(scope: .issued, year: 2026, asOf: civilDate("2026-10-17"))

        // The day of issue first, however low the number. Of the three invoices issued on the same day the highest
        // number comes first: 20260903 is above 20260902 although the printed "2026-09-03" is below "20260902" as text.
        #expect(list.map(\.number) == ["20260801", "2026-09-03", "20260902", "20260901", "20261001"])
    }

    /// The list of Faktury and the bars of the chart belong to the year of the day of issue. The DUZP decides the month
    /// of the VAT only.
    @Test func theIssuedListTheChartAndTheCurrenciesGoByTheDayOfIssueAndNotByTheDUZP() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Supplied on 31 December 2025 and issued on 2 January 2026.
        let invoice = try await save(
            Invoice.fixture(
                number: "20251201", currency: .usd, issued: "2026-01-02", duzp: "2025-12-31",
                vatMode: .outsideCountry),
            in: database)
        let today = civilDate("2026-10-17")

        #expect(try await database.invoices(scope: .issued, year: 2026, asOf: today) == [invoice])
        #expect(try await database.invoices(scope: .issued, year: 2025, asOf: today).isEmpty)
        #expect(
            try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-17"))
                .map(\.id) == [invoice.id])
        #expect(try await database.chartRows(fromYear: 2025, throughYear: 2025, today: civilDate("2026-10-17")).isEmpty)
        #expect(try await database.foreignCurrencies(year: 2026) == [.usd])
        #expect(try await database.foreignCurrencies(year: 2025).isEmpty)
        #expect(try await database.yearsWithData() == [2026])
    }

    @Test func aYearOutsideTheCalendarGivesNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await save(Invoice.fixture(), in: database)
        let day = civilDate("2026-10-17")

        #expect(try await database.invoices(scope: .issued, year: 0, asOf: day).isEmpty)
        #expect(try await database.invoices(scope: .paid, year: 10_000, asOf: day).isEmpty)
        #expect(try await database.receipts(year: -5).isEmpty)
        #expect(try await database.paidInvoices(year: 0).isEmpty)
        #expect(try await database.chartRows(fromYear: 0, throughYear: 0, today: civilDate("2026-10-17")).isEmpty)
        #expect(try await database.chartRows(fromYear: 2026, throughYear: 2025, today: civilDate("2026-10-17")).isEmpty)
        #expect(try await database.vatByDUZPMonth(year: 0) == [Int64](repeating: 0, count: 12))
        #expect(try await database.foreignCurrencies(year: 10_000).isEmpty)
    }

    // MARK: Receipts

    /// The money counts in the year it arrived, whatever the year of the invoice.
    @Test func theReceiptsOfAYearAreItsPaymentsOfIssuedInvoicesAndItsAdjustmentsByDay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let yearEnd = try await save(Self.yearEndInvoice(), in: database)
        let adjustmentID = try await database.saveAdjustment(Self.adjustment("2026-03-15", -100_000, "Dobropis"))
        // A draft and an invoice in review do not count, even with a payment in the year.
        try await save(
            Invoice.fixture(
                number: "20260101", duzp: "2026-01-31", status: .draft, payment: .fixture(on: "2026-02-10")),
            in: database)
        try await save(
            Invoice.fixture(
                number: "20260201", duzp: "2026-02-28", review: ReviewFlag(reason: "Zkontrolovat"),
                payment: .fixture(on: "2026-03-05")),
            in: database)
        // Other years: paid before, paid after, and an adjustment of another year.
        try await save(
            Invoice.fixture(number: "20251101", duzp: "2025-11-30", payment: .fixture(on: "2025-12-31")), in: database)
        try await save(
            Invoice.fixture(number: "20261201", duzp: "2026-12-31", payment: .fixture(on: "2027-01-01")), in: database)
        try await database.saveAdjustment(Self.adjustment("2025-12-31", 5, "Loni"))

        let receipts = try await database.receipts(year: 2026)

        #expect(
            receipts == [
                Receipt(
                    day: civilDate("2026-01-02"), czkNetHalere: 450_000, czkVatHalere: 94_500,
                    source: .invoice(yearEnd.id)),
                Receipt(
                    day: civilDate("2026-03-15"), czkNetHalere: -100_000, czkVatHalere: 0,
                    source: .adjustment(adjustmentID)),
            ])
        // In 2025 it is the other way round: the invoice paid in 2025 counts, the year-end invoice does not.
        let earlier = try await database.receipts(year: 2025)
        #expect(earlier.count == 2)
        #expect(earlier.map(\.day) == [civilDate("2025-12-31"), civilDate("2025-12-31")])
        #expect(!earlier.contains { $0.source == .invoice(yearEnd.id) })
    }

    @Test func aPaymentOnNewYearsDayCountsInTheNewYearAtTheLastRateOfTheYearBefore() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await loadRates(into: database)
        var invoice = Invoice.fixture(
            number: "20251201", currency: .usd, duzp: "2025-12-30", dueDate: "2026-01-14",
            items: [.fixture("10", at: 100_000)], vatMode: .outsideCountry)
        // 1 January is not a day the ČNB declares rates: the rate of 31 December 2025 is the one.
        let lookup = try await database.cnbRate(.usd, on: civilDate("2026-01-01"))
        #expect(lookup == declaredLookup("USD", "20.632", on: "2025-12-31"))
        invoice.payment = PaymentConverter.convert(
            invoice: invoice, date: civilDate("2026-01-01"), requested: .cnbDaily, bankCZKTotalHalere: nil,
            cnbRate: lookup, uniformRate: nil)
        let saved = try await save(invoice, in: database)

        // 10 000,00 USD at 20,632 Kč: 206 320,00 Kč.
        #expect(
            try await database.receipts(year: 2026) == [
                Receipt(
                    day: civilDate("2026-01-01"), czkNetHalere: 20_632_000, czkVatHalere: 0,
                    source: .invoice(saved.id))
            ])
        #expect(try await database.receipts(year: 2025).isEmpty)
        // The chart bar belongs to the year of issue, and the paid list to the year of the payment.
        let bar = try await database.chartRows(fromYear: 2025, throughYear: 2025, today: civilDate("2026-10-17"))
        #expect(bar.map(\.id) == [saved.id])
        #expect(bar.first?.issueDate == civilDate("2025-12-30"))
        let today = civilDate("2026-10-17")
        #expect(try await database.invoices(scope: .issued, year: 2025, asOf: today).map(\.id) == [saved.id])
        #expect(try await database.invoices(scope: .paid, year: 2026, asOf: today).map(\.id) == [saved.id])
        #expect(try await database.invoices(scope: .issued, year: 2026, asOf: today).isEmpty)
    }

    @Test func receiptsOfOneDayComeInvoicePaymentsFirstThenAdjustmentsAndTheEdgesOfTheYearCount() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let late = try await save(
            Invoice.fixture(number: "20260901", payment: .fixture(on: "2026-12-31", net: 300, vat: 63)), in: database)
        let early = try await save(
            Invoice.fixture(number: "20260902", payment: .fixture(on: "2026-01-01", net: 100, vat: 21)), in: database)
        let sameDay = try await save(
            Invoice.fixture(number: "20260903", payment: .fixture(on: "2026-06-30", net: 200, vat: 42)), in: database)
        let adjustmentOnSameDay = try await database.saveAdjustment(Self.adjustment("2026-06-30", -50, "Dobropis"))
        let adjustmentFirstDay = try await database.saveAdjustment(Self.adjustment("2026-01-01", 7, "Nový rok"))

        let receipts = try await database.receipts(year: 2026)

        #expect(
            receipts.map(\.source) == [
                .invoice(early.id), .adjustment(adjustmentFirstDay), .invoice(sameDay.id),
                .adjustment(adjustmentOnSameDay), .invoice(late.id),
            ])
        #expect(receipts.map(\.czkNetHalere) == [100, 7, 200, -50, 300])
        #expect(receipts.map(\.czkVatHalere) == [21, 0, 42, 0, 63])
    }

    // MARK: Years, currencies and VAT

    @Test func theYearsWithDataAreTheIssueYearsAndThePaymentYearsOfInvoices() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.yearsWithData().isEmpty)

        try await save(Self.yearEndInvoice(), in: database)

        #expect(try await database.yearsWithData() == [2025, 2026])
    }

    @Test func draftsAddNoYearButPaymentsAndStoredYearSettingsDo() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await save(Invoice.fixture(number: "20240301", duzp: "2024-03-01", status: .draft), in: database)
        // Issued in 2023 and paid in 2024: both years have data, and 2024 only because of the payment.
        try await save(
            Invoice.fixture(number: "20231201", duzp: "2023-12-01", payment: .fixture(on: "2024-01-10")), in: database)
        try await save(Invoice.fixture(number: "20260901"), in: database)
        try await database.saveYearSettings(YearSettings(year: 2022))
        try await database.saveYearSettings(YearSettings(year: 2026))

        // Oldest first, each year once.
        #expect(try await database.yearsWithData() == [2022, 2023, 2024, 2026])
    }

    @Test func aDraftIsNotEnoughForAYearEvenWhenItIsTheOnlyInvoice() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await save(Invoice.fixture(status: .draft), in: database)

        #expect(try await database.yearsWithData().isEmpty)
    }

    @Test func theForeignCurrenciesOfAYearIgnoreDraftsAndCrownsAndAreSorted() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let pound = try #require(CurrencyCode("GBP"))
        func invoice(
            _ number: String, _ currency: CurrencyCode, _ day: String, status: InvoiceStatus = .issued,
            paidOn paid: String? = nil
        ) -> Invoice {
            Invoice.fixture(
                number: number, currency: currency, duzp: day, vatMode: .outsideCountry, status: status,
                payment: paid.map { .fixture(on: $0, conversion: .cnbDaily) })
        }
        try await save(invoice("20260301", .usd, "2026-03-01"), in: database)
        try await save(invoice("20260302", .usd, "2026-03-02"), in: database)
        // A draft: the euro is not a currency of the year.
        try await save(invoice("20260401", .eur, "2026-04-01", status: .draft), in: database)
        // Issued in 2025 and paid in 2026: a currency of both years.
        try await save(invoice("20251201", pound, "2025-12-20", paidOn: "2026-01-05"), in: database)
        // Crowns are no foreign currency.
        try await save(invoice("20260501", .czk, "2026-05-01", paidOn: "2026-05-10"), in: database)
        // A draft with a payment in 2026 does not count either.
        try await save(invoice("20251202", .eur, "2025-12-21", status: .draft, paidOn: "2026-01-06"), in: database)

        #expect(try await database.foreignCurrencies(year: 2026) == [pound, .usd])
        #expect(try await database.foreignCurrencies(year: 2025) == [pound])
        #expect(try await database.foreignCurrencies(year: 2024).isEmpty)
    }

    @Test func theVATOfAMonthIsGroupedByTheDUZPAndForeignVATIsConvertedAtTheInvoiceRate() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // January: 945,00 Kč (DUZP 31 January, issued in February) and 624,00 Kč (12 % of 4 500,00 Kč).
        try await save(Invoice.fixture(number: "20260101", issued: "2026-02-03", duzp: "2026-01-31"), in: database)
        try await save(Invoice.fixture(number: "20260102", duzp: "2026-01-15", vatMode: .domestic12), in: database)
        // March: 21 % of 100,00 USD is 21,00 USD, at 21,5 Kč: 451,50 Kč.
        try await save(
            Invoice.fixture(
                number: "20260301", currency: .usd, duzp: "2026-03-31", items: [.fixture("1", at: 10_000)],
                invoiceRate: storedRate("USD", "21.5", declaredOn: "2026-03-31")),
            in: database)
        // A draft, a year-end invoice of 2025 issued in 2026, and a foreign invoice with no VAT.
        try await save(Invoice.fixture(number: "20260302", duzp: "2026-03-10", status: .draft), in: database)
        try await save(Invoice.fixture(number: "20251201", issued: "2026-01-02", duzp: "2025-12-31"), in: database)
        try await save(
            Invoice.fixture(
                number: "20260401", currency: .usd, duzp: "2026-04-30", vatMode: .outsideCountry,
                invoiceRate: storedRate("USD", "21.5", declaredOn: "2026-04-30")),
            in: database)
        // An invoice to check counts only once it is resolved.
        let held = try await save(
            Invoice.fixture(number: "20261101", duzp: "2026-11-05", review: ReviewFlag(reason: "Zkontrolovat")),
            in: database)

        let vat = try await database.vatByDUZPMonth(year: 2026)

        #expect(vat.count == 12)
        #expect(vat == [148_500, 0, 45_150, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(try await database.monthsWithVATToCheck(year: 2026) == [11])
        // December 2025 holds the VAT of the invoice supplied on 31 December.
        #expect(try await database.vatByDUZPMonth(year: 2025) == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 94_500])
        #expect(try await database.vatByDUZPMonth(year: 2024) == [Int64](repeating: 0, count: 12))

        var resolved = try #require(try await database.invoice(id: held.id))
        resolved.review = nil
        try await database.saveInvoice(resolved)

        #expect(try await database.vatByDUZPMonth(year: 2026) == [148_500, 0, 45_150, 0, 0, 0, 0, 0, 0, 0, 94_500, 0])
        #expect(try await database.monthsWithVATToCheck(year: 2026).isEmpty)
    }

    @Test func theMonthsWithVATToCheckAreThoseOfInvoicesInReviewWithVATThatAreNoDrafts() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let toCheck = ReviewFlag(reason: "zrušeno ve Fakturoidu")
        try await save(Invoice.fixture(number: "20260201", duzp: "2026-02-10", review: toCheck), in: database)
        // A draft to check, an invoice to check without VAT, one of another year and one that is resolved.
        try await save(
            Invoice.fixture(number: "20260301", duzp: "2026-03-10", status: .draft, review: toCheck), in: database)
        try await save(
            Invoice.fixture(
                number: "20260401", currency: .usd, duzp: "2026-04-30", vatMode: .outsideCountry,
                invoiceRate: storedRate("USD", "21.5", declaredOn: "2026-04-30"), review: toCheck),
            in: database)
        try await save(Invoice.fixture(number: "20251201", duzp: "2025-12-31", review: toCheck), in: database)
        try await save(Invoice.fixture(number: "20260501", duzp: "2026-05-05"), in: database)

        #expect(try await database.monthsWithVATToCheck(year: 2026) == [2])
        #expect(try await database.monthsWithVATToCheck(year: 2025) == [12])
        #expect(try await database.monthsWithVATToCheck(year: 0).isEmpty)
    }

    @Test func eachForeignInvoiceIsConvertedOnItsOwnAndAnInvoiceWithoutARateAddsNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // 0,05 USD with 21 % VAT is 0,01 USD, which is 21,5 haléře at 21,5 Kč and rounds half up to 22 on each.
        let tiny = [InvoiceItem.fixture("1", at: 5)]
        let rate = storedRate("USD", "21.5", declaredOn: "2026-05-29")
        for (number, day) in [("20260501", "2026-05-29"), ("20260502", "2026-05-30")] {
            try await save(
                Invoice.fixture(number: number, currency: .usd, duzp: day, items: tiny, invoiceRate: rate),
                in: database)
        }
        // The same VAT with no rate fixed on the invoice has no value in crowns.
        try await save(
            Invoice.fixture(number: "20260503", currency: .usd, duzp: "2026-05-31", items: tiny), in: database)

        let vat = try await database.vatByDUZPMonth(year: 2026)

        #expect(vat[4] == 44)
        #expect(vat.reduce(0, +) == 44)
    }

    // MARK: Chart rows

    /// Future issue dates use only declarations available by real today, even when later data is already stored.
    @Test func futureIssuedChartsIgnoreDeclarationsAfterToday() async throws {
        try await checkFutureIssuedChartRate(includingExactDeclaration: false)
    }

    /// The exact business-day declaration for a future issue date cannot override the rate known by real today.
    @Test func futureIssuedChartsIgnoreAnExactFutureDeclaration() async throws {
        try await checkFutureIssuedChartRate(includingExactDeclaration: true)
    }

    /// A future declaration alone leaves a future-issued invoice unknown rather than borrowing tomorrow's rate.
    @Test func futureIssuedChartsHaveNoRateWhenNothingWasDeclaredByToday() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-29"), currency: .usd, amount: 1, rate: decimal("30")),
        ])
        try await save(
            Invoice.fixture(currency: .usd, issued: "2026-10-31", duzp: "2026-10-31"), in: database)

        let rows = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-28"))
        let row = try #require(rows.first)
        #expect(row.issueDayRate == nil)
        #expect(!row.issueDayRateIsProvisional)
    }

    /// A USD 100 invoice issued on 31 October is worth CZK 2,000 at the last rate known on 28 October.
    private func checkFutureIssuedChartRate(includingExactDeclaration: Bool) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var rates = [
            CNBRateRow(declaredOn: civilDate("2026-10-27"), currency: .usd, amount: 1, rate: decimal("20")),
            CNBRateRow(declaredOn: civilDate("2026-10-29"), currency: .usd, amount: 1, rate: decimal("30")),
        ]
        if includingExactDeclaration {
            rates.append(
                CNBRateRow(declaredOn: civilDate("2026-10-30"), currency: .usd, amount: 1, rate: decimal("40")))
        }
        try await database.insertCNBRates(rates)
        let invoice = try await save(
            Invoice.fixture(
                currency: .usd, issued: "2026-10-31", duzp: "2026-10-31",
                items: [InvoiceItem.fixture("1", at: 10_000)], vatMode: .outsideCountry), in: database)

        let rows = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-28"))
        #expect(rows.map(\.id) == [invoice.id])
        let row = try #require(rows.first)
        #expect(row.issueDayRate?.czkHalere(fromMinor: row.netMinor) == 200_000)
        #expect(row.issueDayRateIsProvisional)
        #expect(row.paymentDate == nil && row.paymentNetHalere == nil)
    }

    @Test func chartRowsCarryTheRateOfTheIssueDayFromTheStoredCNBRates() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await loadRates(into: database)
        // 17 October 2026 is a Saturday: the rate declared on Friday the 16th is the one.
        let saturday = try await save(
            Invoice.fixture(number: "20261001", currency: .usd, duzp: "2026-10-17", vatMode: .outsideCountry),
            in: database)
        let friday = try await save(
            Invoice.fixture(number: "20261002", currency: .eur, duzp: "2026-10-16", vatMode: .outsideCountry),
            in: database)
        // After real today: use its latest rate provisionally. The first day of the year takes the last rate of
        // the year before.
        let monday = try await save(
            Invoice.fixture(number: "20261003", currency: .usd, duzp: "2026-10-19", vatMode: .outsideCountry),
            in: database)
        let newYear = try await save(
            Invoice.fixture(number: "20260101", currency: .usd, duzp: "2026-01-01", vatMode: .outsideCountry),
            in: database)
        // Crowns need no rate.
        let crowns = try await save(Invoice.fixture(number: "20261004", duzp: "2026-10-16"), in: database)

        let rows = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-17"))

        let usd = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.622"))
        #expect(
            rows.first { $0.id == saturday.id }
                == InvoiceChartRow(
                    id: saturday.id, issueDate: civilDate("2026-10-17"), isDraft: false, inReview: false,
                    currency: .usd, netMinor: 450_000, vatMinor: 0, paymentDate: nil, paymentNetHalere: nil,
                    paymentVatHalere: nil, issueDayRate: usd))
        #expect(
            rows.first { $0.id == friday.id }?.issueDayRate
                == ExchangeRate(currency: .eur, amount: 1, rate: decimal("24.325")))
        #expect(rows.first { $0.id == monday.id }?.issueDayRate == usd)
        #expect(rows.first { $0.id == monday.id }?.issueDayRateIsProvisional == true)
        #expect(
            rows.first { $0.id == newYear.id }?.issueDayRate
                == ExchangeRate(currency: .usd, amount: 1, rate: decimal("20.632")))
        let czk = try #require(rows.first { $0.id == crowns.id })
        #expect(czk.issueDayRate == nil && czk.currency == .czk && czk.netMinor == 450_000 && czk.vatMinor == 94_500)
    }

    @Test func chartRowsHaveNoRateForACurrencyTheCNBDoesNotQuoteOrWhenNoRatesAreStored() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let (bare, bareDirectory) = try makeDatabase()
        defer { removeTemporaryDirectory(bareDirectory) }
        try await loadRates(into: database)
        let unknown = try #require(CurrencyCode("XYZ"))
        let unquoted = try await save(
            Invoice.fixture(currency: unknown, duzp: "2026-10-15", vatMode: .outsideCountry), in: database)
        let withoutRates = try await save(
            Invoice.fixture(currency: .usd, duzp: "2026-10-15", vatMode: .outsideCountry), in: bare)

        let rows = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-17"))
        let rowsWithoutRates = try await bare.chartRows(
            fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-17"))

        #expect(rows.map(\.id) == [unquoted.id] && rows[0].issueDayRate == nil)
        #expect(rowsWithoutRates.map(\.id) == [withoutRates.id] && rowsWithoutRates[0].issueDayRate == nil)
    }

    @Test func chartRowsHoldTheInvoicesIssuedInTheYearsAndThoseOnlyPaidInThemOnceEach() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Saved in an order other than the days of issue, so that the ids do not come in the order of the days.
        let review = try await save(
            Invoice.fixture(number: "20260601", duzp: "2026-06-01", review: ReviewFlag(reason: "?")), in: database)
        let twin = try await save(Invoice.fixture(number: "20260402", duzp: "2026-04-01"), in: database)
        let unpaid = try await save(Invoice.fixture(number: "20260401", duzp: "2026-04-01"), in: database)
        let yearEnd = try await save(Self.yearEndInvoice(), in: database)
        let draft = try await save(
            Invoice.fixture(number: "20260501", duzp: "2026-05-01", status: .draft), in: database)
        let inYear = try await save(
            Invoice.fixture(number: "20260301", duzp: "2026-03-01", payment: .fixture(on: "2026-03-20")), in: database)
        let old = try await save(
            Invoice.fixture(number: "20240101", duzp: "2024-01-01", payment: .fixture(on: "2024-01-20")), in: database)
        let future = try await save(Invoice.fixture(number: "20270101", duzp: "2027-01-01"), in: database)

        let year2026 = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-17"))
        let years = try await database.chartRows(fromYear: 2025, throughYear: 2026, today: civilDate("2026-10-17"))
        let year2025 = try await database.chartRows(fromYear: 2025, throughYear: 2025, today: civilDate("2026-10-17"))

        // Ascending by the day of issue, then by id. The year-end invoice is a bar of 2025, and its payment is a
        // point of the line in 2026, so both years need its row.
        let all2026 = [yearEnd, inYear, twin, unpaid, draft, review].map(\.id)
        #expect(year2026.map(\.id) == all2026)
        #expect(years.map(\.id) == all2026)
        #expect(year2025.map(\.id) == [yearEnd.id])
        #expect(!years.map(\.id).contains(old.id) && !years.map(\.id).contains(future.id))
        let byID = Dictionary(uniqueKeysWithValues: years.map { ($0.id, $0) })
        #expect(byID[yearEnd.id]?.paymentDate == civilDate("2026-01-02"))
        #expect(byID[yearEnd.id]?.paymentNetHalere == 450_000 && byID[yearEnd.id]?.paymentVatHalere == 94_500)
        #expect(byID[yearEnd.id]?.issueDate == civilDate("2025-12-31"))
        #expect(byID[unpaid.id]?.paymentDate == nil && byID[unpaid.id]?.paymentNetHalere == nil)
        #expect(byID[draft.id]?.isDraft == true && byID[draft.id]?.inReview == false)
        #expect(byID[review.id]?.inReview == true && byID[review.id]?.isDraft == false)
        #expect(byID[inYear.id]?.isDraft == false && byID[inYear.id]?.inReview == false)
    }

    @Test func chartRowsOfSeveralYearsHoldEachInvoiceOnceWhenIssuedAndPaidInTheRange() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        for (number, issued, paid) in [
            ("20221201", "2022-12-01", "2023-01-05"), ("20230301", "2023-03-01", "2023-03-30"),
            ("20240301", "2024-03-01", "2025-02-10"), ("20250301", "2025-03-01", "2025-04-02"),
        ] {
            try await save(
                Invoice.fixture(number: number, duzp: issued, payment: .fixture(on: paid)), in: database)
        }

        let rows = try await database.chartRows(fromYear: 2023, throughYear: 2024, today: civilDate("2026-10-17"))

        // 2022-12 is paid in the range, 2025-03 is outside it altogether. Nothing is twice in the list.
        #expect(rows.map(\.issueDate) == [civilDate("2022-12-01"), civilDate("2023-03-01"), civilDate("2024-03-01")])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    // MARK: Invoices due by the end of a month

    /// The unpaid invoices due by the end of November 2026 that were issued since the start of 2025, as read on Sunday
    /// 1 November 2026.
    private func dueUnpaidRows(in database: Database) async throws -> [InvoiceChartRow] {
        try await database.dueUnpaidRows(
            issuedFrom: civilDate("2025-01-01"), dueThrough: civilDate("2026-11-30"), today: civilDate("2026-11-01"))
    }

    @Test func onlyTheIssuedUnpaidInvoicesDueByTheLastDayOfTheMonthAreRead() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // None of these is read.
        for invoice in [
            // Due the day after the last day of the month.
            Self.dueInvoice("20261005", issued: "2026-10-31", due: "2026-12-01"),
            // A draft, and an invoice held for review, are not income.
            Self.dueInvoice("20261006", issued: "2026-10-28", due: "2026-11-10", status: .draft),
            Self.dueInvoice("20261007", issued: "2026-10-28", due: "2026-11-10", review: ReviewFlag(reason: "?")),
            // The money has come: it was paid before today, and it was paid today.
            Self.dueInvoice("20261008", issued: "2026-10-01", due: "2026-10-15", payment: .fixture(on: "2026-10-30")),
            Self.dueInvoice("20261009", issued: "2026-10-01", due: "2026-10-15", payment: .fixture(on: "2026-11-01")),
            // Issued the day before the first day of last year.
            Self.dueInvoice("20241201", issued: "2024-12-31", due: "2025-01-10"),
        ] {
            try await save(invoice, in: database)
        }
        // All of these are read. They are saved in an order other than the days they are due, so that the ids do not
        // come in the order of the days.
        let lastDay = try await save(
            Self.dueInvoice("20261004", issued: "2026-10-31", due: "2026-11-30", net: 500_000), in: database)
        let midMonth = try await save(
            Self.dueInvoice("20261002", issued: "2026-10-20", due: "2026-11-14", net: 300_000), in: database)
        let lastDecember = try await save(
            Self.dueInvoice("20251201", issued: "2025-12-20", due: "2026-01-05", net: 100_000), in: database)
        // A payment dated after today has not come yet.
        let paidLater = try await save(
            Self.dueInvoice(
                "20261003", issued: "2026-10-25", due: "2026-11-20", net: 400_000,
                payment: .fixture(on: "2026-11-25", net: 400_000, vat: 84_000)),
            in: database)
        let overdue = try await save(
            Self.dueInvoice("20261001", issued: "2026-10-01", due: "2026-10-15", net: 200_000), in: database)

        let rows = try await dueUnpaidRows(in: database)

        #expect(rows.map(\.id) == [lastDecember, overdue, midMonth, paidLater, lastDay].map(\.id))
        #expect(rows.map(\.netMinor) == [100_000, 200_000, 300_000, 400_000, 500_000])
        #expect(rows.map(\.vatMinor) == [21_000, 42_000, 63_000, 84_000, 105_000])
        // A row is a chart row: what was issued and what was paid, as the rows of the chart have it.
        #expect(
            rows.first { $0.id == lastDecember.id }
                == InvoiceChartRow(
                    id: lastDecember.id, issueDate: civilDate("2025-12-20"), isDraft: false, inReview: false,
                    currency: .czk, netMinor: 100_000, vatMinor: 21_000, paymentDate: nil, paymentNetHalere: nil,
                    paymentVatHalere: nil, issueDayRate: nil))
        #expect(
            rows.first { $0.id == paidLater.id }
                == InvoiceChartRow(
                    id: paidLater.id, issueDate: civilDate("2026-10-25"), isDraft: false, inReview: false,
                    currency: .czk, netMinor: 400_000, vatMinor: 84_000, paymentDate: civilDate("2026-11-25"),
                    paymentNetHalere: 400_000, paymentVatHalere: 84_000, issueDayRate: nil))
    }

    @Test func anInvoiceIssuedOnTheFirstDayOfLastYearIsRead() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let first = try await save(Self.dueInvoice("20250101", issued: "2025-01-01", due: "2025-01-15"), in: database)

        let rows = try await dueUnpaidRows(in: database)

        #expect(rows.map(\.id) == [first.id])
    }

    @Test func invoicesComeByTheDayTheyAreDueThenByIdWhateverTheDayOfIssue() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // The first two are due on one day, and the one with the lower id was issued later. The third is due earlier
        // and was issued last. The days of issue alone would put the second first and the third last.
        let first = try await save(Self.dueInvoice("20261001", issued: "2026-10-25", due: "2026-11-20"), in: database)
        let second = try await save(Self.dueInvoice("20261002", issued: "2026-10-20", due: "2026-11-20"), in: database)
        let earlier = try await save(Self.dueInvoice("20261003", issued: "2026-10-30", due: "2026-11-05"), in: database)

        let rows = try await dueUnpaidRows(in: database)

        #expect(rows.map(\.id) == [earlier.id, first.id, second.id])
    }

    @Test func aForeignInvoiceDueThisMonthHasTheRateOfItsDayOfIssue() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Friday 16 October is the newest declaration, so the rates of the days after it are not stored yet.
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-15"), currency: .usd, amount: 1, rate: decimal("21")),
            CNBRateRow(declaredOn: civilDate("2026-10-16"), currency: .usd, amount: 1, rate: decimal("22")),
        ])
        let declared = try await save(
            Self.dueInvoice(
                "20261001", issued: "2026-10-15", due: "2026-11-14", currency: .usd, vatMode: .outsideCountry),
            in: database)
        let notDeclared = try await save(
            Self.dueInvoice(
                "20261002", issued: "2026-10-28", due: "2026-11-27", currency: .usd, vatMode: .outsideCountry),
            in: database)
        // The rates stored are the dollar's only, so the euro has no rate. Crowns need none.
        let unquoted = try await save(
            Self.dueInvoice(
                "20261003", issued: "2026-10-15", due: "2026-11-20", currency: .eur, vatMode: .outsideCountry),
            in: database)
        let crowns = try await save(Self.dueInvoice("20261004", issued: "2026-10-15", due: "2026-11-21"), in: database)

        let rows = try await dueUnpaidRows(in: database)

        #expect(rows.map(\.id) == [declared, unquoted, crowns, notDeclared].map(\.id))
        let declaredRow = try #require(rows.first { $0.id == declared.id })
        #expect(declaredRow.issueDayRate == ExchangeRate(currency: .usd, amount: 1, rate: decimal("21")))
        #expect(!declaredRow.issueDayRateIsProvisional)
        // 1 000,00 dollars at 21 crowns.
        #expect(declaredRow.issueDayRate?.czkHalere(fromMinor: declaredRow.netMinor) == 2_100_000)
        // The day is after the newest declaration, so the latest rate before it stands in until it is declared.
        let notDeclaredRow = try #require(rows.first { $0.id == notDeclared.id })
        #expect(notDeclaredRow.issueDayRate == ExchangeRate(currency: .usd, amount: 1, rate: decimal("22")))
        #expect(notDeclaredRow.issueDayRateIsProvisional)
        for id in [unquoted.id, crowns.id] {
            let row = try #require(rows.first { $0.id == id })
            #expect(row.issueDayRate == nil && !row.issueDayRateIsProvisional)
        }
    }

    @Test func aForeignInvoiceIssuedAfterTodayHasTheLatestRateDeclaredByTodayEvenWhenLaterOnesAreStored() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // Monday 2 November is declared in this database already, but today is Sunday 1 November.
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-16"), currency: .usd, amount: 1, rate: decimal("22")),
            CNBRateRow(declaredOn: civilDate("2026-11-02"), currency: .usd, amount: 1, rate: decimal("30")),
        ])
        let later = try await save(
            Self.dueInvoice(
                "20261101", issued: "2026-11-20", due: "2026-11-30", currency: .usd, vatMode: .outsideCountry),
            in: database)

        let rows = try await dueUnpaidRows(in: database)

        #expect(rows.map(\.id) == [later.id])
        #expect(rows.first?.issueDayRate == ExchangeRate(currency: .usd, amount: 1, rate: decimal("22")))
        #expect(rows.first?.issueDayRateIsProvisional == true)
    }

    // MARK: Payments to work out again

    @Test func provisionalPaymentsAreThoseMarkedProvisionalInEveryYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rate = storedRate("USD", "21.5", declaredOn: "2026-10-16")
        let provisionalNow = try await save(
            Invoice.fixture(
                number: "20261001", currency: .usd, duzp: "2026-10-01", vatMode: .outsideCountry, invoiceRate: rate,
                payment: .fixture(on: "2026-10-17", conversion: .cnbDaily, rate: rate, provisional: true)),
            in: database)
        let provisionalBefore = try await save(
            Invoice.fixture(
                number: "20250101", currency: .usd, duzp: "2025-01-01", vatMode: .outsideCountry, invoiceRate: rate,
                payment: .fixture(on: "2025-02-17", conversion: .uniform, rate: rate, provisional: true)),
            in: database)
        try await save(
            Invoice.fixture(
                number: "20261002", currency: .usd, duzp: "2026-10-02", vatMode: .outsideCountry,
                payment: .fixture(on: "2026-10-17", conversion: .cnbDaily, rate: rate)),
            in: database)
        try await save(Invoice.fixture(number: "20261003"), in: database)

        // Newest first, in full.
        #expect(try await database.provisionalPayments() == [provisionalNow, provisionalBefore])
    }

    @Test func noProvisionalPaymentsMeansAnEmptyList() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.provisionalPayments().isEmpty)
    }

    @Test func thePaidInvoicesOfAYearAreThoseWithAPaymentDatedInItWhateverTheirState() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let yearEnd = try await save(Self.yearEndInvoice(), in: database)
        let review = try await save(
            Invoice.fixture(
                number: "20260901", review: ReviewFlag(reason: "Zkontrolovat"), payment: .fixture(on: "2026-10-05")),
            in: database)
        // A payment after any as-of day of the year is still the year's, and the payments of other years are not.
        let december = try await save(
            Invoice.fixture(number: "20261101", duzp: "2026-11-30", payment: .fixture(on: "2026-12-31")), in: database)
        try await save(
            Invoice.fixture(number: "20251101", duzp: "2025-11-30", payment: .fixture(on: "2025-12-31")), in: database)
        try await save(Invoice.fixture(number: "20260801", duzp: "2026-08-01"), in: database)

        #expect(try await database.paidInvoices(year: 2026) == [december, review, yearEnd])
        #expect(try await database.paidInvoices(year: 2025).count == 1)
        #expect(try await database.paidInvoices(year: 2024).isEmpty)
    }

    @Test func theNumberOfInvoicesCountsDraftsAndEveryYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.invoiceCount() == 0)

        try await save(Invoice.fixture(number: "20250901", duzp: "2025-09-01"), in: database)
        try await save(Invoice.fixture(number: "20260901", status: .draft), in: database)
        let third = try await save(Invoice.fixture(number: "20260902"), in: database)
        #expect(try await database.invoiceCount() == 3)

        try await database.deleteInvoice(id: third.id)
        #expect(try await database.invoiceCount() == 2)
    }

    /// What the Koncepty chip of Faktury counts, for the badge of Faktury in the sidebar: the drafts issued in the
    /// year, by the day of issue.
    @Test func theDraftsOfAYearAreTheDraftsIssuedInIt() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await save(Invoice.fixture(number: "20260901", status: .draft), in: database)
        try await save(Invoice.fixture(number: "20261001", duzp: "2026-10-01", status: .draft), in: database)
        try await save(Invoice.fixture(number: "20260902"), in: database)
        try await save(Invoice.fixture(number: "20251201", duzp: "2025-12-31", status: .draft), in: database)
        try await save(
            Invoice.fixture(number: "20270101", issued: "2027-01-01", duzp: "2026-12-31", status: .draft), in: database)

        #expect(try await database.draftCount(year: 2026) == 2)
        #expect(try await database.draftCount(year: 2025) == 1)
        #expect(try await database.draftCount(year: 2027) == 1)
        #expect(try await database.draftCount(year: 2024) == 0)
    }

    // MARK: Transactions

    @Test func aSaveThatFailsHalfWayLeavesNothingBehind() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // The payment fails last: a rate quoted for no units cannot be stored.
        let impossible = ExchangeRate(currency: .usd, amount: 0, rate: decimal("21.5"))
        let invoice = Invoice.fixture(
            items: [.fixture("1", at: 100), .fixture("2", at: 200)],
            payment: .fixture(
                on: "2026-10-05", conversion: .cnbDaily,
                rate: StoredRate(rate: impossible, declaredOn: civilDate("2026-10-05"))))

        await #expect { try await database.saveInvoice(invoice) } throws: { isConstraintViolation($0) }

        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.integer("SELECT count(*) FROM invoice_item") == 0)
        #expect(try await database.integer("SELECT count(*) FROM payment") == 0)
        #expect(await database.writeCount == 0)
    }

    @Test func anUpdateThatFailsHalfWayKeepsTheOldInvoiceWithItsItemsAndPayment() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let stored = try await save(
            Invoice.fixture(
                items: [.fixture("1", at: 100), .fixture("2", at: 200), .fixture("3", at: 300)],
                payment: .fixture(on: "2026-10-05")),
            in: database)
        var changed = stored
        changed.note = "Změněno"
        changed.items = [.fixture("9", at: 900)]
        changed.payment = .fixture(
            on: "2026-10-06", conversion: .cnbDaily,
            rate: StoredRate(
                rate: ExchangeRate(currency: .usd, amount: 0, rate: decimal("21.5")),
                declaredOn: civilDate("2026-10-06")))

        await #expect { try await database.saveInvoice(changed) } throws: { isConstraintViolation($0) }

        #expect(try await database.invoice(id: stored.id) == stored)
    }

    @Test func anInvoiceOfAClientThatDoesNotExistIsRefusedAndLeavesNothingBehind() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var invoice = Invoice.fixture(payment: .fixture(on: "2026-10-05"))
        invoice.clientID = 99

        await #expect { try await database.saveInvoice(invoice) } throws: { isConstraintViolation($0) }

        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.integer("SELECT count(*) FROM invoice_item") == 0)
    }

    @Test func deletingAClientUnlinksItsInvoicesAndTheyStayWithTheirOwnCopyOfTheClient() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var invoice = Invoice.fixture()
        invoice.clientID = clientID
        let saved = try await save(invoice, in: database)

        try await database.write { try $0.run("DELETE FROM client WHERE id = ?", [.integer(clientID)]) }

        var expected = saved
        expected.clientID = nil
        #expect(try await database.invoice(id: saved.id) == expected)
    }

    @Test func everySaveAndDeleteIsOneWriteAndTheQueriesAreNone() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let writesBefore = await database.writeCount
        let invoice = try await save(
            Invoice.fixture(
                items: [.fixture("1", at: 100), .fixture("2", at: 200)], payment: .fixture(on: "2026-10-05")),
            in: database)
        #expect(await database.writeCount == writesBefore + 1)
        try await database.saveInvoice(invoice)
        #expect(await database.writeCount == writesBefore + 2)
        try await database.deleteInvoice(id: invoice.id)
        #expect(await database.writeCount == writesBefore + 3)

        let day = civilDate("2026-10-17")
        let before = await database.writeCount
        _ = try await database.invoice(id: 1)
        _ = try await database.invoices(scope: .issued, year: 2026, asOf: day)
        _ = try await database.invoices(scope: .paid, year: 2026, asOf: day)
        _ = try await database.invoiceNumbers(withDigitsPrefix: "2026")
        _ = try await database.invoice(numberDigits: "20260901", currency: .czk)
        _ = try await database.receipts(year: 2026)
        _ = try await database.chartRows(fromYear: 2025, throughYear: 2026, today: civilDate("2026-10-17"))
        _ = try await database.yearsWithData()
        _ = try await database.foreignCurrencies(year: 2026)
        _ = try await database.vatByDUZPMonth(year: 2026)
        _ = try await database.provisionalPayments()
        _ = try await database.paidInvoices(year: 2026)
        _ = try await database.invoiceCount()
        #expect(await database.writeCount == before)
    }

    @Test func everythingSavedIsStillThereWhenTheDatabaseIsOpenedAgain() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        let full = try await save(Self.fullInvoice(clientID: clientID), in: database)
        let yearEnd = try await save(Self.yearEndInvoice(), in: database)
        await database.close()

        let reopened = try Database(fileURL: database.fileURL, key: key)

        #expect(try await reopened.invoice(id: full.id) == full)
        #expect(try await reopened.invoice(id: yearEnd.id) == yearEnd)
        #expect(try await reopened.invoiceCount() == 2)
    }

    @Test func aStoredInvoiceWithAnUnknownStatusOrDateThrowsInsteadOfStoppingTheApp() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.invoice(c, id: 1, digits: "20260901")
            try c.run("UPDATE invoice SET status = 'maybe' WHERE id = 1")
            try SchemaRows.invoice(c, id: 2, digits: "20260902")
            try c.run("UPDATE invoice SET issue_date = '2026-02-30' WHERE id = 2")
            try SchemaRows.invoice(c, id: 3, digits: "20260903")
            try SchemaRows.invoiceItem(c, invoiceID: 3)
            try c.run("UPDATE invoice_item SET quantity = '6,5' WHERE invoice_id = 3")
            try SchemaRows.invoice(c, id: 4, digits: "20260904")
            try c.run("UPDATE invoice SET issue_date = 'abcd-09-30' WHERE id = 4")
        }

        await #expect(throws: StoredValueError.self, "status") { _ = try await database.invoice(id: 1) }
        await #expect(throws: StoredValueError.self, "date") { _ = try await database.invoice(id: 2) }
        await #expect(throws: StoredValueError.self, "quantity") { _ = try await database.invoice(id: 3) }
        await #expect(throws: StoredValueError.self, "chart row date") {
            _ = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: civilDate("2026-10-17"))
        }
        await #expect(throws: StoredValueError.self, "year of an issue date") {
            _ = try await database.yearsWithData()
        }
    }

    // MARK: Statements

    /// Screens ask for one year, and the statements find that year's rows in an index, so they cost the same with one
    /// year of invoices stored and with ten. Only the statements that are about all years may scan a table.
    @Test func theStatementsOfAYearSearchIndexesAndNeverScanATable() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let year: [SQLValue] = [.day(civilDate("2026-01-01")), .day(civilDate("2026-12-31"))]
        let statements: [(name: String, sql: String, arguments: [SQLValue])] = [
            ("issued list", InvoiceQueries.invoices(where: InvoiceQueries.issuedBetween), year),
            ("issued items", InvoiceQueries.items(where: InvoiceQueries.issuedBetween), year),
            ("paid list", InvoiceQueries.invoices(where: InvoiceQueries.paidBetween), year),
            ("paid items", InvoiceQueries.items(where: InvoiceQueries.paidBetween), year),
            ("by id", InvoiceQueries.invoices(where: InvoiceQueries.byID), [.integer(1)]),
            ("items by id", InvoiceQueries.items(where: InvoiceQueries.byID), [.integer(1)]),
            (
                "by number", InvoiceQueries.invoices(where: InvoiceQueries.byNumber),
                [.text("20260901"), .currency(.czk)]
            ),
            ("receipts", InvoiceQueries.receipts, year + year),
            ("provisional receipts", InvoiceQueries.provisionalReceipt, year),
            ("chart rows", InvoiceQueries.chartRows, year + year + year),
            (
                "due unpaid rows", InvoiceQueries.dueUnpaidRows,
                [.day(civilDate("2025-01-01")), .day(civilDate("2026-11-30")), .day(civilDate("2026-11-01"))]
            ),
            ("VAT by DUZP", InvoiceQueries.vatByDUZP, year),
            ("VAT to check by DUZP", InvoiceQueries.vatToCheckByDUZP, year),
            ("foreign currencies", InvoiceQueries.foreignCurrencies, year + year),
            ("numbers by prefix", InvoiceQueries.numbersWithDigitsPrefix, [.text("202609"), .text("202609:")]),
            ("drafts of a year", InvoiceQueries.draftsIssuedBetween, year),
        ]
        let tables = ["invoice", "invoice_item", "payment", "income_adjustment"]

        for statement in statements {
            let plan = try await database.read { connection in
                try connection.query("EXPLAIN QUERY PLAN " + statement.sql, statement.arguments).map { $0.text(3) }
            }
            #expect(plan.contains { $0.hasPrefix("SEARCH") }, "\(statement.name): \(plan)")
            for table in tables {
                #expect(!plan.contains { $0.hasPrefix("SCAN \(table)") }, "\(statement.name) scans \(table): \(plan)")
            }
        }
    }
}

// MARK: - Ten years of invoices

/// With 5 000 invoices over ten years, the lists and sums of one year each take under half a second and are about
/// that year's invoices only.
struct InvoiceRepositoryPerformanceTests {
    private let limit = Duration.milliseconds(500)

    @Test func tenYearsOfInvoicesDoNotSlowDownTheScreensOfOneYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rates)
        try await database.insertGeneratedInvoices(years: 2017...2026, perYear: 500)
        #expect(try await database.invoiceCount() == 5_000)
        let clock = ContinuousClock()
        let asOf = civilDate("2026-10-17")

        var start = clock.now
        let issued = try await database.invoices(scope: .issued, year: 2026, asOf: asOf)
        let issuedTime = clock.now - start

        start = clock.now
        let chart = try await database.chartRows(fromYear: 2026, throughYear: 2026, today: asOf)
        let chartTime = clock.now - start

        start = clock.now
        let paid = try await database.invoices(scope: .paid, year: 2026, asOf: asOf)
        let paidTime = clock.now - start

        start = clock.now
        let receipts = try await database.receipts(year: 2026)
        let receiptsTime = clock.now - start

        start = clock.now
        let years = try await database.yearsWithData()
        let yearsTime = clock.now - start

        start = clock.now
        let vat = try await database.vatByDUZPMonth(year: 2026)
        let vatTime = clock.now - start

        start = clock.now
        let currencies = try await database.foreignCurrencies(year: 2026)
        let currenciesTime = clock.now - start

        start = clock.now
        let provisional = try await database.provisionalPayments()
        let provisionalTime = clock.now - start

        start = clock.now
        let september = try await database.invoiceNumbers(withDigitsPrefix: "202609")
        let numbersTime = clock.now - start

        // 500 rows in under half a second, and the rows of 2026 only.
        #expect(issued.count == 500)
        #expect(issued.allSatisfy { $0.issueDate.year == 2026 && $0.items.count == 2 })
        #expect(issuedTime < limit, "issued list took \(issuedTime)")
        #expect(chartTime < limit, "chart rows took \(chartTime)")
        #expect(paidTime < limit, "paid list took \(paidTime)")
        #expect(receiptsTime < limit, "receipts took \(receiptsTime)")
        #expect(yearsTime < limit, "years with data took \(yearsTime)")
        #expect(vatTime < limit, "VAT by month took \(vatTime)")
        #expect(currenciesTime < limit, "foreign currencies took \(currenciesTime)")
        #expect(provisionalTime < limit, "provisional payments took \(provisionalTime)")
        #expect(numbersTime < limit, "numbers of a month took \(numbersTime)")

        // The answers are about 2026, and agree with what the whole table says.
        let expectedChartRows = try await database.integer(
            """
            SELECT count(*) FROM invoice LEFT JOIN payment ON payment.invoice_id = invoice.id
            WHERE invoice.issue_date BETWEEN '2026-01-01' AND '2026-12-31'
               OR payment.date BETWEEN '2026-01-01' AND '2026-12-31'
            """)
        #expect(Int64(chart.count) == expectedChartRows)
        #expect(Set(chart.map(\.id)).count == chart.count)
        let expectedPaid = try await database.integer(
            "SELECT count(*) FROM payment WHERE date BETWEEN '2026-01-01' AND '2026-10-17'")
        #expect(Int64(paid.count) == expectedPaid)
        #expect(paid.allSatisfy { ($0.payment?.date).map { $0.year == 2026 && $0 <= asOf } == true })
        let expectedReceipts = try await database.integer(
            "SELECT count(*) FROM payment WHERE date BETWEEN '2026-01-01' AND '2026-12-31'")
        #expect(Int64(receipts.count) == expectedReceipts)
        #expect(receipts.allSatisfy { $0.day.year == 2026 })
        // December 2026 is paid in January 2027.
        #expect(years == Array(2017...2027))
        #expect(vat.count == 12 && vat.allSatisfy { $0 > 0 })
        #expect(currencies == [.eur, .usd])
        #expect(!provisional.isEmpty && provisional.allSatisfy { $0.payment?.provisional == true })
        // Invoices 8, 20, 32 ... 488 of each year are issued in September, 41 of them.
        #expect(september.count == 41)
        #expect(september.allSatisfy { InvoiceNumbering.digits(of: $0).hasPrefix("202609") })

        // Historical rows retain their valid-day rate. Future rows use Friday 16 October's rate provisionally.
        for row in chart {
            if row.currency.isCZK {
                #expect(row.issueDayRate == nil)
                continue
            }
            if row.issueDate > asOf {
                let expected = ExchangeRate(
                    currency: row.currency, amount: 1,
                    rate: row.currency == .usd ? decimal("21.622") : decimal("24.325"))
                #expect(row.issueDayRate == expected, "\(row.currency) \(row.issueDate)")
                #expect(row.issueDayRateIsProvisional)
                continue
            }
            let lookup = try await database.cnbRate(row.currency, on: row.issueDate)
            guard case .declared(let rate, _) = lookup else {
                #expect(row.issueDayRate == nil, "\(row.currency) \(row.issueDate)")
                continue
            }
            #expect(row.issueDayRate == rate, "\(row.currency) \(row.issueDate)")
        }
        #expect(chart.contains { $0.issueDayRate != nil })
        #expect(chart.contains { !$0.currency.isCZK && $0.issueDayRateIsProvisional && $0.issueDate > asOf })
    }
}
