import Foundation
import Testing
@testable import InvoicesTracker

/// What the detail of an invoice in Faktury says, and what the dialog that deletes it and the step that removes its
/// payment list as the consequences. In every expected string `\u{00A0}` is the no-break space.
struct InvoiceDetailBuilderTests {
    // MARK: Helpers

    /// The day the detail is shown as of ("K datu"), and today, which the status is as of: the same day unless a test
    /// says otherwise.
    private let asOf = civilDate("2026-10-17")
    private let today = civilDate("2026-10-17")

    /// 205 hours at 70,00 USD for Bravo Labs: 14 350,00 USD, fixed at 21,359 on 30. 9. 2026 and paid on 2. 10. 2026 at
    /// 21,305, which is 305 726,75 Kč.
    private var paidDollarInvoice: Invoice {
        var invoice = SearchFixtures.dollarInvoice()
        invoice.id = 10
        return invoice
    }

    /// 7,5 hours at 600,00 Kč and 21 % VAT for Alfa Systems, 5 445,00 Kč in all, not paid.
    private func crownInvoice(
        dueDate: String = "2026-10-14", status: InvoiceStatus = .issued, review: ReviewFlag? = nil,
        payment: Payment? = nil
    ) -> Invoice {
        var invoice = Invoice.fixture(dueDate: dueDate, status: status, review: review, payment: payment)
        invoice.id = 11
        return invoice
    }

    private func effect(of invoice: Invoice, on day: String = "2026-10-15") -> ReceiptEffect {
        ReceiptEffect(
            receipt: Receipt(
                day: civilDate(day), czkNetHalere: invoice.netMinor, czkVatHalere: invoice.vatMinor,
                source: .invoice(invoice.id)),
            tax: 675, social: 723, health: 304, total: 1_702)
    }

    private func detailOf(
        _ invoice: Invoice, asOf: CivilDate? = nil, statusDay: CivilDate? = nil, duzpRate: StoredRate? = nil,
        paymentEffect: ReceiptEffect? = nil, estimate: LevyEstimate? = nil
    ) -> InvoiceDetail {
        InvoiceDetailBuilder.build(
            InvoiceDetailInput(
                invoice: invoice, asOf: asOf ?? self.asOf, statusDay: statusDay ?? today, duzpRate: duzpRate,
                paymentEffect: paymentEffect, estimate: estimate))
    }

    // MARK: The top of the detail

    @Test func theHeadOfThePaidDollarInvoiceNamesTheClientTheTotalAndTheItems() {
        let detail = detailOf(paidDollarInvoice)

        #expect(detail.invoiceID == 10)
        #expect(detail.number == "20260902")
        #expect(detail.statusLabel == "Uhrazená 2.\u{00A0}10.")
        #expect(detail.status == .paid(civilDate("2026-10-02")))
        #expect(detail.client == "Bravo Labs, Inc. · Spojené státy americké")
        #expect(detail.total == "14\u{00A0}350,00\u{00A0}USD")
        #expect(detail.itemLines == ["205\u{00A0}hod × 70,00\u{00A0}USD · Software development"])
        #expect(detail.canPay == false)
        #expect(detail.estimate == nil)
        #expect(detail.reviewNote == nil)
    }

    @Test func onlyADraftCanBeIssuedAndOnlyAnIssuedInvoiceCanBePaid() {
        let draft = detailOf(crownInvoice(status: .draft))
        let unpaid = detailOf(crownInvoice())
        let paid = detailOf(paidDollarInvoice)

        #expect(draft.canIssue)
        #expect(draft.canPay == false)
        #expect(unpaid.canIssue == false)
        #expect(unpaid.canPay)
        #expect(paid.canIssue == false)
        #expect(paid.canPay == false)
        #expect(draft.canEditPayment == false)
        #expect(unpaid.canEditPayment == false)
        #expect(paid.canEditPayment)
        #expect(draft.canEdit)
        #expect(unpaid.canEdit)
        #expect(paid.canEdit == false)
    }

    @Test func aPaidInvoiceToCheckIsNotOfferedAChangeOfItsPayment() {
        let invoice = crownInvoice(
            review: ReviewFlag(reason: "zrušeno ve Fakturoidu"), payment: .fixture(on: "2026-10-15"))

        #expect(detailOf(invoice).canEditPayment == false)
    }

    @Test func aCzechClientIsNamedWithItsCountryInCzech() {
        let detail = detailOf(crownInvoice())

        #expect(detail.client == "Alfa Systems s.r.o. · Česko")
        #expect(detail.itemLines == ["7,5\u{00A0}hod × 600,00\u{00A0}Kč · Vývoj"])
        #expect(detail.total == "5\u{00A0}445,00\u{00A0}Kč")
    }

    /// The country is named as the client's card and the printed invoice name it: by `Countries`, in Czech.
    @Test(arguments: [
        ("US", "Spojené státy americké"), ("GB", "Spojené království"), ("DE", "Německo"),
        ("us", "Spojené státy americké"), ("JP", "Japonsko"), ("ZZ", "ZZ"), ("Brazil", "Brazil"), (" cz ", "Česko"),
    ])
    func theCountryOfAClientIsNamedBySharedNames(code: String, name: String) {
        var invoice = crownInvoice()
        invoice.client.country = code

        #expect(detailOf(invoice).client == "Alfa Systems s.r.o. · \(name)")
    }

    @Test(arguments: ["", "  "])
    func aClientWithoutACountryIsNamedAlone(country: String) {
        var invoice = crownInvoice()
        invoice.client.country = country

        #expect(detailOf(invoice).client == "Alfa Systems s.r.o.")
    }

    @Test func aPaidInvoiceFromAnotherYearShowsTheYearOfThePayment() {
        var invoice = crownInvoice(payment: .fixture(on: "2025-12-20"))
        invoice.issueDate = civilDate("2025-12-10")
        invoice.duzp = civilDate("2025-12-10")

        let detail = detailOf(invoice)

        #expect(detail.statusLabel == "Uhrazená 20.\u{00A0}12.\u{00A0}2025")
    }

