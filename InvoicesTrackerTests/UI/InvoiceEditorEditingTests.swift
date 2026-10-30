import Foundation
import Testing
@testable import InvoicesTracker

/// The model of the invoice editor for an invoice that exists: what the editor says of it, what stays when it is saved
/// (the number, the rate of the DUZP, the data of the client of an issued invoice, the payment), what changes with it,
/// the effect on the levies of the year, an imported invoice, and an invoice that was changed or deleted while the
/// editor was open. The data is the sample year 2026 with invented clients (`EditorFixture`); invoice 10 is
/// 20260901, 205 hours at 70,00 USD for Bravo, paid on 2. 10. 2026 at 21,305, and invoice 11 is 20260902, 7,5 hours
/// at 600,00 Kč with 21 % VAT for Cetus, paid on 15. 10. 2026. In every expected string `\u{00A0}` is the no-break
/// space.
@Suite(.settlesBackups)
@MainActor
struct InvoiceEditorEditingTests {
    /// The page is measured in the font it is set in, so the fonts are registered before any test, as the app does at
    /// its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: What the editor says

    @Test func aPaidInvoiceSaysSoInTheHeaderTheBarAndTheWarning() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 11)

            #expect(model.title == "Upravit fakturu 20260902")
            #expect(model.subtitle == "Uhrazená faktura")
            #expect(model.templateBarName == nil)
            #expect(
                model.editBarState == "vystavená 30.\u{00A0}9.\u{00A0}2026 · uhrazená 15.\u{00A0}10.\u{00A0}2026")
            #expect(
                model.editWarning
                    == "Faktura už je vystavená. Po uložení se změní i její PDF – pokud jste ji už poslali, "
                    + "pošlete odběrateli opravenou verzi. Platba zůstane a příjem se přepočte stejným kurzem."
            )
            #expect(model.numberHint == "číslo faktury se při úpravě nemění")
            #expect(model.numberIsEditable == false)
            #expect(model.primaryTitle == "Uložit změny")
            #expect(model.showsSaveDraft == false)
        }
    }

    @Test func anIssuedInvoiceThatIsNotPaidHasNoWordAboutThePayment() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()

            let model = try await f.editor(editing: invoice.id)

            #expect(model.subtitle == "Vystavená faktura")
            #expect(model.editBarState == "vystavená 30.\u{00A0}9.\u{00A0}2026")
            #expect(
                model.editWarning
                    == "Faktura už je vystavená. Po uložení se změní i její PDF – pokud jste ji už poslali, "
                    + "pošlete odběrateli opravenou verzi."
            )
        }
    }

    @Test func anInvoiceToCheckSaysSoInTheBarBecauseAnEditDoesNotResolveIt() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(review: ReviewFlag(reason: "Částka v Kč chybí"))

            let model = try await f.editor(editing: invoice.id)

            #expect(model.editBarState == "vystavená 30.\u{00A0}9.\u{00A0}2026 · ke kontrole")
        }
    }

    @Test func aDraftIsSavedAsADraftOrIssuedAndItsNumberCanBeChanged() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(number: "20260905", status: .draft)

            let model = try await f.editor(editing: invoice.id)

            #expect(model.title == "Upravit fakturu 20260905")
            #expect(model.subtitle == "Koncept")
            #expect(model.editBarState == "koncept")
            #expect(model.editWarning == nil)
            #expect(model.numberHint == "řada RRRRMMPP podle měsíce DUZP")
            #expect(model.numberIsEditable)
            #expect(model.primaryTitle == "Vystavit fakturu")
            #expect(model.showsSaveDraft)
            #expect(model.templateBarName == nil)
        }
    }

    @Test func aNewInvoiceShowsTheTemplateItUses() async throws {
        try await EditorFixture.with { f in
            let blank = await f.newEditor()
            let fromTemplate = await f.newEditor(template: f.dollarTemplate)

            #expect(blank.templateBarName == "Prázdná faktura")
            #expect(fromTemplate.templateBarName == "Software development")
            #expect(blank.editBarState == nil)
            #expect(blank.editWarning == nil)
            #expect(blank.numberHint == "řada RRRRMMPP podle měsíce DUZP")
            #expect(blank.numberIsEditable)
            #expect(blank.primaryTitle == "Vystavit fakturu")
            #expect(blank.showsSaveDraft)
        }
    }

    @Test func theEditorOfAnInvoiceStartsWithItsOwnData() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 10)

            #expect(model.clientID == f.bravoID)
            #expect(model.number == "20260901")
            #expect(model.duzp == civilDate("2026-09-30"))
            #expect(model.dueDays == 30)
            #expect(model.vatMode == .outsideCountry)
            #expect(model.items.map(\.description) == ["Služby"])
            #expect(model.items.map(\.quantityText) == ["205"])
            #expect(model.items.map(\.unit) == ["h"])
            #expect(model.items.map(\.unitPriceText) == ["70,00"])
            #expect(model.qrEnabled == false)
            #expect(model.note.isEmpty)
            #expect(model.canIssue)
            #expect(model.validation.isEmpty)
            // The page of an invoice that is issued is not a draft's.
            #expect(model.document?.isProvisional == false)
            #expect(model.document?.invoice.status == .issued)
        }
    }

    @Test func aDraftsPreviewIsProvisional() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(number: "20260905", status: .draft)

            let model = try await f.editor(editing: invoice.id)

            #expect(model.document?.isProvisional == true)
            #expect(model.document?.invoice.status == .draft)
        }
    }

    // MARK: The number

    @Test func anIssuedInvoiceKeepsItsNumber() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            model.number = "20269999"

            let id = try await model.saveChanges()

            #expect(try await f.stored(id).number == "20260903")
        }
    }

    @Test func aDraftsNumberCanBeChangedButNotToOneThatExists() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(number: "20260905", status: .draft)
            let model = try await f.editor(editing: invoice.id)
            model.number = "2026-09-02"

            await #expect(throws: InvoiceError.duplicateNumber("2026-09-02")) {
                try await model.saveDraft()
            }
            #expect(try await f.stored(invoice.id) == invoice)

            model.number = "2026-09-77"
            try await model.saveDraft()

            #expect(try await f.stored(invoice.id).number == "2026-09-77")
        }
    }

    @Test func anIssuedInvoiceWhoseNumberHasNoDigitCanStillBeSaved() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(
                number: "Z-ABC", source: .imported(fakturoidID: "F-8", fingerprint: "row-8", changedInApp: false))
            let model = try await f.editor(editing: invoice.id)
            model.items[0].description = "Checked"

            #expect(model.validation.isEmpty)
            try await model.saveChanges()

            #expect(try await f.stored(invoice.id).number == "Z-ABC")
        }
    }

    @Test func aDraftWhoseDUZPMovesToAnotherMonthGetsTheNextNumberOfThatMonth() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "20260905", status: .draft)
            let model = try await f.editor(editing: draft.id)
            #expect(model.number == "20260905")

            // Another day of the same month keeps the number the draft has.
            model.duzp = civilDate("2026-09-12")
            await model.recompute()
            #expect(model.number == "20260905")

            model.duzp = civilDate("2026-10-15")
            await model.recompute()
            #expect(model.number == "20261001")

            // Back in September the draft has its own number again.
            model.duzp = civilDate("2026-09-30")
            await model.recompute()
            #expect(model.number == "20260905")

            model.duzp = civilDate("2026-10-15")
            await model.recompute()
            try await model.saveChanges()
            #expect(try await f.stored(draft.id).number == "20261001")
        }
    }

    @Test func aDraftWhoseNumberWasTypedKeepsItWhenTheDUZPMoves() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "20260905", status: .draft)
            let model = try await f.editor(editing: draft.id)
            model.number = "2026-09-77"

            model.duzp = civilDate("2026-10-15")
            await model.recompute()

            #expect(model.number == "2026-09-77")
        }
    }

    @Test func aDraftWhoseNumberIsNotOfTheMonthOfItsDUZPKeepsItWhenTheDUZPMoves() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "FV-7", status: .draft)
            let model = try await f.editor(editing: draft.id)

            model.duzp = civilDate("2026-10-15")
            await model.recompute()

            #expect(model.number == "FV-7")
        }
    }

    @Test func aNumberTakenMeanwhileMovesTheProposalOn() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.number == "20261001")

            // Another window, or an import, takes it and tells the app of the write.
            try await f.storeIssuedDollarInvoice(number: "20261001")
            await f.app.didWrite()
            await model.recompute()

            #expect(model.number == "20261002")
        }
    }

    @Test func aNumberTakenWithoutAWordIsProposedAgainAfterTheSaveFailsOnIt() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.number == "20261001")

            try await f.storeIssuedDollarInvoice(number: "20261001")
            await #expect(throws: InvoiceError.duplicateNumber("20261001")) {
                try await model.saveDraft()
            }
            await model.recompute()

            #expect(model.number == "20261002")
            let id = try await model.saveDraft()
            #expect(try await f.stored(id).number == "20261002")
        }
    }

    // MARK: The day of issue

    @Test func changingAnExistingInvoicesDUZPPreservesItsIssueAndDueDates() async throws {
        try await EditorFixture.with { f in
            // Supplied on 30. 9. 2026, issued on 2. 10. 2026, due on 30. 10. 2026.
            let invoice = try await f.storeIssuedDollarInvoice(issued: "2026-10-02")
            let model = try await f.editor(editing: invoice.id)
            #expect(model.dueDays == 28)
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-10-30")))

            // DUZP changes leave the independently stored issue date and its due date alone.
            model.duzp = civilDate("2026-10-15")
            #expect(model.issueDate == civilDate("2026-10-02"))
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-10-30")))

            // Returning DUZP to its stored day also leaves the issue date unchanged.
            model.duzp = civilDate("2026-09-30")
            #expect(model.dueDateText == CzechFormat.date(civilDate("2026-10-30")))
            try await model.saveChanges()

            let stored = try await f.stored(invoice.id)
            #expect(stored.issueDate == civilDate("2026-10-02"))
            #expect(stored.duzp == civilDate("2026-09-30"))
            #expect(stored.dueDate == civilDate("2026-10-30"))
        }
    }

    // MARK: The rate of the DUZP

    @Test func anIssuedInvoiceKeepsItsRateUntilTheDUZPChanges() async throws {
        try await EditorFixture.with { f in
            // Fixed at 21,359 on 30. 9. 2026; the fixtures' rate of that day is 21,522.
            let invoice = try await f.storeIssuedDollarInvoice()
            let first = try await f.editor(editing: invoice.id)
            #expect(
                first.currencyText
                    == "USD · kurz 21,359\u{00A0}Kč/USD (ČNB k DUZP, vyhlášený 30.\u{00A0}9.\u{00A0}2026, "
                    + "platí od vystavení)")
            first.items[0].description = "Software development, corrected"

            try await first.saveChanges()

            var stored = try await f.stored(invoice.id)
            #expect(stored.invoiceRate == storedRate("USD", "21.359", declaredOn: "2026-09-30"))
            #expect(stored.items[0].description == "Software development, corrected")
            #expect(stored.status == .issued)
            #expect(stored.issueDate == civilDate("2026-09-30"))

            // A new DUZP fixes its own rate, while the issue and due dates stay unchanged.
            let second = try await f.editor(editing: invoice.id)
            second.duzp = civilDate("2026-10-15")
            await second.recompute()
            #expect(
                second.currencyText
                    == "USD · kurz 21,732\u{00A0}Kč/USD (ČNB k DUZP, vyhlášený 15.\u{00A0}10.\u{00A0}2026, "
                    + "při vystavení se zafixuje)")

            try await second.saveChanges()

            stored = try await f.stored(invoice.id)
            #expect(stored.invoiceRate == storedRate("USD", "21.732", declaredOn: "2026-10-15"))
            #expect(stored.duzp == civilDate("2026-10-15"))
            #expect(stored.issueDate == civilDate("2026-09-30"))
            #expect(stored.dueDate == civilDate("2026-10-30"))
            #expect(stored.number == "20260903")
        }
    }

    @Test func aRateQuotedForManyUnitsNamesTheQuantityOnTheLineOfTheCurrency() async throws {
        try await EditorFixture.with { f in
            // Issued invoices of 1 000 000,00 whose rate of 30. 9. 2026 is fixed on them for `amount` units.
            for (number, code, amount, rate, label) in [
                ("20269001", "HUF", 100, "6.337", "6,337\u{00A0}Kč/100 HUF"),
                ("20269002", "IDR", 1_000, "1.204", "1,204\u{00A0}Kč/1\u{00A0}000 IDR"),
            ] {
                var invoice = Invoice.fixture(
                    number: number, currency: CurrencyCode(code)!, dueDate: "2026-10-30",
                    items: [.fixture("1", at: 100_000_000)], vatMode: .outsideCountry,
                    invoiceRate: storedRate(code, rate, declaredOn: "2026-09-30", amount: amount))
                invoice.id = try await f.database.saveInvoice(invoice)

                let model = try await f.editor(editing: invoice.id)

                #expect(
                    model.currencyText
                        == "\(code) · kurz \(label)"
                        + " (ČNB k DUZP, vyhlášený 30.\u{00A0}9.\u{00A0}2026, platí od vystavení)")
            }
        }
    }

    @Test func aChangeOfCurrencyFixesTheRateOfTheNewOne() async throws {
        try await EditorFixture.with { f in
            var euro = SearchFixtures.bravo
            euro.name = "Delta Software GmbH"
            euro.currency = .eur
            euro.vatMode = .euReverseCharge
            let euroID = try await f.database.saveClient(euro)
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)

            model.pickClient(euroID)
            try await model.saveChanges()

            let stored = try await f.stored(invoice.id)
            #expect(stored.currency == .eur)
            #expect(stored.invoiceRate == storedRate("EUR", "24.440", declaredOn: "2026-09-30"))
            #expect(stored.vatMode == .euReverseCharge)
            #expect(stored.client.name == "Delta Software GmbH")
            #expect(stored.clientID == euroID)
        }
    }

    @Test func aCrownInvoiceHasNoRate() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)

            model.pickClient(f.alfaID)
            try await model.saveChanges()

            let stored = try await f.stored(invoice.id)
            #expect(stored.currency == .czk)
            #expect(stored.invoiceRate == nil)
            #expect(stored.vatMode == .domestic21)
            #expect(stored.dueDate == civilDate("2026-10-14"))
            #expect(stored.language == .cs)
            #expect(stored.paymentMethod == "Převodem")
            #expect(stored.client.name == "Alfa Systems s.r.o.")
            #expect(stored.qrEnabled)
        }
    }

    /// What the editor says while the rate of the DUZP is not in the cache, and the invoice is only a draft.
    private let ratesNotDownloaded =
        "Kurz ČNB k DUZP zatím není stažený. Fakturu vystavíte, až se kurzy stáhnou – koncept můžete uložit už teď."

    /// The same for an invoice that is issued, which has no draft to save: its changes wait.
    private let changesWaitForRates =
        "Kurz ČNB k DUZP zatím není stažený. Změny uložíte, až se kurzy stáhnou."

    /// What the editor says of a currency that the ČNB does not quote on the day, where nothing will come.
    private let currencyNotQuoted = "ČNB pro tuto měnu kurz nevyhlašuje – fakturu v ní vystavit nejde."

    @Test func aCurrencyWithoutAnyRateCannotBeIssuedButItsDraftIsSaved() async throws {
        try await EditorFixture.with { f in
            var pounds = SearchFixtures.bravo
            pounds.name = "Echo Ltd"
            pounds.currency = try #require(CurrencyCode("GBP"))
            let poundsID = try await f.database.saveClient(pounds)
            let model = await f.newEditor(template: f.dollarTemplate)

            // The ČNB declared rates on 15. 10. 2026, only none for pounds (the cache has dollars and euros).
            model.duzp = civilDate("2026-10-15")
            model.pickClient(poundsID)
            await model.recompute()

            #expect(model.currencyText == "GBP · kurz ČNB zatím není k dispozici")
            #expect(model.document?.invoice.invoiceRate == nil)
            #expect(model.impactText == nil)
            #expect(model.validation == [currencyNotQuoted])
            #expect(model.canIssue == false)
            #expect(model.canSaveDraft)
            await #expect(throws: InvoiceEditorError.invalid(currencyNotQuoted)) {
                try await model.issue()
            }
            try await f.expectInvoiceCount(11)

            let id = try await model.saveDraft()

            let draft = try await f.stored(id)
            #expect(draft.status == .draft)
            #expect(draft.invoiceRate == nil)
            // There is nothing to ask for: that day is not missing, the currency is not quoted.
            #expect(f.http.requests.isEmpty)
        }
    }

    @Test func aHoleInTheRatesBeforeTheDUZPIsNotFilledWithAnOlderRate() async throws {
        try await EditorFixture.with { f in
            // The cache holds the dollar rates of 2022, 2025 and 2026, and none of 2023 and 2024.
            try await f.addDollarRates(ofYears: [2022])
            let model = await f.newEditor(template: f.dollarTemplate)

            model.duzp = civilDate("2024-05-31")
            await model.recompute()

            #expect(model.currencyText == "USD · kurz ČNB zatím není k dispozici")
            #expect(model.rate == nil)
            #expect(model.canIssue == false)
            #expect(model.validation == [ratesNotDownloaded])
            #expect(model.canSaveDraft)
            // The file of the year is asked for once. It does not come, and the gap stays.
            #expect(f.http.requests == [CNBEndpoints.yearly(2024)])
            await model.recompute()
            #expect(f.http.requests == [CNBEndpoints.yearly(2024)])
            let log = try await f.database.recentFetchLog(limit: 5)
            #expect(log.count == 1)
            #expect(log.first?.ok == false)
        }
    }

    @Test func theMissingRatesAreAskedForAndTheInvoiceCanBeIssuedOnceTheyCome() async throws {
        let file = try Data(contentsOf: fixtureURL("cnb_rok_2022", "txt"))
        try await EditorFixture.with(http: StubHTTPClient([CNBEndpoints.yearly(2022): file])) { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            model.duzp = civilDate("2022-06-30")
            await model.recompute()

            #expect(f.http.requests == [CNBEndpoints.yearly(2022)])
            #expect(model.rate?.declaredOn == civilDate("2022-06-30"))
            #expect(model.validation.isEmpty)
            #expect(model.canIssue)
            #expect(model.currencyText.contains("vyhlášený 30.\u{00A0}6.\u{00A0}2022"))
            let log = try await f.database.recentFetchLog(limit: 5)
            #expect(log.count == 1)
            #expect(log.first?.ok == true)
        }
    }

    @Test func aDUZPThatIsStillAheadTakesTheLastDeclaredRateWhileTheCacheIsCurrent() async throws {
        try await EditorFixture.with { f in
            // The DUZP is the end of the month, 31. 10. 2026, and the newest declaration is that of Friday 16. 10.
            let model = await f.newEditor(template: f.dollarTemplate)

            await model.recompute()

            #expect(model.duzp == civilDate("2026-10-31"))
            #expect(model.rate == storedRate("USD", "21.622", declaredOn: "2026-10-16"))
            #expect(
                model.currencyText
                    == "USD · kurz 21,622\u{00A0}Kč/USD (ČNB k DUZP, vyhlášený 16.\u{00A0}10.\u{00A0}2026, "
                    + "při vystavení se zafixuje)")
            #expect(model.canIssue)
            #expect(f.http.requests.isEmpty)
        }
    }

    @Test func aDUZPThatIsStillAheadWaitsForTheRatesWhenTheCacheIsBehind() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            // A week later, with nothing newer fetched, the last rate may be days old.
            f.clock.set(localNoon(2026, 10, 23))

            await model.recompute()

            #expect(model.rate == nil)
            #expect(model.canIssue == false)
            #expect(model.validation == [ratesNotDownloaded])
            #expect(model.canSaveDraft)
            #expect(f.http.requests == [CNBEndpoints.yearly(2026)])
        }
    }

    @Test func anIssuedInvoiceWhoseDUZPMovesToADayWithoutARateIsNotSavedUntilTheRatesCome() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)

            model.duzp = civilDate("2024-05-31")
            await model.recompute()

            // There is no draft to save for an invoice that is issued: its changes wait for the rates.
            #expect(model.validation == [changesWaitForRates])
            await #expect(throws: InvoiceEditorError.invalid(changesWaitForRates)) {
                try await model.saveChanges()
            }
            let stored = try await f.stored(invoice.id)
            #expect(stored.duzp == civilDate("2026-09-30"))
            #expect(stored.invoiceRate == storedRate("USD", "21.359", declaredOn: "2026-09-30"))
        }
    }

    @Test func aDraftWhoseDUZPMovesToADayWithoutARateCanStillBeSavedAndSaysSo() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "20260905", status: .draft)
            let model = try await f.editor(editing: draft.id)

            model.duzp = civilDate("2024-05-31")
            await model.recompute()

            #expect(model.validation == [ratesNotDownloaded])
            #expect(model.canSaveDraft)
            await #expect(throws: InvoiceEditorError.invalid(ratesNotDownloaded)) {
                try await model.issue()
            }
            try await model.saveChanges()
            let stored = try await f.stored(draft.id)
            #expect(stored.duzp == civilDate("2024-05-31"))
            #expect(stored.invoiceRate == nil)
        }
    }

    @Test func anIssuedInvoiceChangedToACurrencyTheCNBDoesNotQuoteIsNotSavedAndSaysWhy() async throws {
        try await EditorFixture.with { f in
            var pounds = SearchFixtures.bravo
            pounds.name = "Echo Ltd"
            pounds.currency = try #require(CurrencyCode("GBP"))
            let poundsID = try await f.database.saveClient(pounds)
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)

            // The ČNB declared rates on 30. 9. 2026, none for pounds (the cache has dollars and euros): nothing to ask.
            model.pickClient(poundsID)
            await model.recompute()

            #expect(model.validation == [currencyNotQuoted])
            await #expect(throws: InvoiceEditorError.invalid(currencyNotQuoted)) {
                try await model.saveChanges()
            }
            #expect(f.http.requests.isEmpty)
            #expect(try await f.stored(invoice.id).currency == .usd)
        }
    }

    @Test func anIssuedInvoiceKeepsItsRateAndItsEditsAreNotHeldUpByRatesThatAreMissing() async throws {
        try await EditorFixture.with { f in
            // Nothing of the cache is needed while the DUZP and the currency stay.
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            f.clock.set(localNoon(2026, 12, 1))
            model.items[0].description = "Software development, corrected"

            await model.recompute()

            #expect(model.validation.isEmpty)
            #expect(model.canIssue)
            #expect(f.http.requests.isEmpty)
            try await model.saveChanges()
            #expect(try await f.stored(invoice.id).items[0].description == "Software development, corrected")
        }
    }

    // MARK: The data of the client

    @Test func anIssuedInvoiceKeepsTheClientDataItWasWrittenWith() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            var bravo = try #require(try await f.database.client(id: f.bravoID))
            bravo.street = "Nová 7"
            try await f.database.saveClient(bravo)
            let model = try await f.editor(editing: invoice.id)
            #expect(model.document?.invoice.client.street == "100 Congress Avenue")

            try await model.saveChanges()

            #expect(try await f.stored(invoice.id).client.street == "100 Congress Avenue")
        }
    }

    @Test func aDraftIsIssuedWithTheClientDataOfTheDayItIsIssued() async throws {
        try await EditorFixture.with { f in
            let id = try await f.newEditor(template: f.dollarTemplate).saveDraft()
            var bravo = try #require(try await f.database.client(id: f.bravoID))
            bravo.street = "Nová 7"
            try await f.database.saveClient(bravo)
            let model = try await f.editor(editing: id)
            #expect(model.document?.invoice.client.street == "Nová 7")

            try await model.issue()

            let issued = try await f.stored(id)
            #expect(issued.status == .issued)
            #expect(issued.number == "20261001")
            #expect(issued.client.street == "Nová 7")
            #expect(issued.invoiceRate == storedRate("USD", "21.622", declaredOn: "2026-10-16"))
        }
    }

    @Test func aDraftStaysADraftWhenItIsSavedAgain() async throws {
        try await EditorFixture.with { f in
            let id = try await f.newEditor(template: f.dollarTemplate).saveDraft()

            let model = try await f.editor(editing: id)
            model.items[0].quantityText = "100"
            try await model.saveChanges()

            let draft = try await f.stored(id)
            #expect(draft.status == .draft)
            #expect(draft.items[0].quantity == decimal("100"))
            #expect(f.app.banner == AppBanner(text: "Změny faktury 20261001 jsou uložené.", screen: .invoices))
        }
    }

    @Test func anIssuedInvoiceCannotBeSavedAsADraftOrIssuedAgain() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 11)

            await #expect(throws: InvoiceEditorError.notAvailable) { try await model.saveDraft() }
            await #expect(throws: InvoiceEditorError.notAvailable) { try await model.issue() }

            #expect(try await f.stored(11).status == .issued)
        }
    }

    // MARK: A payment

    @Test func aPaidInvoiceKeepsItsPaymentAndRateAndSaysWhatTheLeviesChangeBy() async throws {
        try await EditorFixture.with { f in
            // The ČNB rate of 2. 10. 2026 that the payment of the sample was converted at, in place of the one of the
            // yearly file: the save converts the payments of the year again at the rates stored for their days.
            try await f.database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-10-02"), currency: .usd, amount: 1, rate: decimal("21.305"))
            ])
            let model = try await f.editor(editing: 10)
            model.items[0].quantityText = "220"

            await model.recompute()

            // The income of 2. 10. 2026 goes from 305 726,75 Kč to 328 097,00 Kč (220 h at 70,00 USD at 21,305).
            let before = try await f.app.effect(
                of: Receipt(
                    day: civilDate("2026-10-02"), czkNetHalere: 30_572_675, czkVatHalere: 0, source: .invoice(10)))
            let after = try await f.app.effect(
                of: Receipt(
                    day: civilDate("2026-10-02"), czkNetHalere: 32_809_700, czkVatHalere: 0, source: .invoice(10)))
            let change = after.total - before.total
            #expect(change > 0)
            #expect(
                model.impactText
                    == "Po úpravě se odvody za rok 2026 změní o +\(CzechFormat.grouped(change))\u{00A0}Kč")
            #expect(
                model.impactDetail
                    == "Faktura je uhrazená 2.\u{00A0}10.\u{00A0}2026. "
                    + "Příjem z ní bude 328\u{00A0}097,00\u{00A0}Kč místo 305\u{00A0}726,75\u{00A0}Kč."
            )

            let id = try await model.saveChanges()

            let stored = try await f.stored(id)
            #expect(
                stored.payment
                    == Payment(
                        date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 32_809_700,
                        czkVatHalere: 0, rate: storedRate("USD", "21.305", declaredOn: "2026-10-02")))
            #expect(stored.items[0].quantity == decimal("220"))
            #expect(stored.netMinor == 1_540_000)
            #expect(stored.source == .app)
            #expect(f.app.banner == AppBanner(text: "Změny faktury 20260901 jsou uložené.", screen: .invoices))
            #expect(f.app.pendingDetailInvoiceID == 10)
            #expect(f.app.screen == .invoices)
            #expect(f.app.editorRequest == nil)
            #expect(f.app.asOf.year == 2026)
        }
    }

    @Test func anInvoiceThatIsNotChangedChangesNothingOnTheLevies() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 10)

            // The receipt of the stored payment is replaced by itself, never counted twice.
            #expect(model.impactText == "Po úpravě se odvody za rok 2026 změní o 0\u{00A0}Kč")
            #expect(
                model.impactDetail
                    == "Faktura je uhrazená 2.\u{00A0}10.\u{00A0}2026. "
                    + "Příjem z ní bude 305\u{00A0}726,75\u{00A0}Kč jako dosud."
            )
        }
    }

    @Test func aSmallerInvoiceLowersTheLevies() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 10)
            model.items[0].quantityText = "200"

            await model.recompute()

            let text = try #require(model.impactText)
            #expect(text.hasPrefix("Po úpravě se odvody za rok 2026 změní o \u{2212}"))
            #expect(text.hasSuffix("\u{00A0}Kč"))
        }
    }

    @Test func aPaidCrownInvoiceTakesTheNewAmountsAsIncome() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 11)
            model.items[0].quantityText = "7"

            let id = try await model.saveChanges()

            let stored = try await f.stored(id)
            // 7 hours at 600,00 Kč, and 21 % VAT.
            #expect(
                stored.payment
                    == Payment(
                        date: civilDate("2026-10-15"), conversion: .czk, czkNetHalere: 420_000, czkVatHalere: 88_200))
        }
    }

    @Test func aPaymentOfAnAmountFromTheBankStaysAsEntered() async throws {
        try await EditorFixture.with { f in
            let payment = Payment(
                date: civilDate("2026-10-02"), conversion: .bankCZK, czkNetHalere: 30_600_000, czkVatHalere: 0,
                bankCZKTotalHalere: 30_600_000)
            let invoice = try await f.storeIssuedDollarInvoice(payment: payment)
            let model = try await f.editor(editing: invoice.id)
            model.items[0].quantityText = "120"

            await model.recompute()

            #expect(model.impactText == "Po úpravě se odvody za rok 2026 změní o 0\u{00A0}Kč")
            #expect(
                model.impactDetail
                    == "Faktura je uhrazená 2.\u{00A0}10.\u{00A0}2026. "
                    + "Příjem z ní bude 306\u{00A0}000,00\u{00A0}Kč jako dosud – částka v Kč podle banky se nemění."
            )

            try await model.saveChanges()

            #expect(try await f.stored(invoice.id).payment == payment)
        }
    }

    @Test func aProvisionalPaymentIsConvertedAgainWithTheRateThatIsKnownNow() async throws {
        try await EditorFixture.with { f in
            // Paid on 14. 10. 2026, converted at the rate of the invoice until the rate of that day was known.
            let provisional = Payment(
                date: civilDate("2026-10-14"), conversion: .cnbDaily, czkNetHalere: 14_951_300, czkVatHalere: 0,
                rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true)
            let invoice = try await f.storeIssuedDollarInvoice(payment: provisional)
            let model = try await f.editor(editing: invoice.id)
            model.items[0].quantityText = "110"

            try await model.saveChanges()

            // 110 hours at 70,00 USD at the rate declared on 14. 10. 2026.
            #expect(
                try await f.stored(invoice.id).payment
                    == Payment(
                        date: civilDate("2026-10-14"), conversion: .cnbDaily, czkNetHalere: 16_750_580,
                        czkVatHalere: 0, rate: storedRate("USD", "21.754", declaredOn: "2026-10-14")))
        }
    }

    @Test func aProvisionalPaymentWhoseRateIsStillUnknownStaysProvisional() async throws {
        try await EditorFixture.with { f in
            // Monday 19. 10. 2026 is after the newest rate there is.
            let provisional = Payment(
                date: civilDate("2026-10-19"), conversion: .cnbDaily, czkNetHalere: 14_951_300, czkVatHalere: 0,
                rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true)
            let invoice = try await f.storeIssuedDollarInvoice(payment: provisional)
            let model = try await f.editor(editing: invoice.id)
            model.items[0].quantityText = "110"

            try await model.saveChanges()

            #expect(
                try await f.stored(invoice.id).payment
                    == Payment(
                        date: civilDate("2026-10-19"), conversion: .cnbDaily, czkNetHalere: 16_446_430,
                        czkVatHalere: 0, rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"),
                        provisional: true))
        }
    }

    @Test func aChangedCurrencyOfAPaidInvoiceIsConvertedAfreshNotReapplied() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 10)

            model.pickClient(f.alfaID)
            try await model.saveChanges()

            let stored = try await f.stored(10)
            #expect(stored.currency == .czk)
            // 205 hours at 70,00 Kč and 21 % VAT: the crowns are the invoice's own amounts.
            #expect(
                stored.payment
                    == Payment(
                        date: civilDate("2026-10-02"), conversion: .czk, czkNetHalere: 1_435_000,
                        czkVatHalere: 301_350))
        }
    }

    @Test func anInvoiceInReviewHasNoImpactAndKeepsItsFlag() async throws {
        try await EditorFixture.with { f in
            let payment = Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 14_951_300, czkVatHalere: 0,
                rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"))
            let flag = ReviewFlag(reason: "Částka v Kč chybí")
            let invoice = try await f.storeIssuedDollarInvoice(payment: payment, review: flag)
            let model = try await f.editor(editing: invoice.id)
            model.items[0].description = "Checked"

            #expect(model.impactText == nil)
            #expect(model.impactDetail == nil)

            try await model.saveChanges()

            let stored = try await f.stored(invoice.id)
            #expect(stored.review == flag)
            #expect(stored.items[0].description == "Checked")
        }
    }

    // MARK: What a payment would add

    @Test func aNewInvoiceSaysWhatItsPaymentWouldAddToTheLevies() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)

            // This scenario explicitly issues at month end, so its 30-day due date is 30. 11. 2026.
            model.issueDate = civilDate("2026-10-31")
            await model.recompute()

            // 12 040,00 USD at the rate 21,622 is 260 328,88 Kč, expected on the due date, 30. 11. 2026.
            let effect = try await f.app.effect(
                of: Receipt(
                    day: civilDate("2026-11-30"), czkNetHalere: 26_032_888, czkVatHalere: 0, source: .synthetic))
            let hundreds = (effect.total + 50) / 100 * 100
            #expect(effect.total > 0)
            #expect(
                model.impactText
                    == "Až přijde platba, přibude k odvodům za rok 2026 zhruba "
                    + "\(CzechFormat.grouped(hundreds))\u{00A0}Kč")
            let share = try #require(InvoiceDetailBuilder.share(of: effect, income: 26_032_888))
            // The income of the sample year is past the cap of the flat-rate expenses before 30. 11.
            #expect(effect.crossings == [ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .whole)])
            #expect(
                model.impactDetail
                    == "To je \(share) z příjmu bez DPH 260\u{00A0}328,88\u{00A0}Kč, "
                    + "pokud zaplatí do splatnosti 30.\u{00A0}11.\u{00A0}2026. "
                    + "Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem. "
                    + "Když peníze dorazí až v dalším roce, patří příjem i odvody tam."
            )
        }
    }

    @Test func anInvoiceDueInTheNextYearAddsToTheLeviesOfThatYear() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)
            model.issueDate = civilDate("2026-12-31")

            await model.recompute()

            let text = try #require(model.impactText)
            #expect(text.hasPrefix("Až přijde platba, přibude k odvodům za rok 2027 zhruba "))
        }
    }

    @Test func anInvoiceWhoseDueTimeIsNotUsableSaysNothingOfTheLevies() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.crownTemplate)
            #expect(model.impactText != nil)

            model.dueDays = 1_200
            await model.recompute()

            #expect(model.impactText == nil)
            #expect(model.impactDetail == nil)
        }
    }

    @Test func aBlankInvoiceWouldAddNothing() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()

            #expect(model.impactText == "Až přijde platba, přibude k odvodům za rok 2026 zhruba 0\u{00A0}Kč")
            #expect(
                model.impactDetail
                    == "To je 0\u{00A0}% z příjmu bez DPH 0,00\u{00A0}Kč, "
                    + "pokud zaplatí do splatnosti 31.\u{00A0}10.\u{00A0}2026. "
                    + "Když peníze dorazí až v dalším roce, patří příjem i odvody tam."
            )
        }
    }

    // MARK: Changed or deleted meanwhile

    @Test func anInvoiceChangedMeanwhileIsNotOverwritten() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            model.items[0].description = "Edited in the editor"
            // A payment is recorded while the editor is open.
            var changed = try await f.stored(invoice.id)
            changed.payment = Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 14_951_300, czkVatHalere: 0,
                rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"))
            try await f.database.saveInvoice(changed)
            f.app.editorRequest = .edit(invoice.id)
            let version = f.app.dataVersion

            await #expect(throws: InvoiceEditorError.invoiceChanged) {
                try await model.saveChanges()
            }

            #expect(try await f.stored(invoice.id) == changed)
            #expect(
                InvoiceEditorModel.failureText(for: InvoiceEditorError.invoiceChanged)
                    == "Faktura se mezitím změnila. Zavřete úpravy a otevřete ji znovu.")
            // The editor stays open, and nothing was announced.
            #expect(f.app.editorRequest == .edit(invoice.id))
            #expect(f.app.banner == nil)
            #expect(f.app.dataVersion == version)
        }
    }

    @Test func theTextOfAFailedSaveStaysUntilTheNextEdit() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            model.items[0].description = "Edited in the editor"
            var changed = try await f.stored(invoice.id)
            changed.note = "Changed meanwhile"
            try await f.database.saveInvoice(changed)
            #expect(model.failure == nil)

            await #expect(throws: InvoiceEditorError.invoiceChanged) {
                try await model.saveChanges()
            }

            #expect(model.failure == "Faktura se mezitím změnila. Zavřete úpravy a otevřete ji znovu.")
            model.items[0].description = "Edited once more"
            #expect(model.failure == nil)
        }
    }

    @Test func aSecondSaveWhileOneIsRunningIsRefused() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.isSaving == false)

            // The first save has begun, and waits for the data, when its task is made.
            let first = Task.immediate { try await model.saveDraft() }
            #expect(model.isSaving)
            await #expect(throws: InvoiceEditorError.alreadySaving) {
                try await model.saveDraft()
            }
            let id = try await first.value

            #expect(model.isSaving == false)
            #expect(model.failure == nil)
            try await f.expectInvoiceCount(12)
            #expect(try await f.stored(id).status == .draft)
        }
    }

    @Test func anInvoiceDeletedMeanwhileIsNeverBroughtBack() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            try await f.database.deleteInvoice(id: invoice.id)
            let count = try await f.database.invoiceCount()

            await #expect(throws: InvoiceError.notFound) {
                try await model.saveChanges()
            }

            #expect(try await f.database.invoice(id: invoice.id) == nil)
            try await f.expectInvoiceCount(count)
            #expect(InvoiceEditorModel.failureText(for: InvoiceError.notFound) == "Faktura mezitím byla smazána.")
        }
    }

    @Test func otherFailuresAreSaidInGeneralWords() {
        #expect(InvoiceEditorModel.failureText(for: SQLiteError.step("x")) == "Fakturu se nepodařilo uložit.")
        #expect(InvoiceEditorModel.failureText(for: VaultError.locked) == "Fakturu se nepodařilo uložit.")
        #expect(
            InvoiceEditorModel.failureText(for: InvoiceEditorError.notAvailable) == "Fakturu se nepodařilo uložit.")
        #expect(
            InvoiceEditorModel.failureText(for: InvoiceEditorError.invalid("Zadejte platné datum."))
                == "Zadejte platné datum.")
    }

    // MARK: An imported invoice

    @Test func anImportedInvoiceIsMarkedAsChangedInTheApp() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(
                number: "Z20260905", source: .imported(fakturoidID: "F-7", fingerprint: "row-7", changedInApp: false))
            let model = try await f.editor(editing: invoice.id)
            model.items[0].description = "Checked"

            try await model.saveChanges()

            let stored = try await f.stored(invoice.id)
            #expect(stored.source == .imported(fakturoidID: "F-7", fingerprint: "row-7", changedInApp: true))
            #expect(stored.number == "Z20260905")
            #expect(stored.items[0].description == "Checked")
        }
    }

    @Test func savingAnImportedInvoiceWithoutAChangeWritesNothingAndKeepsItAsImported() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice(
                number: "Z20260905", source: .imported(fakturoidID: "F-7", fingerprint: "row-7", changedInApp: false))
            f.app.editorRequest = .edit(invoice.id)
            let model = try await f.editor(editing: invoice.id)
            let version = f.app.dataVersion

            let id = try await model.saveChanges()

            #expect(id == invoice.id)
            let stored = try await f.stored(invoice.id)
            #expect(stored.source == .imported(fakturoidID: "F-7", fingerprint: "row-7", changedInApp: false))
            // Nothing was written, so nothing is announced; the editor closes on the invoice all the same.
            #expect(f.app.dataVersion == version)
            #expect(f.app.banner == nil)
            #expect(f.app.editorRequest == nil)
            #expect(f.app.pendingDetailInvoiceID == invoice.id)
        }
    }

    @Test func savingWithoutAChangeStillNeedsTheInvoiceToBeThereAsTheEditorKnowsIt() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            var changed = try await f.stored(invoice.id)
            changed.note = "Changed meanwhile"
            try await f.database.saveInvoice(changed)

            await #expect(throws: InvoiceEditorError.invoiceChanged) {
                try await model.saveChanges()
            }
            #expect(try await f.stored(invoice.id) == changed)

            try await f.database.deleteInvoice(id: invoice.id)

            await #expect(throws: InvoiceError.notFound) {
                try await model.saveChanges()
            }
        }
    }

    @Test func anInvoiceOfTheAppStaysAnInvoiceOfTheApp() async throws {
        try await EditorFixture.with { f in
            let model = try await f.editor(editing: 11)

            try await model.saveChanges()

            #expect(try await f.stored(11).source == .app)
        }
    }

    // MARK: Leaving without saving

    @Test func zrusitOnAnInvoiceThatIsEditedShowsFakturyWithItsDetail() async throws {
        try await EditorFixture.with { f in
            f.app.screen = .invoices
            f.app.editorRequest = .edit(10)
            let model = try await f.editor(editing: 10)
            model.items[0].quantityText = "220"

            model.cancel()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == 10)
            // Nothing was saved.
            #expect(try await f.stored(10).items[0].quantity == decimal("205"))
        }
    }

    @Test func zrusitOnANewInvoiceShowsFakturyWithNoDetail() async throws {
        try await EditorFixture.with { f in
            f.app.startNewInvoice(templateID: nil)
            let model = await f.newEditor()

            model.cancel()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == nil)
            try await f.expectInvoiceCount(11)
        }
    }

    @Test func vybratJinouOpensTheChooserOverTheEditor() async throws {
        try await EditorFixture.with { f in
            f.app.startNewInvoice(templateID: f.dollarTemplate.id)
            let model = await f.newEditor(template: f.dollarTemplate)

            model.chooseAnotherTemplate()

            #expect(f.app.editorRequest == .chooser)
            #expect(f.app.shownEditorRequest == .new(templateID: f.dollarTemplate.id))
        }
    }

    // MARK: Nothing else changes

    @Test(arguments: [Int64(10), 11])
    func savingAnInvoiceWithoutChangesChangesNothing(id: Int64) async throws {
        try await EditorFixture.with { f in
            let before = try await f.stored(id)
            let model = try await f.editor(editing: id)

            try await model.saveChanges()

            #expect(try await f.stored(id) == before)
        }
    }
}
