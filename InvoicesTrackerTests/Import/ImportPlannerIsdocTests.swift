import Foundation
import Testing

@testable import InvoicesTracker

/// What an import of CSV rows and ISDOC invoices together makes of an invoice, worked out without a database: each
/// format sets only the fields it owns, either order gives the same invoice, and only what changed is applied. The
/// ISDOC files are the invented fixtures in `Fixtures/Import/isdoc/`, and the rows are made to match them.
struct ImportPlannerIsdocTests {
    // MARK: Helpers

    private static let known: Set<CurrencyCode> = [.czk, .usd, .eur]

    /// The row Fakturoid exports for the ISDOC fixture `czk-21`: 20260902, 5 040,00 Kč and 1 058,40 Kč VAT, paid on
    /// 10 September 2026. Its subject is the id of the client in Fakturoid, as a real export has it.
    static let crownRow: FakturoidCSV.Row = [
        "Id": "7001", "Number": "20260902", "Subject": "4410", "Client name": "Truhlářství Doubek s.r.o.",
        "Client street": "Na Výsluní 112", "Client city": "Benešov", "Client zip": "25601", "Client country": "CZ",
        "Client registration no": "17392047", "Client vat no": "CZ17392047",
        "Client email": "ucetni@doubek.example", "Client phone": "+420 777 000 111", "Issued on": "2026-09-02",
        "Taxable fulfillment due": "2026-09-02", "Due": "14", "Due on": "2026-09-16", "Subtotal": "5040,0",
        "Total": "6098,4", "Vat": "1058.4", "Status": "paid", "Paid on": "2026-09-10",
    ]

    /// The row Fakturoid exports for the ISDOC fixture `usd-0`: 20260901, 14 356,00 USD at 21,278 Kč without VAT, paid
    /// on 21 September 2026.
    static let dollarRow: FakturoidCSV.Row = [
        "Id": "7002", "Number": "20260901", "Subject": "4411", "Client name": "Harborlight Software, Inc.",
        "Client street": "1450 Alder Ridge Rd", "Client city": "Boise", "Client zip": "83702",
        "Client country": "US", "Client registration no": "", "Client vat no": "",
        "Client email": "ap@harborlight.example", "Issued on": "2026-09-02", "Taxable fulfillment due": "2026-09-02",
        "Due": "14", "Due on": "2026-09-16", "Currency": "USD", "Exchange rate": "21.278", "Language": "en",
        "Payment method": "bank", "Payment method human": "Bank transfer", "Subtotal": "14356,0",
        "Total": "14356,0", "Vat": "0.0", "Status": "paid", "Paid on": "2026-09-21",
    ]

    /// The plan of an import of `rows` and `isdocs` against `existing` and `clients`.
    private func plan(
        rows: [FakturoidRow] = [],
        isdocs: [IsdocInvoice] = [],
        existing: [Invoice] = [],
        clients: [Client] = [],
        payments: [String: Payment] = [:],
        invoiceRates: [String: StoredRate] = [:]
    ) -> ImportPlan {
        ImportPlanner.plan(
            sources: ImportSources(rows: rows, isdocs: isdocs), existingInvoices: existing, clients: clients,
            knownCurrencies: Self.known, payments: payments, invoiceRates: invoiceRates
        )
    }

    /// The ISDOC fixture `name`, as the reader reads it.
    private func isdoc(_ name: String) throws -> IsdocInvoice {
        try IsdocReader.read(Data(contentsOf: fixtureURL(name, "isdoc")))
    }

    /// `isdoc` with the fields that are given replaced, and without its issue date or its rate when asked.
    private func copy(
        of isdoc: IsdocInvoice,
        documentType: Int? = nil,
        number: String? = nil,
        note: String? = nil,
        paymentMeansCode: String? = nil,
        withoutIssueDate: Bool = false,
        withoutRate: Bool = false
    ) -> IsdocInvoice {
        IsdocInvoice(
            documentType: documentType ?? isdoc.documentType, number: number ?? isdoc.number, uuid: isdoc.uuid,
            issueDate: withoutIssueDate ? nil : isdoc.issueDate, taxPointDate: isdoc.taxPointDate,
            dueDate: isdoc.dueDate, note: note ?? isdoc.note, currency: isdoc.currency,
            rate: withoutRate ? nil : isdoc.rate, customer: isdoc.customer, supplier: isdoc.supplier,
            lines: isdoc.lines, paymentMeansCode: paymentMeansCode ?? isdoc.paymentMeansCode
        )
    }

    /// The payment the importer gives `row`: converted from the invoice the row makes, as `FakturoidImporter` does,
    /// at 21,50 Kč for a dollar.
    private func payment(of row: FakturoidRow) throws -> Payment {
        let invoice = try #require(ImportPlanner.invoice(from: row, knownCurrencies: Self.known))
        let day = try #require(row.paidOn)
        return PaymentConverter.convert(
            invoice: invoice, date: day, requested: invoice.currency.isCZK ? .czk : .cnbDaily,
            bankCZKTotalHalere: nil, cnbRate: declaredLookup("USD", "21.5", on: "2026-09-18"), uniformRate: nil
        )
    }

    /// What the database holds once `plan` is applied over `existing` and `clients`: an update replaces the invoice
    /// with its id, an added invoice gets the next id, and new clients get ids and are linked to their invoices.
    private func applied(
        _ plan: ImportPlan, over existing: [Invoice] = [], clients: [Client] = []
    ) -> (invoices: [Invoice], clients: [Client]) {
        var allClients = clients
        for filled in plan.clientUpdates {
            if let index = allClients.firstIndex(where: { $0.id == filled.id }) {
                allClients[index] = filled
            }
        }
        var newClientIDs: [Int64] = []
        for var client in plan.newClients {
            client.id = (allClients.map(\.id).max() ?? 0) + 1
            newClientIDs.append(client.id)
            allClients.append(client)
        }
        var invoices = existing
        for var changed in plan.updates + plan.flaggedCancelled {
            if let index = plan.newClientIndexByDigits[changed.numberDigits] {
                changed.clientID = newClientIDs[index]
            }
            if let place = invoices.firstIndex(where: { $0.id == changed.id }) {
                invoices[place] = changed
            }
        }
        for var added in plan.inserts {
            added.id = (invoices.map(\.id).max() ?? 0) + 1
            if let index = plan.newClientIndexByDigits[added.numberDigits] {
                added.clientID = newClientIDs[index]
            }
            invoices.append(added)
        }
        return (invoices, allClients)
    }

