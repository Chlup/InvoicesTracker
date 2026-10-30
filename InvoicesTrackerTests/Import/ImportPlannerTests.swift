import Foundation
import Testing
@testable import InvoicesTracker

/// What the import makes of the rows of an export, worked out without a database: which rows are invoices, which are
/// held for review or skipped, what a re-import does to an invoice that is there already, and which clients are
/// created or filled.
struct ImportPlannerTests {
    // MARK: Helpers

    private static let known: Set<CurrencyCode> = [.czk, .usd, .eur]

    private func plan(
        _ rows: [FakturoidRow],
        existing: [Invoice] = [],
        clients: [Client] = [],
        known: Set<CurrencyCode> = Self.known,
        payments: [String: Payment] = [:],
        invoiceRates: [String: StoredRate] = [:]
    ) -> ImportPlan {
        ImportPlanner.plan(
            rows: rows, existingInvoices: existing, clients: clients, knownCurrencies: known, payments: payments,
            invoiceRates: invoiceRates
        )
    }

    private func sample(_ name: String = "fakturoid_sample") throws -> [FakturoidRow] {
        try fakturoidFixtureRows(name)
    }

    /// What the database holds once `plan` is applied: the invoices with ids and the links to their clients, and the
    /// clients with ids.
    private func applied(_ plan: ImportPlan) -> (invoices: [Invoice], clients: [Client]) {
        var clients = plan.newClients
        for index in clients.indices {
            clients[index].id = Int64(index + 1)
        }
        var invoices: [Invoice] = []
        for (offset, var invoice) in (plan.inserts + plan.updates).enumerated() {
            invoice.id = Int64(offset + 1)
            if let index = plan.newClientIndexByDigits[invoice.numberDigits] {
                invoice.clientID = clients[index].id
            }
            invoices.append(invoice)
        }
        return (invoices, clients)
    }

    private func invoice(_ number: String, in plan: ImportPlan) throws -> Invoice {
        try #require((plan.inserts + plan.updates + plan.flaggedCancelled).first { $0.number == number })
    }

    private func client(_ name: String, in plan: ImportPlan) throws -> Client {
        try #require(plan.newClients.first { $0.name == name })
    }

    private func invoiceOf(_ overrides: FakturoidCSV.Row, known: Set<CurrencyCode> = Self.known) throws -> Invoice {
        let row = try FakturoidCSV.parsed(overrides)
        return try #require(ImportPlanner.invoice(from: row, knownCurrencies: known))
    }

    private func classify(_ overrides: FakturoidCSV.Row, known: Set<CurrencyCode> = Self.known) throws -> RowClass {
        ImportPlanner.classify(try FakturoidCSV.parsed(overrides), knownCurrencies: known)
    }

    // MARK: Which rows are invoices

    @Test func aProformaOrAPartialProformaIsSkipped() throws {
        #expect(try classify(["Proforma": "true"]) == .skipProforma)
        #expect(try classify(["Partial proforma": "true"]) == .skipProforma)
        #expect(try classify(["Proforma": "true", "Cancelled at": "2026-10-05 12:00:00"]) == .skipProforma)
    }

    @Test func anInvoiceCancelledInFakturoidIsSkipped() throws {
        #expect(try classify(["Cancelled at": "2026-10-05 12:00:00"]) == .skipCancelled)
        #expect(try classify(["Status": "cancelled"]) == .skipCancelled)
    }

    @Test(arguments: ["open", "sent", "overdue", "paid"])
    func anOpenSentOverdueOrPaidInvoiceIsAnInvoice(status: String) throws {
        let paid = status == "paid" ? ["Paid on": "2026-10-15"] : [:]

        #expect(try classify(["Status": status].merging(paid) { $1 }) == .invoice(reviewReason: nil))
    }

    @Test func aNegativeAmountIsHeldForReview() throws {
        let negative = ["Subtotal": "-4500,0", "Total": "-5445,0", "Vat": "-945.0"]

        #expect(try classify(negative) == .invoice(reviewReason: "záporná částka"))
    }

    @Test(arguments: [
        ("uncollectible", "neznámý stav faktury: uncollectible"), ("draft", "neznámý stav faktury: draft"),
        ("", "neznámý stav faktury"),
    ])
    func aStatusTheImportDoesNotKnowIsHeldForReview(status: String, reason: String) throws {
        #expect(try classify(["Status": status]) == .invoice(reviewReason: reason))
    }