    @Test func theFactsAreTheDatesThePaymentMethodAndTheVAT() {
        let detail = detailOf(crownInvoice())

        #expect(
            detail.facts == [
                DetailFact(label: "Vystaveno", value: "30.\u{00A0}9.\u{00A0}2026"),
                DetailFact(label: "DUZP", value: "30.\u{00A0}9.\u{00A0}2026"),
                DetailFact(label: "Splatnost", value: "14.\u{00A0}10.\u{00A0}2026"),
                DetailFact(label: "Platba", value: "Převodem"),
                DetailFact(label: "DPH", value: "Tuzemsko 21 % · 945,00\u{00A0}Kč"),
            ])
    }

    @Test func anInvoiceWithoutVATNamesTheModeAlone() {
        var invoice = crownInvoice()
        invoice.vatMode = .none

        #expect(detailOf(invoice).facts.last == DetailFact(label: "DPH", value: "Bez DPH"))
    }

    /// A fact that has nothing to say is left out, as the design has it ("label/value facts, empty ones left out"):
    /// an invoice whose method of payment is empty, or only white space, has no row "Platba" at all, not one with a
    /// dash for a value.
    @Test(arguments: ["", "  ", "\n"])
    func anInvoiceWithoutAPaymentMethodHasNoRowForIt(method: String) {
        var invoice = crownInvoice()
        invoice.paymentMethod = method

        let facts = detailOf(invoice).facts

        #expect(facts.map(\.label) == ["Vystaveno", "DUZP", "Splatnost", "DPH"])
        #expect(facts.allSatisfy { !$0.value.isEmpty })
    }

    /// A rate that is not known is not an empty fact, whatever the facts before it: its row stays, as a dash with the
    /// reason under it, which only the app has to say (`withoutAnyRateTheRowSaysSo`), and it is still the last row.
    @Test func aRateThatIsNotKnownStaysAsADashWithItsReasonWhileTheMethodOfPaymentIsLeftOut() {
        var invoice = paidDollarInvoice
        invoice.paymentMethod = ""
        invoice.invoiceRate = nil

        let facts = detailOf(invoice).facts

        #expect(facts.map(\.label) == ["Vystaveno", "DUZP", "Splatnost", "DPH", "Kurz ČNB k DUZP"])
        #expect(
            facts.last == DetailFact(label: "Kurz ČNB k DUZP", value: "—", note: "kurz ČNB zatím není k dispozici"))
    }

    // MARK: Kurz ČNB k DUZP

    @Test func theRateOfTheDUZPIsShownWithTheCrownsItMakesAndTheDayItWasDeclared() {
        let detail = detailOf(paidDollarInvoice)

        #expect(
            detail.facts.last
                == DetailFact(
                    label: "Kurz ČNB k DUZP", value: "21,359\u{00A0}Kč/USD → 306\u{00A0}501,65\u{00A0}Kč",
                    note: "vyhlášený 30.\u{00A0}9.\u{00A0}2026"))
        // An invoice in crowns has no such row.
        #expect(self.detailOf(crownInvoice()).facts.map(\.label) == ["Vystaveno", "DUZP", "Splatnost", "Platba", "DPH"])
    }

    @Test func aDUZPOnASundayTakesTheRateOfTheFridayBefore() {
        var invoice = paidDollarInvoice
        invoice.duzp = civilDate("2025-11-30")
        invoice.invoiceRate = storedRate("USD", "21.359", declaredOn: "2025-11-28")

        let note = detailOf(invoice).facts.last?.note

        #expect(note == "vyhlášený 28.\u{00A0}11.\u{00A0}2025, DUZP 30.\u{00A0}11.\u{00A0}2025 připadlo na víkend")
    }

    @Test func aDUZPOnAHolidayTakesTheRateOfTheBusinessDayBefore() {
        var invoice = paidDollarInvoice
        // 1. 5. 2026 is a Friday and a public holiday.
        invoice.duzp = civilDate("2026-05-01")
        invoice.invoiceRate = storedRate("USD", "21.359", declaredOn: "2026-04-30")

        let note = detailOf(invoice).facts.last?.note

        #expect(note == "vyhlášený 30.\u{00A0}4.\u{00A0}2026, DUZP 1.\u{00A0}5.\u{00A0}2026 připadlo na svátek")
    }

    @Test func aRateThatWasNotDeclaredOnTheDUZPOfABusinessDaySaysWhichRateStands() {
        var invoice = paidDollarInvoice
        invoice.duzp = civilDate("2026-09-30")
        invoice.invoiceRate = storedRate("USD", "21.359", declaredOn: "2026-09-29")

        let note = detailOf(invoice).facts.last?.note

        #expect(note == "kurz k DUZP nebyl vyhlášen – platí kurz vyhlášený 29.\u{00A0}9.\u{00A0}2026")
    }

    @Test func aDraftShowsTheRateThatWouldBeUsedAndSaysItIsFixedOnIssue() {
        var draft = paidDollarInvoice
        draft.status = .draft
        draft.payment = nil
        draft.invoiceRate = nil

        let detail = detailOf(draft, duzpRate: storedRate("USD", "21.359", declaredOn: "2026-09-30"))

        #expect(
            detail.facts.last
                == DetailFact(
                    label: "Kurz ČNB k DUZP", value: "21,359\u{00A0}Kč/USD → 306\u{00A0}501,65\u{00A0}Kč",
                    note: "vyhlášený 30.\u{00A0}9.\u{00A0}2026 · při vystavení se zafixuje"))
        #expect(detail.statusLabel == "Koncept")
        #expect(detail.canPay == false)
    }

    @Test func aDraftOnAWeekendSaysBothThings() {
        var draft = paidDollarInvoice
        draft.status = .draft
        draft.payment = nil
        draft.duzp = civilDate("2025-11-30")

        let note = detailOf(draft, duzpRate: storedRate("USD", "21.359", declaredOn: "2025-11-28")).facts.last?.note

        #expect(
            note
                == "vyhlášený 28.\u{00A0}11.\u{00A0}2025, DUZP 30.\u{00A0}11.\u{00A0}2025 připadlo na víkend"
                + " · při vystavení se zafixuje")
    }

    @Test func aDUZPWhoseRateIsNotDeclaredYetSaysThatTheLatestRateStands() {
        // 31. 10. 2026 is a Saturday: its rate is the one of Friday 30. 10., which the ČNB has not declared by the day
        // shown, 17. 10. The latest rate there is, of 16. 10., stands for now.
        var draft = paidDollarInvoice
        draft.status = .draft
        draft.payment = nil
        draft.duzp = civilDate("2026-10-31")

        let note = detailOf(draft, duzpRate: storedRate("USD", "21.622", declaredOn: "2026-10-16")).facts.last?.note

        #expect(
            note
                == "kurz k DUZP zatím nebyl vyhlášen – platí poslední vyhlášený kurz z 16.\u{00A0}10.\u{00A0}2026 · při vystavení se zafixuje"
        )
    }

    @Test func aDraftIgnoresTheRateItStoredAndShowsTheOneThatWouldBeUsedNow() {
        var draft = paidDollarInvoice
        draft.status = .draft
        draft.payment = nil
        draft.invoiceRate = storedRate("USD", "20.000", declaredOn: "2026-09-01")

        let value = detailOf(draft, duzpRate: storedRate("USD", "21.359", declaredOn: "2026-09-30")).facts.last?.value

        #expect(value == "21,359\u{00A0}Kč/USD → 306\u{00A0}501,65\u{00A0}Kč")
    }

    @Test func anImportedInvoiceWithoutARateUsesTheRateTheModelLookedUp() {
        var invoice = paidDollarInvoice
        invoice.invoiceRate = nil

        let detail = detailOf(invoice, duzpRate: storedRate("USD", "21.359", declaredOn: "2026-09-30"))

        #expect(detail.facts.last?.value == "21,359\u{00A0}Kč/USD → 306\u{00A0}501,65\u{00A0}Kč")
        #expect(detail.facts.last?.note == "vyhlášený 30.\u{00A0}9.\u{00A0}2026")
    }

    @Test func aRateQuotedForManyUnitsNamesTheQuantityOnTheRow() {
        // 1 000 000,00 of the currency, whose rate of 30. 9. 2026 is fixed on the invoice for `amount` units.
        func value(of code: String, quotedFor amount: Int, at rate: String) -> String? {
            var invoice = Invoice.fixture(
                currency: CurrencyCode(code)!, items: [.fixture("1", at: 100_000_000)], vatMode: .outsideCountry,
                invoiceRate: storedRate(code, rate, declaredOn: "2026-09-30", amount: amount))
            invoice.id = 12
            return detailOf(invoice).facts.last?.value
        }

        #expect(
            value(of: "HUF", quotedFor: 100, at: "6.337") == "6,337\u{00A0}Kč/100 HUF → 63\u{00A0}370,00\u{00A0}Kč")
        #expect(
            value(of: "IDR", quotedFor: 1_000, at: "1.204")
                == "1,204\u{00A0}Kč/1\u{00A0}000 IDR → 1\u{00A0}204,00\u{00A0}Kč")
    }

    @Test func withoutAnyRateTheRowSaysSo() {
        var invoice = paidDollarInvoice
        invoice.invoiceRate = nil

        let fact = detailOf(invoice).facts.last

        #expect(fact == DetailFact(label: "Kurz ČNB k DUZP", value: "—", note: "kurz ČNB zatím není k dispozici"))
    }

    // MARK: The payment

    @Test func theAmountPaidInDollarsIsTheIncomeAtTheRateOfTheDay() {
        let payment = detailOf(paidDollarInvoice).payment

        #expect(payment?.line == "2.\u{00A0}10.\u{00A0}2026 · 14\u{00A0}350,00\u{00A0}USD")
        #expect(payment?.crowns == "305\u{00A0}726,75\u{00A0}Kč")
        #expect(payment?.note == "kurz ČNB ke dni přijetí 21,305")
        #expect(payment?.laterNote == nil)
        #expect(payment?.effect == nil)
    }

    @Test func theUniformRateIsNamedWithItsYear() {
        var invoice = paidDollarInvoice
        invoice.payment = .fixture(
            on: "2025-10-08", conversion: .uniform, net: 31_340_400, vat: 0,
            rate: storedRate("USD", "21.84", declaredOn: "2025-12-31"))

        #expect(detailOf(invoice, asOf: civilDate("2025-12-31")).payment?.note == "jednotný kurz za rok 2025 21,840")
    }

    @Test func theAmountFromTheBankIsNamedSo() {
        var invoice = paidDollarInvoice
        invoice.payment = .fixture(
            on: "2026-10-02", conversion: .bankCZK, net: 30_600_000, vat: 0, bankCZKTotalHalere: 30_600_000)

        let payment = detailOf(invoice).payment

        #expect(payment?.crowns == "306\u{00A0}000,00\u{00A0}Kč")
        #expect(payment?.note == "částka v Kč podle banky")
    }

    @Test func aPaymentInCrownsNamesTheVATItHolds() {
        let payment = detailOf(crownInvoice(payment: .fixture(on: "2026-10-15"))).payment

        #expect(payment?.line == "15.\u{00A0}10.\u{00A0}2026 · 5\u{00A0}445,00\u{00A0}Kč")
        #expect(payment?.crowns == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(payment?.note == "z toho DPH 945,00\u{00A0}Kč")
    }

    @Test func aPaymentThatWaitsForItsRateIsApproximateAndSaysWhy() {
        var invoice = paidDollarInvoice
        invoice.payment = .fixture(
            on: "2026-10-02", conversion: .cnbDaily, net: 30_650_165, vat: 0,
            rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true)

        let payment = detailOf(invoice).payment

        #expect(payment?.crowns == "≈ 306\u{00A0}501,65\u{00A0}Kč")
        #expect(payment?.note == "předběžný kurz 21,359 · přepočte se, až bude kurz vyhlášen")
    }

    /// What the detail says of a payment that is dated after today: that the money counts as income only from that day.
    private static let laterNote = "Platba má datum po dnešku – do příjmů se započítá až ten den."

    /// The note that the payment is dated later is for a payment dated after today alone, whichever day the screen is
    /// shown as of: the invoice of a past year that was paid on 7. 1. of the next year has no such note on 17. 10., as
    /// the money came, and a payment dated after today has it in the list of a past year, of the current one and of a
    /// year to come, as the money has not. A payment of today is not after it.
    @Test(
        arguments: [
            // The list of 2025, as of its last day: a payment of January 2026 is before today.
            ("2025-12-31", "2026-10-17", "2026-01-07", false),
            // The list of the current year, as of today: before today, on the day itself and after it.
            ("2026-10-17", "2026-10-17", "2026-10-15", false),
            ("2026-10-17", "2026-10-17", "2026-10-17", false),
            ("2026-10-17", "2026-10-17", "2026-10-18", true),
            // The list of 2025: a payment dated after today is after it there too.
            ("2025-12-31", "2026-10-17", "2026-12-01", true),
            // The list of 2027, as of its last day, which is after the payment: it is after today all the same.
            ("2027-12-31", "2026-10-17", "2027-03-01", true),
        ] as [(String, String, String, Bool)])
    func theLaterNoteNeedsAPaymentAfterToday(asOf: String, today: String, paid: String, hasNote: Bool) {
        let invoice = crownInvoice(dueDate: "2026-10-30", payment: .fixture(on: paid))

        let detail = detailOf(invoice, asOf: civilDate(asOf), statusDay: civilDate(today))

        #expect(detail.payment?.laterNote == (hasNote ? Self.laterNote : nil))
    }

    /// A payment dated before today but after the day shown is paid as of today, and has no note about the day: the
    /// status is as of today whatever day the screen is shown as of.
    @Test func aPaymentAfterTheDayShownButBeforeTodayIsPaidWithoutANote() {
        let invoice = crownInvoice(dueDate: "2026-10-30", payment: .fixture(on: "2026-10-15"))

        let detail = detailOf(invoice, asOf: civilDate("2026-10-01"))

        #expect(detail.payment?.laterNote == nil)
        #expect(detail.status == .paid(civilDate("2026-10-15")))
        #expect(detail.statusLabel == "Uhrazená 15.\u{00A0}10.")
        // It has a payment, so it cannot be marked paid again.
        #expect(detail.canPay == false)
    }

    /// A payment dated after today has not come yet, so the invoice is not paid but awaits payment or is overdue as of
    /// today, and the note says that the money counts from the day of the payment. The payment is there, so the invoice
    /// cannot be marked paid again and only its payment can be changed: the invoice itself cannot be edited.
    @Test func aPaymentAfterTodayLeavesTheInvoiceUnpaidWithTheNoteAndItsPaymentToChange() {
        let invoice = crownInvoice(dueDate: "2026-10-30", payment: .fixture(on: "2026-10-20"))

        let detail = detailOf(invoice)

        #expect(detail.payment?.laterNote == Self.laterNote)
        #expect(detail.status == .awaitingPayment)
        #expect(detail.statusLabel == "Čeká na platbu")
        #expect(detail.canPay == false)
        #expect(detail.canEditPayment)
        #expect(detail.canEdit == false)
    }

    @Test func theDetailOfAnInvoicePaidLaterShowsItAsPaid() {
        // Issued on 30. 12. 2025, due on 13. 1. 2026 and paid on 2. 1. 2026, seen in 2025 as of 31. 12. with today the
        // 20th of October 2026.
        var invoice = crownInvoice(dueDate: "2026-01-13", payment: .fixture(on: "2026-01-02"))
        invoice.issueDate = civilDate("2025-12-30")
        invoice.duzp = civilDate("2025-12-30")

        let detail = detailOf(invoice, asOf: civilDate("2025-12-31"), statusDay: civilDate("2026-10-20"))

        #expect(detail.status == .paid(civilDate("2026-01-02")))
        // The year is written because the payment is of another year than the day shown.
        #expect(detail.statusLabel == "Uhrazená 2.\u{00A0}1.\u{00A0}2026")
        #expect(detail.canPay == false)
        // The money came on 2. 1., before today, so nothing says that it counts later: the list of 2025 does not count
        // it as income of 2025, because it is income of 2026 (the section of the levies says so).
        #expect(detail.payment?.laterNote == nil)
    }

    @Test func theDetailOfAnInvoiceThatIsNotPaidIsOverdueByTodayWhateverTheDayShown() {
        // Due on 14. 10. 2026. On 1. 10., the day shown, it awaited payment, but today is the 17th.
        let invoice = crownInvoice()

        let detail = detailOf(invoice, asOf: civilDate("2026-10-01"))

        #expect(detail.status == .overdue)
        #expect(detail.statusLabel == "Po splatnosti")
        #expect(detail.canPay)
    }

    @Test func theDetailOfAnInvoiceThatIsNotDueTodayAwaitsPaymentWhateverTheDayShown() {
        // Due on 14. 10. 2026. On 31. 12., a day in the future, it would be overdue, but today is the 13th.
        let invoice = crownInvoice()

        let detail = detailOf(invoice, asOf: civilDate("2026-12-31"), statusDay: civilDate("2026-10-13"))

        #expect(detail.status == .awaitingPayment)
        #expect(detail.statusLabel == "Čeká na platbu")
        #expect(detail.canPay)
    }

    // MARK: What the payment adds to the levies

    @Test func thePaymentNamesWhatItAddsToTheLeviesOfItsYear() {
        let invoice = crownInvoice(payment: .fixture(on: "2026-10-15"))

        let detail = detailOf(invoice, paymentEffect: effect(of: invoice))

        let effect = detail.payment?.effect
        #expect(effect?.heading == "Dopad na odvody 2026")
        #expect(effect?.total == "+1\u{00A0}702\u{00A0}Kč")
        #expect(
            effect?.rows == [
                EffectRow(authority: .tax, title: "Daň z příjmů", value: "+675"),
                EffectRow(authority: .social, title: "Sociální pojištění", value: "+723"),
                EffectRow(authority: .health, title: "Zdravotní pojištění", value: "+304"),
            ])
        #expect(
            effect?.note
                == "37,8\u{00A0}% z příjmu 4\u{00A0}500,00\u{00A0}Kč – peníze přišly 15.\u{00A0}10.\u{00A0}2026, proto patří do roku 2026."
        )
    }

    @Test func aPaymentOfAnotherYearBelongsToThatYear() {
        let invoice = crownInvoice(payment: .fixture(on: "2025-12-30"))
        let levies = ReceiptEffect(
            receipt: Receipt(day: civilDate("2025-12-30"), czkNetHalere: 450_000, czkVatHalere: 94_500, source: .invoice(11)),
            tax: 0, social: 1_000, health: 500, total: 1_500)

        let detail = detailOf(invoice, asOf: civilDate("2026-10-17"), paymentEffect: levies)

        #expect(detail.payment?.effect?.heading == "Dopad na odvody 2025")
        #expect(detail.payment?.effect?.rows.map(\.value) == ["+0", "+1\u{00A0}000", "+500"])
        #expect(detail.payment?.effect?.note.hasSuffix("proto patří do roku 2025.") == true)
    }

    // MARK: What the payment leaves

    /// The dollar invoice paid on 2. 10. 2026 is worth 305 726,75 Kč, and the payment adds 1 702 Kč to the levies, so
    /// it leaves 304 024,75 Kč, which the detail writes in whole Kč.
    @Test func thePaymentShowsTheNetIncomeOfItsEffect() {
        let invoice = paidDollarInvoice

        let payment = detailOf(invoice, paymentEffect: effect(of: invoice, on: "2026-10-02")).payment

        #expect(payment?.netIncome == "304\u{00A0}025\u{00A0}Kč")
    }

    /// The row of the net income is there exactly when the section of the effect is: a payment whose effect is not
    /// known has neither.
    @Test func aPaymentWithoutItsEffectHasNoNetIncome() throws {
        let payment = try #require(detailOf(paidDollarInvoice).payment)

        #expect(payment.effect == nil)
        #expect(payment.netIncome == nil)
    }

    /// The payment waits for the rate of its day, so what it leaves is an estimate, and the sign says so before the
    /// figure: 306 501,65 Kč less 1 702 Kč is 304 799,65 Kč.
    @Test func aProvisionalPaymentShowsTheSignOfAnEstimateBeforeItsNet() {
        var invoice = paidDollarInvoice
        invoice.payment = .fixture(
            on: "2026-10-02", conversion: .cnbDaily, net: 30_650_165, vat: 0,
            rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true)

        let payment = detailOf(invoice, paymentEffect: effect(of: invoice, on: "2026-10-02")).payment

        #expect(payment?.netIncome == "≈\u{00A0}304\u{00A0}800\u{00A0}Kč")
        #expect(payment?.netIncome?.hasPrefix(PredictionBuilder.estimateSign) == true)
    }

    /// The payment of 220 000,00 Kč on 3. 2. 2026 brings the tax bonus, so the tax falls by 37 524 Kč and the social
    /// insurance rises by 4 123 Kč: the levies fall by 33 401 Kč, which the detail writes with the minus sign and not
    /// as "+−", and the payment leaves 253 401 Kč, more than it is worth.
    @Test func aPaymentThatLowersTheLeviesSaysSoWithTheMinusSign() throws {
        let invoice = crownInvoice(payment: .fixture(on: "2026-02-03", net: 22_000_000, vat: 0))
        let levies = ReceiptEffect(
            receipt: Receipt(
                day: civilDate("2026-02-03"), czkNetHalere: 22_000_000, czkVatHalere: 0, source: .invoice(11)),
            tax: -37_524, social: 4_123, health: 0, total: -33_401)

        let payment = try #require(detailOf(invoice, paymentEffect: levies).payment)

        #expect(payment.effect?.total == "\u{2212}33\u{00A0}401\u{00A0}Kč")
        #expect(payment.effect?.rows.map(\.value) == ["\u{2212}37\u{00A0}524", "+4\u{00A0}123", "+0"])
        #expect(payment.netIncome == "253\u{00A0}401\u{00A0}Kč")
    }

    /// A payment after the day shown still shows what it adds to the levies, as the list shows the net income of such
    /// an invoice, so it says what the payment leaves too: 4 500,00 Kč less 1 702 Kč. Dated before today it has no
    /// note, and dated after today it has the note and shows the same.
    @Test func aPaymentAfterTheDayShownStillShowsWhatItLeaves() {
        let before = crownInvoice(dueDate: "2026-10-30", payment: .fixture(on: "2026-10-15"))
        let after = crownInvoice(dueDate: "2026-10-30", payment: .fixture(on: "2026-10-20"))

        let early = detailOf(before, asOf: civilDate("2026-10-01"), paymentEffect: effect(of: before)).payment
        let late = detailOf(after, asOf: civilDate("2026-10-01"), paymentEffect: effect(of: after)).payment

        #expect(early?.laterNote == nil)
        #expect(early?.netIncome == "2\u{00A0}798\u{00A0}Kč")
        #expect(late?.laterNote == Self.laterNote)
        #expect(late?.netIncome == "2\u{00A0}798\u{00A0}Kč")
    }

    // MARK: What a payment would add

    @Test func anInvoiceThatIsNotPaidSaysRoughlyWhatItWouldAdd() {
        let invoice = crownInvoice(dueDate: "2026-10-30")
        let estimate = LevyEstimate(day: civilDate("2026-10-30"), incomeHalere: 450_000, effect: effect(of: invoice, on: "2026-10-30"))

        let detail = detailOf(invoice, estimate: estimate)

        // The income of 4 500,00 Kč less the levies of 1 702 Kč is 2 798 Kč, which is 2 800 Kč in hundreds.
        #expect(
            detail.estimate
                == "Až přijde platba, přibude k odvodům za rok 2026 zhruba 1\u{00A0}700\u{00A0}Kč (37,8\u{00A0}% z příjmu), pokud peníze dorazí do 30.\u{00A0}10.\u{00A0}2026."
                + " Čistý příjem z ní by byl zhruba 2\u{00A0}800\u{00A0}Kč."
        )
        #expect(detail.canPay == true)
        #expect(detail.payment == nil)
    }

    @Test func aDraftSaysWhatItWouldAddOnceIssuedAndPaid() {
        var draft = crownInvoice(dueDate: "2026-10-30", status: .draft)
        draft.id = 12
        let estimate = LevyEstimate(day: civilDate("2026-10-30"), incomeHalere: 450_000, effect: effect(of: draft, on: "2026-10-30"))

        let detail = detailOf(draft, estimate: estimate)

        #expect(
            detail.estimate
                == "Po vystavení a zaplacení přibude k odvodům za rok 2026 zhruba 1\u{00A0}700\u{00A0}Kč (37,8\u{00A0}% z příjmu), pokud peníze dorazí do 30.\u{00A0}10.\u{00A0}2026."
                + " Čistý příjem z ní by byl zhruba 2\u{00A0}800\u{00A0}Kč."
        )
    }

    @Test func anEstimateWithoutIncomeHasNoShare() {
        let invoice = crownInvoice(dueDate: "2026-10-30")
        let none = ReceiptEffect(
            receipt: Receipt(day: civilDate("2026-10-30"), czkNetHalere: 0, czkVatHalere: 0, source: .invoice(11)),
            tax: 0, social: 0, health: 0, total: 0)

        let detail = detailOf(invoice, estimate: LevyEstimate(day: civilDate("2026-10-30"), incomeHalere: 0, effect: none))

        #expect(
            detail.estimate
                == "Až přijde platba, přibude k odvodům za rok 2026 zhruba 0\u{00A0}Kč, pokud peníze dorazí do 30.\u{00A0}10.\u{00A0}2026."
                + " Čistý příjem z ní by byl zhruba 0\u{00A0}Kč."
        )
    }

    @Test func theEstimateIsRoundedToHundredsHalfUp() {
        let invoice = crownInvoice(dueDate: "2026-10-30")
        func estimate(total: Int64) -> String? {
            let levies = ReceiptEffect(
                receipt: Receipt(day: civilDate("2026-10-30"), czkNetHalere: 450_000, czkVatHalere: 0, source: .invoice(11)),
                tax: 0, social: 0, health: total, total: total)
            return detailOf(invoice, estimate: LevyEstimate(day: civilDate("2026-10-30"), incomeHalere: 450_000, effect: levies)).estimate
        }

        #expect(estimate(total: 1_949)?.contains("zhruba 1\u{00A0}900\u{00A0}Kč") == true)
        #expect(estimate(total: 1_950)?.contains("zhruba 2\u{00A0}000\u{00A0}Kč") == true)
    }

    /// The draft of 12 040 USD is expected on 30. 11. 2026 and is worth 256 692,80 Kč at 21,320. The levies are
    /// 97 057 Kč, so it would leave 159 635,80 Kč, which the note says in hundreds as it says the levies: the net is
    /// the last sentence of the note, after the one about a threshold when the income reaches one.
    @Test func theEstimateEndsWithTheNetIncomeRoundedToHundreds() {
        let draft = crownInvoice(dueDate: "2026-11-30", status: .draft)
        let day = civilDate("2026-11-30")
        var levies = ReceiptEffect(
            receipt: Receipt(day: day, czkNetHalere: 25_669_280, czkVatHalere: 0, source: .invoice(11)),
            tax: 0, social: 0, health: 97_057, total: 97_057)
        let levyNote =
            "Po vystavení a zaplacení přibude k odvodům za rok 2026 zhruba 97\u{00A0}100\u{00A0}Kč"
            + " (37,8\u{00A0}% z příjmu), pokud peníze dorazí do 30.\u{00A0}11.\u{00A0}2026."
        let net = " Čistý příjem z ní by byl zhruba 159\u{00A0}600\u{00A0}Kč."

        #expect(
            detailOf(draft, estimate: LevyEstimate(day: day, incomeHalere: 25_669_280, effect: levies)).estimate
                == levyNote + net)

        levies.crossings = [ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .whole)]
        let threshold =
            " Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."

        #expect(
            detailOf(draft, estimate: LevyEstimate(day: day, incomeHalere: 25_669_280, effect: levies)).estimate
                == levyNote + threshold + net)
    }

    /// The net is rounded to whole Kč, half up, as the list rounds it, and then to hundreds, half up, as the levies
    /// are: 159 649,50 Kč is 159 650 Kč and so 159 700 Kč, though 159 600 Kč is nearer, and 159 649,49 Kč is
    /// 159 600 Kč. A net below nothing, when the levies are more than the income, is rounded the same way.
    @Test(arguments: [
        (25_670_650 as Int64, 97_057 as Int64, "159\u{00A0}700\u{00A0}Kč"),
        (25_670_649, 97_057, "159\u{00A0}600\u{00A0}Kč"),
        (0, 1_234, "\u{2212}1\u{00A0}200\u{00A0}Kč"),
    ])
    func theNetOfTheEstimateIsRoundedToWholeKcAndThenToHundredsHalfUp(income: Int64, levies: Int64, net: String) {
        let draft = crownInvoice(dueDate: "2026-11-30", status: .draft)
        let effect = ReceiptEffect(
            receipt: Receipt(day: civilDate("2026-11-30"), czkNetHalere: income, czkVatHalere: 0, source: .invoice(11)),
            tax: 0, social: 0, health: levies, total: levies)

        let estimate = detailOf(
            draft, estimate: LevyEstimate(day: civilDate("2026-11-30"), incomeHalere: income, effect: effect)
        ).estimate

        #expect(estimate?.hasSuffix(" Čistý příjem z ní by byl zhruba \(net).") == true)
    }

    /// An invoice that is not paid and has no estimate, such as one in a currency that has neither a rate of the ČNB
    /// nor a rate of its own, says nothing of the levies it would add and nothing of what it would leave.
    @Test func anUnpaidInvoiceWithoutAnEstimateHasNoNetSentence() {
        var inPounds = Invoice.fixture(
            currency: CurrencyCode("GBP")!, dueDate: "2026-10-30", items: [.fixture("10", at: 7_000)],
            vatMode: .outsideCountry)
        let detail = detailOf(inPounds)

        #expect(detail.estimate == nil)
        #expect(detail.payment == nil)
        #expect(detail.canPay == true)
        // Nor does a draft that has none.
        inPounds.status = .draft
        #expect(detailOf(inPounds).estimate == nil)
    }

    // MARK: Why the levies take the share they do

    /// The payment of `day` in the year of the engine's threshold tests (`TaxEngineThresholdTests.year2026`), put on
    /// the invoice in dollars, and what the engine says it adds to the levies.
    private func realPayment(on day: String) throws -> (invoice: Invoice, effect: ReceiptEffect) {
        let effect = try TaxEngineThresholdTests.effect(on: day)
        var invoice = paidDollarInvoice
        invoice.payment = .fixture(on: day, conversion: .cnbDaily, net: effect.receipt.czkNetHalere, vat: 0)
        return (invoice, effect)
    }

    /// 7. 7.: the income of the year stays below the cap of the flat-rate expenses, so the note is the share alone.
    @Test func aPaymentBelowTheCapNamesItsShareAlone() throws {
        let (invoice, effect) = try realPayment(on: "2026-07-07")

        let note = detailOf(invoice, paymentEffect: effect).payment?.effect?.note

        #expect(
            note
                == "15,1\u{00A0}% z příjmu 288\u{00A0}806,00\u{00A0}Kč – peníze přišly 7.\u{00A0}7.\u{00A0}2026, proto patří do roku 2026."
        )
    }

    /// 2. 10.: the income passes 2 000 000 Kč, so the note says how much of the payment is past the cap, which is why
    /// the levies take 29,0 % of it and not 15 %.
    @Test func aPaymentThatStraddlesTheCapSaysHowMuchOfItIsPastIt() throws {
        let (invoice, effect) = try realPayment(on: "2026-10-02")

        let note = detailOf(invoice, paymentEffect: effect).payment?.effect?.note

        #expect(
            note
                == "29,0\u{00A0}% z příjmu 305\u{00A0}726,75\u{00A0}Kč – peníze přišly 2.\u{00A0}10.\u{00A0}2026, proto patří do roku 2026."
                + " Z platby je 187\u{00A0}271\u{00A0}Kč nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
        )
    }

    /// 15. 10.: the income was past the cap before the payment, so all of the payment is, and the levies take 37,8 % of
    /// it.
    @Test func aPaymentAboveTheCapSaysAllOfItIsPastIt() throws {
        let (invoice, effect) = try realPayment(on: "2026-10-15")

        let note = detailOf(invoice, paymentEffect: effect).payment?.effect?.note

        #expect(
            note
                == "37,8\u{00A0}% z příjmu 4\u{00A0}500,00\u{00A0}Kč – peníze přišly 15.\u{00A0}10.\u{00A0}2026, proto patří do roku 2026."
                + " Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
        )
    }

    /// Each threshold is named with the limit it starts at, and with the part of the payment past it or all of it.
    @Test(
        arguments: [
            (
                ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .part(187_271)),
                "Z platby je 187\u{00A0}271\u{00A0}Kč nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
            ),
            (
                ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .whole),
                "Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
            ),
            (
                ThresholdCrossing(threshold: .taxBand, limit: 1_762_812, extent: .part(28_871)),
                "Z platby je 28\u{00A0}871\u{00A0}Kč v 23% pásmu daně (základ daně nad 1\u{00A0}762\u{00A0}812\u{00A0}Kč)."
            ),
            (
                ThresholdCrossing(threshold: .taxBand, limit: 1_762_812, extent: .whole),
                "Celá platba je v 23% pásmu daně (základ daně nad 1\u{00A0}762\u{00A0}812\u{00A0}Kč)."
            ),
            (
                ThresholdCrossing(threshold: .socialMaximum, limit: 2_350_416, extent: .part(526_518)),
                "Z platby je 526\u{00A0}518\u{00A0}Kč nad stropem sociálního pojištění (vyměřovací základ 2\u{00A0}350\u{00A0}416\u{00A0}Kč),"
                    + " kde už sociální pojištění nepřibývá."
            ),
            (
                ThresholdCrossing(threshold: .socialMaximum, limit: 2_350_416, extent: .whole),
                "Celá platba je nad stropem sociálního pojištění (vyměřovací základ 2\u{00A0}350\u{00A0}416\u{00A0}Kč),"
                    + " kde už sociální pojištění nepřibývá."
            ),
            (
                ThresholdCrossing(threshold: .bonusIncome, limit: 134_400, extent: .part(115_600), bonus: 37_524),
                "Příjmy tím dosáhnou šestinásobku minimální mzdy (134\u{00A0}400\u{00A0}Kč),"
                    + " takže se vyplatí daňový bonus 37\u{00A0}524\u{00A0}Kč."
            ),
            (
                ThresholdCrossing(threshold: .bonusIncome, limit: 124_800, extent: .part(0), bonus: 100),
                "Příjmy tím dosáhnou šestinásobku minimální mzdy (124\u{00A0}800\u{00A0}Kč),"
                    + " takže se vyplatí daňový bonus 100\u{00A0}Kč."
            ),
        ] as [(ThresholdCrossing, String)])
    func eachThresholdIsNamedWithTheLimitItStartsAt(crossing: ThresholdCrossing, sentence: String) {
        var levies = effect(of: crownInvoice())
        levies.crossings = [crossing]

        #expect(InvoiceDetailBuilder.thresholdsText(of: levies) == sentence)
    }

    @Test func severalThresholdsAreNamedOneSentenceEachInTheirOrder() {
        var levies = effect(of: crownInvoice())
        levies.crossings = [
            ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .whole),
            ThresholdCrossing(threshold: .taxBand, limit: 1_762_812, extent: .part(28_871)),
        ]

        #expect(
            InvoiceDetailBuilder.thresholdsText(of: levies)
                == "Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
                + " Z platby je 28\u{00A0}871\u{00A0}Kč v 23% pásmu daně (základ daně nad 1\u{00A0}762\u{00A0}812\u{00A0}Kč)."
        )
    }

    /// The engine's family test of the bonus (`TaxEngineFamilyTests`): with the sample family, 120 000 Kč on 20. 1.
    /// 2026 and this payment of 130 000 Kč on 20. 2. take the income past six minimum wages, so the whole bonus of the
    /// children is paid. The detail says why the levies fall, and what it shows is the true change, the bonus included:
    /// 37 524 Kč less tax, 6 050 Kč more social and 139 Kč more health insurance.
    @Test func aPaymentThatBringsTheBonusSaysSoAndCountsIt() throws {
        let input = TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts)
        let effect = TaxEngine.effect(of: try #require(input.receipts.last), in: input)
        let invoice = crownInvoice(payment: .fixture(on: "2026-02-20", net: 13_000_000, vat: 0))

        let levies = try #require(detailOf(invoice, paymentEffect: effect).payment?.effect)

        #expect(levies.total == "\u{2212}31\u{00A0}335\u{00A0}Kč")
        #expect(levies.rows.map(\.value) == ["\u{2212}37\u{00A0}524", "+6\u{00A0}050", "+139"])
        #expect(
            levies.note
                == "\u{2212}24,1\u{00A0}% z příjmu 130\u{00A0}000,00\u{00A0}Kč"
                + " – peníze přišly 20.\u{00A0}2.\u{00A0}2026, proto patří do roku 2026."
                + " Příjmy tím dosáhnou šestinásobku minimální mzdy (134\u{00A0}400\u{00A0}Kč),"
                + " takže se vyplatí daňový bonus 37\u{00A0}524\u{00A0}Kč.")
    }

    @Test func withoutAThresholdThereIsNothingToExplain() {
        #expect(InvoiceDetailBuilder.thresholdsText(of: effect(of: crownInvoice())) == nil)
    }

    /// What a payment would add says it too, after the day the money is expected.
    @Test func anEstimatePastTheCapSaysSoAfterTheDay() {
        let invoice = crownInvoice(dueDate: "2026-10-30")
        var levies = effect(of: invoice, on: "2026-10-30")
        levies.crossings = [ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .whole)]

        let detail = detailOf(
            invoice, estimate: LevyEstimate(day: civilDate("2026-10-30"), incomeHalere: 450_000, effect: levies))

        #expect(
            detail.estimate
                == "Až přijde platba, přibude k odvodům za rok 2026 zhruba 1\u{00A0}700\u{00A0}Kč (37,8\u{00A0}% z příjmu), pokud peníze dorazí do 30.\u{00A0}10.\u{00A0}2026."
                + " Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem."
                + " Čistý příjem z ní by byl zhruba 2\u{00A0}800\u{00A0}Kč."
        )
    }

    // MARK: Invoices to check

    @Test func anInvoiceToCheckSaysWhyAndThatItIsNotCountedYet() {
        let invoice = crownInvoice(review: ReviewFlag(reason: "záporná částka"))

        let detail = detailOf(invoice)

        #expect(detail.statusLabel == "Ke kontrole")
        #expect(
            detail.reviewNote
                == "Ke kontrole: záporná částka. Faktura se nezapočítává do příjmů, dokud ji nevyřešíte"
                + " – označte ji jako uhrazenou nebo ji smažte."
        )
        // It can be marked paid, which resolves it.
        #expect(detail.canPay == true)
        // Nothing is said about levies it does not add to.
        #expect(detail.estimate == nil)
    }

    @Test func anInvoiceToCheckThatIsPaidAlreadyIsNotToldToBeMarkedPaid() {
        let invoice = crownInvoice(
            review: ReviewFlag(reason: "zrušeno ve Fakturoidu"), payment: .fixture(on: "2026-10-15"))

        let detail = detailOf(invoice)

        #expect(
            detail.reviewNote
                == "Ke kontrole: zrušeno ve Fakturoidu. Faktura se nezapočítává do příjmů, dokud ji nevyřešíte"
                + " – smažte ji.")
        // There is no payment left to record.
        #expect(detail.canPay == false)
    }

    // MARK: Deleting

    @Test func deletingAPaidInvoiceNamesTheIncomeAndTheLevyDrop() {
        let invoice = crownInvoice(payment: .fixture(on: "2026-10-15"))

        let summary = InvoiceDetailBuilder.deletion(of: invoice, effect: effect(of: invoice))

        #expect(summary.title == "Smazat fakturu 20260901?")
        #expect(summary.subtitle == "Alfa Systems s.r.o. · 5\u{00A0}445,00\u{00A0}Kč")
        #expect(summary.number == "20260901")
        #expect(
            summary.lines == [
                "Faktura 20260901 (Alfa Systems s.r.o., 5\u{00A0}445,00\u{00A0}Kč) zmizí ze seznamu faktur, z přehledů i z výpočtu odvodů.",
                "Platba z 15.\u{00A0}10.\u{00A0}2026 přestane být příjmem: příjem za rok 2026 klesne o 4\u{00A0}500,00\u{00A0}Kč a odvody o 1\u{00A0}702\u{00A0}Kč.",
                "Pokud jste fakturu poslali odběrateli nebo ji uvedli v přiznání k DPH, zůstane tam – opravte to i tam.",
            ])
    }

    @Test func aDraftHasNeitherAPaymentNorACopySentToTheClient() {
        let draft = crownInvoice(status: .draft)

        let summary = InvoiceDetailBuilder.deletion(of: draft, effect: nil)

        #expect(summary.lines.count == 1)
        #expect(summary.lines[0].hasPrefix("Faktura 20260901 (Alfa Systems s.r.o., 5\u{00A0}445,00\u{00A0}Kč) zmizí"))
    }

    @Test func anImportedInvoiceWouldComeBackWithTheNextImport() {
        var invoice = crownInvoice()
        invoice.source = .imported(fakturoidID: "F-1", fingerprint: "row", changedInApp: false)

        let summary = InvoiceDetailBuilder.deletion(of: invoice, effect: nil)

        #expect(
            summary.lines == [
                "Faktura 20260901 (Alfa Systems s.r.o., 5\u{00A0}445,00\u{00A0}Kč) zmizí ze seznamu faktur, z přehledů i z výpočtu odvodů.",
                "Pokud jste fakturu poslali odběrateli nebo ji uvedli v přiznání k DPH, zůstane tam – opravte to i tam.",
                "Při dalším importu stejného exportu z Fakturoidu by se faktura přidala znovu.",
            ])
    }

    @Test func aPaymentThatWasNeverIncomeIsNotSaidToStopBeingIncome() {
        // An invoice to check does not count: its payment, if it had one, adds nothing to the levies now.
        var invoice = crownInvoice(review: ReviewFlag(reason: "neznámý stav faktury"), payment: .fixture(on: "2026-10-15"))
        invoice.id = 11

        let summary = InvoiceDetailBuilder.deletion(of: invoice, effect: nil)

        #expect(summary.lines.contains { $0.hasPrefix("Platba z") } == false)
    }

    @Test func aPaymentInDollarsNamesTheCrownsItWasWorth() {
        let invoice = paidDollarInvoice

        let summary = InvoiceDetailBuilder.deletion(of: invoice, effect: effect(of: invoice, on: "2026-10-02"))

        #expect(
            summary.lines[1]
                == "Platba z 2.\u{00A0}10.\u{00A0}2026 přestane být příjmem: příjem za rok 2026 klesne o 305\u{00A0}726,75\u{00A0}Kč a odvody o 1\u{00A0}702\u{00A0}Kč."
        )
        #expect(summary.subtitle == "Bravo Labs, Inc. · 14\u{00A0}350,00\u{00A0}USD")
    }

    // MARK: Removing a payment

    /// The invoice 20260601 of the sample year: 13 720,00 USD paid on 7. 7. 2026 at 21,050, which is 288 806,00 Kč of
    /// income. The effect is an invented one; the step names only its total, in whole Kč.
    @Test func theRemovalSummaryNamesWhatChanges() throws {
        let invoice = try #require(SampleYear2026.invoices.first { $0.number == "20260601" })

        let summary = InvoiceDetailBuilder.paymentRemoval(of: invoice, effect: effect(of: invoice, on: "2026-07-07"))

        #expect(summary.title == "Odebrat platbu faktury 20260601?")
        #expect(
            summary.subtitle == "Bravo Labs, Inc. · zaplaceno 7.\u{00A0}7.\u{00A0}2026 · 13\u{00A0}720,00\u{00A0}USD")
        #expect(summary.number == "20260601")
        #expect(
            summary.lines == [
                "Faktura bude znovu nezaplacená a půjde upravit.",
                "Příjem za rok 2026 klesne o 288\u{00A0}806,00\u{00A0}Kč a odvody o 1\u{00A0}702\u{00A0}Kč.",
                "Pokud jste platbu už uvedli v přiznání nebo v přehledech, opravte ji i tam.",
            ])

        // Without the effect, the sentence about the income ends after the income.
        let withoutEffect = InvoiceDetailBuilder.paymentRemoval(of: invoice, effect: nil)
        #expect(
            withoutEffect.lines == [
                "Faktura bude znovu nezaplacená a půjde upravit.",
                "Příjem za rok 2026 klesne o 288\u{00A0}806,00\u{00A0}Kč.",
                "Pokud jste platbu už uvedli v přiznání nebo v přehledech, opravte ji i tam.",
            ])
    }

    @Test func theRemovalNamesTheYearOfThePaymentAndTheCrownsOfAPaymentInCrowns() {
        // Issued on 30. 9. 2026 and paid on 4. 1. 2027: the income of 2027 drops, without the VAT.
        let invoice = crownInvoice(payment: .fixture(on: "2027-01-04"))

        let summary = InvoiceDetailBuilder.paymentRemoval(of: invoice, effect: nil)

        #expect(
            summary.subtitle == "Alfa Systems s.r.o. · zaplaceno 4.\u{00A0}1.\u{00A0}2027 · 5\u{00A0}445,00\u{00A0}Kč")
        #expect(summary.lines.contains("Příjem za rok 2027 klesne o 4\u{00A0}500,00\u{00A0}Kč."))
    }

    @Test func thePaymentOfAnInvoiceToCheckIsNotSaidToLowerTheIncome() {
        // An invoice to check does not count: removing its payment takes nothing from the income of its year.
        let invoice = crownInvoice(
            review: ReviewFlag(reason: "neznámý stav faktury"), payment: .fixture(on: "2026-10-15"))

        let summary = InvoiceDetailBuilder.paymentRemoval(of: invoice, effect: effect(of: invoice))

        #expect(
            summary.lines == [
                "Faktura bude znovu nezaplacená a půjde upravit.",
                "Pokud jste platbu už uvedli v přiznání nebo v přehledech, opravte ji i tam.",
            ])
    }
}