    /// `invoice` without what the database gives it, its id and the link to its client, so that invoices planned in
    /// different ways can be compared.
    private func unlinked(_ invoice: Invoice) -> Invoice {
        var copy = invoice
        copy.id = 0
        copy.clientID = nil
        return copy
    }

    // MARK: An ISDOC file alone

    @Test func anISDOCAloneAddsAnUnpaidInvoiceWithItsLines() throws {
        let file = try isdoc("czk-21")

        let plan = plan(isdocs: [file])

        let added = try #require(plan.inserts.first)
        #expect(plan.inserts.count == 1 && plan.updates.isEmpty && plan.conflicts.isEmpty)
        #expect(added.number == "20260902" && added.currency == .czk && added.invoiceRate == nil)
        #expect(
            added.items == [
                InvoiceItem(
                    description: "Správa IT a podpora – září 2026", quantity: decimal("7"), unit: "hod",
                    unitPriceMinor: 72_000)
            ])
        #expect(added.netMinor == 504_000 && added.vatMinor == 105_840 && added.vatMode == .domestic21)
        #expect(added.issueDate == civilDate("2026-09-02") && added.duzp == civilDate("2026-09-02"))
        #expect(added.dueDate == civilDate("2026-09-16"))
        #expect(added.note == "Fakturujeme vám za září.")
        #expect(
            added.client
                == ClientSnapshot(
                    name: "Truhlářství Doubek s.r.o.", street: "Na Výsluní 112", postcode: "25601", city: "Benešov",
                    country: "CZ", ico: "17392047", dic: "CZ17392047", email: ""))
        // Unpaid and issued, without the QR code, in Czech for a Czech client, and by transfer as code 42 says.
        #expect(added.payment == nil && added.review == nil && added.status == .issued && !added.qrEnabled)
        #expect(added.language == .cs && added.paymentMethod == "Převodem")
        // No row of the CSV is imported for it yet.
        #expect(added.source == .imported(fakturoidID: "", fingerprint: "", changedInApp: false))
        #expect(added.isdocFingerprint == file.fingerprint)
        #expect(plan.newNumbers == ["20260902"])
        // The customer of the file is a new client.
        #expect(plan.newClients.map(\.name) == ["Truhlářství Doubek s.r.o."])
        #expect(plan.newClients.first?.ico == "17392047" && plan.newClients.first?.street == "Na Výsluní 112")
        #expect(plan.newClientIndexByDigits["20260902"] == 0)
    }

    @Test func anISDOCAloneInDollarsIsInEnglishOutsideTheCountryAtItsRate() throws {
        let added = try #require(plan(isdocs: [try isdoc("usd-0")]).inserts.first)

        #expect(added.currency == .usd && added.language == .en && added.paymentMethod == "Bank transfer")
        #expect(added.vatMode == .outsideCountry && added.netMinor == 1_435_600 && added.vatMinor == 0)
        #expect(
            added.invoiceRate
                == StoredRate(
                    rate: ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.278")),
                    declaredOn: CzechCalendar.rateDeclarationDay(for: civilDate("2026-09-02"))))
        #expect(added.client.street == "1450 Alder Ridge Rd" && added.client.country == "US")
        #expect(added.client.ico.isEmpty && added.review == nil && added.payment == nil)
    }

    @Test func anISDOCAloneTakesTheLanguageAndPaymentMethodOfTheClientItMatches() throws {
        let client = Client(
            id: 4, name: "Truhlářství Doubek s.r.o.", ico: "17392047", paymentMethod: "Hotově", language: .en)
        let file = try isdoc("czk-21")
        let withoutCode = copy(of: file, paymentMeansCode: "")

        let byCode = try #require(plan(isdocs: [file], clients: [client]).inserts.first)
        let byClient = try #require(plan(isdocs: [withoutCode], clients: [client]).inserts.first)
        let byNobody = try #require(plan(isdocs: [withoutCode]).inserts.first)

        #expect(byCode.language == .en && byCode.paymentMethod == "Bank transfer" && byCode.clientID == 4)
        #expect(byClient.language == .en && byClient.paymentMethod == "Hotově")
        #expect(byNobody.language == .cs && byNobody.paymentMethod == "")
    }

    @Test func aClientMadeFromAnIsdocAloneHasTheLanguageAndPaymentMethodOfItsInvoice() throws {
        let dollars = try isdoc("usd-0")

        let byCode = plan(isdocs: [dollars])
        let withoutCode = plan(isdocs: [copy(of: dollars, paymentMeansCode: "")])
        let czech = plan(isdocs: [try isdoc("czk-21")])

        // The language goes by the country of the customer, and code 42 is a transfer in that language.
        let english = try #require(byCode.newClients.first)
        let invoice = try #require(byCode.inserts.first)
        #expect(english.language == .en && english.paymentMethod == "Bank transfer")
        #expect(english.language == invoice.language && english.paymentMethod == invoice.paymentMethod)
        // Without the code the file does not say how the client pays.
        let custom = try #require(withoutCode.newClients.first)
        #expect(custom.language == .en && custom.paymentMethod == "")
        let local = try #require(czech.newClients.first)
        #expect(local.language == .cs && local.paymentMethod == "Převodem")
    }

    @Test func theClientOfAnIsdocAndItsRowIsTheSameInEitherOrder() throws {
        let file = try isdoc("usd-0")
        let row = try FakturoidCSV.parsed(Self.dollarRow)

        let isdocFirst = applied(plan(isdocs: [file]))
        let isdocThenCsv = applied(
            plan(rows: [row], existing: isdocFirst.invoices, clients: isdocFirst.clients), over: isdocFirst.invoices,
            clients: isdocFirst.clients)
        let csvFirst = applied(plan(rows: [row]))
        let csvThenIsdoc = applied(
            plan(isdocs: [file], existing: csvFirst.invoices, clients: csvFirst.clients), over: csvFirst.invoices,
            clients: csvFirst.clients)
        let together = applied(plan(rows: [row], isdocs: [file]))

        for clients in [isdocThenCsv.clients, csvThenIsdoc.clients, together.clients] {
            #expect(clients.map(\.language) == [.en] && clients.map(\.paymentMethod) == ["Bank transfer"])
        }
    }

    @Test func aLanguageAndAPaymentMethodARowSaysWinOverWhatAnIsdocSuggests() throws {
        // An older invoice of the client in Czech, paid in cash, and a newer ISDOC of it from a customer in the US.
        let older = try FakturoidCSV.parsed(
            Self.dollarRow.merging([
                "Id": "7000", "Number": "20260801", "Issued on": "2026-08-03", "Taxable fulfillment due": "2026-08-03",
                "Due on": "2026-08-17", "Language": "cz", "Payment method": "cash", "Payment method human": "Hotově",
                "Status": "open", "Paid on": "",
            ]) { $1 })

        let plan = plan(rows: [older], isdocs: [try isdoc("usd-0")])

        let client = try #require(plan.newClients.first)
        #expect(plan.newClients.count == 1)
        #expect(client.language == .cs && client.paymentMethod == "Hotově")
    }

    @Test func anIsdocFillsOnlyTheEmptyFieldsOfAClientThatIsThere() throws {
        let client = Client(
            id: 4, name: "Harborlight Software, Inc.", country: "US", paymentMethod: "", language: .cs)

        let plan = plan(isdocs: [try isdoc("usd-0")], clients: [client])

        let filled = try #require(plan.clientUpdates.first)
        #expect(plan.newClients.isEmpty && filled.id == 4)
        #expect(filled.street == "1450 Alder Ridge Rd" && filled.city == "Boise")
        // What the client has is kept, and an ISDOC says nothing of the client's own payment method.
        #expect(filled.language == .cs && filled.paymentMethod == "")
    }

    // MARK: Both formats

    @Test(arguments: [("czk-21", Self.crownRow), ("usd-0", Self.dollarRow)])
    func csvThenIsdocIsdocThenCsvAndBothTogetherGiveTheSameInvoice(
        fixture: String, overrides: FakturoidCSV.Row
    ) throws {
        let file = try isdoc(fixture)
        let row = try FakturoidCSV.parsed(overrides)
        let payments = [row.fingerprint: try payment(of: row)]

        let csvFirst = applied(plan(rows: [row], payments: payments))
        let csvThenIsdoc = try #require(
            plan(isdocs: [file], existing: csvFirst.invoices, clients: csvFirst.clients).updates.first)
        let isdocFirst = applied(plan(isdocs: [file]))
        let isdocThenCsv = try #require(
            plan(rows: [row], existing: isdocFirst.invoices, clients: isdocFirst.clients, payments: payments)
                .updates.first)
        let together = try #require(plan(rows: [row], isdocs: [file], payments: payments).inserts.first)

        for other in [isdocThenCsv, together] {
            #expect(other.items == csvThenIsdoc.items)
            #expect(other.number == csvThenIsdoc.number)
            #expect(other.issueDate == csvThenIsdoc.issueDate && other.duzp == csvThenIsdoc.duzp)
            #expect(other.dueDate == csvThenIsdoc.dueDate)
            #expect(other.client == csvThenIsdoc.client)
            #expect(other.vatMode == csvThenIsdoc.vatMode)
            #expect(other.invoiceRate == csvThenIsdoc.invoiceRate)
            #expect(other.payment == csvThenIsdoc.payment)
            #expect(other.language == csvThenIsdoc.language)
            #expect(other.paymentMethod == csvThenIsdoc.paymentMethod)
            #expect(unlinked(other) == unlinked(csvThenIsdoc))
        }
        // It is the invoice of both files: the lines of the ISDOC, and the state and the payment of the row.
        #expect(csvThenIsdoc.items == IsdocInvoiceBuilder.items(of: file).items)
        #expect(csvThenIsdoc.note == file.note && csvThenIsdoc.isdocFingerprint == file.fingerprint)
        #expect(csvThenIsdoc.payment == payments[row.fingerprint] && csvThenIsdoc.review == nil)
        #expect(csvThenIsdoc.client.email == row.clientEmail)
        #expect(
            csvThenIsdoc.source
                == .imported(fakturoidID: row.fakturoidID, fingerprint: row.fingerprint, changedInApp: false))
    }

    @Test func aCsvRowAfterAnIsdocChangesNoFieldTheIsdocOwns() throws {
        let file = try isdoc("czk-21")
        let fromIsdoc = applied(plan(isdocs: [file]))
        let before = try #require(fromIsdoc.invoices.first)
        // A row that disagrees with the ISDOC on all the ISDOC owns, and says the invoice is paid, in English.
        let row = try FakturoidCSV.parsed([
            "Id": "7001", "Number": "2026-09-02", "Subject": "Vývoj software, září 2026",
            "Client name": "Jiný název s.r.o.", "Client street": "Jiná 5", "Client street2": "patro 2",
            "Client city": "Kolín", "Client zip": "28002", "Client country": "SK",
            "Client registration no": "17392047", "Client vat no": "SK17392047",
            "Client email": "nova@doubek.example", "Issued on": "2026-09-05", "Taxable fulfillment due": "2026-09-04",
            "Due on": "2026-09-30", "Subtotal": "4500,0", "Total": "5445,0", "Vat": "945.0", "Language": "en",
            "Payment method": "custom", "Payment method human": "Hotově", "Status": "paid",
            "Paid on": "2026-09-10",
        ])
        let converted = try payment(of: row)

        let plan = plan(
            rows: [row], existing: fromIsdoc.invoices, clients: fromIsdoc.clients,
            payments: [row.fingerprint: converted])

        let after = try #require(plan.updates.first)
        // What the ISDOC owns is as the ISDOC has it.
        #expect(after.number == "20260902" && after.items == before.items && after.note == before.note)
        #expect(after.issueDate == before.issueDate && after.duzp == before.duzp && after.dueDate == before.dueDate)
        #expect(after.currency == before.currency && after.invoiceRate == before.invoiceRate)
        #expect(after.vatMode == .domestic21)
        var printed = before.client
        printed.email = "nova@doubek.example"
        #expect(after.client == printed)
        #expect(after.isdocFingerprint == file.fingerprint)
        // What the CSV owns is as the row has it.
        #expect(after.language == .en && after.paymentMethod == "Hotově" && after.status == .issued)
        #expect(after.review == nil)
        #expect(after.source == .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: false))
        // The payment of the row, converted again for the amounts of the lines.
        #expect(after.payment == PaymentConverter.reapply(converted, to: after))
        #expect(after.payment?.czkNetHalere == 504_000 && after.payment?.czkVatHalere == 105_840)
        // The subject of the row is used nowhere.
        let texts =
            after.items.map(\.description) + [after.note, after.paymentMethod, after.number]
            + [after.client.name, after.client.street, after.client.city, after.client.email]
        #expect(!texts.contains { $0.contains("Vývoj software") })
        #expect(plan.notes == ["2026-09-02 — částka v CSV nesouhlasí s položkami z ISDOC — ponechány položky"])
    }

    @Test func aCsvTotalThatDisagreesWithIsdocItemsKeepsTheItemsAndNotesIt() throws {
        let file = try isdoc("czk-21")
        let disagreeing = try FakturoidCSV.parsed(
            Self.crownRow.merging(["Subtotal": "4500,0", "Total": "5445,0", "Vat": "945.0"]) { $1 })
        let agreeing = try FakturoidCSV.parsed(Self.crownRow)

        let together = plan(rows: [disagreeing], isdocs: [file])
        let agreed = plan(rows: [agreeing], isdocs: [file])

        let added = try #require(together.inserts.first)
        #expect(added.items == IsdocInvoiceBuilder.items(of: file).items && added.netMinor == 504_000)
        #expect(together.notes == ["20260902 — částka v CSV nesouhlasí s položkami z ISDOC — ponechány položky"])
        // The note does not hold the invoice: it counts.
        #expect(added.review == nil && together.reviewItems.isEmpty)
        #expect(agreed.notes.isEmpty)
    }

    @Test func aLineThatIsTakenAsOneTimesItsAmountIsNoted() throws {
        let file = try isdoc("czk-21")
        var lines = file.lines
        lines[0].quantity = decimal("7.3")
        let uneven = IsdocInvoice(
            documentType: 1, number: file.number, uuid: file.uuid, issueDate: file.issueDate,
            taxPointDate: file.taxPointDate, dueDate: file.dueDate, note: file.note, currency: file.currency,
            rate: file.rate, customer: file.customer, supplier: file.supplier, lines: lines,
            paymentMeansCode: file.paymentMeansCode)

        let plan = plan(isdocs: [uneven])

        #expect(plan.inserts.first?.items.first?.quantity == decimal("1"))
        #expect(plan.notes == ["20260902 — položka „Správa IT a podpora – září 2026“ převzata jako 1 × částka řádku"])
    }

    // MARK: The CSV alone

    @Test func aNewCsvOnlyInvoiceSaysImportZFakturoidu() throws {
        // The subject of a row is the id of its client in Fakturoid, never a description of the invoice.
        let row = try FakturoidCSV.parsed(Self.crownRow.merging(["Subject": "Vývoj software, září 2026"]) { $1 })

        let added = try #require(plan(rows: [row]).inserts.first)

        #expect(
            added.items == [
                InvoiceItem(
                    description: "Import z Fakturoidu", quantity: decimal("1"), unit: "", unitPriceMinor: 504_000)
            ])
        #expect(added.isdocFingerprint == nil && added.note.isEmpty)
    }

    // MARK: Fakturoid is the source of truth

    @Test func anIsdocReplacesItemsOfAnInvoiceChangedInTheApp() throws {
        let row = try FakturoidCSV.parsed(Self.crownRow)
        let first = applied(plan(rows: [row]))
        var edited = try #require(first.invoices.first)
        edited.items = [InvoiceItem.fixture("8", at: 60_000)]
        edited.note = "Upraveno v aplikaci"
        edited.source = .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: true)
        let file = try isdoc("czk-21")

        let plan = plan(isdocs: [file], existing: [edited], clients: first.clients)

        let updated = try #require(plan.updates.first)
        #expect(updated.id == edited.id)
        #expect(updated.items == IsdocInvoiceBuilder.items(of: file).items)
        #expect(updated.note == "Fakturujeme vám za září.")
        #expect(updated.source == .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: false))
        #expect(plan.overwrittenNumbers == ["20260902"] && plan.unchangedNumbers.isEmpty)
    }

    @Test func anIsdocThatChangesTheTotalConvertsThePaymentAgainWithoutAFlag() throws {
        // The row says 14 350,00 USD, and the lines of the ISDOC give 14 356,00 USD.
        let row = try FakturoidCSV.parsed(Self.dollarRow.merging(["Subtotal": "14350,0", "Total": "14350,0"]) { $1 })
        let converted = try payment(of: row)
        let first = applied(plan(rows: [row], payments: [row.fingerprint: converted]))
        let paid = try #require(first.invoices.first)
        #expect(paid.payment == converted && converted.czkNetHalere == 30_852_500)
        let file = try isdoc("usd-0")

        let plan = plan(isdocs: [file], existing: first.invoices, clients: first.clients)

        let updated = try #require(plan.updates.first)
        #expect(updated.netMinor == 1_435_600)
        #expect(updated.payment == PaymentConverter.reapply(converted, to: updated))
        #expect(updated.payment?.czkNetHalere == 30_865_400 && updated.payment?.czkVatHalere == 0)
        #expect(updated.payment?.date == civilDate("2026-09-21") && updated.payment?.rate == converted.rate)
        #expect(updated.review == nil && plan.reviewItems.isEmpty)
    }

    @Test func anAppMadeInvoiceWithTheNumberIsUpdatedAndBecomesImported() throws {
        var appInvoice = Invoice.fixture(number: "20260902", duzp: "2026-09-02")
        appInvoice.id = 5
        let file = try isdoc("czk-21")
        let row = try FakturoidCSV.parsed(Self.crownRow)

        let byIsdoc = plan(isdocs: [file], existing: [appInvoice])
        let byRow = plan(rows: [row], existing: [appInvoice])

        let fromIsdoc = try #require(byIsdoc.updates.first)
        #expect(fromIsdoc.id == 5 && fromIsdoc.items == IsdocInvoiceBuilder.items(of: file).items)
        #expect(fromIsdoc.source == .imported(fakturoidID: "", fingerprint: "", changedInApp: false))
        #expect(fromIsdoc.isdocFingerprint == file.fingerprint)
        let fromRow = try #require(byRow.updates.first)
        #expect(fromRow.id == 5 && fromRow.netMinor == 504_000)
        #expect(fromRow.source == .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: false))
        for plan in [byIsdoc, byRow] {
            #expect(plan.conflicts.isEmpty && plan.notAdded.isEmpty && plan.inserts.isEmpty)
            #expect(plan.overwrittenNumbers == ["20260902"])
        }
    }

    @Test func aChangedCsvRowRemovesAPaymentRecordedInTheApp() throws {
        let open = Self.crownRow.merging(["Status": "open", "Paid on": ""]) { $1 }
        let row = try FakturoidCSV.parsed(open)
        let first = applied(plan(rows: [row]))
        var recorded = try #require(first.invoices.first)
        recorded.payment = Payment.fixture(on: "2026-09-12", net: 504_000, vat: 105_840)
        recorded.source = .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: true)
        // Fakturoid still says it is open, and its due date has moved.
        let changed = try FakturoidCSV.parsed(open.merging(["Due on": "2026-09-30"]) { $1 })

        let plan = plan(rows: [changed], existing: [recorded], clients: first.clients)

        let updated = try #require(plan.updates.first)
        #expect(updated.payment == nil && updated.dueDate == civilDate("2026-09-30"))
        #expect(
            updated.source == .imported(fakturoidID: "7001", fingerprint: changed.fingerprint, changedInApp: false))
    }

    @Test func aChangedCsvRowMovesAPaymentRecordedInTheAppToItsDay() throws {
        let open = Self.crownRow.merging(["Status": "open", "Paid on": ""]) { $1 }
        let first = applied(plan(rows: [try FakturoidCSV.parsed(open)]))
        var recorded = try #require(first.invoices.first)
        recorded.payment = Payment.fixture(on: "2026-09-12", net: 504_000, vat: 105_840)
        let paid = try FakturoidCSV.parsed(Self.crownRow)
        let converted = try payment(of: paid)

        let plan = plan(
            rows: [paid], existing: [recorded], clients: first.clients, payments: [paid.fingerprint: converted])

        #expect(plan.updates.first?.payment == converted)
        #expect(converted.date == civilDate("2026-09-10"))
    }

    @Test func bankBecomesPrevodemOrBankTransferAndCustomStaysAsTyped() throws {
        #expect(ImportPlanner.paymentMethod(code: "bank", human: "Banka", language: .cs) == "Převodem")
        #expect(ImportPlanner.paymentMethod(code: "bank", human: "Banka", language: .en) == "Bank transfer")
        #expect(ImportPlanner.paymentMethod(code: "custom", human: "ACH (USD)", language: .en) == "ACH (USD)")
        #expect(ImportPlanner.paymentMethod(code: "", human: "Hotově", language: .cs) == "Hotově")
        let rows = try FakturoidCSV.rows([
            FakturoidCSV.row(["Number": "20261001", "Payment method": "bank", "Language": "cz"]),
            FakturoidCSV.row([
                "Number": "20261002", "Payment method": "Bank", "Language": "en", "Client name": "Gamma GmbH",
                "Client registration no": "", "Client vat no": "DE123456789", "Client country": "DE", "Vat": "0.0",
            ]),
            FakturoidCSV.row([
                "Number": "20261003", "Payment method": "custom", "Payment method human": "ACH (USD)",
                "Language": "en", "Client name": "Harborlight Software, Inc.", "Client registration no": "",
                "Client vat no": "", "Client country": "US", "Currency": "USD", "Vat": "0.0",
            ]),
        ])

        let plan = plan(rows: rows)

        #expect(plan.inserts.map(\.paymentMethod) == ["Převodem", "Bank transfer", "ACH (USD)"])
        // A new client prints it the same way.
        #expect(plan.newClients.map(\.paymentMethod) == ["Převodem", "Bank transfer", "ACH (USD)"])
    }

    // MARK: Only what changed is applied

    @Test func theSameRowAgainIsUnchangedAndLeavesAResolvedInvoiceAlone() throws {
        // Paid without a date: held for review at the first import.
        let row = try FakturoidCSV.parsed(Self.crownRow.merging(["Paid on": ""]) { $1 })
        let first = applied(plan(rows: [row]))
        var resolved = try #require(first.invoices.first)
        #expect(resolved.review == ReviewFlag(reason: "zaplaceno bez data platby"))
        // The person entered the payment in the app, which took the flag away.
        resolved.review = nil
        resolved.payment = Payment.fixture(on: "2026-09-10", net: 504_000, vat: 105_840)
        resolved.source = .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: true)

        let plan = plan(rows: [row], existing: [resolved], clients: first.clients)

        #expect(plan.unchangedNumbers == ["20260902"])
        #expect(plan.updates.isEmpty && plan.inserts.isEmpty && plan.reviewItems.isEmpty && plan.invoiceCount == 0)
    }

    @Test func theSameIsdocAgainIsUnchanged() throws {
        let file = try isdoc("czk-21")
        let row = try FakturoidCSV.parsed(Self.crownRow)
        let fromIsdoc = applied(plan(isdocs: [file]))
        let fromBoth = applied(plan(rows: [row], isdocs: [file]))

        let again = plan(isdocs: [file], existing: fromIsdoc.invoices, clients: fromIsdoc.clients)
        let bothAgain = plan(rows: [row], isdocs: [file], existing: fromBoth.invoices, clients: fromBoth.clients)
        let changed = plan(
            isdocs: [copy(of: file, note: "Nová poznámka.")], existing: fromIsdoc.invoices,
            clients: fromIsdoc.clients)

        for plan in [again, bothAgain] {
            #expect(plan.unchangedNumbers == ["20260902"])
            #expect(plan.invoiceCount == 0 && plan.notes.isEmpty)
            #expect(plan.newClients.isEmpty && plan.clientUpdates.isEmpty)
        }
        #expect(changed.overwrittenNumbers == ["20260902"] && changed.updates.first?.note == "Nová poznámka.")
    }

    @Test func aBankCreditedAmountSurvivesACsvThatAgreesOnThePaymentDate() throws {
        let row = try FakturoidCSV.parsed(Self.dollarRow)
        let file = try isdoc("usd-0")
        let first = applied(plan(rows: [row], isdocs: [file], payments: [row.fingerprint: try payment(of: row)]))
        var paid = try #require(first.invoices.first)
        // The person entered the crowns the bank credited.
        paid.payment = Payment.fixture(
            on: "2026-09-21", conversion: .bankCZK, net: 30_900_000, vat: 0, bankCZKTotalHalere: 30_900_000)
        paid.source = .imported(fakturoidID: "7002", fingerprint: row.fingerprint, changedInApp: true)
        // Fakturoid has a new e-mail of the client, and the same day of the payment; or the payment on another day.
        let sameDay = try FakturoidCSV.parsed(
            Self.dollarRow.merging(["Client email": "billing@harborlight.example"]) { $1 })
        let otherDay = try FakturoidCSV.parsed(Self.dollarRow.merging(["Paid on": "2026-09-24"]) { $1 })
        let otherConverted = try payment(of: otherDay)

        let kept = plan(
            rows: [sameDay], existing: [paid], clients: first.clients,
            payments: [sameDay.fingerprint: try payment(of: sameDay)])
        let moved = plan(
            rows: [otherDay], existing: [paid], clients: first.clients,
            payments: [otherDay.fingerprint: otherConverted])

        #expect(kept.updates.first?.payment == paid.payment)
        #expect(kept.updates.first?.client.email == "billing@harborlight.example")
        #expect(moved.updates.first?.payment == otherConverted)
    }

    // MARK: Skipped and not added

    @Test func aCancelledRowSkipsTheIsdocOfItsInvoice() throws {
        let row = try FakturoidCSV.parsed(
            Self.crownRow.merging(["Status": "cancelled", "Cancelled at": "2026-09-20 09:00:00", "Paid on": ""]) {
                $1
            })
        let file = try isdoc("czk-21")
        let open = try FakturoidCSV.parsed(Self.crownRow.merging(["Status": "open", "Paid on": ""]) { $1 })
        let stored = applied(plan(rows: [open]))

        let alone = plan(rows: [row], isdocs: [file])
        let overStored = plan(rows: [row], isdocs: [file], existing: stored.invoices, clients: stored.clients)

        #expect(alone.skipped == ["20260902 — zrušeno ve Fakturoidu"] && alone.skippedNumbers == ["20260902"])
        #expect(alone.inserts.isEmpty && alone.newClients.isEmpty && alone.conflicts.isEmpty)
        let flagged = try #require(overStored.flaggedCancelled.first)
        #expect(flagged.review == ReviewFlag(reason: "zrušeno ve Fakturoidu"))
        #expect(flagged.items == stored.invoices[0].items && flagged.isdocFingerprint == nil)
        #expect(overStored.overwrittenNumbers == ["20260902"] && overStored.updates.isEmpty)
        #expect(overStored.skipped.isEmpty && overStored.inserts.isEmpty)
    }

    @Test func anIsdocProformaOrOtherDocumentTypeIsSkipped() throws {
        let proforma = try isdoc("proforma")
        let otherKind = copy(of: try isdoc("czk-21"), documentType: 2, number: "20260903")

        let plan = plan(isdocs: [proforma, otherKind])

        #expect(plan.skipped == ["20260902 — zálohová faktura", "20260903 — jiný typ dokladu (2)"])
        #expect(plan.skippedNumbers == ["20260902", "20260903"])
        #expect(plan.inserts.isEmpty && plan.conflicts.isEmpty && plan.newClients.isEmpty)
    }

    @Test func anInvoiceInBothExportsIsCountedOnceWhenOneOfThemIsSkipped() throws {
        let proformaRow = try FakturoidCSV.parsed(Self.crownRow.merging(["Proforma": "true"]) { $1 })
        let creditRow = try FakturoidCSV.parsed(
            Self.crownRow.merging([
                "Subtotal": "-5040,0", "Total": "-6098,4", "Vat": "-1058.4", "Status": "open", "Paid on": "",
            ]) { $1 })
        let file = try isdoc("czk-21")
        let creditNote = copy(of: file, documentType: 2)

        let proformas = plan(rows: [proformaRow], isdocs: [try isdoc("proforma")])
        let credit = plan(rows: [creditRow], isdocs: [creditNote])
        let creditFirst = plan(isdocs: [creditNote, file])

        // A proforma in the CSV and in the ISDOC is one invoice skipped once.
        #expect(proformas.skippedNumbers == ["20260902"] && proformas.skipped == ["20260902 — zálohová faktura"])
        #expect(ImportSummary(plan: proformas, files: [], exportSupplier: nil).skipped == 1)
        // A credit note the CSV adds for review is not also skipped for its ISDOC, whichever comes first.
        for plan in [credit, creditFirst] {
            #expect(plan.newNumbers == ["20260902"] && plan.skippedNumbers.isEmpty && plan.skipped.isEmpty)
        }
        #expect(credit.inserts.first?.review == ReviewFlag(reason: "záporná částka"))
        // Another number, or the same digits in another currency, is another invoice.
        let otherNumber = copy(of: file, documentType: 2, number: "20260903")
        let dollarProforma = try FakturoidCSV.parsed(
            Self.dollarRow.merging(["Number": "20260902", "Proforma": "true"]) { $1 })
        let twoNumbers = plan(rows: [proformaRow], isdocs: [otherNumber])
        let twoCurrencies = plan(rows: [dollarProforma], isdocs: [try isdoc("proforma")])
        #expect(twoNumbers.skippedNumbers == ["20260902", "20260903"])
        #expect(twoCurrencies.skippedNumbers == ["20260902", "20260902"])
        // A proforma invoice is a document of its own: it stays skipped beside the invoice with the same digits.
        let ownProforma = try FakturoidCSV.parsed(
            Self.crownRow.merging(["Id": "7000", "Number": "Z20260902", "Proforma": "true"]) { $1 })
        let besideItsInvoice = plan(rows: [ownProforma], isdocs: [file, try isdoc("proforma")])
        #expect(besideItsInvoice.newNumbers == ["20260902"] && besideItsInvoice.skippedNumbers == ["Z20260902"])
    }

    @Test func twoIdenticalIsdocFilesAreOneInvoice() throws {
        let file = try isdoc("czk-21")
        let other = copy(of: file, note: "Druhé znění poznámky.")

        let identical = plan(isdocs: [file, try isdoc("czk-21")])
        let differing = plan(isdocs: [file, other])

        #expect(identical.inserts.count == 1 && identical.inserts.first?.review == nil)
        #expect(identical.conflicts.isEmpty && identical.reviewItems.isEmpty && identical.newNumbers == ["20260902"])
        // Two files of one invoice that differ are held like rows that differ: the first one gives the content, and
        // the invoice is stored under the fingerprint of both files.
        let both = ImportPlanner.fingerprint(ofAll: [file.fingerprint, other.fingerprint])
        let held = try #require(differing.inserts.first)
        #expect(differing.inserts.count == 1 && held.note == file.note && held.payment == nil)
        #expect(held.review == ReviewFlag(reason: "v importu vícekrát s různým obsahem"))
        #expect(held.isdocFingerprint == both)
        #expect(differing.reviewItems == ["20260902 — v importu vícekrát s různým obsahem — ke kontrole"])
        // An invoice that is there keeps what it holds, and is held.
        let stored = applied(identical)
        let overStored = plan(isdocs: [file, other], existing: stored.invoices, clients: stored.clients)
        var expected = stored.invoices[0]
        expected.review = ReviewFlag(reason: "v importu vícekrát s různým obsahem")
        expected.isdocFingerprint = both
        #expect(overStored.updates == [expected])
        // Once the person has resolved it, the same two files, in either order, leave it alone.
        var resolved = expected
        resolved.review = nil
        let again = plan(isdocs: [other, file], existing: [resolved], clients: stored.clients)
        #expect(again.unchangedNumbers == ["20260902"] && again.updates.isEmpty && again.reviewItems.isEmpty)
    }

    /// `invoice` as the person leaves it once they have resolved it in the app: without its review flag, and marked as
    /// changed there.
    private func resolvedInApp(_ invoice: Invoice) -> Invoice {
        var resolved = invoice
        resolved.review = nil
        if case .imported(let id, let fingerprint, _) = invoice.source {
            resolved.source = .imported(fakturoidID: id, fingerprint: fingerprint, changedInApp: true)
        }
        return resolved
    }

    @Test func anInvoiceHeldForItsRowsTakesTheIsdocThatCameWithThemFromTheNextCleanImport() throws {
        let row = try FakturoidCSV.parsed(Self.crownRow)
        let other = try FakturoidCSV.parsed(Self.crownRow.merging(["Due on": "2026-09-30"]) { $1 })
        let file = try isdoc("czk-21")
        let payments = [row.fingerprint: try payment(of: row)]
        let fromCsv = applied(plan(rows: [row], payments: payments))
        let stored = try #require(fromCsv.invoices.first)

        let held = try #require(
            plan(rows: [row, other], isdocs: [file], existing: fromCsv.invoices, clients: fromCsv.clients)
                .updates.first)

        // Neither the rows nor the ISDOC file are applied, and the invoice is not stored as having taken the file.
        #expect(held.review == ReviewFlag(reason: "v importu vícekrát s různým obsahem"))
        #expect(held.items == stored.items && held.isdocFingerprint != file.fingerprint)
        let resolved = resolvedInApp(held)
        let same = plan(rows: [other, row], isdocs: [file], existing: [resolved], clients: fromCsv.clients)
        let clean = plan(
            rows: [row], isdocs: [file], existing: [resolved], clients: fromCsv.clients, payments: payments)
        // The same files again leave the resolved invoice alone.
        #expect(same.unchangedNumbers == ["20260902"] && same.invoiceCount == 0 && same.reviewItems.isEmpty)
        // A clean import applies both: the lines of the ISDOC, and the state and the payment of the row.
        let updated = try #require(clean.updates.first)
        #expect(clean.overwrittenNumbers == ["20260902"] && clean.reviewItems.isEmpty)
        #expect(updated.items == IsdocInvoiceBuilder.items(of: file).items && updated.note == file.note)
        #expect(updated.isdocFingerprint == file.fingerprint)
        #expect(updated.review == nil && updated.status == .issued && updated.payment == payments[row.fingerprint])
        #expect(
            updated.source == .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: false))
    }

    @Test func anInvoiceHeldForItsIsdocFilesTakesTheRowThatCameWithThemFromTheNextCleanImport() throws {
        let row = try FakturoidCSV.parsed(Self.crownRow)
        let open = try FakturoidCSV.parsed(Self.crownRow.merging(["Status": "open", "Paid on": ""]) { $1 })
        let file = try isdoc("czk-21")
        let other = copy(of: file, note: "Druhé znění poznámky.")
        let payments = [row.fingerprint: try payment(of: row)]
        // A new invoice held for its files, and one the app had from an open row, held for its files with the row
        // that says it is paid now.
        let added = applied(plan(rows: [row], isdocs: [file, other], payments: payments))
        let fromOpen = applied(plan(rows: [open]))
        let heldThere = try #require(
            plan(
                rows: [row], isdocs: [file, other], existing: fromOpen.invoices, clients: fromOpen.clients,
                payments: payments
            ).updates.first)
        let heldNew = try #require(added.invoices.first)

        for held in [heldNew, heldThere] {
            #expect(held.review == ReviewFlag(reason: "v importu vícekrát s různým obsahem") && held.payment == nil)
        }
        let cases = [
            (heldNew, added.clients), (resolvedInApp(heldNew), added.clients), (heldThere, fromOpen.clients),
            (resolvedInApp(heldThere), fromOpen.clients),
        ]
        for (stored, clients) in cases {
            let same = plan(
                rows: [row], isdocs: [other, file], existing: [stored], clients: clients, payments: payments)
            let clean = plan(rows: [row], isdocs: [file], existing: [stored], clients: clients, payments: payments)
            // The same files again leave the invoice alone, resolved or not.
            #expect(same.unchangedNumbers == ["20260902"] && same.invoiceCount == 0)
            // A clean import applies both: the payment and the state of the row, and the lines of the ISDOC.
            let updated = try #require(clean.updates.first)
            #expect(updated.review == nil && updated.payment == payments[row.fingerprint])
            #expect(clean.reviewItems.isEmpty)
            #expect(updated.items == IsdocInvoiceBuilder.items(of: file).items && updated.note == file.note)
            #expect(updated.isdocFingerprint == file.fingerprint)
            #expect(
                updated.source == .imported(fakturoidID: "7001", fingerprint: row.fingerprint, changedInApp: false))
        }
    }

    @Test func mixedVatIsNotAddedWithItsReason() throws {
        let plan = plan(isdocs: [try isdoc("mixed-vat")])

        #expect(plan.conflicts == ["20260902 — sazba DPH, kterou aplikace nemá — nepřidáno"])
        #expect(plan.notAdded == [ImportNotAddedItem(number: "20260902", reason: "sazba DPH, kterou aplikace nemá")])
        #expect(plan.inserts.isEmpty && plan.newClients.isEmpty && plan.reviewItems.isEmpty)
    }

    @Test func anIsdocThatCannotBeAddedSaysWhy() throws {
        let crowns = try isdoc("czk-21")
        let dollars = try isdoc("usd-0")
        var euros = Invoice.fixture(number: "20260902", currency: .eur, vatMode: VatMode.none)
        euros.id = 3

        let alone = plan(isdocs: [
            copy(of: crowns, number: "ABC"), copy(of: crowns, number: "20260903", withoutIssueDate: true),
            copy(of: dollars, withoutRate: true),
        ])
        let overEuros = plan(isdocs: [crowns], existing: [euros])

        #expect(
            alone.notAdded == [
                ImportNotAddedItem(number: "ABC", reason: "číslo bez číslic"),
                ImportNotAddedItem(number: "20260903", reason: "chybí datum vystavení"),
                ImportNotAddedItem(number: "20260901", reason: "chybí kurz faktury"),
            ])
        #expect(alone.conflicts.first == "ABC — číslo bez číslic — nepřidáno")
        #expect(alone.inserts.isEmpty && alone.reviewItems.isEmpty)
        #expect(
            overEuros.notAdded == [
                ImportNotAddedItem(number: "20260902", reason: "číslo už používá faktura v jiné měně")
            ])
        #expect(overEuros.updates.isEmpty && overEuros.inserts.isEmpty)
    }

    @Test func aForeignIsdocWithoutARateKeepsTheRateOfTheStoredInvoice() throws {
        let row = try FakturoidCSV.parsed(Self.dollarRow.merging(["Exchange rate": "21.3"]) { $1 })
        let first = applied(plan(rows: [row]))
        let stored = try #require(first.invoices.first)

        let plan = plan(
            isdocs: [copy(of: try isdoc("usd-0"), withoutRate: true)], existing: first.invoices,
            clients: first.clients)

        let updated = try #require(plan.updates.first)
        #expect(updated.invoiceRate == stored.invoiceRate && updated.invoiceRate != nil)
        #expect(updated.netMinor == 1_435_600 && plan.notAdded.isEmpty)
    }

    // MARK: Review and outcomes

    /// The thirteen conditions that hold an invoice of the CSV for review, each with the rows that meet it and, for
    /// a cancellation, the row of the invoice that is there.
    enum ReviewCondition: CaseIterable, Sendable {
        case numberWithoutDigits
        case unreadableSubtotal
        case negativeSubtotal
        case unreadableVAT
        case vatUnderTenPercent
        case paymentDateWhileUnpaid
        case paidWithoutDate
        case unknownStatus
        case noCurrency
        case currencyWithoutRates
        case paidForeignWithoutRate
        case differingRows
        case cancelledInFakturoid

        /// The reason the invoice is held for.
        var reason: String {
            switch self {
            case .numberWithoutDigits: "číslo bez číslic"
            case .unreadableSubtotal: "neplatná nebo příliš velká částka"
            case .negativeSubtotal: "záporná částka"
            case .unreadableVAT: "neplatná nebo příliš velká DPH"
            case .vatUnderTenPercent: "neznámá sazba DPH"
            case .paymentDateWhileUnpaid: "datum platby u nezaplacené faktury"
            case .paidWithoutDate: "zaplaceno bez data platby"
            case .unknownStatus: "neznámý stav faktury"
            case .noCurrency: "chybí měna"
            case .currencyWithoutRates: "měna XYZ bez kurzů ČNB"
            case .paidForeignWithoutRate: "chybí kurz faktury"
            case .differingRows: "v importu vícekrát s různým obsahem"
            case .cancelledInFakturoid: "zrušeno ve Fakturoidu"
            }
        }

        /// The changes of the rows of the import from `FakturoidCSV.row`.
        var rows: [FakturoidCSV.Row] {
            switch self {
            case .numberWithoutDigits: [["Number": "ABC"]]
            case .unreadableSubtotal: [["Subtotal": "10000000000,0"]]
            case .negativeSubtotal: [["Subtotal": "-4500,0", "Total": "-5445,0", "Vat": "-945.0"]]
            case .unreadableVAT: [["Vat": "abc"]]
            case .vatUnderTenPercent: [["Subtotal": "5000,0", "Vat": "499.0"]]
            case .paymentDateWhileUnpaid: [["Status": "open", "Paid on": "2026-10-15"]]
            case .paidWithoutDate: [["Status": "paid"]]
            case .unknownStatus: [["Status": ""]]
            case .noCurrency: [["Currency": ""]]
            case .currencyWithoutRates: [["Currency": "XYZ", "Vat": "0.0", "Client country": "US"]]
            case .paidForeignWithoutRate:
                [
                    [
                        "Currency": "USD", "Exchange rate": "", "Vat": "0.0", "Client country": "US",
                        "Status": "paid", "Paid on": "2026-10-15",
                    ]
                ]
            case .differingRows: [[:], ["Subtotal": "4600,0", "Total": "5566,0", "Vat": "966.0"]]
            case .cancelledInFakturoid: [["Status": "cancelled", "Cancelled at": "2026-10-16 09:00:00"]]
            }
        }

        /// The changes of the row an invoice that is there was imported from, if there is one.
        var storedRow: FakturoidCSV.Row? {
            self == .cancelledInFakturoid ? [:] : nil
        }
    }

    @Test(arguments: ReviewCondition.allCases)
    func theThirteenReviewConditionsStillFlag(condition: ReviewCondition) throws {
        let rows = try FakturoidCSV.rows(condition.rows.map { FakturoidCSV.row($0) })
        var existing: [Invoice] = []
        if let storedRow = condition.storedRow {
            var stored = try #require(
                ImportPlanner.invoice(from: try FakturoidCSV.parsed(storedRow), knownCurrencies: Self.known))
            stored.id = 1
            existing = [stored]
        }

        let plan = plan(rows: rows, existing: existing)

        let flags = (plan.inserts + plan.updates + plan.flaggedCancelled).map(\.review)
        #expect(flags == [ReviewFlag(reason: condition.reason)])
        #expect(plan.reviewItems.count == 1 && plan.reviewItems.first?.contains(condition.reason) == true)
        #expect(ReviewCondition.allCases.count == 13)
    }

    @Test func thePlanNamesItsNumbersPerOutcome() throws {
        let stored = applied(
            plan(
                rows: try FakturoidCSV.rows([
                    FakturoidCSV.row(["Id": "1", "Number": "20261001"]),
                    FakturoidCSV.row(["Id": "2", "Number": "20261002"]),
                    FakturoidCSV.row(["Id": "3", "Number": "20261003"]),
                ])))
        let rows = try FakturoidCSV.rows([
            // The same as stored, changed, and cancelled in Fakturoid.
            FakturoidCSV.row(["Id": "1", "Number": "20261001"]),
            FakturoidCSV.row(["Id": "2", "Number": "20261002", "Due on": "2026-10-30"]),
            FakturoidCSV.row(["Id": "3", "Number": "20261003", "Status": "cancelled"]),
            // New, a proforma, and cancelled without an invoice in the app.
            FakturoidCSV.row(["Id": "4", "Number": "20261004"]),
            FakturoidCSV.row(["Id": "5", "Number": "Z20261005", "Proforma": "true"]),
            FakturoidCSV.row(["Id": "6", "Number": "20261006", "Status": "cancelled"]),
        ])
        let mixed = copy(of: try isdoc("mixed-vat"), number: "20261007")
        let withoutDigits = copy(of: try isdoc("czk-21"), number: "ABC")

        let plan = plan(
            rows: rows, isdocs: [try isdoc("czk-21"), mixed, withoutDigits], existing: stored.invoices,
            clients: stored.clients)

        #expect(plan.newNumbers == ["20261004", "20260902"])
        #expect(plan.overwrittenNumbers == ["20261002", "20261003"])
        #expect(plan.unchangedNumbers == ["20261001"])
        #expect(plan.skippedNumbers == ["Z20261005", "20261006"])
        #expect(
            plan.notAdded == [
                ImportNotAddedItem(number: "20261007", reason: "sazba DPH, kterou aplikace nemá"),
                ImportNotAddedItem(number: "ABC", reason: "číslo bez číslic"),
            ])
        #expect(plan.invoiceCount == 4)
        #expect(plan.inserts.count == 2 && plan.updates.count == 1 && plan.flaggedCancelled.count == 1)
    }
}