    @Test func anInvoiceThatIsPaidWithoutAPaymentDateIsHeldForReview() throws {
        #expect(try classify(["Status": "paid"]) == .invoice(reviewReason: "zaplaceno bez data platby"))
        #expect(
            try classify(["Status": "paid", "Paid on": "not a date"])
                == .invoice(reviewReason: "zaplaceno bez data platby"))
    }

    @Test func aPaymentDateOnAnInvoiceThatIsNotPaidIsHeldForReview() throws {
        #expect(
            try classify(["Status": "open", "Paid on": "2026-10-15"])
                == .invoice(reviewReason: "datum platby u nezaplacené faktury"))
    }

    @Test func aCurrencyWithoutRatesIsHeldForReviewAndCrownsNeverAre() throws {
        #expect(try classify(["Currency": "XYZ"]) == .invoice(reviewReason: "měna XYZ bez kurzů ČNB"))
        #expect(try classify(["Currency": "GBP"]) == .invoice(reviewReason: "měna GBP bez kurzů ČNB"))
        #expect(try classify(["Currency": "USD"]) == .invoice(reviewReason: nil))
        #expect(try classify(["Currency": "CZK"], known: []) == .invoice(reviewReason: nil))
        #expect(try classify(["Currency": "USD"], known: []) == .invoice(reviewReason: "měna USD bez kurzů ČNB"))
    }

    @Test func theCurrenciesTheCNBQuotesAreTheCachedOnesAndThoseOfTheNewestUniformTableAndCrowns() throws {
        let withoutRates = ImportPlanner.quotedCurrencies(cached: [])

        // A database without rates still knows the currencies of the newest table that is built in.
        let newest = try #require(BuiltInUniformRates.instructions.keys.max())
        let table = Set(BuiltInUniformRates.rates(year: newest).map(\.currency))
        #expect(table.contains(.usd) && table.contains(.eur) && !table.contains(.czk))
        #expect(withoutRates == table.union([.czk]))
        #expect(!withoutRates.contains(CurrencyCode("XYZ")!))
        // A currency that has rates in the database is quoted, whether or not that table has it (the kuna is only in
        // the table of 2022).
        let kuna = CurrencyCode("HRK")!
        #expect(!table.contains(kuna))
        #expect(ImportPlanner.quotedCurrencies(cached: [kuna]) == table.union([.czk, kuna]))
    }

    @Test func aRowWithoutACurrencyIsHeldForReviewAndIsNeverTakenForCrowns() throws {
        #expect(try classify(["Currency": ""]) == .invoice(reviewReason: "chybí měna"))
        #expect(try classify(["Currency": "  "]) == .invoice(reviewReason: "chybí měna"))

        let invoice = try invoiceOf(["Currency": ""])
        #expect(invoice.review == ReviewFlag(reason: "chybí měna"))
        // "XXX" is the code for no currency: the amount is not shown as crowns, and no invoice in crowns matches it.
        #expect(invoice.currency == CurrencyCode("XXX")! && !invoice.currency.isCZK)
        #expect(invoice.invoiceRate == nil && invoice.payment == nil)
    }

    @Test func aRowWithoutACurrencyNeverUpdatesAnInvoiceInCrowns() throws {
        let stored = try imported(["Number": "20261001"])

        let plan = plan(try rows(["Number": "20261001", "Currency": ""]), existing: [stored])

        #expect(plan.conflicts == ["20261001 — číslo už používá faktura v jiné měně — nepřidáno"])
        #expect(plan.inserts.isEmpty && plan.updates.isEmpty)
    }

    @Test(arguments: ["abc", "12,345", "1.234,50", "10000000000,0", "945.0 Kč"])
    func aVATThatIsThereButCannotBeReadIsHeldForReview(vat: String) throws {
        #expect(try classify(["Vat": vat]) == .invoice(reviewReason: "neplatná nebo příliš velká DPH"))
    }

    @Test func anEmptyVATCellIsNoVAT() throws {
        #expect(try classify(["Vat": ""]) == .invoice(reviewReason: nil))
        let invoice = try invoiceOf(["Vat": "", "Client country": "US", "Currency": "USD"])
        #expect(invoice.vatMode == .outsideCountry && invoice.review == nil)
    }

    @Test(arguments: ["", "ABC", "Z-", "č. (neuvedeno)"])
    func aNumberWithoutADigitIsHeldForReview(number: String) throws {
        #expect(try classify(["Number": number]) == .invoice(reviewReason: "číslo bez číslic"))
    }

    @Test func aNumberIsOnlyMadeOfAsciiDigits() throws {
        // Arabic-Indic and full-width digits are not the digits the variable symbol is made of.
        #expect(try classify(["Number": "٢٠٢٦"]) == .invoice(reviewReason: "číslo bez číslic"))
        #expect(try classify(["Number": "２０２６"]) == .invoice(reviewReason: "číslo bez číslic"))
    }

    @Test func aRowWithoutAnIssueDateOrWithACurrencyThatIsNoCodeIsHeldForReview() throws {
        #expect(try classify(["Issued on": ""]) == .invoice(reviewReason: "chybí datum vystavení"))
        #expect(try classify(["Currency": "US"]) == .invoice(reviewReason: "neplatná měna"))
        #expect(try classify(["Currency": "US Dollar"]) == .invoice(reviewReason: "neplatná měna"))
    }

    @Test(arguments: ["", "abc", "10000000000,0", "12,345", "1,234.50"])
    func anAmountThatCannotBeTakenExactlyIsHeldForReview(subtotal: String) throws {
        #expect(
            try classify(["Subtotal": subtotal]) == .invoice(reviewReason: "neplatná nebo příliš velká částka"))
    }

    @Test func anAmountJustBelowTheBoundIsTaken() throws {
        let invoice = try invoiceOf(["Subtotal": "9999999999,99", "Vat": "0.0", "Currency": "CZK"])

        #expect(invoice.items[0].unitPriceMinor == 999_999_999_999)
        #expect(invoice.review == nil)
    }

    @Test func aVATThatIsNoRateTheAppKnowsIsHeldForReview() throws {
        #expect(try classify(["Subtotal": "5000,0", "Vat": "499.0"]) == .invoice(reviewReason: "neznámá sazba DPH"))
        #expect(try classify(["Subtotal": "0,0", "Vat": "5.0"]) == .invoice(reviewReason: "neznámá sazba DPH"))
        #expect(try classify(["Subtotal": "5000,0", "Vat": "-1050.0"]) == .invoice(reviewReason: "neznámá sazba DPH"))
    }

    @Test func theFirstReasonIsTheOneThatIsGiven() throws {
        let row = ["Number": "ABC", "Status": "uncollectible", "Subtotal": "-5,0", "Currency": "XYZ"]

        #expect(try classify(row) == .invoice(reviewReason: "číslo bez číslic"))
        #expect(
            try classify(["Status": "uncollectible", "Subtotal": "-5,0", "Currency": "XYZ"])
                == .invoice(reviewReason: "záporná částka"))
        #expect(
            try classify(["Status": "uncollectible", "Currency": "XYZ"])
                == .invoice(reviewReason: "neznámý stav faktury: uncollectible"))
    }

    // MARK: The invoice a row becomes

    @Test func anInvoiceIsMadeOfTheRowAsTheExportPrintsIt() throws {
        let row = try sample()[0]

        let invoice = try #require(ImportPlanner.invoice(from: row, knownCurrencies: Self.known))

        #expect(invoice.id == 0 && invoice.clientID == nil)
        #expect(invoice.number == "20260902")
        #expect(invoice.currency == .czk)
        #expect(invoice.issueDate == civilDate("2026-09-30") && invoice.duzp == civilDate("2026-09-30"))
        #expect(invoice.dueDate == civilDate("2026-10-30"))
        #expect(
            invoice.items == [
                InvoiceItem(
                    description: "Vývoj software, září 2026", quantity: decimal("1"), unit: "",
                    unitPriceMinor: 450_000)
            ])
        #expect(invoice.netMinor == 450_000 && invoice.vatMinor == 94_500 && invoice.totalMinor == 544_500)
        #expect(invoice.vatMode == .domestic21)
        #expect(invoice.invoiceRate == nil)
        #expect(invoice.status == .issued && !invoice.qrEnabled && invoice.note.isEmpty)
        #expect(invoice.language == .cs)
        #expect(invoice.paymentMethod == "Banka")
        #expect(invoice.review == nil && invoice.payment == nil)
        #expect(invoice.source == .imported(fakturoidID: "5001", fingerprint: row.fingerprint, changedInApp: false))
        #expect(
            invoice.client
                == ClientSnapshot(
                    name: "Alfa Systems s.r.o.", street: "Náměstí 1", postcode: "26101", city: "Příbram",
                    country: "CZ", ico: "12345678", dic: "CZ12345678", email: "fakturace@alfa.example"))
    }

    @Test func aForeignInvoiceIsInEnglishAndHasTheRateOfTheExportOnTheDayItWasDeclared() throws {
        let invoice = try #require(ImportPlanner.invoice(from: try sample()[1], knownCurrencies: Self.known))

        #expect(invoice.currency == .usd && invoice.language == .en)
        #expect(invoice.vatMode == .outsideCountry)
        #expect(invoice.netMinor == 1_435_000 && invoice.vatMinor == 0)
        #expect(invoice.invoiceRate == storedRate("USD", "21.359", declaredOn: "2026-09-30"))
        #expect(invoice.paymentMethod == "ACH (USD)")
        #expect(invoice.number == "20260901")
    }

    @Test func theRateIsDeclaredOnTheBusinessDayBeforeADuzpOnAWeekend() throws {
        // 3 October 2026 is a Saturday: the rate valid on it is the one declared on Friday 2 October.
        let invoice = try invoiceOf([
            "Currency": "USD", "Exchange rate": "21.795", "Taxable fulfillment due": "2026-10-03", "Vat": "0.0",
            "Client country": "US",
        ])

        #expect(invoice.invoiceRate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
    }

    @Test func anInvoiceInCrownsHasNoRateAndAForeignOneWithoutARateHasNone() throws {
        #expect(try invoiceOf(["Currency": "CZK", "Exchange rate": "1.0"]).invoiceRate == nil)
        #expect(try invoiceOf(["Currency": "USD", "Exchange rate": "", "Vat": "0.0"]).invoiceRate == nil)
        #expect(try invoiceOf(["Currency": "USD", "Exchange rate": "0", "Vat": "0.0"]).invoiceRate == nil)
    }

    @Test func theNumberIsAsPrintedAndItsDigitsAreTheOnesOfTheNumber() throws {
        let invoice = try invoiceOf(["Number": "2026-10-01"])

        #expect(invoice.number == "2026-10-01")
        #expect(invoice.numberDigits == "20261001")
    }

    @Test func theItemTakesItsDescriptionFromTheSubjectOrSaysWhereItCameFrom() throws {
        #expect(try invoiceOf(["Subject": "Vývoj"]).items[0].description == "Vývoj")
        #expect(try invoiceOf(["Subject": ""]).items[0].description == "Import z Fakturoidu")
        #expect(try invoiceOf(["Subject": "   "]).items[0].description == "Import z Fakturoidu")
        let quoted = try invoiceOf(["Subject": "Konzultace \"říjen\", 2. část"])
        #expect(quoted.items[0].description == "Konzultace \"říjen\", 2. část")
    }

    @Test func aNegativeAmountIsANegativePriceOfOneUnit() throws {
        let invoice = try invoiceOf(["Subtotal": "-4500,0", "Total": "-5445,0", "Vat": "-945.0"])

        #expect(invoice.items[0].unitPriceMinor == -450_000 && invoice.items[0].quantity == decimal("1"))
        #expect(invoice.review == ReviewFlag(reason: "záporná částka"))
        #expect(invoice.vatMode == .domestic21)
    }

    @Test func theDuzpIsTheDateOfTheSupplyOrTheDayOfIssue() throws {
        let supplied = try invoiceOf(["Issued on": "2026-10-05", "Taxable fulfillment due": "2026-09-30"])
        let notGiven = try invoiceOf(["Issued on": "2026-10-05", "Taxable fulfillment due": ""])

        #expect(supplied.duzp == civilDate("2026-09-30") && supplied.issueDate == civilDate("2026-10-05"))
        #expect(notGiven.duzp == civilDate("2026-10-05"))
    }

    @Test func theDueDateIsTheOneInTheExportOrTheIssueDayAndTheDaysUntilDue() throws {
        let given = try invoiceOf(["Issued on": "2026-10-05", "Due on": "2026-10-20", "Due": "30"])
        let counted = try invoiceOf(["Issued on": "2026-10-05", "Due on": "", "Due": "30"])
        let neither = try invoiceOf(["Issued on": "2026-10-05", "Due on": "", "Due": ""])

        #expect(given.dueDate == civilDate("2026-10-20"))
        #expect(counted.dueDate == civilDate("2026-11-04"))
        #expect(neither.dueDate == civilDate("2026-10-05"))
    }

    @Test(arguments: [("cz", InvoiceLanguage.cs), ("CZ", .cs), ("en", .en), ("de", .en), ("", .en)])
    func theLanguageIsCzechForCzAndEnglishForAnythingElse(language: String, expected: InvoiceLanguage) throws {
        #expect(try invoiceOf(["Language": language]).language == expected)
    }

    @Test func theClientSnapshotIsTheOneOfTheRowWithTheSecondLineOfTheStreet() throws {
        let invoice = try invoiceOf([
            "Client name": "Beta Labs, Inc.", "Client street": "100 Main St", "Client street2": "Suite 4",
            "Client city": "Austin, TX", "Client zip": "78701", "Client country": "us", "Client registration no": "",
            "Client vat no": "", "Client email": "billing@beta.example", "Client phone": "+1 555 0100",
            "Currency": "USD", "Vat": "0.0",
        ])

        #expect(
            invoice.client
                == ClientSnapshot(
                    name: "Beta Labs, Inc.", street: "100 Main St, Suite 4", postcode: "78701", city: "Austin, TX",
                    country: "US", ico: "", dic: "", email: "billing@beta.example"))
    }

    // MARK: The rate of an invoice in a foreign currency

    private static let dollarsPaid: FakturoidCSV.Row = [
        "Number": "20261001", "Currency": "USD", "Exchange rate": "", "Vat": "0.0", "Client country": "US",
        "Status": "paid", "Paid on": "2026-10-15",
    ]

    @Test func aPaidInvoiceInADollarWithoutARateOfItsOwnIsHeldForReviewUntilTheCacheHasOne() throws {
        let row = try FakturoidCSV.parsed(Self.dollarsPaid)
        let cached = storedRate("USD", "21.5", declaredOn: "2026-09-30")

        #expect(
            ImportPlanner.classify(row, knownCurrencies: Self.known) == .invoice(reviewReason: "chybí kurz faktury"))
        #expect(
            ImportPlanner.classify(row, knownCurrencies: Self.known, invoiceRates: [row.fingerprint: cached])
                == .invoice(reviewReason: nil))
        let invoice = try #require(
            ImportPlanner.invoice(from: row, knownCurrencies: Self.known, invoiceRates: [row.fingerprint: cached]))
        #expect(invoice.invoiceRate == cached && invoice.review == nil)
    }

    @Test func theRateOfTheExportComesBeforeTheRateOfTheCache() throws {
        let row = try FakturoidCSV.parsed(Self.dollarsPaid.merging(["Exchange rate": "21.359"]) { $1 })
        let cached = storedRate("USD", "21.5", declaredOn: "2026-09-30")

        let invoice = try #require(
            ImportPlanner.invoice(from: row, knownCurrencies: Self.known, invoiceRates: [row.fingerprint: cached]))

        #expect(invoice.invoiceRate == storedRate("USD", "21.359", declaredOn: "2026-10-01"))
        #expect(ImportPlanner.classify(row, knownCurrencies: Self.known) == .invoice(reviewReason: nil))
    }

    @Test(arguments: [
        ["Status": "open", "Paid on": ""],  // not paid
        ["Currency": "CZK", "Client country": "CZ", "Vat": "945.0"],  // in crowns
    ])
    func aRateOfItsOwnIsNeededOnlyForAPaidInvoiceInAForeignCurrency(change: FakturoidCSV.Row) throws {
        let row = try FakturoidCSV.parsed(Self.dollarsPaid.merging(change) { $1 })

        #expect(ImportPlanner.classify(row, knownCurrencies: Self.known) == .invoice(reviewReason: nil))
        let invoice = try #require(ImportPlanner.invoice(from: row, knownCurrencies: Self.known))
        #expect(invoice.invoiceRate == nil)
    }

    @Test func aCurrencyWithoutRatesComesBeforeAMissingRateOfTheInvoice() throws {
        let row = try FakturoidCSV.parsed(Self.dollarsPaid.merging(["Currency": "XYZ"]) { $1 })

        #expect(
            ImportPlanner.classify(row, knownCurrencies: Self.known)
                == .invoice(reviewReason: "měna XYZ bez kurzů ČNB"))
    }

    @Test func aFlagForAMissingRateIsClearedWhenTheCacheHasOneAndOtherwiseLeftAlone() throws {
        let row = try FakturoidCSV.parsed(Self.dollarsPaid)
        let cached = storedRate("USD", "21.5", declaredOn: "2026-09-30")
        let payment = Payment.fixture(on: "2026-10-15", conversion: .cnbDaily, net: 100, vat: 0, rate: cached)
        var held = try #require(ImportPlanner.invoice(from: row, knownCurrencies: Self.known))
        held.id = 4
        #expect(held.review == ReviewFlag(reason: "chybí kurz faktury"))

        let stillMissing = plan([row], existing: [held])
        let arrived = plan(
            [row], existing: [held], payments: [row.fingerprint: payment], invoiceRates: [row.fingerprint: cached])

        #expect(stillMissing.unchanged == ["20261001"] && stillMissing.updates.isEmpty)
        #expect(arrived.updates.map(\.id) == [4] && arrived.updates.first?.review == nil)
        #expect(arrived.updates.first?.payment == payment && arrived.updates.first?.invoiceRate == cached)
    }

    @Test func aFlagIsNotChangedToAnotherReasonWhenTheRowHasNotChanged() throws {
        // Flagged for a currency without rates, and the currency is quoted now, but the invoice has no rate of its own.
        let row = try FakturoidCSV.parsed(Self.dollarsPaid)
        var stored = try #require(ImportPlanner.invoice(from: row, knownCurrencies: [.czk]))
        stored.id = 4
        #expect(stored.review == ReviewFlag(reason: "měna USD bez kurzů ČNB"))

        let plan = plan([row], existing: [stored])

        #expect(plan.unchanged == ["20261001"] && plan.updates.isEmpty)
    }

    // MARK: VAT

    @Test(arguments: [
        // Subtotal, VAT, country, transferred tax liability, expected mode
        ("4500,0", "945.0", "CZ", "false", VatMode.domestic21),
        ("1000,0", "120.0", "CZ", "false", .domestic12),
        ("5000,0", "1000.0", "CZ", "false", .domestic21),
        ("5000,0", "500.0", "CZ", "false", .domestic12),
        ("5000,0", "1150.0", "CZ", "false", .domestic21),
        ("14350,0", "0.0", "US", "false", .outsideCountry),
        ("14350,0", "", "US", "false", .outsideCountry),
        ("100,0", "0.0", "CH", "false", .outsideCountry),
        ("100,0", "0.0", "gb", "false", .outsideCountry),
        ("2000,0", "0.0", "DE", "true", .euReverseCharge),
        ("2000,0", "0.0", "US", "true", .euReverseCharge),
        ("2000,0", "0.0", "DE", "false", .none),
        ("2000,0", "0.0", "SK", "false", .none),
        ("100,0", "0.0", "CZ", "false", .none),
        ("100,0", "0.0", "", "false", .none),
        ("100,0", "0.0", "Švýcarsko", "false", .none),
        ("0,0", "0.0", "US", "false", .outsideCountry),
    ])
    func theVATModeFollowsTheVATTheCountryAndTheTransferredTaxLiability(
        subtotal: String, vat: String, country: String, transferred: String, expected: VatMode
    ) throws {
        let invoice = try invoiceOf([
            "Subtotal": subtotal, "Vat": vat, "Client country": country, "Transferred tax liability": transferred,
        ])

        #expect(invoice.vatMode == expected)
        #expect(invoice.review == nil)
    }

    @Test(arguments: ["AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IE", "IT",
        "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK"])
    func aMemberOfTheEUWithoutVATIsNotOutsideTheCountryBySection9(country: String) throws {
        #expect(try invoiceOf(["Client country": country, "Vat": "0.0"]).vatMode == .none)
    }

    @Test(arguments: ["US", "GB", "CH", "NO", "CA", "JP", "AU", "UA"])
    func aCountryOutsideTheEUWithoutVATIsOutsideTheCountry(country: String) throws {
        #expect(try invoiceOf(["Client country": country, "Vat": "0.0"]).vatMode == .outsideCountry)
    }

    @Test func aVATThatCannotBeReadTellsNothingAboutTheVATModeOfTheClient() throws {
        // Read as no VAT, the row would make the client of a customer in the US an outside-the-country client.
        let unreadable = plan(try rows(["Vat": "abc", "Client country": "US", "Currency": "USD"]))
        let readable = plan(try rows(["Vat": "0.0", "Client country": "US", "Currency": "USD"]))

        #expect(try client("Alfa Systems s.r.o.", in: readable).vatMode == .outsideCountry)
        #expect(try client("Alfa Systems s.r.o.", in: unreadable).vatMode == Client().vatMode)
    }

    // MARK: Country

    @Test(arguments: [
        ("CZ", "CZ"), ("us", "US"), (" de ", "DE"), ("Česko", "CZ"), ("Česká republika", "CZ"),
        ("Czech Republic", "CZ"), ("czech republic", "CZ"), ("Slovensko", "SK"), ("Slovakia", "SK"),
        ("Německo", "DE"), ("NEMECKO", "DE"), ("Germany", "DE"), ("Deutschland", "DE"), ("Rakousko", "AT"),
        ("Austria", "AT"), ("Spojené státy", "US"), ("United States", "US"), ("USA", "US"),
        ("United States of America", "US"), ("Spojené státy americké", "US"), ("Velká Británie", "GB"),
        ("United Kingdom", "GB"), ("Polsko", "PL"), ("Poland", "PL"),
    ])
    func aCountryNameIsMappedToItsCodeAndACodeIsKept(text: String, code: String) throws {
        let invoice = try invoiceOf(["Client country": text])

        #expect(invoice.client.country == code)
    }

    @Test func aCountryTheImportDoesNotKnowIsKeptAsWrittenAndNotedOnce() throws {
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row(["Number": "20261001", "Client country": "Švýcarsko", "Vat": "0.0"]),
            FakturoidCSV.row(["Number": "20261002", "Client country": "Švýcarsko", "Vat": "0.0"]),
            FakturoidCSV.row(["Number": "20261003", "Client country": "CZ"]),
        ])

        let plan = plan(rows)

        #expect(plan.inserts.map(\.client.country) == ["Švýcarsko", "Švýcarsko", "CZ"])
        #expect(plan.newClients.map(\.country) == ["CZ"])  // Alfa is one client, and its newest row says CZ
        #expect(plan.reviewItems == ["země „Švýcarsko“ — není kód země, ponecháno jak je"])
    }

    // MARK: The sample, planned against an empty database

    @Test func theSampleBecomesElevenInvoicesAndTwoRowsAreSkipped() throws {
        let plan = plan(try sample())

        #expect(
            plan.inserts.map(\.number) == [
                "20260902", "20260901", "2026-10-01", "20261003", "20261004", "20261005", "20261006", "20261007",
                "20261008", "20261009", "20261010",
            ])
        #expect(plan.skipped == ["Z20261001 — zálohová faktura", "20261099 — zrušeno ve Fakturoidu"])
        #expect(plan.updates.isEmpty && plan.unchanged.isEmpty && plan.kept.isEmpty)
        #expect(plan.conflicts.isEmpty && plan.flaggedCancelled.isEmpty && plan.clientUpdates.isEmpty)
    }

    @Test func fourOfTheElevenAreHeldForReviewWithTheirReasons() throws {
        let plan = plan(try sample())

        let inReview = plan.inserts.filter { $0.review != nil }

        #expect(inReview.map(\.number) == ["20261003", "20261004", "20261005", "20261006"])
        #expect(
            inReview.map(\.review) == [
                ReviewFlag(reason: "záporná částka"), ReviewFlag(reason: "neznámý stav faktury: uncollectible"),
                ReviewFlag(reason: "zaplaceno bez data platby"), ReviewFlag(reason: "měna XYZ bez kurzů ČNB"),
            ])
        #expect(
            plan.reviewItems == [
                "20261003 — záporná částka", "20261004 — neznámý stav faktury: uncollectible",
                "20261005 — zaplaceno bez data platby", "20261006 — měna XYZ bez kurzů ČNB",
            ])
    }

    @Test func theVATModesOfTheSampleFollowTheRows() throws {
        let plan = plan(try sample())

        #expect(try invoice("20260902", in: plan).vatMode == .domestic21)
        #expect(try invoice("20260901", in: plan).vatMode == .outsideCountry)
        #expect(try invoice("2026-10-01", in: plan).vatMode == .domestic21)
        #expect(try invoice("20261007", in: plan).vatMode == .euReverseCharge)
        #expect(try invoice("20261008", in: plan).vatMode == .domestic12)
        #expect(try invoice("20261009", in: plan).vatMode == .domestic21)
        #expect(try invoice("20261010", in: plan).vatMode == .domestic21)
    }

    @Test func theSampleCreatesFourClientsAndLinksNoInvoiceToOneYet() throws {
        let plan = plan(try sample())

        #expect(
            plan.newClients.map(\.name) == ["Alfa Systems s.r.o.", "Beta Labs, Inc.", "Gamma GmbH", "delta S.R.O."])
        #expect(plan.newClients.allSatisfy { $0.id == 0 && $0.origin == .imported && !$0.editedAfterImport })
        #expect(plan.inserts.allSatisfy { $0.clientID == nil })
        #expect(plan.newClientIndexByDigits.count == 11)
    }

    @Test func eachInvoiceIsLinkedToTheNewClientOfItsRow() throws {
        let plan = plan(try sample())

        func clientName(of number: String) throws -> String {
            let digits = InvoiceNumbering.digits(of: number)
            return plan.newClients[try #require(plan.newClientIndexByDigits[digits])].name
        }

        #expect(try clientName(of: "20260902") == "Alfa Systems s.r.o.")
        #expect(try clientName(of: "2026-10-01") == "Alfa Systems s.r.o.")
        #expect(try clientName(of: "20261008") == "Alfa Systems s.r.o.")
        #expect(try clientName(of: "20260901") == "Beta Labs, Inc.")
        #expect(try clientName(of: "20261006") == "Beta Labs, Inc.")
        #expect(try clientName(of: "20261007") == "Gamma GmbH")
        #expect(try clientName(of: "20261009") == "delta S.R.O.")
        #expect(try clientName(of: "20261010") == "delta S.R.O.")
    }

    @Test func alfaIsOneClientAndTakesItsValuesFromItsNewestRowsAndItsPhoneFromRowThree() throws {
        let alfa = try client("Alfa Systems s.r.o.", in: plan(try sample()))

        #expect(alfa.street == "Náměstí 1" && alfa.postcode == "26101" && alfa.city == "Příbram")
        #expect(alfa.country == "CZ")
        #expect(alfa.ico == "12345678" && alfa.dic == "CZ12345678")
        #expect(alfa.email == "fakturace@alfa.example")
        // Only row 3 has the phone: the older row 1 has none, and the rows after it leave it out.
        #expect(alfa.phone == "+420 111 222 333")
        #expect(alfa.currency == .czk && alfa.paymentMethod == "Banka" && alfa.language == .cs)
        // The newest invoice of Alfa is the one of 8 October: 12 % VAT and 15 days (row 1 had 21 % and 30 days).
        #expect(alfa.vatMode == .domestic12 && alfa.dueDays == 15)
    }

    @Test func betaIsOutsideTheCountryInEnglishWithThirtyDaysAndKeepsDollars() throws {
        let beta = try client("Beta Labs, Inc.", in: plan(try sample()))

        #expect(beta.vatMode == .outsideCountry)
        #expect(beta.language == .en)
        #expect(beta.dueDays == 30)
        #expect(beta.paymentMethod == "ACH (USD)")
        #expect(beta.street == "100 Main St" && beta.postcode == "78701" && beta.city == "Austin, TX")
        #expect(beta.country == "US" && beta.email == "billing@beta.example")
        #expect(beta.ico.isEmpty && beta.dic.isEmpty && beta.phone.isEmpty)
        // Its newest row is in a currency without rates, which is not a currency to start an invoice in.
        #expect(beta.currency == .usd)
    }

    @Test func gammaIsAnEUClientWithReverseCharge() throws {
        let gamma = try client("Gamma GmbH", in: plan(try sample()))

        #expect(gamma.vatMode == .euReverseCharge)
        #expect(gamma.currency == .eur && gamma.language == .en && gamma.dueDays == 30)
        #expect(gamma.country == "DE" && gamma.dic == "DE123456789" && gamma.ico.isEmpty)
        #expect(gamma.street == "Hauptstraße 7" && gamma.postcode == "10115" && gamma.city == "Berlin")
        #expect(gamma.paymentMethod == "Bank transfer")
    }

    @Test func deltaIsOneClientEvenThoughOneRowNamesItInOtherCaseWithoutNumbers() throws {
        let plan = plan(try sample())

        // Row 13 is matched to row 12 by the folded name, and it is the newest, so it gives the spelling of the name.
        let delta = try client("delta S.R.O.", in: plan)
        #expect(plan.newClients.filter { SearchFolding.fold($0.name) == "delta s.r.o." }.count == 1)
        // What only the older row has stays.
        #expect(delta.dic == "CZ87654321" && delta.email == "info@delta.example")
        #expect(delta.ico.isEmpty && delta.vatMode == .domestic21 && delta.dueDays == 14)
        // Each invoice keeps what its own row printed.
        #expect(try invoice("20261009", in: plan).client.name == "Delta s.r.o.")
        #expect(try invoice("20261009", in: plan).client.dic == "CZ87654321")
        #expect(try invoice("20261010", in: plan).client.name == "delta S.R.O.")
        #expect(try invoice("20261010", in: plan).client.dic.isEmpty)
    }

    @Test func theRowsThatAreSkippedCreateNoClient() throws {
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row([
                "Number": "Z20261001", "Proforma": "true", "Client name": "Epsilon s.r.o.",
                "Client registration no": "11111111",
            ]),
            FakturoidCSV.row([
                "Number": "20261002", "Status": "cancelled", "Client name": "Zeta s.r.o.",
                "Client registration no": "22222222",
            ]),
        ])

        let plan = plan(rows)

        #expect(plan.newClients.isEmpty && plan.inserts.isEmpty)
        #expect(plan.skipped.count == 2)
    }

    @Test func eachInvoiceKeepsTheFingerprintOfItsRow() throws {
        let rows = try sample()
        let plan = plan(rows)

        let byNumber = Dictionary(uniqueKeysWithValues: rows.map { ($0.number, $0.fingerprint) })

        for invoice in plan.inserts {
            guard case .imported(let id, let fingerprint, let changedInApp) = invoice.source else {
                Issue.record("\(invoice.number) is not an imported invoice")
                continue
            }
            #expect(fingerprint == byNumber[invoice.number])
            #expect(!id.isEmpty && !changedInApp)
        }
    }

    // MARK: Payments

    @Test func aPaymentIsGivenToAnInvoiceThatIsNotInReviewWhenItsRowHasOne() throws {
        let rows = try sample()
        let payment = Payment.fixture(on: "2026-10-15")
        let reviewed = Payment.fixture(on: "2026-10-16")
        let payments = [rows[0].fingerprint: payment, rows[5].fingerprint: reviewed]

        let plan = plan(rows, payments: payments)

        #expect(try invoice("20260902", in: plan).payment == payment)
        // An invoice held for review is not paid by the import: whoever resolves it decides.
        #expect(try invoice("20261003", in: plan).payment == nil)
        #expect(plan.inserts.filter { $0.payment != nil }.count == 1)
    }

    // MARK: Existing clients

    private func existingAlfa() -> Client {
        Client(
            id: 7, name: "Alfa Systems s.r.o.", street: "", postcode: "261 01", city: "Příbram", country: "CZ",
            ico: "12345678", dic: "CZ12345678", email: "ucetni@example.com", phone: "+420 999 000 111",
            currency: .czk, vatMode: .domestic21, dueDays: 14, paymentMethod: "Převodem", language: .cs
        )
    }

    @Test func anExistingClientGetsOnlyItsEmptyFieldsFilled() throws {
        let alfa = existingAlfa()

        let plan = plan(try sample(), clients: [alfa])

        var filled = alfa
        filled.street = "Náměstí 1"
        #expect(plan.clientUpdates == [filled])
        #expect(plan.newClients.map(\.name) == ["Beta Labs, Inc.", "Gamma GmbH", "delta S.R.O."])
    }

    @Test func nothingTheClientHasIsOverwrittenNotEvenByNewerRows() throws {
        var alfa = existingAlfa()
        alfa.street = "Moje ulice 5"

        let plan = plan(try sample(), clients: [alfa])

        #expect(plan.clientUpdates.isEmpty)
    }

    @Test func theInvoicesOfAnExistingClientAreLinkedToIt() throws {
        let plan = plan(try sample(), clients: [existingAlfa()])

        let alfaInvoices = plan.inserts.filter { $0.client.ico == "12345678" }

        #expect(alfaInvoices.count == 6)
        #expect(alfaInvoices.allSatisfy { $0.clientID == 7 })
        #expect(alfaInvoices.allSatisfy { plan.newClientIndexByDigits[$0.numberDigits] == nil })
    }

    @Test func fillingAClientKeepsItsOriginAndWhetherItWasEdited() throws {
        var alfa = existingAlfa()
        alfa.origin = .imported
        alfa.editedAfterImport = true
        alfa.phone = ""
        alfa.city = ""

        let plan = plan(try sample(), clients: [alfa])

        let filled = try #require(plan.clientUpdates.first)
        #expect(filled.origin == .imported && filled.editedAfterImport)
        #expect(filled.phone == "+420 111 222 333" && filled.city == "Příbram" && filled.street == "Náměstí 1")
        #expect(filled.email == "ucetni@example.com" && filled.postcode == "261 01")
        #expect(filled.vatMode == .domestic21 && filled.dueDays == 14 && filled.paymentMethod == "Převodem")
    }

    @Test func aClientIsMatchedByCompanyNumberBeforeVATNumberBeforeName() throws {
        let byNumber = Client(id: 1, name: "Jiný název", ico: "111")
        let byVAT = Client(id: 2, name: "Jiný název dva", dic: "CZ222")
        let byName = Client(id: 3, name: "Foo s.r.o.")
        let clients = [byName, byVAT, byNumber]

        func linked(_ overrides: FakturoidCSV.Row) throws -> Int64? {
            let rows = try FakturoidCSV.rows([FakturoidCSV.row(overrides)])
            return plan(rows, clients: clients).inserts.first?.clientID
        }

        let all = ["Client registration no": "111", "Client vat no": "CZ222", "Client name": "Foo s.r.o."]
        #expect(try linked(all) == 1)
        #expect(try linked(all.merging(["Client registration no": ""]) { $1 }) == 2)
        #expect(try linked(all.merging(["Client registration no": "", "Client vat no": ""]) { $1 }) == 3)
        let nobody = all.merging(["Client registration no": "999", "Client vat no": "", "Client name": "Nikdo"]) { $1 }
        #expect(try linked(nobody) == nil)
    }

    @Test func aMatchByVATNumberFillsTheCompanyNumberOfAClientWithoutOne() throws {
        let existing = Client(id: 2, name: "Delta", dic: "CZ87654321")
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row([
                "Client name": "Delta s.r.o.", "Client registration no": "87654321", "Client vat no": "cz 87654321",
            ])
        ])

        let plan = plan(rows, clients: [existing])

        #expect(plan.newClients.isEmpty)
        #expect(plan.clientUpdates.map(\.ico) == ["87654321"])
        #expect(plan.inserts.first?.clientID == 2)
    }

    @Test func aNameMatchIgnoresCaseDiacriticsAndWhitespace() throws {
        let existing = Client(id: 4, name: "Příbramská strojírna s.r.o.")
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row([
                "Client name": "  PRIBRAMSKA   strojirna S.R.O. ", "Client registration no": "", "Client vat no": "",
            ])
        ])

        #expect(plan(rows, clients: [existing]).inserts.first?.clientID == 4)
    }

    @Test func twoCompaniesWithTheSameNameButDifferentNumbersAreNotMerged() throws {
        let existing = Client(id: 4, name: "Novák s.r.o.", ico: "111")
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row([
                "Number": "20261001", "Client name": "Novák s.r.o.", "Client registration no": "222",
                "Client vat no": "",
            ])
        ])

        let plan = plan(rows, clients: [existing])

        #expect(plan.newClients.map(\.ico) == ["222"])
        #expect(plan.inserts.first?.clientID == nil)
        #expect(plan.clientUpdates.isEmpty)
    }

    @Test func aRowWithoutAClientNameAndNoMatchCreatesNoClient() throws {
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row(["Client name": "", "Client registration no": "333", "Client vat no": ""])
        ])

        let plan = plan(rows)

        #expect(plan.newClients.isEmpty)
        #expect(plan.inserts.map(\.number) == ["20261001"])
        #expect(plan.inserts.first?.clientID == nil && plan.newClientIndexByDigits.isEmpty)
    }

    @Test func theNewestRowOfAClientGivesTheValuesAndOlderRowsOnlyFillWhatIsMissing() throws {
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row([
                "Number": "20260101", "Issued on": "2026-01-10", "Client city": "Praha", "Client phone": "111",
                "Client email": "old@example.com", "Due": "30", "Payment method human": "Hotově", "Language": "en",
            ]),
            FakturoidCSV.row([
                "Number": "20260301", "Issued on": "2026-03-10", "Client city": "Brno", "Client phone": "",
                "Client email": "", "Due": "", "Payment method human": "", "Language": "",
            ]),
        ])

        let client = try #require(plan(rows).newClients.first)

        #expect(client.city == "Brno")
        #expect(client.phone == "111" && client.email == "old@example.com")
        #expect(client.dueDays == 30 && client.paymentMethod == "Hotově" && client.language == .en)
    }

    @Test func theNewestRowIsTheOneWithTheLatestIssueDateWhateverTheOrderInTheFile() throws {
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row(["Number": "20260301", "Issued on": "2026-03-10", "Client city": "Brno"]),
            FakturoidCSV.row(["Number": "20260101", "Issued on": "2026-01-10", "Client city": "Praha"]),
        ])

        #expect(try #require(plan(rows).newClients.first).city == "Brno")
    }

    // MARK: A second import of the same rows

    @Test func importingTheSameRowsAgainChangesNothing() throws {
        let rows = try sample()
        let first = plan(rows)
        let (invoices, clients) = applied(first)

        let second = plan(rows, existing: invoices, clients: clients)

        #expect(second.unchanged.count == 11)
        #expect(second.unchanged == first.inserts.map(\.number))
        #expect(second.skipped.count == 2)
        #expect(second.inserts.isEmpty && second.updates.isEmpty && second.kept.isEmpty)
        #expect(second.conflicts.isEmpty && second.flaggedCancelled.isEmpty && second.reviewItems.isEmpty)
        #expect(second.newClients.isEmpty && second.clientUpdates.isEmpty)
    }

    // MARK: Rows for invoices that are there already

    /// The invoice an earlier import made of the row of `overrides`, as the database holds it.
    private func imported(
        _ overrides: FakturoidCSV.Row = [:], known: Set<CurrencyCode> = Self.known, id: Int64 = 1,
        changedInApp: Bool = false
    ) throws -> Invoice {
        var invoice = try invoiceOf(overrides, known: known)
        invoice.id = id
        if case .imported(let fakturoidID, let fingerprint, _) = invoice.source {
            invoice.source = .imported(fakturoidID: fakturoidID, fingerprint: fingerprint, changedInApp: changedInApp)
        }
        return invoice
    }

    private func rows(_ overrides: FakturoidCSV.Row...) throws -> [FakturoidRow] {
        try FakturoidCSV.rows(overrides.map { FakturoidCSV.row($0) })
    }

    @Test func aChangedRowUpdatesAnInvoiceThatWasNotChangedInTheApp() throws {
        let stored = try imported(["Number": "20260902"], id: 41)
        let alfa = Client(id: 9, name: "Alfa Systems s.r.o.", ico: "12345678")
        let changed = try rows([
            "Number": "20260902", "Subtotal": "4600,0", "Total": "5566,0", "Vat": "966.0", "Status": "paid",
            "Paid on": "2026-10-20",
        ])
        let payment = Payment.fixture(on: "2026-10-20", net: 460_000, vat: 96_600)

        let plan = plan(changed, existing: [stored], clients: [alfa], payments: [changed[0].fingerprint: payment])

        let updated = try #require(plan.updates.first)
        #expect(plan.updates.count == 1 && plan.inserts.isEmpty && plan.unchanged.isEmpty && plan.kept.isEmpty)
        #expect(updated.id == 41)
        #expect(updated.clientID == 9)
        #expect(updated.netMinor == 460_000 && updated.vatMinor == 96_600)
        #expect(updated.payment == payment)
        #expect(updated.source == .imported(fakturoidID: "1", fingerprint: changed[0].fingerprint, changedInApp: false))
    }

    @Test func theDigitsOfTheNumberMatchWhateverTheWayItIsWritten() throws {
        let stored = try imported(["Number": "20260902"], id: 41)
        let changed = try rows(["Number": "2026-09-02", "Subtotal": "4600,0", "Vat": "966.0"])

        let plan = plan(changed, existing: [stored])

        #expect(plan.updates.map(\.number) == ["2026-09-02"])
        #expect(plan.updates.first?.id == 41)
        #expect(plan.inserts.isEmpty)
    }

    @Test func aRowThatIsTheSameAsTheLastImportIsUnchanged() throws {
        let stored = try imported(["Number": "20260902"])
        let same = try rows(["Number": "20260902"])

        let plan = plan(same, existing: [stored])

        #expect(plan.unchanged == ["20260902"])
        #expect(plan.updates.isEmpty && plan.inserts.isEmpty)
    }

    @Test func aChangedRowForAnInvoiceChangedInTheAppIsKeptAndListed() throws {
        let stored = try imported(["Number": "20260902"], changedInApp: true)
        let changed = try rows(["Number": "20260902", "Subtotal": "4600,0", "Vat": "966.0"])

        let plan = plan(changed, existing: [stored])

        #expect(plan.kept == ["20260902 — změněno v aplikaci — ponecháno"])
        #expect(plan.updates.isEmpty && plan.unchanged.isEmpty && plan.inserts.isEmpty)
    }

    @Test func aRowThatHasNotChangedLeavesAnInvoiceChangedInTheAppAlone() throws {
        // Nothing differs between the export and the last import, so there is nothing to keep it from.
        let stored = try imported(["Number": "20260902"], changedInApp: true)

        let plan = plan(try rows(["Number": "20260902"]), existing: [stored])

        #expect(plan.unchanged == ["20260902"])
        #expect(plan.kept.isEmpty && plan.updates.isEmpty)
    }

    @Test func anInvoiceMadeInTheAppIsNeverTouchedAndTheRowIsAConflict() throws {
        let appInvoice = Invoice.fixture(number: "20261102", currency: .czk, duzp: "2026-11-02")
        let changed = try rows(["Number": "20261102", "Issued on": "2026-11-02"])

        let plan = plan(changed, existing: [appInvoice])

        #expect(
            plan.conflicts == ["20261102 — číslo už používá faktura vytvořená v aplikaci — nepřidáno"])
        #expect(plan.inserts.isEmpty && plan.updates.isEmpty && plan.unchanged.isEmpty && plan.kept.isEmpty)
    }

    @Test func aNumberThatAnInvoiceInAnotherCurrencyHasIsAConflict() throws {
        // Numbers are unique by their digits, so the same digits in another currency cannot be added.
        let stored = try imported(["Number": "20260902", "Currency": "EUR", "Vat": "0.0", "Client country": "DE"])
        let changed = try rows(["Number": "20260902"])

        let plan = plan(changed, existing: [stored])

        #expect(plan.conflicts == ["20260902 — číslo už používá faktura v jiné měně — nepřidáno"])
        #expect(plan.inserts.isEmpty && plan.updates.isEmpty)
    }

    @Test func aRowWhoseFakturoidIdIsAlreadyImportedUnderAnotherNumberIsAConflictNotADuplicate() throws {
        let stored = try imported(["Id": "5001", "Number": "20260902"])
        let renumbered = try rows(["Id": "5001", "Number": "20260903"])

        let plan = plan(renumbered, existing: [stored])

        #expect(plan.conflicts == ["20260903 — už importováno pod číslem 20260902 — nepřidáno"])
        #expect(plan.inserts.isEmpty && plan.updates.isEmpty)
    }

    @Test func rowsWithoutAnIdAreNeverTakenForTheSameInvoice() throws {
        let stored = try imported(["Id": "", "Number": "20260902"])

        let plan = plan(try rows(["Id": "", "Number": "20260903"]), existing: [stored])

        #expect(plan.inserts.map(\.number) == ["20260903"])
        #expect(plan.conflicts.isEmpty)
    }

    @Test func aRowOfAnotherFakturoidInvoiceWithTheSameDigitsIsAConflictAndLeavesTheStoredInvoiceAlone() throws {
        let stored = try imported(["Id": "5001", "Number": "20260902"], id: 41)
        // Another invoice of Fakturoid, whose number has the same digits written otherwise.
        let other = try rows(["Id": "5009", "Number": "2026-09-02", "Subtotal": "4600,0", "Vat": "966.0"])

        let plan = plan(other, existing: [stored])

        #expect(plan.conflicts == ["2026-09-02 — číslo už používá jiná faktura z Fakturoidu — nepřidáno"])
        #expect(plan.updates.isEmpty && plan.inserts.isEmpty && plan.unchanged.isEmpty && plan.kept.isEmpty)
        #expect(plan.flaggedCancelled.isEmpty && plan.reviewItems.isEmpty)
    }

    @Test func aCancelledRowOfAnotherFakturoidInvoiceWithTheSameDigitsDoesNotFlagTheStoredOne() throws {
        let stored = try imported(["Id": "5002", "Number": "20260901"], id: 12)

        let plan = plan(try cancelledRow(["Id": "5009"]), existing: [stored])

        #expect(plan.conflicts == ["20260901 — číslo už používá jiná faktura z Fakturoidu — nepřidáno"])
        #expect(plan.flaggedCancelled.isEmpty && plan.updates.isEmpty && plan.skipped.isEmpty)
    }

    @Test func aRowWithTheSameFakturoidIdOrWithoutAnyIdUpdatesTheInvoiceAsBefore() throws {
        let stored = try imported(["Id": "5001", "Number": "20260902"], id: 41)
        let same = try rows(["Id": "5001", "Number": "20260902", "Subtotal": "4600,0", "Vat": "966.0"])
        #expect(plan(same, existing: [stored]).updates.map(\.id) == [41])

        // An export without the ids cannot tell another invoice apart: the digits match as before.
        let withoutID = try rows(["Id": "", "Number": "20260902", "Subtotal": "4600,0", "Vat": "966.0"])
        #expect(plan(withoutID, existing: [stored]).updates.map(\.id) == [41])

        // An invoice imported without an id is the invoice of the row.
        let storedWithoutID = try imported(["Id": "", "Number": "20260902"], id: 41)
        #expect(plan(same, existing: [storedWithoutID]).updates.map(\.id) == [41])
    }

    @Test func aChangeOfTheReviewUpdatesAnInvoiceThatWasNotChangedInTheApp() throws {
        // The currency had no rates at the first import, so the invoice was held; the rates are there now.
        let row = ["Number": "20260902", "Currency": "USD", "Vat": "0.0", "Client country": "US"]
        let held = try imported(row, known: [.czk])
        #expect(held.review == ReviewFlag(reason: "měna USD bez kurzů ČNB"))

        let plan = plan(try rows(row), existing: [held])

        #expect(plan.updates.count == 1 && plan.unchanged.isEmpty)
        #expect(plan.updates.first?.review == nil)
        #expect(plan.updates.first?.id == held.id)
    }

    @Test func aChangeOfTheReviewDoesNotTouchAnInvoiceChangedInTheApp() throws {
        let row = ["Number": "20260902", "Currency": "USD", "Vat": "0.0", "Client country": "US"]
        var resolved = try imported(row, known: [.czk], changedInApp: true)
        resolved.review = nil

        let plan = plan(try rows(row), existing: [resolved])

        #expect(plan.unchanged == ["20260902"])
        #expect(plan.updates.isEmpty && plan.kept.isEmpty)
    }

    @Test func aFlagThatTheAppLeftOnAnInvoiceItChangedIsNotTakenAwayByTheImport() throws {
        let row = ["Number": "20260902", "Currency": "USD", "Vat": "0.0", "Client country": "US"]
        let stored = try imported(row, known: [.czk], changedInApp: true)
        #expect(stored.review == ReviewFlag(reason: "měna USD bez kurzů ČNB"))

        let plan = plan(try rows(row), existing: [stored])

        #expect(plan.unchanged == ["20260902"])
        #expect(plan.updates.isEmpty && plan.kept.isEmpty)
    }

    @Test func aFlagIsNeverSetOnAnInvoiceThatHasNoneWhenTheRowHasNotChanged() throws {
        // The invoice was fine when it was imported. If the import cannot tell now that the ČNB quotes the currency,
        // the row is the same, so the invoice (and its payment) stays as it is.
        let row = ["Number": "20260902", "Currency": "USD", "Vat": "0.0", "Client country": "US"]
        let stored = try imported(row)
        #expect(stored.review == nil)

        let plan = plan(try rows(row), existing: [stored], known: [.czk])

        #expect(plan.unchanged == ["20260902"])
        #expect(plan.updates.isEmpty && plan.reviewItems.isEmpty && plan.kept.isEmpty)
    }

    @Test func aFlagOfAnotherReasonIsNotChangedWhenTheRowHasNotChanged() throws {
        let row = ["Number": "20260902", "Currency": "USD", "Vat": "0.0", "Client country": "US"]
        var stored = try imported(row, known: [.czk])
        stored.review = ReviewFlag(reason: "zkontrolováno jinak")

        let plan = plan(try rows(row), existing: [stored], known: [.czk])

        #expect(plan.unchanged == ["20260902"] && plan.updates.isEmpty)
    }

    @Test func aRowThatIsNowInReviewUpdatesTheInvoiceAndIsListed() throws {
        let stored = try imported(["Number": "20260902"])
        let negative = try rows(["Number": "20260902", "Subtotal": "-4500,0", "Total": "-5445,0", "Vat": "-945.0"])

        let plan = plan(negative, existing: [stored])

        #expect(plan.updates.first?.review == ReviewFlag(reason: "záporná částka"))
        #expect(plan.reviewItems == ["20260902 — záporná částka"])
    }

    // MARK: Cancelled rows

    private func cancelledRow(_ overrides: FakturoidCSV.Row = [:]) throws -> [FakturoidRow] {
        let cancelled = ["Number": "20260901", "Status": "cancelled", "Cancelled at": "2026-10-16 09:00:00"]
        return try rows(cancelled.merging(overrides) { $1 })
    }

    @Test func aCancelledRowTurnsAnImportedInvoiceIntoOneToCheck() throws {
        var stored = try imported(["Id": "5002", "Number": "20260901"], id: 12)
        stored.payment = Payment.fixture(on: "2026-10-02")
        let cancelled = try cancelledRow(["Id": "5002"])

        let plan = plan(cancelled, existing: [stored])

        let flagged = try #require(plan.flaggedCancelled.first)
        #expect(plan.flaggedCancelled.count == 1)
        #expect(flagged.id == 12)
        #expect(flagged.review == ReviewFlag(reason: "zrušeno ve Fakturoidu"))
        #expect(
            flagged.source
                == .imported(fakturoidID: "5002", fingerprint: cancelled[0].fingerprint, changedInApp: false))
        #expect(flagged.payment == stored.payment)
        #expect(flagged.items == stored.items && flagged.number == "20260901")
        #expect(plan.reviewItems == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(plan.skipped.isEmpty && plan.updates.isEmpty && plan.inserts.isEmpty && plan.unchanged.isEmpty)
    }

    @Test func aCancelledRowThatWasFlaggedAlreadyChangesNothing() throws {
        let cancelled = try cancelledRow(["Id": "5002"])
        var stored = try imported(["Id": "5002", "Number": "20260901"], id: 12)
        stored.review = ReviewFlag(reason: "zrušeno ve Fakturoidu")
        stored.source = .imported(fakturoidID: "5002", fingerprint: cancelled[0].fingerprint, changedInApp: false)

        let plan = plan(cancelled, existing: [stored])

        #expect(plan.unchanged == ["20260901"])
        #expect(plan.flaggedCancelled.isEmpty && plan.reviewItems.isEmpty && plan.skipped.isEmpty)
    }

    @Test func aCancelledRowFlagsAnInvoiceChangedInTheAppAndKeepsEverythingElseOfIt() throws {
        var stored = try imported(["Id": "5002", "Number": "20260901"], id: 12, changedInApp: true)
        stored.payment = Payment.fixture(on: "2026-10-02")
        stored.note = "Domluveno telefonicky"
        let cancelled = try cancelledRow(["Id": "5002"])

        let plan = plan(cancelled, existing: [stored])

        // Every field of the app's version stays, the payment too; the flag is new, and so is the row it came from.
        var expected = stored
        expected.review = ReviewFlag(reason: "zrušeno ve Fakturoidu")
        expected.source = .imported(fakturoidID: "5002", fingerprint: cancelled[0].fingerprint, changedInApp: true)
        #expect(plan.flaggedCancelled == [expected])
        #expect(plan.kept.isEmpty && plan.skipped.isEmpty && plan.updates.isEmpty && plan.unchanged.isEmpty)
        #expect(plan.reviewItems == ["20260901 — zrušeno ve Fakturoidu a změněno v aplikaci — ponecháno ke kontrole"])
    }

    @Test func aCancelledRowThatFlaggedAnInvoiceChangedInTheAppChangesNothingTheNextTime() throws {
        let stored = try imported(["Id": "5002", "Number": "20260901"], id: 12, changedInApp: true)
        let cancelled = try cancelledRow(["Id": "5002"])
        let flagged = try #require(plan(cancelled, existing: [stored]).flaggedCancelled.first)
        // The person has taken the flag away since: the row is the same, so it does not come back.
        var resolved = flagged
        resolved.review = nil

        let again = plan(cancelled, existing: [flagged])
        let afterResolving = plan(cancelled, existing: [resolved])

        #expect(again.unchanged == ["20260901"] && again.flaggedCancelled.isEmpty && again.reviewItems.isEmpty)
        #expect(afterResolving.unchanged == ["20260901"] && afterResolving.flaggedCancelled.isEmpty)
    }

    @Test func aCancelledRowForNoInvoiceInTheAppIsSkipped() throws {
        let plan = plan(try cancelledRow())

        #expect(plan.skipped == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(plan.flaggedCancelled.isEmpty && plan.inserts.isEmpty)
    }

    @Test func aCancelledRowNeverTouchesAnInvoiceMadeInTheApp() throws {
        let appInvoice = Invoice.fixture(number: "20260901", currency: .czk)

        let plan = plan(try cancelledRow(), existing: [appInvoice])

        #expect(plan.skipped == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(plan.flaggedCancelled.isEmpty && plan.conflicts.isEmpty)
    }

    @Test func aCancelledRowOfAnotherCurrencyThanTheInvoiceInTheAppIsSkipped() throws {
        let stored = try imported(["Id": "5002", "Number": "20260901"])

        let plan = plan(try cancelledRow(["Id": "5002", "Currency": "EUR", "Vat": "0.0"]), existing: [stored])

        #expect(plan.skipped.count == 1 && plan.flaggedCancelled.isEmpty)
    }

    // MARK: Rows that cannot be added, and rows that come twice

    @Test func aRowWithoutAnIssueDateOrWithACurrencyThatIsNoCodeCannotBeAdded() throws {
        let plan = plan(try rows(["Number": "20261002", "Issued on": ""], ["Number": "20261003", "Currency": "US"]))

        #expect(
            plan.conflicts == [
                "20261002 — chybí datum vystavení — nepřidáno", "20261003 — neplatná měna — nepřidáno",
            ])
        #expect(plan.inserts.isEmpty && plan.newClients.isEmpty)
    }

    // MARK: A number without a digit

    // Numbers are unique by their digits, so only one invoice can have no digit in its number. That one is added in
    // review, and a later row finds it by its Fakturoid id, since its number says nothing.

    @Test func aNumberWithoutADigitIsAddedInReview() throws {
        let plan = plan(try rows(["Id": "9", "Number": "ABC"], ["Id": "10", "Number": ""]))

        let invoice = try #require(plan.inserts.first)
        #expect(plan.inserts.count == 1 && invoice.number == "ABC" && invoice.numberDigits.isEmpty)
        #expect(invoice.review == ReviewFlag(reason: "číslo bez číslic"))
        #expect(plan.reviewItems == ["ABC — číslo bez číslic"])
        #expect(plan.newClients.count == 1 && plan.newClientIndexByDigits[""] == 0)
    }

    @Test func onlyOneNumberWithoutADigitIsAddedAtATime() throws {
        let plan = plan(
            try rows(["Id": "9", "Number": "ABC"], ["Id": "10", "Number": ""], ["Id": "11", "Number": "XYZ"]))

        #expect(plan.inserts.map(\.number) == ["ABC"])
        #expect(
            plan.conflicts == [
                "(bez čísla) — jiná faktura už má číslo bez číslic — nepřidáno",
                "XYZ — jiná faktura už má číslo bez číslic — nepřidáno",
            ])
    }

    @Test func aNumberWithoutADigitThatComesTwiceAlikeIsAddedOnce() throws {
        let plan = plan(try rows(["Id": "9", "Number": "ABC"], ["Id": "9", "Number": "ABC"]))

        #expect(plan.inserts.map(\.number) == ["ABC"])
        #expect(plan.conflicts.isEmpty)
    }

    @Test func rowsWithoutADigitAndWithoutAnIdAreNeverTakenForOneInvoice() throws {
        // Not even when they are alike: nothing says they are the same invoice.
        let plan = plan(try rows(["Id": "", "Number": "ABC"], ["Id": "", "Number": "ABC"]))

        #expect(plan.inserts.map(\.number) == ["ABC"])
        #expect(plan.conflicts == ["ABC — jiná faktura už má číslo bez číslic — nepřidáno"])
    }

    @Test func aNumberWithoutADigitIsTheInvoiceWithTheSameFakturoidId() throws {
        let stored = try imported(["Id": "9", "Number": "ABC"], id: 5)
        let same = try rows(["Id": "9", "Number": "ABC"])
        let changed = try rows(["Id": "9", "Number": "ABC", "Subtotal": "4600,0", "Total": "5566,0", "Vat": "966.0"])
        var changedInApp = stored
        if case .imported(let id, let fingerprint, _) = stored.source {
            changedInApp.source = .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: true)
        }

        let unchanged = plan(same, existing: [stored])
        let updated = plan(changed, existing: [stored])
        let kept = plan(changed, existing: [changedInApp])

        #expect(unchanged.unchanged == ["ABC"] && unchanged.updates.isEmpty && unchanged.conflicts.isEmpty)
        #expect(updated.updates.map(\.id) == [5] && updated.updates.first?.number == "ABC")
        #expect(updated.updates.first?.netMinor == 460_000 && updated.inserts.isEmpty)
        #expect(kept.kept == ["ABC — změněno v aplikaci — ponecháno"] && kept.updates.isEmpty)
    }

    @Test func aNumberWithoutADigitIsNeverTheInvoiceOfAnotherRowOrOfTheApp() throws {
        let stored = try imported(["Id": "9", "Number": "ABC"], id: 5)
        let appInvoice = Invoice.fixture(number: "ABC")
        let other = try rows(["Id": "10", "Number": "XYZ"])
        let withoutId = try rows(["Id": "", "Number": "XYZ"])

        let ofAnotherId = plan(other, existing: [stored])
        let ofNoId = plan(withoutId, existing: [stored])
        let ofTheApp = plan(other, existing: [appInvoice])

        let message = "XYZ — jiná faktura už má číslo bez číslic — nepřidáno"
        #expect(ofAnotherId.conflicts == [message] && ofNoId.conflicts == [message] && ofTheApp.conflicts == [message])
        #expect([ofAnotherId, ofNoId, ofTheApp].allSatisfy { $0.inserts.isEmpty && $0.updates.isEmpty })
    }

    @Test func aNumberThatLostItsDigitsInFakturoidIsAConflictLikeAnyRenumberedInvoice() throws {
        let stored = try imported(["Id": "9", "Number": "20260902"], id: 5)

        let plan = plan(try rows(["Id": "9", "Number": "ABC"]), existing: [stored])

        #expect(plan.conflicts == ["ABC — už importováno pod číslem 20260902 — nepřidáno"])
        #expect(plan.inserts.isEmpty && plan.updates.isEmpty)
    }

    @Test func aCancelledRowWithoutADigitFindsItsInvoiceByTheFakturoidId() throws {
        let stored = try imported(["Id": "9", "Number": "ABC"], id: 5)
        let cancelled = ["Status": "cancelled", "Cancelled at": "2026-10-16 09:00:00"]
        let itself = try rows(cancelled.merging(["Id": "9", "Number": "ABC"]) { $1 })
        let another = try rows(cancelled.merging(["Id": "10", "Number": "XYZ"]) { $1 })
        let withoutId = try rows(cancelled.merging(["Id": "", "Number": "XYZ"]) { $1 })

        #expect(plan(itself, existing: [stored]).flaggedCancelled.map(\.id) == [5])
        #expect(plan(another, existing: [stored]).skipped == ["XYZ — zrušeno ve Fakturoidu"])
        #expect(plan(withoutId, existing: [stored]).skipped == ["XYZ — zrušeno ve Fakturoidu"])
        #expect(plan(another, existing: [stored]).flaggedCancelled.isEmpty)
    }

    @Test func aRowThatComesTwiceInTheSameImportIsAddedOnce() throws {
        let twice = try rows(["Number": "20261001"], ["Number": "20261001"])

        let plan = plan(twice)

        #expect(plan.inserts.map(\.number) == ["20261001"])
        #expect(plan.conflicts.isEmpty && plan.unchanged.isEmpty)
    }

    // MARK: One invoice in several rows of the import

    // The rows of one import with the same number (by its digits) in the same currency are one invoice. If one of them
    // is cancelled, the cancellation wins. Otherwise the rows must agree, or the invoice is held for review without a
    // payment. Whichever file comes first makes no difference.

    /// The older export of the invoice says it is paid, the newer one that it is cancelled.
    private func paidAndCancelled(reversed: Bool) throws -> [FakturoidRow] {
        let paid = FakturoidCSV.row([
            "Id": "5002", "Number": "20260901", "Status": "paid", "Paid on": "2026-10-02",
        ])
        let cancelled = FakturoidCSV.row([
            "Id": "5002", "Number": "20260901", "Status": "cancelled", "Cancelled at": "2026-10-16 09:00:00",
            "Paid on": "2026-10-02",
        ])
        return try FakturoidCSV.rows(reversed ? [cancelled, paid] : [paid, cancelled])
    }

    /// Two exports of the invoice whose amounts differ.
    private func twoVersions(reversed: Bool) throws -> [FakturoidRow] {
        let first = FakturoidCSV.row([
            "Id": "5002", "Number": "20260901", "Status": "paid", "Paid on": "2026-10-02",
        ])
        let second = FakturoidCSV.row([
            "Id": "5002", "Number": "2026-09-01", "Status": "paid", "Paid on": "2026-10-02", "Subtotal": "4600,0",
            "Total": "5566,0", "Vat": "966.0",
        ])
        return try FakturoidCSV.rows(reversed ? [second, first] : [first, second])
    }

    private func paymentsOf(_ rows: [FakturoidRow]) -> [String: Payment] {
        Dictionary(
            rows.map { ($0.fingerprint, Payment.fixture(on: "2026-10-02")) }, uniquingKeysWith: { first, _ in first })
    }

    @Test(arguments: [false, true])
    func aCancelledRowWinsOverTheOtherRowsOfTheInvoiceAndNothingIsAdded(reversed: Bool) throws {
        let rows = try paidAndCancelled(reversed: reversed)

        let plan = plan(rows, payments: paymentsOf(rows))

        #expect(plan.skipped == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(plan.inserts.isEmpty && plan.updates.isEmpty && plan.unchanged.isEmpty && plan.kept.isEmpty)
        #expect(plan.conflicts.isEmpty && plan.reviewItems.isEmpty && plan.flaggedCancelled.isEmpty)
        // The invoice is not one of the client's, as far as this import knows.
        #expect(plan.newClients.isEmpty)
    }

    @Test(arguments: [false, true])
    func aCancelledRowWinsEvenOverRowsThatDiffer(reversed: Bool) throws {
        let versions = try twoVersions(reversed: false)
        let cancelled = try FakturoidCSV.rows([
            FakturoidCSV.row([
                "Id": "5002", "Number": "20260901", "Status": "cancelled", "Cancelled at": "2026-10-16 09:00:00",
            ])
        ])
        let rows = reversed ? cancelled + versions : versions + cancelled

        let plan = plan(rows, payments: paymentsOf(rows))

        #expect(plan.skipped == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(plan.inserts.isEmpty && plan.conflicts.isEmpty && plan.reviewItems.isEmpty)
    }

    @Test(arguments: [false, true])
    func aCancelledRowWinsOverTheOtherRowsOfAnImportedInvoiceAndFlagsIt(reversed: Bool) throws {
        let stored = try imported(
            ["Id": "5002", "Number": "20260901", "Status": "paid", "Paid on": "2026-10-02"], id: 12)
        let rows = try paidAndCancelled(reversed: reversed)

        let plan = plan(rows, existing: [stored], payments: paymentsOf(rows))

        // The paid row is the one the invoice was made from, and it does not matter: the invoice is cancelled.
        #expect(plan.flaggedCancelled.map(\.id) == [12])
        #expect(plan.flaggedCancelled.first?.review == ReviewFlag(reason: "zrušeno ve Fakturoidu"))
        #expect(plan.unchanged.isEmpty && plan.updates.isEmpty && plan.inserts.isEmpty && plan.conflicts.isEmpty)
        #expect(plan.reviewItems == ["20260901 — zrušeno ve Fakturoidu"])
    }

    @Test(arguments: [false, true])
    func aCancelledRowThatIsNotStoredDoesNotTakeTheNumberOfAnotherCurrency(reversed: Bool) throws {
        let cancelled = FakturoidCSV.row([
            "Number": "20261001", "Currency": "USD", "Vat": "0.0", "Status": "cancelled",
            "Cancelled at": "2026-10-16 09:00:00",
        ])
        let live = FakturoidCSV.row(["Number": "20261001"])

        let plan = plan(try FakturoidCSV.rows(reversed ? [live, cancelled] : [cancelled, live]))

        #expect(plan.inserts.map(\.currency) == [.czk] && plan.conflicts.isEmpty)
        #expect(plan.skipped == ["20261001 — zrušeno ve Fakturoidu"])
    }

    @Test(arguments: [false, true])
    func rowsOfOneInvoiceWithDifferentContentHoldItForReviewWithoutAPayment(reversed: Bool) throws {
        let rows = try twoVersions(reversed: reversed)

        let plan = plan(rows, payments: paymentsOf(rows))

        let held = try #require(plan.inserts.first)
        #expect(plan.inserts.count == 1 && plan.updates.isEmpty && plan.conflicts.isEmpty && plan.skipped.isEmpty)
        #expect(held.review == ReviewFlag(reason: "v importu vícekrát s různým obsahem"))
        #expect(held.payment == nil)
        #expect(plan.reviewItems == ["\(rows[0].number) — v importu vícekrát s různým obsahem — ke kontrole"])
        // It has the content of the row that comes first.
        #expect(held.number == rows[0].number && held.netMinor == rows[0].subtotalMinor)
        #expect(held.source == .imported(fakturoidID: "5002", fingerprint: rows[0].fingerprint, changedInApp: false))
    }

    @Test func oneRowThatDiffersAmongRepeatsHoldsTheInvoiceToo() throws {
        let rows = try twoVersions(reversed: false)
        let repeated = [rows[0], rows[0], rows[1], rows[0]]

        let plan = plan(repeated)

        #expect(plan.inserts.count == 1 && plan.inserts.first?.review?.reason == "v importu vícekrát s různým obsahem")
        #expect(plan.conflicts.isEmpty)
    }

    @Test(arguments: [false, true])
    func rowsOfAnImportedInvoiceWithDifferentContentFlagItAndKeepWhatItHolds(reversed: Bool) throws {
        var stored = try imported(
            ["Id": "5002", "Number": "20260901", "Status": "paid", "Paid on": "2026-10-02"], id: 12)
        stored.payment = Payment.fixture(on: "2026-10-02")
        let rows = try twoVersions(reversed: reversed)

        let plan = plan(rows, existing: [stored], payments: paymentsOf(rows))

        // Neither row is applied: the invoice keeps its content and its payment, and is not counted until resolved.
        var expected = stored
        expected.review = ReviewFlag(reason: "v importu vícekrát s různým obsahem")
        #expect(plan.updates == [expected])
        #expect(plan.inserts.isEmpty && plan.conflicts.isEmpty && plan.unchanged.isEmpty && plan.kept.isEmpty)
        #expect(plan.reviewItems == ["\(rows[0].number) — v importu vícekrát s různým obsahem — ke kontrole"])
    }

    @Test func theInvoiceThatWasFlaggedForItsRowsIsLeftAloneTheNextTime() throws {
        var stored = try imported(
            ["Id": "5002", "Number": "20260901", "Status": "paid", "Paid on": "2026-10-02"], id: 12)
        stored.review = ReviewFlag(reason: "v importu vícekrát s různým obsahem")
        var changedInApp = stored
        changedInApp.review = nil
        if case .imported(let id, let fingerprint, _) = stored.source {
            changedInApp.source = .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: true)
        }
        let rows = try twoVersions(reversed: false)

        let again = plan(rows, existing: [stored])
        let resolved = plan(rows, existing: [changedInApp])

        #expect(again.unchanged == [rows[0].number] && again.updates.isEmpty && again.reviewItems.isEmpty)
        #expect(resolved.kept == ["\(rows[0].number) — změněno v aplikaci — ponecháno"] && resolved.updates.isEmpty)
    }

    @Test func aFlagForRowsThatDifferedIsClearedWhenTheRowIsTheSameAgain() throws {
        // Only one of the exports is imported now, and it is the one the invoice was made from.
        let rows = try twoVersions(reversed: false)
        var stored = try imported(
            ["Id": "5002", "Number": "20260901", "Status": "paid", "Paid on": "2026-10-02"], id: 12)
        stored.review = ReviewFlag(reason: "v importu vícekrát s různým obsahem")
        let payment = Payment.fixture(on: "2026-10-02")

        let plan = plan([rows[0]], existing: [stored], payments: [rows[0].fingerprint: payment])

        #expect(plan.updates.map(\.id) == [12] && plan.updates.first?.review == nil)
        #expect(plan.updates.first?.payment == payment && plan.unchanged.isEmpty)
    }

    @Test func theSameDigitsInTwoCurrenciesInOneImportAreOneInvoiceAndOneConflict() throws {
        let plan = plan(try rows(["Number": "20261001"], ["Number": "20261001", "Currency": "EUR", "Vat": "0.0"]))

        #expect(plan.inserts.map(\.currency) == [.czk])
        #expect(plan.conflicts == ["20261001 — číslo už používá faktura v jiné měně — nepřidáno"])
    }

    // MARK: The summary

    @Test func theSummaryOfTheSampleCountsWhatThePlanDoes() throws {
        let plan = plan(try sample())

        let summary = ImportSummary(plan: plan, files: ["fakturoid_sample.csv"], exportSupplier: nil)

        #expect(summary.files == ["fakturoid_sample.csv"])
        #expect(summary.added == 11 && summary.updated == 0 && summary.unchanged == 0 && summary.skipped == 2)
        #expect(summary.needsReview == 4)
        #expect(summary.keptChangedInApp == 0 && summary.conflicts == 0 && summary.flaggedCancelled == 0)
        #expect(summary.newClients == 4 && summary.filledClients == 0)
        #expect(summary.reviewItems.count == 4 && summary.keptItems.isEmpty && summary.conflictItems.isEmpty)
        #expect(summary.exportSupplier == nil)
    }

    @Test func theSummaryCountsFilledClientsAndListsEveryKindOfItem() throws {
        let reimport = try sample("fakturoid_reimport")
        let first = plan(try sample())
        var (invoices, clients) = applied(first)
        // Invoice 20260902 was changed in the app, and an invoice of the app has the number of row 14.
        if case .imported(let id, let fingerprint, _) = invoices[0].source {
            invoices[0].source = .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: true)
        }
        invoices.append(Invoice.fixture(number: "20261102", currency: .czk, duzp: "2026-11-02"))
        clients[0].phone = ""

        let plan = plan(reimport, existing: invoices, clients: clients)
        let supplier = Supplier(name: "Jana Vzorová")
        let summary = ImportSummary(plan: plan, files: ["a.csv", "b.csv"], exportSupplier: supplier)

        #expect(summary.files == ["a.csv", "b.csv"])
        #expect(summary.added == 0 && summary.updated == 1 && summary.unchanged == 8 && summary.skipped == 2)
        #expect(summary.keptChangedInApp == 1)
        #expect(summary.keptItems == ["20260902 — změněno v aplikaci — ponecháno"])
        #expect(summary.conflicts == 1 && summary.conflictItems.count == 1)
        #expect(summary.flaggedCancelled == 1 && summary.needsReview == 0)
        #expect(summary.reviewItems == ["20260901 — zrušeno ve Fakturoidu"])
        #expect(summary.newClients == 0 && summary.filledClients == 1)
        #expect(summary.exportSupplier == supplier)
    }

    @Test func aSummaryIsCodable() throws {
        let plan = plan(try sample())
        let supplier = Supplier(name: "Jana Vzorová", ico: "11223344")
        let summary = ImportSummary(plan: plan, files: ["x.csv"], exportSupplier: supplier)

        let data = try JSONEncoder().encode(summary)

        #expect(try JSONDecoder().decode(ImportSummary.self, from: data) == summary)
        #expect(summary.newestYear == 2026)
    }

    @Test func aSummaryOfAnOlderLogWithoutTheNewestYearIsStillRead() throws {
        let summary = ImportSummary(plan: plan(try sample()), files: ["x.csv"], exportSupplier: nil)
        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(summary))
        var object = try #require(encoded as? [String: Any])
        // The log of an import made before the summary named the year has every other key.
        object["newestYear"] = nil

        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ImportSummary.self, from: data)

        #expect(decoded.newestYear == nil && decoded.added == 11 && decoded.files == ["x.csv"])
    }

    @Test func theSummaryNamesTheNewestYearOfTheInvoicesThePlanAddsUpdatesOrFlags() throws {
        let older = try rows(
            ["Number": "20240101", "Issued on": "2024-01-01", "Taxable fulfillment due": "2024-01-01"],
            ["Number": "20250310", "Issued on": "2025-03-10", "Taxable fulfillment due": "2025-03-10"])

        let added = ImportSummary(plan: plan(older), files: [], exportSupplier: nil)
        let sampleOnly = ImportSummary(plan: plan(try sample()), files: [], exportSupplier: nil)

        #expect(added.newestYear == 2025)
        #expect(sampleOnly.newestYear == 2026)
    }

    @Test func theSummaryHasNoNewestYearWhenThePlanChangesNoInvoice() throws {
        let first = plan(try sample())
        let (invoices, clients) = applied(first)

        let again = plan(try sample(), existing: invoices, clients: clients)

        #expect(again.inserts.isEmpty && again.updates.isEmpty && again.flaggedCancelled.isEmpty)
        #expect(ImportSummary(plan: again, files: [], exportSupplier: nil).newestYear == nil)
        #expect(ImportSummary().newestYear == nil)
    }

    @Test func anInvoiceThatIsOnlyFlaggedAsCancelledInFakturoidCountsForTheNewestYearToo() throws {
        let stored = try imported(["Number": "20250901", "Issued on": "2025-09-30"], id: 7)
        let cancelled = try rows([
            "Number": "20250901", "Issued on": "2025-09-30", "Status": "cancelled",
            "Cancelled at": "2025-10-16 09:00:00",
        ])

        let plan = plan(cancelled, existing: [stored])

        #expect(plan.inserts.isEmpty && plan.updates.isEmpty)
        #expect(plan.flaggedCancelled.map(\.number) == ["20250901"])
        #expect(ImportSummary(plan: plan, files: [], exportSupplier: nil).newestYear == 2025)
    }
}
