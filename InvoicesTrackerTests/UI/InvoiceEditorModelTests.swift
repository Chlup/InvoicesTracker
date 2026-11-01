import Foundation
import Testing
@testable import InvoicesTracker

/// The model of the invoice editor for a new invoice: what a template or a blank invoice starts with, the client chips
/// and the QR code that follows the currency, the number by the month of the DUZP, what makes an invoice unfit to be
/// saved or issued, the live preview, and what issuing and saving a draft store. The data is the sample year 2026 with
/// invented clients and templates (`EditorFixture`), in a temporary database; the app is as of 17. 10. 2026, and the
/// ČNB rates are those of the fixtures, which end on 16. 10. 2026. In every expected string `\u{00A0}` is the
/// no-break space.
@Suite(.settlesBackups)
@MainActor
struct InvoiceEditorModelTests {
    /// The page is measured in the font it is set in, so the fonts are registered before any test, as the app does at
    /// its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: A new invoice from a template

    @Test func aDollarTemplateFillsTheEditorForTheEndOfTheMonth() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            #expect(model.clientID == f.bravoID)
            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.number == "20261001")
            #expect(model.items.map(\.description) == ["Software development October 2026"])
            #expect(model.items.map(\.quantityText) == ["172"])
            #expect(model.items.map(\.unit) == ["h"])
            #expect(model.items.map(\.unitPriceText) == ["70,00"])
            #expect(model.vatMode == .outsideCountry)
            #expect(model.dueDays == 30)
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-11-16")))
            #expect(model.note == "Payment due within 30 days.")
            #expect(model.qrEnabled == false)
            #expect(model.title == "Nová faktura")
            #expect(model.subtitle == "Ze šablony Software development")
            #expect(model.canIssue)
            #expect(model.validation.isEmpty)
        }
    }

    @Test func aLegacyTemplateAlsoStartsWithTheRealMonthEnd() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)

            #expect(model.clientID == f.alfaID)
            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.number == "20261001")
            #expect(model.items.map(\.description) == ["Služby říjen 2026", "Hosting"])
            #expect(model.items.map(\.quantityText) == ["7,5", "1"])
            #expect(model.items.map(\.unitPriceText) == ["600,00", "100,00"])
            #expect(model.vatMode == .domestic21)
            #expect(model.dueDays == 14)
            // A crown invoice has the QR code on by default.
            #expect(model.qrEnabled)
            #expect(model.note.isEmpty)
        }
    }

    @Test func aNewInvoiceUsesRealTodayEvenWhenAHistoricalYearIsSelected() async throws {
        try await EditorFixture.with { f in
            f.app.selectYear(2025)

            let model = await f.newEditor(template: f.dollarTemplate)

            #expect(model.issueDate == civilDate("2026-10-17"))
            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.number == "20261001")
            #expect(model.items.map(\.description) == ["Software development October 2026"])
        }
    }

    @Test func theLivePreviewIsTheDraftWithTheRateThatWouldBeFixed() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            let document = try #require(model.document)
            #expect(document.isProvisional)
            #expect(document.invoice.status == .draft)
            #expect(document.invoice.number == "20261001")
            #expect(document.invoice.client.name == "Bravo Labs, Inc.")
            #expect(document.invoice.totalMinor == 1_204_000)
            // Saturday 31. 10. 2026: no rate later than the one of 16. 10. 2026 is known.
            #expect(document.invoice.invoiceRate == storedRate("USD", "21.622", declaredOn: "2026-10-16"))
            #expect(
                model.currencyText
                    == "USD · kurz 21,622\u{00A0}Kč/USD (ČNB k DUZP, vyhlášený 16.\u{00A0}10.\u{00A0}2026, "
                    + "při vystavení se zafixuje)")
            #expect(model.totals?.base == "12\u{00A0}040,00\u{00A0}USD")
            #expect(model.totals?.vatLabel == "DPH 0\u{00A0}%")
            #expect(model.totals?.total == "12\u{00A0}040,00\u{00A0}USD")
            #expect(model.totals?.inCrowns == "≈ 260\u{00A0}328,88\u{00A0}Kč kurzem ČNB k DUZP")
        }
    }

    // MARK: A blank invoice

    @Test func aBlankInvoiceStartsWithTheFirstClientAndOneEmptyItem() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()

            #expect(model.clients.map(\.name) == ["Alfa Systems s.r.o.", "Bravo Labs, Inc.", "Cetus Data s.r.o."])
            #expect(model.clientID == f.alfaID)
            #expect(model.vatMode == .domestic21)
            #expect(model.dueDays == 14)
            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.number == "20261001")
            #expect(model.items.count == 1)
            #expect(model.items.map(\.quantityText) == ["1"])
            #expect(model.items.map(\.unit) == ["h"])
            #expect(model.items.map(\.unitPriceText) == [""])
            #expect(model.items.map(\.description) == [""])
            #expect(model.qrEnabled)
            #expect(model.title == "Nová faktura")
            #expect(model.subtitle == "Prázdná faktura")
            // Nothing is priced yet.
            #expect(model.canIssue == false)
            #expect(model.validation == ["Celková částka musí být větší než nula."])
            #expect(model.canSaveDraft)
        }
    }

    /// The real date supplies independent defaults, and editing either date preserves the other through a save.
    @Test func newInvoiceDatesAreIndependentAndSurviveReopening() async throws {
        try await EditorFixture.with(clock: ManualClock(localNoon(2026, 10, 28))) { f in
            let model = await f.newEditor(template: f.crownTemplate)
            #expect(model.issueDate == civilDate("2026-10-28"))
            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.dueDateText == "11.\u{00A0}11.\u{00A0}2026")

            model.issueDate = civilDate("2026-11-02")
            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.dueDateText == "16.\u{00A0}11.\u{00A0}2026")

            model.duzp = civilDate("2026-09-30")
            #expect(model.issueDate == civilDate("2026-11-02"))
            #expect(model.dueDateText == "16.\u{00A0}11.\u{00A0}2026")
            let id = try await model.saveDraft()
            let reopened = try await f.editor(editing: id)
            #expect(reopened.issueDate == civilDate("2026-11-02"))
            #expect(reopened.duzp == civilDate("2026-09-30"))
            #expect(reopened.dueDateText == "16.\u{00A0}11.\u{00A0}2026")
        }
    }

    @Test func nothingIsWrittenToTheDatabaseUntilASaveButton() async throws {
        try await EditorFixture.with { f in
            let version = f.app.dataVersion
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items[0].description = "Something else"
            model.pickClient(f.cetusID)
            model.number = "20261099"
            await model.recompute()

            try await f.expectInvoiceCount(11)
            #expect(f.app.dataVersion == version)
        }
    }

    // MARK: The client

    @Test func pickingAClientSetsItsVATModeAndDueDays() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()

            model.pickClient(f.bravoID)

            #expect(model.clientID == f.bravoID)
            #expect(model.vatMode == .outsideCountry)
            #expect(model.dueDays == 30)
            #expect(
                model.clientInfo
                    == "výchozí: USD · ACH (USD) · splatnost 30 dní · Mimo tuzemsko – § 9 odst. 1 (bez DPH) · "
                    + "faktura anglicky")
            #expect(model.methodText == "ACH (USD)")
            #expect(model.currency == .usd)

            model.pickClient(f.cetusID)

            #expect(model.vatMode == .domestic21)
            #expect(model.dueDays == 14)
            #expect(model.currency == .czk)
            #expect(model.currencyText == "CZK – česká koruna")
        }
    }

    @Test func pickingTheClientThatIsPickedAlreadyChangesNothing() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()
            model.vatMode = .domestic12
            model.dueDays = 5
            model.qrEnabled = false

            model.pickClient(f.alfaID)

            #expect(model.vatMode == .domestic12)
            #expect(model.dueDays == 5)
            #expect(model.qrEnabled == false)
        }
    }

    @Test func aCrownClientHasTheQRCodeOnAndADollarClientOff() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()
            #expect(model.clientID == f.alfaID)
            #expect(model.qrEnabled)
            #expect(model.qrAvailable)

            model.pickClient(f.bravoID)
            await model.recompute()

            #expect(model.qrEnabled == false)
            #expect(model.qrAvailable == false)
            #expect(model.qrNote == "Pro platby v USD QR standard není, faktura bude bez QR kódu.")

            // A person who unticks the box on a crown invoice gets it back on picking a client again.
            model.pickClient(f.cetusID)
            #expect(model.qrEnabled)
            model.qrEnabled = false
            model.pickClient(f.alfaID)
            #expect(model.qrEnabled)
        }
    }

    @Test func theQRCodeIsOnThePageOnlyWhileTheBoxIsTicked() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)
            await model.recompute()
            guard case .payload(let text, let label) = try #require(model.document).qr else {
                Issue.record("A crown invoice with the box ticked has a QR code.")
                return
            }
            #expect(text.hasPrefix("SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:"))
            #expect(label == "QR Platba")
            #expect(
                model.qrNote
                    == "QR Platba s číslem účtu, částkou a variabilním symbolem – "
                    + "odběratel ji naskenuje v mobilní bance.")

            model.qrEnabled = false
            await model.recompute()

            #expect(model.document?.qr == .unavailable("Faktura je bez QR kódu."))
            #expect(model.document?.invoice.qrEnabled == false)
        }
    }

    @Test func aSupplierWithoutAnIBANInCrownsGetsTheReasonOfTheQRCode() async throws {
        try await EditorFixture.with { f in
            try await f.database.saveBankAccounts([InvoicePageFixtures.usdAccount])

            let model = await f.newEditor(template: f.crownTemplate)

            // The box is the person's choice; the page cannot have the code, and the editor says why.
            #expect(model.qrEnabled)
            #expect(model.qrAvailable)
            #expect(model.qrNote == "Doplňte IBAN účtu v Kč v Nastavení › Moje údaje.")
            #expect(model.canIssue)
        }
    }

    @Test func aEuroClientHasTheSEPACodeAvailable() async throws {
        try await EditorFixture.with { f in
            var euro = SearchFixtures.bravo
            euro.name = "Delta Software GmbH"
            euro.currency = .eur
            euro.vatMode = .euReverseCharge
            let euroID = try await f.database.saveClient(euro)

            let model = await f.newEditor()
            model.pickClient(euroID)
            model.items[0].unitPriceText = "100,00"
            await model.recompute()

            #expect(model.qrEnabled)
            #expect(model.qrAvailable)
            #expect(model.qrNote == "QR kód pro platbu SEPA (EPC) s IBAN, částkou a referencí.")
        }
    }

    @Test func withoutAnyClientTheEditorSaysSo() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.clientID = 0
            await model.recompute()

            #expect(model.validation == ["Vyberte odběratele."])
            #expect(model.canIssue == false)
            #expect(model.canSaveDraft == false)
            #expect(model.document == nil)
        }
    }

    @Test func theVATModeDecidesTheVATAndTheTotal() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)
            // 7,5 hours at 600,00 Kč and one piece at 100,00 Kč.
            #expect(model.totals?.base == "4\u{00A0}600,00\u{00A0}Kč")
            #expect(model.totals?.vatLabel == "DPH 21\u{00A0}%")
            #expect(model.totals?.vat == "966,00\u{00A0}Kč")
            #expect(model.totals?.total == "5\u{00A0}566,00\u{00A0}Kč")
            #expect(model.totals?.inCrowns == nil)

            model.vatMode = .domestic12
            await model.recompute()
            #expect(model.totals?.vatLabel == "DPH 12\u{00A0}%")
            #expect(model.totals?.vat == "552,00\u{00A0}Kč")
            #expect(model.totals?.total == "5\u{00A0}152,00\u{00A0}Kč")
            #expect(model.document?.invoice.vatMode == .domestic12)

            model.vatMode = .euReverseCharge
            await model.recompute()
            #expect(model.totals?.vat == "0,00\u{00A0}Kč")
            #expect(model.totals?.total == "4\u{00A0}600,00\u{00A0}Kč")
        }
    }

    // MARK: The date and the number

    @Test func aNewDUZPMonthHasItsOwnNumberAndFillsTheDescriptionAgain() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.duzp = civilDate("2026-09-30")
            await model.recompute()

            // Two invoices of September exist: 20260901 and 20260902.
            #expect(model.number == "20260903")
            #expect(model.items.map(\.description) == ["Software development September 2026"])
            #expect(model.document?.invoice.issueDate == civilDate("2026-10-17"))
            // The ČNB rate declared for 30. 9. 2026.
            #expect(model.document?.invoice.invoiceRate == storedRate("USD", "21.522", declaredOn: "2026-09-30"))
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-11-16")))
        }
    }

    @Test func aDescriptionTypedByHandIsNotFilledAgain() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items[0].description = "Software development, my words"

            model.duzp = civilDate("2026-11-30")
            await model.recompute()

            #expect(model.items.map(\.description) == ["Software development, my words"])
            #expect(model.number == "20261101")
        }
    }

    @Test func aNumberTypedByHandStaysWhenTheDateChanges() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.number = "2026-10-A"

            model.duzp = civilDate("2026-11-30")
            await model.recompute()

            #expect(model.number == "2026-10-A")
        }
    }

    @Test func aNumberIsOneMoreThanTheHighestOfTheMonthIncludingDrafts() async throws {
        try await EditorFixture.with { f in
            let first = await f.newEditor(template: f.dollarTemplate)
            try await first.saveDraft()

            let second = await f.newEditor(template: f.dollarTemplate)

            #expect(first.number == "20261001")
            #expect(second.number == "20261002")
        }
    }

    @Test func aNumberWithoutADigitIsRefused() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.number = "  "
            await model.recompute()

            #expect(model.validation == ["Číslo faktury musí obsahovat alespoň jednu číslici."])
            #expect(model.canSaveDraft == false)
            await #expect(throws: InvoiceEditorError.invalid("Číslo faktury musí obsahovat alespoň jednu číslici.")) {
                try await model.saveDraft()
            }
            try await f.expectInvoiceCount(11)
        }
    }

    @Test func aNumberThatExistsAlreadyIsRefusedWhenSaving() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            // 20260902 is stored; numbers are the same by their digits.
            model.number = "2026-09-02"

            await #expect(throws: InvoiceError.duplicateNumber("2026-09-02")) {
                try await model.issue()
            }

            try await f.expectInvoiceCount(11)
            #expect(f.app.pendingDetailInvoiceID == nil)
            #expect(
                InvoiceEditorModel.failureText(for: InvoiceError.duplicateNumber("2026-09-02"))
                    == "Číslo faktury už existuje.")
        }
    }

    @Test func aDateOutsideTheYearsOfAnInvoiceIsRefusedWithoutHarm() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.duzp = civilDate("0001-01-01")
            await model.recompute()

            #expect(model.validation == ["Zadejte platné datum."])
            #expect(model.canSaveDraft == false)
            #expect(model.dueDateText == "—")

            model.duzp = civilDate("9999-12-31")
            await model.recompute()

            #expect(model.validation == ["Zadejte platné datum."])
        }
    }

    @Test func aDueTimeOutsideZeroToNineHundredNinetyNineDaysIsRefusedWithoutHarm() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.dueDays = 1_000
            await model.recompute()
            #expect(model.validation == ["Splatnost musí být 0 až 999 dní."])
            #expect(model.canSaveDraft == false)

            model.dueDays = -1
            await model.recompute()
            #expect(model.validation == ["Splatnost musí být 0 až 999 dní."])

            model.dueDays = 0
            await model.recompute()
            #expect(model.validation.isEmpty)
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-10-17")))
        }
    }

    @Test func theDueDaysAreHeldAsTypedAndReadWhenTheyAreWorkedOut() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.dueDaysText == "30")
            #expect(model.dueDays == 30)

            model.dueDaysText = " 45 "
            await model.recompute()

            #expect(model.dueDays == 45)
            #expect(model.validation.isEmpty)
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-12-01")))
        }
    }

    @Test func dueDaysThatAreTypedAndSavedAtOnceAreTheOnesThatAreSaved() async throws {
        // ⌘↩ or a click on a button can come before the model has worked the text out: the save works it out afresh.
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.dueDaysText = "45"
            let id = try await model.saveDraft()

            #expect(try await f.stored(id).dueDate == civilDate("2026-12-01"))
        }
    }

    @Test(arguments: ["", "  ", "abc", "3x", "1 0", "-1", "+5", "1000", "12,5", "99999999999999999999", "٣٠"])
    func dueDaysThatAreNotAWholeNumberFromZeroTo999AreRefused(text: String) async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.dueDaysText = text
            await model.recompute()

            #expect(model.validation == ["Splatnost musí být 0 až 999 dní."])
            #expect(model.canSaveDraft == false)
            #expect(model.dueDateText == "—")
            await #expect(throws: InvoiceEditorError.invalid("Splatnost musí být 0 až 999 dní.")) {
                try await model.saveDraft()
            }
        }
    }

    @Test func pickingAClientPutsItsDueDaysInTheField() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.dueDaysText = "abc"

            model.pickClient(f.cetusID)

            #expect(model.dueDaysText == "14")
            #expect(model.dueDays == 14)
        }
    }

    // MARK: The items

    @Test func anEmptyListOfItemsCannotBeIssuedButADraftCanBeSaved() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.items = []
            await model.recompute()

            #expect(model.canIssue == false)
            #expect(model.validation == ["Přidejte alespoň jednu položku."])
            #expect(model.canSaveDraft)
            await #expect(throws: InvoiceEditorError.invalid("Přidejte alespoň jednu položku.")) {
                try await model.issue()
            }
            try await f.expectInvoiceCount(11)
        }
    }

    @Test func eachItemNeedsAQuantityAboveZero() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items.append(.typed("Second", "0", "h", "10,00"))
            model.items.append(.typed("Third", "-2", "h", "10,00"))
            model.items.append(.typed("Fourth", "", "h", "10,00"))

            await model.recompute()

            #expect(
                model.validation == [
                    "Položka 2: zadejte počet větší než nula.", "Položka 3: zadejte počet větší než nula.",
                    "Položka 4: zadejte počet větší než nula.",
                ])
            #expect(model.canIssue == false)
            // What a draft needs is a number that can be read, not an amount.
            #expect(model.canSaveDraft)
        }
    }

    @Test func anItemWhoseNumbersCannotBeReadBlocksEvenADraft() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items.append(.typed("Second", "6,5h", "h", "10,00"))
            model.items.append(.typed("Third", "1", "h", "1.234,50"))

            await model.recompute()

            #expect(
                model.validation == [
                    "Položka 2: zadejte počet větší než nula.",
                    "Položka 3: zadejte cenu za MJ ve tvaru 13 340 nebo 13 340,50.",
                ])
            #expect(model.items[1].quantityError == "Zadejte počet, například 6,5.")
            #expect(model.items[2].priceError == "Zadejte částku ve tvaru 13 340 nebo 13 340,50.")
            #expect(model.items[0].quantityError == nil)
            #expect(model.items[0].priceError == nil)
            #expect(model.canSaveDraft == false)
        }
    }

    @Test func aTotalOfZeroCannotBeIssued() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items[0].unitPriceText = "0"

            await model.recompute()

            #expect(model.validation == ["Celková částka musí být větší než nula."])
            #expect(model.canIssue == false)
        }
    }

    @Test func aTotalOfZeroFromAnItemAndADiscountCannotBeIssuedEither() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items.append(.typed("Discount", "1", "ks", "-12 040,00"))

            await model.recompute()

            #expect(model.validation == ["Celková částka musí být větší než nula."])
        }
    }

    @Test func itemsAreAddedAndRemovedUpToTwelve() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.addItem()
            #expect(model.items.count == 2)
            // A new row is a quantity of one in the unit of the row above, with nothing else.
            #expect(model.items[1].quantityText == "1")
            #expect(model.items[1].unit == "h")
            #expect(model.items[1].description.isEmpty)
            #expect(model.items[1].unitPriceText.isEmpty)

            for _ in 0..<20 {
                model.addItem()
            }
            #expect(model.items.count == 12)
            #expect(model.canAddItem == false)

            model.removeItem(at: 5)
            #expect(model.items.count == 11)
            #expect(model.canAddItem)
            model.removeItem(at: 99)
            model.removeItem(at: -1)
            #expect(model.items.count == 11)
        }
    }

    @Test func moreThanTwelveItemsAreRefused() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.items = (1...13).map { .typed("Item \($0)", "1", "ks", "1,00") }

            await model.recompute()

            #expect(model.validation == ["Faktura může mít nejvýše 12 položek."])
            #expect(model.canSaveDraft == false)
        }
    }

    @Test func theUnitsOfferedAreHoursDaysMonthsAndPieces() {
        #expect(InvoiceEditorModel.units == ["h", "hod", "den", "měs.", "ks"])
    }

    @Test func theAmountOfAnItemIsItsQuantityTimesItsPrice() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)

            #expect(model.amountText(ofItem: 0) == "4\u{00A0}500,00\u{00A0}Kč")
            #expect(model.amountText(ofItem: 1) == "100,00\u{00A0}Kč")

            model.items[0].quantityText = "x"
            #expect(model.amountText(ofItem: 0) == "—")
            #expect(model.amountText(ofItem: 7) == "—")
        }
    }

    @Test func amountsTooHighToBeAnInvoiceAreRefusedWithoutHarm() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            // 999 999 pieces at 9 999 999 999,99 is far beyond what an invoice carries, and beyond Int64 when added up.
            model.items = (1...12).map { .typed("Item \($0)", "999 999", "ks", "9 999 999 999,99") }
            await model.recompute()

            #expect(model.validation == ["Částka na faktuře je příliš vysoká."])
            #expect(model.document == nil)
            #expect(model.canSaveDraft == false)
            #expect(model.totals == nil)
            #expect(model.amountText(ofItem: 0) == "—")

            // Twelve items that are each within the limit but together above it.
            model.items = (1...12).map { .typed("Item \($0)", "1", "ks", "900 000 000,00") }
            await model.recompute()

            #expect(model.validation == ["Částka na faktuře je příliš vysoká."])
            #expect(model.document == nil)

            // The VAT counts too: 21 % on a net just below the limit.
            model.vatMode = .domestic21
            model.items = [.typed("Item", "1", "ks", "9 000 000 000,00")]
            await model.recompute()

            #expect(model.validation == ["Částka na faktuře je příliš vysoká."])

            model.items = [.typed("Item", "1", "ks", "8 000 000 000,00")]
            await model.recompute()

            #expect(model.validation.isEmpty)
        }
    }

    // MARK: The note and the page

    @Test func aNoteOfTwentyLinesIsEnoughAndOneMoreIsRefused() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.note = InvoicePageFixtures.note(lines: 20)
            await model.recompute()
            #expect(model.validation.isEmpty)
            #expect(model.noteLineCount == 20)

            model.note = InvoicePageFixtures.note(lines: 21)
            await model.recompute()
            #expect(model.validation == ["Poznámka může mít nejvýše 20 řádků."])
            #expect(model.canSaveDraft == false)
            #expect(model.noteLineCount == 21)

            // Lines at the end that print nothing do not count.
            model.note = InvoicePageFixtures.note(lines: 20) + "\n\n  \n"
            await model.recompute()
            #expect(model.validation.isEmpty)
            #expect(model.noteLineCount == 20)
        }
    }

    /// While the note is empty it shows the example of the prototype in it, as a field with a prompt does.
    @Test func theNoteShowsAnExampleWhileItIsEmpty() {
        #expect(InvoiceEditorModel.notePlaceholder == "Např. platební instrukce")
    }

    @Test func whatChangedInTheDataMeanwhileIsSeenWhenTheInvoiceIsWorkedOutAgain() async throws {
        try await EditorFixture.with { f in
            // The editor stays while the person is on other screens, where a client is renamed.
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.clients.first { $0.id == f.bravoID }?.name == "Bravo Labs, Inc.")
            var bravo = try #require(try await f.database.client(id: f.bravoID))
            bravo.name = "Bravo Labs Renamed"
            bravo.street = "Nová 7"
            try await f.database.saveClient(bravo)
            await f.app.didWrite()

            await model.recompute()

            #expect(model.clients.first { $0.id == f.bravoID }?.name == "Bravo Labs Renamed")
            #expect(model.document?.invoice.client.name == "Bravo Labs Renamed")
            #expect(model.document?.invoice.client.street == "Nová 7")
        }
    }

    @Test func anInvoiceThatDoesNotFitOnePageIsRefusedByEverySaveButton() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)
            model.items = InvoicePageFixtures.items(12, words: 32).map {
                .typed($0.description, "1", $0.unit, "100,00")
            }
            model.note = InvoicePageFixtures.note(lines: 20)
            await model.recompute()

            let page = try #require(model.document)
            #expect(!InvoicePDFRenderer.fitsOnOnePage(page), "The test needs an invoice that does not fit")
            let message = "Faktura se nevejde na jednu stránku – zkraťte popisy položek nebo poznámku."
            #expect(model.validation == [message])
            #expect(model.canIssue == false)
            #expect(model.canSaveDraft == false)
            await #expect(throws: InvoiceEditorError.invalid(message)) { try await model.saveDraft() }
            await #expect(throws: InvoiceEditorError.invalid(message)) { try await model.issue() }
            try await f.expectInvoiceCount(11)

            model.note = ""
            model.items = Array(model.items.prefix(2))
            await model.recompute()
            #expect(model.validation.isEmpty)
            #expect(model.canIssue)
        }
    }

    @Test func anInvoiceThatDoesNotFitOnePageIsRefusedWhenItsChangesAreSavedToo() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.newEditor(template: f.crownTemplate).saveDraft()
            let issued = try await f.storeIssuedDollarInvoice()
            let message = "Faktura se nevejde na jednu stránku – zkraťte popisy položek nebo poznámku."

            for id in [draft, issued.id] {
                let model = try await f.editor(editing: id)
                model.items = InvoicePageFixtures.items(12, words: 32).map {
                    .typed($0.description, "1", $0.unit, "100,00")
                }
                model.note = InvoicePageFixtures.note(lines: 20)
                await model.recompute()
                let page = try #require(model.document)
                #expect(!InvoicePDFRenderer.fitsOnOnePage(page), "The test needs an invoice that does not fit")

                await #expect(throws: InvoiceEditorError.invalid(message)) { try await model.saveChanges() }
            }
            try await f.expectInvoiceCount(13)
            #expect(try await f.stored(issued.id).items.count == 1)
        }
    }

    // MARK: Saving a draft

    @Test func anIncompleteDraftCanBeSavedButNotIssued() async throws {
        try await EditorFixture.with { f in
            f.app.editorRequest = .new(templateID: nil)
            let model = await f.newEditor()
            #expect(model.canIssue == false)
            #expect(model.canSaveDraft)
            await #expect(throws: InvoiceEditorError.invalid("Celková částka musí být větší než nula.")) {
                try await model.issue()
            }

            let id = try await model.saveDraft()

            let draft = try await f.stored(id)
            #expect(draft.status == .draft)
            #expect(draft.number == "20261001")
            #expect(draft.clientID == f.alfaID)
            #expect(draft.client.name == "Alfa Systems s.r.o.")
            #expect(draft.totalMinor == 0)
            #expect(await f.app.draftCountOfSelectedYear() == 1)
            #expect(f.app.editorRequest == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == id)
        }
    }

    @Test func aDraftStoresTheRateThatWouldBeFixedAndAFreshOneIsFixedWhenItIsIssued() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            let id = try await model.saveDraft()

            let draft = try await f.stored(id)
            #expect(draft.status == .draft)
            #expect(draft.invoiceRate == storedRate("USD", "21.622", declaredOn: "2026-10-16"))
            #expect(draft.source == .app)
            #expect(draft.review == nil)
            #expect(draft.payment == nil)
        }
    }

    // MARK: Issuing

    @Test func issuingFixesTheRateOfTheDUZPAndStoresTheInvoiceAsIssued() async throws {
        try await EditorFixture.with { f in
            f.app.editorRequest = .new(templateID: f.dollarTemplate.id)
            let model = await f.newEditor(template: f.dollarTemplate)

            let id = try await model.issue()

            let invoice = try await f.stored(id)
            #expect(invoice.status == .issued)
            #expect(invoice.number == "20261001")
            #expect(invoice.clientID == f.bravoID)
            #expect(invoice.client == ClientSnapshot(client: SearchFixtures.bravo))
            #expect(invoice.currency == .usd)
            #expect(invoice.issueDate == civilDate("2026-10-17"))
            #expect(invoice.duzp == civilDate("2026-10-31"))
            #expect(invoice.dueDate == civilDate("2026-11-16"))
            // Saturday 31. 10. 2026: the rate declared on 16. 10. 2026 is the latest there is.
            #expect(invoice.invoiceRate == storedRate("USD", "21.622", declaredOn: "2026-10-16"))
            #expect(
                invoice.items == [
                    InvoiceItem(
                        description: "Software development October 2026", quantity: decimal("172"), unit: "h",
                        unitPriceMinor: 7_000)
                ])
            #expect(invoice.vatMode == .outsideCountry)
            #expect(invoice.qrEnabled == false)
            #expect(invoice.note == "Payment due within 30 days.")
            #expect(invoice.language == .en)
            #expect(invoice.paymentMethod == "ACH (USD)")
            #expect(invoice.payment == nil)
            #expect(invoice.review == nil)
            #expect(invoice.source == .app)
            // Faktury opens with the detail of the invoice.
            #expect(f.app.editorRequest == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == id)
            #expect(f.app.banner == nil)
        }
    }

    @Test func issuingACrownInvoiceFixesNoRate() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)

            let id = try await model.issue()

            let invoice = try await f.stored(id)
            #expect(invoice.status == .issued)
            #expect(invoice.invoiceRate == nil)
            #expect(invoice.qrEnabled)
            #expect(invoice.language == .cs)
            #expect(invoice.paymentMethod == "Převodem")
            #expect(invoice.issueDate == civilDate("2026-10-17"))
            #expect(invoice.dueDate == civilDate("2026-10-31"))
            #expect(invoice.totalMinor == 556_600)
        }
    }

    @Test func aPriceTypedInTheEditorIsStoredInMinorUnits() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()
            model.items = [.typed("Konzultace", "6,5", "hod", "1 234,56")]

            let id = try await model.issue()

            let invoice = try await f.stored(id)
            #expect(
                invoice.items == [
                    InvoiceItem(
                        description: "Konzultace", quantity: decimal("6.5"), unit: "hod", unitPriceMinor: 123_456)
                ])
            // 6,5 × 1 234,56 = 8 024,64 and 21 % VAT.
            #expect(invoice.netMinor == 802_464)
            #expect(invoice.vatMinor == 168_517)
        }
    }

    @Test func textsAreStoredWithoutTheSpacesAroundThem() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)
            model.number = " 20261077 "
            model.items[0].description = "  Služby  \n"
            model.items[0].unit = " hod "
            model.note = "\n  Poznámka  \n\n"

            let id = try await model.issue()

            let invoice = try await f.stored(id)
            #expect(invoice.number == "20261077")
            #expect(invoice.items[0].description == "Služby")
            #expect(invoice.items[0].unit == "hod")
            #expect(invoice.note == "Poznámka")
        }
    }

    // MARK: After a new invoice

    @Test func aNewInvoiceOfAPastYearSwitchesTheSelectedYear() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.issueDate = civilDate("2025-12-31")
            model.duzp = civilDate("2025-12-31")

            let id = try await model.issue()

            #expect(f.app.asOf.year == 2025)
            #expect(f.app.asOf.asOf == civilDate("2025-12-31"))
            #expect(f.app.pendingDetailInvoiceID == id)
            #expect(try await f.stored(id).number == "20251201")
        }
    }

    @Test func aNewInvoiceOfTheYearShownKeepsTheDayShown() async throws {
        try await EditorFixture.with { f in
            f.app.pickAsOf(civilDate("2026-06-30"))
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.issueDate == civilDate("2026-10-17"))
            #expect(model.duzp == civilDate("2026-10-31"))
            model.duzp = civilDate("2026-06-15")

            try await model.issue()

            #expect(f.app.asOf.year == 2026)
            #expect(f.app.asOf.asOf == civilDate("2026-06-30"))
        }
    }

    @Test func aNewInvoiceIssuedInTheCurrentYearBringsBackItsAutomaticMonthEnd() async throws {
        try await EditorFixture.with { f in
            f.app.selectYear(2025)
            let model = await f.newEditor(template: f.dollarTemplate)
            model.duzp = civilDate("2026-03-31")

            try await model.issue()

            #expect(f.app.asOf.year == 2026)
            #expect(f.app.asOf.asOf == civilDate("2026-10-31"))
            #expect(f.app.asOf.followsToday)
        }
    }

    @Test func aNewInvoiceOfAYearInTheFutureLeavesTheYearAlone() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            model.issueDate = civilDate("2027-01-01")
            model.duzp = civilDate("2027-01-31")

            let id = try await model.issue()

            #expect(f.app.asOf.year == 2026)
            #expect(f.app.asOf.asOf == civilDate("2026-10-31"))
            #expect(f.app.pendingDetailInvoiceID == id)
        }
    }

    @Test func theAppIsToldOfTheWrite() async throws {
        try await EditorFixture.with { f in
            let version = f.app.dataVersion
            let model = await f.newEditor(template: f.dollarTemplate)

            try await model.issue()

            #expect(f.app.dataVersion == version + 1)
        }
    }

    // MARK: Opening the editor for a request

    @Test func aRequestOpensTheEditorOfItsTemplateOrItsInvoice() async throws {
        try await EditorFixture.with { f in
            let blank = try #require(try await InvoiceEditorModel.opening(.new(templateID: nil), in: f.app))
            #expect(blank.template == nil && blank.editing == nil)

            let fromTemplate = try #require(
                try await InvoiceEditorModel.opening(.new(templateID: f.dollarTemplate.id), in: f.app))
            #expect(fromTemplate.template == f.dollarTemplate)

            let editing = try #require(try await InvoiceEditorModel.opening(.edit(10), in: f.app))
            #expect(editing.editing?.id == 10)

            // A template deleted meanwhile is a blank invoice; an invoice deleted meanwhile is nothing to edit.
            try await f.database.deleteTemplate(id: f.dollarTemplate.id)
            let gone = try #require(
                try await InvoiceEditorModel.opening(.new(templateID: f.dollarTemplate.id), in: f.app))
            #expect(gone.template == nil)
            try await f.database.deleteInvoice(id: 10)
            #expect(try await InvoiceEditorModel.opening(.edit(10), in: f.app) == nil)
            #expect(try await InvoiceEditorModel.opening(.chooser, in: f.app) == nil)
        }
    }
}

