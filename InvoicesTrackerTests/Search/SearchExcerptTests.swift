import Testing
@testable import InvoicesTracker

/// The line under a row of the list that says why an invoice was found when the table does not show the reason.
struct SearchExcerptTests {
    private func excerpt(_ invoice: Invoice, _ query: String) -> SearchExcerptResult? {
        SearchExcerpt.excerpt(for: invoice, words: SearchFolding.words(query))
    }

    /// The part of the text of an excerpt that is marked.
    private func marked(_ result: SearchExcerptResult) -> String {
        String(result.text[result.highlight])
    }

    private func invoice(note: String) -> Invoice {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.note = note
        return invoice
    }

    // MARK: What is shown

    @Test func aWordOfTheNoteGivesTheNoteWithTheWordMarkedAsItIsWritten() throws {
        let result = try #require(excerpt(SearchFixtures.dollarInvoice(), "routing"))

        #expect(result.label == "Poznámka")
        #expect(result.text == "Routing number: [ROUTING NUMBER]")
        #expect(marked(result) == "Routing")
    }

    @Test func aWordTypedInCapitalsAndWithoutDiacriticsMarksTheTextWithItsDiacritics() throws {
        let result = try #require(excerpt(SearchFixtures.crownInvoice(), "PRIBRAM"))

        #expect(result.label == "Adresa")
        #expect(result.text == "Hlavní 1, 261 01 Příbram, Česko")
        #expect(marked(result) == "Příbram")
    }

    @Test func aWordThatFoldingWritesLongerStillMarksTheWholeLetter() throws {
        let result = try #require(excerpt(invoice(note: "Hlavní Straße 5"), "strasse"))

        #expect(result.text == "Hlavní Straße 5")
        #expect(marked(result) == "Straße")
    }

    @Test func aLetterWrittenWithACombiningMarkIsMarkedWithItsMark() throws {
        // r + caron, i + acute
        let result = try #require(excerpt(invoice(note: "Pr\u{030C}i\u{0301}bram"), "pribram"))

        #expect(marked(result) == "Pr\u{030C}i\u{0301}bram")
    }

    @Test func aMatchInTheMiddleOfALongTextIsCutToAboutSixtyCharactersWithDotsOnBothSides() throws {
        let note = String(repeating: "a", count: 30) + " Routing " + String(repeating: "b", count: 40)

        let result = try #require(excerpt(invoice(note: note), "routing"))

        // 24 characters before the word and 32 after it
        let expected = "…" + String(repeating: "a", count: 23) + " Routing " + String(repeating: "b", count: 31) + "…"
        #expect(result.text == expected)
        #expect(marked(result) == "Routing")
        #expect(result.text.count == 65)
    }

    @Test func aMatchNearTheStartHasNoDotBeforeIt() throws {
        let note = "Routing " + String(repeating: "b", count: 50)

        let result = try #require(excerpt(invoice(note: note), "routing"))

        #expect(result.text == "Routing " + String(repeating: "b", count: 31) + "…")
        #expect(marked(result) == "Routing")
    }

    @Test func aMatchNearTheEndHasNoDotAfterIt() throws {
        let note = String(repeating: "b", count: 50) + " Routing"

        let result = try #require(excerpt(invoice(note: note), "routing"))

        #expect(result.text == "…" + String(repeating: "b", count: 23) + " Routing")
        #expect(marked(result) == "Routing")
    }

    @Test func theWhitespaceOfATextBecomesOneSpaceAndItsEndsAreTrimmed() throws {
        let result = try #require(excerpt(invoice(note: "\n Routing\n\n  number:\t[x] \u{00A0}\n"), "number"))

        #expect(result.text == "Routing number: [x]")
        #expect(marked(result) == "number")
    }

    @Test func theFirstOccurrenceInTheTextIsMarked() throws {
        let result = try #require(excerpt(invoice(note: "routing, Routing, ROUTING"), "routing"))

        #expect(result.text == "routing, Routing, ROUTING")
        #expect(marked(result) == "routing")
        #expect(result.highlight.lowerBound == result.text.startIndex)
    }

