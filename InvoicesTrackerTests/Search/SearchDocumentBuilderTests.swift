import Testing
@testable import InvoicesTracker

/// The fields of an invoice that the search covers, and the document made of them. The invoices are invented.
struct SearchDocumentBuilderTests {
    private let nb = "\u{00A0}"

    private func field(_ label: String, _ text: String, _ shownInTable: Bool = false) -> SearchField {
        SearchField(label: label, text: text, shownInTable: shownInTable)
    }

    /// The texts of the fields with `label`, in the order of the fields.
    private func texts(_ label: String, of invoice: Invoice) -> [String] {
        SearchDocumentBuilder.fields(for: invoice).filter { $0.label == label }.map(\.text)
    }

    private func labels(of invoice: Invoice) -> [String] {
        SearchDocumentBuilder.fields(for: invoice).map(\.label)
    }

    // MARK: The fields

    @Test func aPaidCrownInvoiceHasEveryFieldOfTheSearchWithItsTableFlag() {
        let fields = SearchDocumentBuilder.fields(for: SearchFixtures.crownInvoice())

        #expect(
            fields == [
                field("Číslo", "20260901", true),
                field("Odběratel", "Alfa Systems s.r.o.", true),
                field("Adresa", "Hlavní 1, 261 01 Příbram, Česko"),
                field("IČO", "12345678"),
                field("DIČ", "CZ12345678"),
                field("E-mail", "ucetni@example.com"),
                field("Položka", "Vývoj"),
                field("Množství", "7,5 hod"),
                field("Cena za jednotku", "600,00\(nb)Kč"),
                field("Cena za jednotku", "600,00"),
                field("Cena za jednotku", "600.00"),
                field("Bez DPH", "4\(nb)500,00\(nb)Kč", true),
                field("Bez DPH", "4500,00", true),
                field("Bez DPH", "4500.00", true),
                field("DPH", "945,00\(nb)Kč"),
                field("DPH", "945,00"),
                field("DPH", "945.00"),
                field("S DPH", "5\(nb)445,00\(nb)Kč"),
                field("S DPH", "5445,00"),
                field("S DPH", "5445.00"),
                field("Měna", "CZK", true),
                field("Režim DPH", VatMode.domestic21.label),
                field("Vystaveno", "30.\(nb)9.\(nb)2026", true),
                field("Vystaveno", "30.9.2026", true),
                field("Vystaveno", "30.09.2026", true),
                field("Vystaveno", "2026-09-30", true),
                field("DUZP", "30.\(nb)9.\(nb)2026"),
                field("DUZP", "30.9.2026"),
                field("DUZP", "30.09.2026"),
                field("DUZP", "2026-09-30"),
                field("Splatnost", "14.\(nb)10.\(nb)2026"),
                field("Splatnost", "14.10.2026"),
                field("Splatnost", "2026-10-14"),
                field("Měsíc DUZP", "září 2026"),
                field("Způsob platby", "Převodem"),
                field("Zaplaceno", "15.\(nb)10.\(nb)2026", true),
                field("Zaplaceno", "15.10.2026", true),
                field("Zaplaceno", "2026-10-15", true),
                field("Stav", "Vystavená, uhrazená", true),
            ]
        )
    }

    @Test func aPaidDollarInvoiceAddsItsCrownValueItsRatesAndItsNote() {
        let fields = SearchDocumentBuilder.fields(for: SearchFixtures.dollarInvoice())

        #expect(
            fields == [
                field("Číslo", "20260902", true),
                field("Odběratel", "Bravo Labs, Inc.", true),
                field("Adresa", "100 Congress Avenue, 78701 Austin, TX, Spojené státy americké"),
                field("E-mail", "billing@example.org"),
                field("Položka", "Software development"),
                field("Množství", "205 hod"),
                field("Cena za jednotku", "70,00\(nb)USD"),
                field("Cena za jednotku", "70,00"),
                field("Cena za jednotku", "70.00"),
                field("Bez DPH", "14\(nb)350,00\(nb)USD", true),
                field("Bez DPH", "14350,00", true),
                field("Bez DPH", "14350.00", true),
                field("Měna", "USD", true),
                field("Režim DPH", VatMode.outsideCountry.label),
                field("Vystaveno", "30.\(nb)9.\(nb)2026", true),
                field("Vystaveno", "30.9.2026", true),
                field("Vystaveno", "30.09.2026", true),
                field("Vystaveno", "2026-09-30", true),
                field("DUZP", "30.\(nb)9.\(nb)2026"),
                field("DUZP", "30.9.2026"),
                field("DUZP", "30.09.2026"),
                field("DUZP", "2026-09-30"),
                field("Splatnost", "30.\(nb)10.\(nb)2026"),
                field("Splatnost", "30.10.2026"),
                field("Splatnost", "2026-10-30"),
                field("Měsíc DUZP", "září 2026"),
                field("Způsob platby", "ACH transfer"),
                field("V Kč", "305\(nb)726,75\(nb)Kč", true),
                field("V Kč", "305726,75", true),
                field("V Kč", "305726.75", true),
                field("Kurz k DUZP", "21,359"),
                field("Zaplaceno", "2.\(nb)10.\(nb)2026", true),
                field("Zaplaceno", "2.10.2026", true),
                field("Zaplaceno", "02.10.2026", true),
                field("Zaplaceno", "2026-10-02", true),
                field("Kurz platby", "21,305"),
                field("Stav", "Vystavená, uhrazená", true),
                field("Poznámka", "Routing number: [ROUTING NUMBER]"),
            ]
        )
    }

    // MARK: Amounts

    @Test func everyAmountHasThreeSpellings() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.items = [
            InvoiceItem(description: "Konzultace", quantity: decimal("1"), unit: "ks", unitPriceMinor: 123_456_789)
        ]

        #expect(
            texts("Cena za jednotku", of: invoice) == ["1\(nb)234\(nb)567,89\(nb)Kč", "1234567,89", "1234567.89"])
        invoice.items[0].unitPriceMinor = 5
        #expect(texts("Cena za jednotku", of: invoice) == ["0,05\(nb)Kč", "0,05", "0.05"])
    }

    @Test func aNegativeAmountKeepsTheMinusSignOfTheScreenAndAlsoHasTheTypedOne() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.items = [
            InvoiceItem(description: "Sleva", quantity: decimal("-1"), unit: "ks", unitPriceMinor: 125_000)
        ]
        invoice.vatMode = .none

        #expect(texts("Bez DPH", of: invoice) == ["\u{2212}1\(nb)250,00\(nb)Kč", "-1250,00", "-1250.00"])
        #expect(texts("Množství", of: invoice) == ["-1 ks"])
    }

    @Test func anInvoiceWithoutVatHasNoVatAndNoTotalWithVat() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.vatMode = .none

        #expect(!labels(of: invoice).contains("DPH") && !labels(of: invoice).contains("S DPH"))
        #expect(texts("Bez DPH", of: invoice).first == "4\(nb)500,00\(nb)Kč")
        #expect(texts("Režim DPH", of: invoice) == [VatMode.none.label])
    }

    @Test func theVatAndTheTotalAreThoseOfTheInvoiceAtTheRateOfItsMode() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.vatMode = .domestic12

        #expect(texts("DPH", of: invoice) == ["540,00\(nb)Kč", "540,00", "540.00"])
        #expect(texts("S DPH", of: invoice) == ["5\(nb)040,00\(nb)Kč", "5040,00", "5040.00"])
    }

    /// The table has no column with the total with VAT (it shows the net income in its place), so a match on it is
    /// explained under the client, as a match on the VAT is. The total without VAT is a column still.
    @Test func theTotalWithVatIsNotInTheTable() {
        let fields = SearchDocumentBuilder.fields(for: SearchFixtures.crownInvoice())
        let withVat = fields.filter { $0.label == "S DPH" }

        #expect(withVat.map(\.text) == ["5\(nb)445,00\(nb)Kč", "5445,00", "5445.00"])
        #expect(withVat.allSatisfy { !$0.shownInTable })
        #expect(fields.filter { $0.label == "Bez DPH" }.allSatisfy { $0.shownInTable })
    }

    // MARK: The value in crowns

    @Test func aForeignInvoiceThatIsNotPaidIsWorthItsNetAtTheRateFixedOnIt() {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.payment = nil

        // 14 350,00 USD at 21,359
        #expect(texts("V Kč", of: invoice) == ["306\(nb)501,65\(nb)Kč", "306501,65", "306501.65"])
        #expect(texts("Kurz k DUZP", of: invoice) == ["21,359"])
        #expect(texts("Zaplaceno", of: invoice).isEmpty && texts("Kurz platby", of: invoice).isEmpty)
        #expect(texts("Stav", of: invoice) == ["Vystavená"])
    }

    @Test func aPaidForeignInvoiceIsWorthWhatWasPaidNotWhatTheInvoiceRateSays() {
        let value = texts("V Kč", of: SearchFixtures.dollarInvoice())

        #expect(value.first == "305\(nb)726,75\(nb)Kč")
    }

    @Test func aForeignInvoiceWithNeitherARateNorAPaymentHasNoValueInCrowns() {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.payment = nil
        invoice.invoiceRate = nil

        #expect(!labels(of: invoice).contains("V Kč") && !labels(of: invoice).contains("Kurz k DUZP"))
    }

    @Test func aPaymentWithoutARateHasNoPaymentRateAndAnInvoiceInCrownsHasNoValueInCrowns() {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.payment?.rate = nil
        #expect(!labels(of: invoice).contains("Kurz platby"))

        #expect(!labels(of: SearchFixtures.crownInvoice()).contains("V Kč"))
    }

    // MARK: Items

    @Test func everyItemAddsItsDescriptionItsQuantityWithUnitAndItsPrice() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.items = [
            InvoiceItem(description: "Vývoj – září", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000),
            InvoiceItem(description: "Hosting", quantity: decimal("1"), unit: "měs", unitPriceMinor: 12_550),
        ]

        #expect(texts("Položka", of: invoice) == ["Vývoj – září", "Hosting"])
        #expect(texts("Množství", of: invoice) == ["7,5 hod", "1 měs"])
        #expect(texts("Cena za jednotku", of: invoice).count == 6)
        #expect(texts("Cena za jednotku", of: invoice)[3...] == ["125,50\(nb)Kč", "125,50", "125.50"])
        // 450 000 + 12 550
        #expect(texts("Bez DPH", of: invoice).last == "4625.50")
    }

    @Test func aQuantityWithoutAUnitAndAnItemWithoutADescriptionAreWrittenWithoutGaps() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.items = [InvoiceItem(description: "", quantity: decimal("2.25"), unit: "", unitPriceMinor: 100)]

        #expect(texts("Množství", of: invoice) == ["2,25"])
        #expect(texts("Položka", of: invoice).isEmpty)
    }

    // MARK: Dates

    @Test func aDayWithOneDigitIsWrittenWithAndWithoutTheLeadingZeros() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.issueDate = civilDate("2026-01-05")

        #expect(texts("Vystaveno", of: invoice) == ["5.\(nb)1.\(nb)2026", "5.1.2026", "05.01.2026", "2026-01-05"])
    }

    @Test func aDayWithTwoDigitsInAMonthWithTwoDigitsHasNoSpellingTwice() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.issueDate = civilDate("2026-11-21")

        #expect(texts("Vystaveno", of: invoice) == ["21.\(nb)11.\(nb)2026", "21.11.2026", "2026-11-21"])
    }

    @Test func theMonthOfTheSupplyIsNamedWithItsYear() {
        var invoice = SearchFixtures.crownInvoice()
        let months = [("2026-01-31", "leden 2026"), ("2026-12-01", "prosinec 2026"), ("2025-03-15", "březen 2025")]
        for (day, expected) in months {
            invoice.duzp = civilDate(day)
            #expect(texts("Měsíc DUZP", of: invoice) == [expected], "\(day)")
        }
    }

    // MARK: Number, client and address

    @Test func theNumberIsFollowedByItsDigitsWhenTheyAreNotTheNumber() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.number = "2026-09-01"

        #expect(texts("Číslo", of: invoice) == ["2026-09-01", "20260901"])
        #expect(SearchDocumentBuilder.fields(for: invoice).prefix(2).allSatisfy { $0.shownInTable })
    }

    @Test func theAddressLeavesOutWhatTheClientDoesNotHave() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.client.street = ""
        #expect(texts("Adresa", of: invoice) == ["261 01 Příbram, Česko"])

        invoice.client.postcode = ""
        #expect(texts("Adresa", of: invoice) == ["Příbram, Česko"])

        invoice.client.city = ""
        #expect(texts("Adresa", of: invoice) == ["Česko"])

        invoice.client.country = ""
        #expect(texts("Adresa", of: invoice).isEmpty)
    }

    @Test func theCountryIsNamedInCzechAsEverywhereElseAndAnUnknownCodeIsKeptAsItIs() {
        var invoice = SearchFixtures.crownInvoice()
        for (code, name) in [
            ("SK", "Slovensko"), ("DE", "Německo"), ("US", "Spojené státy americké"), ("JP", "Japonsko"), ("ZZ", "ZZ"),
            ("XX", "XX"),
        ] {
            invoice.client.country = code
            #expect(texts("Adresa", of: invoice) == ["Hlavní 1, 261 01 Příbram, \(name)"], "\(code)")
        }
    }

    @Test func theTaxNumbersAndTheEmailOfAClientWithoutThemAreLeftOut() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.client.ico = ""
        invoice.client.dic = ""
        invoice.client.email = ""

        #expect(!labels(of: invoice).contains("IČO") && !labels(of: invoice).contains("DIČ"))
        #expect(!labels(of: invoice).contains("E-mail"))
    }

    // MARK: Status, note and source

    @Test func theStatusWordsDoNotDependOnTheDay() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.payment = nil
        #expect(texts("Stav", of: invoice) == ["Vystavená"])

        invoice.payment = .fixture(on: "2026-10-15")
        #expect(texts("Stav", of: invoice) == ["Vystavená, uhrazená"])

        invoice.review = ReviewFlag(reason: "Částka nesedí")
        #expect(texts("Stav", of: invoice) == ["Vystavená, uhrazená, ke kontrole"])

        invoice.payment = nil
        #expect(texts("Stav", of: invoice) == ["Vystavená, ke kontrole"])

        invoice.status = .draft
        invoice.review = nil
        #expect(texts("Stav", of: invoice) == ["Koncept"])
    }

    @Test func theStatusIsInTheTableAndTheNoteAndTheSourceAreNot() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.note = "Děkujeme"
        invoice.source = .imported(fakturoidID: "F-1", fingerprint: "abc", changedInApp: false)
        let fields = SearchDocumentBuilder.fields(for: invoice)

        #expect(fields.first { $0.label == "Stav" }?.shownInTable == true)
        #expect(fields.first { $0.label == "Poznámka" } == field("Poznámka", "Děkujeme"))
        #expect(fields.first { $0.label == "Zdroj" } == field("Zdroj", "import z Fakturoidu"))
        #expect(fields.last == field("Zdroj", "import z Fakturoidu"))
    }

    @Test func anInvoiceMadeInTheAppHasNoSourceAndAnEmptyNoteIsLeftOut() {
        let invoice = SearchFixtures.crownInvoice()

        #expect(!labels(of: invoice).contains("Zdroj") && !labels(of: invoice).contains("Poznámka"))
    }

    @Test func aNoteOfOnlyWhitespaceIsLeftOut() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.note = " \n\t\(nb) "

        #expect(!labels(of: invoice).contains("Poznámka"))
    }

    // MARK: The document

    @Test func theDocumentIsTheFoldedFieldsJoinedWithABar() {
        for invoice in [SearchFixtures.crownInvoice(), SearchFixtures.dollarInvoice()] {
            let fields = SearchDocumentBuilder.fields(for: invoice)

            let document = SearchDocumentBuilder.document(for: invoice)

            #expect(document == fields.map { SearchFolding.fold($0.text) }.joined(separator: " | "))
            #expect(SearchFolding.fold(document) == document)
            #expect(!document.contains(nb))
        }
    }

    @Test func aTextThatFoldsToNothingLeavesNoGapInTheDocument() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.note = "\u{0000}"

        let document = SearchDocumentBuilder.document(for: invoice)

        #expect(document == SearchDocumentBuilder.document(for: SearchFixtures.crownInvoice()))
        #expect(!document.contains(" |  | ") && !document.hasSuffix(" | "))
    }

    @Test func theDocumentHasEverySpellingThatTheSearchIsToFind() {
        let document = SearchDocumentBuilder.document(for: SearchFixtures.dollarInvoice())

        let spellings = [
            "bravo labs, inc.", "100 congress avenue, 78701 austin, tx, spojene staty", "billing@example.org",
            "software development", "205 hod", "70,00 usd", "14 350,00 usd", "14350,00", "14350.00", "usd",
            "zari 2026", "305 726,75 kc", "305726,75", "21,359", "21,305", "20260902", "ach transfer",
            "30. 9. 2026", "30.9.2026", "30.09.2026", "2026-09-30", "2. 10. 2026", "2.10.2026", "02.10.2026",
            "2026-10-02", "vystavena, uhrazena", "routing number: [routing number]",
        ]
        for spelling in spellings {
            #expect(document.contains(spelling), "\(spelling)")
        }
        #expect(!document.contains("Bravo") && !document.contains("září"))
    }

    // MARK: The client as it is now

    @Test func aClientThatHasNotChangedAddsNothing() {
        let snapshot = ClientSnapshot(client: SearchFixtures.alfa)

        #expect(SearchDocumentBuilder.additionalDocument(forCurrent: snapshot, besides: snapshot).isEmpty)
    }

    @Test func aClientThatOnlyChangedItsCaseOrItsDiacriticsAddsNothing() {
        let snapshot = ClientSnapshot(client: SearchFixtures.alfa)
        var current = snapshot
        current.name = "ALFA SYSTEMS S.R.O."
        current.city = "PRIBRAM"

        #expect(SearchDocumentBuilder.additionalDocument(forCurrent: current, besides: snapshot).isEmpty)
    }

    @Test func aClientAddsTheFieldsThatDifferFromTheSnapshotAndNoOthers() {
        let snapshot = ClientSnapshot(client: SearchFixtures.alfa)
        var current = snapshot
        current.name = "Alfa Prime"
        current.city = "Brno"
        current.email = "fakturace@example.com"

        let extra = SearchDocumentBuilder.additionalDocument(forCurrent: current, besides: snapshot)

        #expect(extra == "alfa prime | hlavni 1, 261 01 brno, cesko | fakturace@example.com")
    }

    @Test func aClientThatGainedATaxNumberAddsIt() {
        let snapshot = ClientSnapshot(client: SearchFixtures.bravo)
        var current = snapshot
        current.dic = "US99-1234567"

        #expect(SearchDocumentBuilder.additionalDocument(forCurrent: current, besides: snapshot) == "us99-1234567")
    }
}