/// A row of items as it is typed: its numbers are read as every form of the app reads them, and a description made from
/// a template follows the DUZP until it is typed over.
struct EditableItemTests {
    @Test func quantitiesAreReadInCzechOrEnglishStyle() {
        #expect(EditableItem.typed("x", "6,5", "h", "").quantity == decimal("6.5"))
        #expect(EditableItem.typed("x", "6.5", "h", "").quantity == decimal("6.5"))
        #expect(EditableItem.typed("x", " 176 ", "h", "").quantity == decimal("176"))
        #expect(EditableItem.typed("x", "1 000", "h", "").quantity == decimal("1000"))
        #expect(EditableItem.typed("x", "0,000001", "h", "").quantity == decimal("0.000001"))
        #expect(EditableItem.typed("x", "-2", "h", "").quantity == decimal("-2"))
    }

    @Test(arguments: ["6,5h", "1.234,5", "0,0000001", "1 0000", "abc", "1e3", "999 999 999"])
    func aQuantityThatIsNotANumberIsNotReadAndSaysSo(text: String) {
        let item = EditableItem.typed("x", text, "h", "")

        #expect(item.quantity == nil)
        #expect(item.quantityError == "Zadejte počet, například 6,5.")
    }

    @Test func aQuantityThatIsEmptyIsNotReadAndSaysNothing() {
        let item = EditableItem.typed("x", "  ", "h", "")

        #expect(item.quantity == nil)
        #expect(item.quantityIsBlank)
        #expect(item.quantityError == nil)
    }