    // MARK: Which field

    @Test func aWordThatTheTableShowsNeedsNoExcerpt() {
        #expect(excerpt(SearchFixtures.crownInvoice(), "alfa 2026") == nil)
        #expect(excerpt(SearchFixtures.crownInvoice(), "kč") == nil)
        #expect(excerpt(SearchFixtures.crownInvoice(), "20260901 4500") == nil)
        #expect(excerpt(SearchFixtures.dollarInvoice(), "14350 305726,75") == nil)
        #expect(excerpt(SearchFixtures.dollarInvoice(), "2026 vystavená") == nil)
    }

    @Test func aWordThatAlsoOccursInAFieldTheTableShowsNeedsNoExcerpt() {
        var invoice = SearchFixtures.crownInvoice()
        invoice.note = "Alfa"

        #expect(excerpt(invoice, "alfa") == nil)
    }

    @Test func theFirstFieldTheTableDoesNotShowIsTheOneThatIsUsed() throws {
        var invoice = SearchFixtures.crownInvoice()
        invoice.items = [
            InvoiceItem(description: "Služby v Příbrami", quantity: decimal("1"), unit: "ks", unitPriceMinor: 100)
        ]
        invoice.note = "Příbram"

        // The address comes before the items and the note.
        #expect(try #require(excerpt(invoice, "pribram")).label == "Adresa")
        #expect(try #require(excerpt(invoice, "sluzby")).label == "Položka")
        #expect(try #require(excerpt(invoice, "pribrami")).label == "Položka")
    }

    @Test func aMatchOnlyOnTheAmountWithVATSaysWhy() throws {
        // The table has no column with the amount with VAT, so the line under the client says where it was found.
        let result = try #require(excerpt(SearchFixtures.crownInvoice(), "5445"))

        #expect(result.label == "S DPH")
        #expect(result.text == "5445,00")
        #expect(marked(result) == "5445")
    }

    @Test func theMonthOfTheSupplyIsNotInTheTable() throws {
        let result = try #require(excerpt(SearchFixtures.crownInvoice(), "září"))

        #expect(result.label == "Měsíc DUZP")
        #expect(result.text == "září 2026")
        #expect(marked(result) == "září")
    }

    @Test func theFirstWordThatTheTableDoesNotShowGivesTheExcerpt() throws {
        let invoice = SearchFixtures.crownInvoice()

        let address = try #require(excerpt(invoice, "alfa pribram example"))
        let email = try #require(excerpt(invoice, "alfa example pribram"))

        #expect(address.label == "Adresa" && marked(address) == "Příbram")
        #expect(email.label == "E-mail" && marked(email) == "example")
    }

    @Test func onlyTheWordsOutsideTheTableAreExplained() throws {
        let result = try #require(excerpt(SearchFixtures.dollarInvoice(), "bravo 2026 routing"))

        #expect(result.label == "Poznámka")
        #expect(marked(result) == "Routing")
    }

    // MARK: Nothing to show

    @Test func anInvoiceThatLacksAWordHasNoExcerpt() {
        #expect(excerpt(SearchFixtures.crownInvoice(), "routing") == nil)
        #expect(excerpt(SearchFixtures.dollarInvoice(), "bravo nonexistent") == nil)
        #expect(excerpt(SearchFixtures.crownInvoice(), "pribram zzzz") == nil)
    }

    @Test func noWordsGiveNoExcerpt() {
        #expect(SearchExcerpt.excerpt(for: SearchFixtures.dollarInvoice(), words: []) == nil)
    }

    @Test func theResultIsAValueThatCanBeComparedAndKept() throws {
        let first = try #require(excerpt(SearchFixtures.dollarInvoice(), "routing"))
        let second = try #require(excerpt(SearchFixtures.dollarInvoice(), "routing"))

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }
}