    @Test func pricesAreReadInMinorUnits() {
        #expect(EditableItem.typed("x", "1", "h", "70,00").unitPriceMinor == 7_000)
        #expect(EditableItem.typed("x", "1", "h", "1 234,56").unitPriceMinor == 123_456)
        #expect(EditableItem.typed("x", "1", "h", "13 340").unitPriceMinor == 1_334_000)
        #expect(EditableItem.typed("x", "1", "h", "800.5").unitPriceMinor == 80_050)
        #expect(EditableItem.typed("x", "1", "h", "-12 040,00").unitPriceMinor == -1_204_000)
    }

    @Test(arguments: ["1.234,50", "12,345", "12 50", "Kč 100", "1 000 000 000 000"])
    func aPriceThatIsNotAnAmountIsNotReadAndSaysSo(text: String) {
        let item = EditableItem.typed("x", "1", "h", text)

        #expect(item.unitPriceMinor == nil)
        #expect(item.priceError == "Zadejte částku ve tvaru 13 340 nebo 13 340,50.")
    }

    @Test func aPriceThatIsEmptyIsNotReadAndSaysNothing() {
        let item = EditableItem.typed("x", "1", "h", "")

        #expect(item.unitPriceMinor == nil)
        #expect(item.priceIsBlank)
        #expect(item.priceError == nil)
    }

    @Test func aStoredItemIsReadBackAsItIs() {
        let stored = InvoiceItem(description: "Služby", quantity: decimal("6.5"), unit: "hod", unitPriceMinor: 123_456)

        let item = EditableItem(item: stored)

        #expect(item.quantityText == "6,5")
        #expect(item.unitPriceText == "1\u{00A0}234,56")
        #expect(item.quantity == decimal("6.5"))
        #expect(item.unitPriceMinor == 123_456)
        #expect(item.description == "Služby")
        #expect(item.unit == "hod")
        #expect(item.isFilledFromTemplate == false)
    }

    @Test func aDescriptionFromATemplateFollowsTheDUZPUntilItIsTypedOver() {
        let template = TemplateItem(
            description: "Vývoj {měsíc} {rok} / {month} {year}", quantity: decimal("1"), unit: "ks",
            unitPriceMinor: 100)
        var item = EditableItem(templateItem: template, duzp: civilDate("2026-10-31"))
        #expect(item.description == "Vývoj říjen 2026 / October 2026")
        #expect(item.isFilledFromTemplate)

        item.fillFromTemplate(for: civilDate("2026-11-30"))
        #expect(item.description == "Vývoj listopad 2026 / November 2026")

        // Typed over, it is the person's own text: the editor does not fill it in again.
        item.description += "!"
        #expect(item.isFilledFromTemplate == false)
    }

    @Test func aRowThatHasNoTemplateIsNeverFilledIn() {
        var item = EditableItem.typed("Konzultace {rok}", "1", "h", "100,00")

        item.fillFromTemplate(for: civilDate("2026-10-31"))

        #expect(item.description == "Konzultace {rok}")
        #expect(item.isFilledFromTemplate == false)
    }
}
