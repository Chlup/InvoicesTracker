import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Rozpočet: what a load reads and shows, how the slider, the typed fields, the checkbox and the choice of
/// the remainder change the split, when the split is saved in the settings of the app, and how the source and the
/// invoice are chosen. The data is the editor's fixture as of 17. 10. 2026, whose average net income is 187 111 Kč a
/// month and whose latest paid invoice is 20260902. A model saves 500 ms after the last change unless a test says
/// otherwise; the tests that watch the wait give it a `ManualDelay`. In every expected string `\u{00A0}` is the
/// no-break space.
@Suite(.settlesBackups)
@MainActor
struct BudgetModelTests {
    // MARK: Helpers

    /// The hint under a % field whose text is no percentage.
    private let percentHint = BudgetHint(
        text: "Zadejte procenta, nejvýš s jedním desetinným místem.", tone: .attention)

    /// The hint under a Kč field whose text is no amount in whole Kč.
    private let amountHint = BudgetHint(text: "Zadejte částku v celých korunách.", tone: .attention)

    /// A model of `f`'s app that has loaded, which waits for `delay` before it saves where one is given.
    private func loadedModel(of f: EditorFixture, delay: ManualDelay? = nil) async -> BudgetModel {
        let model: BudgetModel
        if let delay {
            model = BudgetModel(app: f.app, saveDelay: .milliseconds(500), wait: delay.wait)
        } else {
            model = BudgetModel(app: f.app)
        }
        await model.load()
        return model
    }

    /// The row of `category` as `model` shows it, or nil while it shows nothing.
    private func row(_ category: BudgetCategory, of model: BudgetModel) -> BudgetRow? {
        model.data?.rows.first { $0.category == category }
    }

    /// The holding of `category` in the split stored in the data, as read from the database itself.
    private func storedHolding(_ category: BudgetCategory, in f: EditorFixture) async throws -> BudgetHolding {
        try await f.database.appSettings().budget.split.holding(of: category)
    }

    // MARK: Loading

    @Test func aNewAppStartsWithAnEmptyBudget() async throws {
        try await EditorFixture.with { f in
            #expect(f.app.appSettings.budget == BudgetSettings())
            let model = BudgetModel(app: f.app)
            #expect(model.data == nil)

            await model.load()

            let data = try #require(model.data)
            #expect(model.errorText == nil)
            #expect(data.source == .actual)
            #expect(data.keyFigure.figure == "187\u{00A0}111\u{00A0}Kč")
            #expect(data.remainder == .spending)
            #expect(data.rows.map(\.mode) == [.fixed, .remainder, .share, .share])
            #expect(data.rows.map(\.percentText) == ["0,0\u{00A0}%", "100,0\u{00A0}%", "0,0", "0,0"])
            #expect(data.rows.map(\.amountText) == ["0", "187\u{00A0}111\u{00A0}Kč", "0", "0"])
            #expect(data.rows.allSatisfy { $0.hint == nil })
            #expect(!model.hasUnsavedInput)
        }
    }

    @Test func aPastYearShowsTheActualAverageForAPrediction() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            await model.chooseSource(.prediction)
            #expect(model.data?.source == .prediction)

            f.app.selectYear(2025)
            await model.load()

            // 2025 is over, so its estimate is what it was: the screen shows Skutečnost, Přehled's average of the whole
            // year (the minimum insurance of a year without income), and the choice stays saved.
            let data = try #require(model.data)
            let average = try await f.app.averageNetIncome()
            #expect(data.source == .actual)
            #expect(data.keyFigure.eyebrow == "Čistý příjem průměrně za měsíc")
            #expect(data.keyFigure.figure == CzechFormat.wholeKc(average.monthlyKc))
            #expect(data.keyFigure.sentence == "Průměr za celý rok 2025.")
            #expect(data.sources.first { $0.value == .prediction }?.isEnabled == false)
            #expect(f.app.appSettings.budget.source == .prediction)

            f.app.selectYear(2026)
            await model.load()

            #expect(model.data?.source == .prediction)
        }
    }

    @Test func aFailedLoadShowsTheLineAndKeepsTheSplit() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            model.slide(.savings, toPercent: 15)
            await model.saveNow()
            let saved = f.app.appSettings.budget

            // The data is locked.
            f.app.database = nil
            await model.load()

            #expect(model.errorText == "Rozpočet se nepodařilo načíst.")
            #expect(BudgetModel.loadFailureText == "Rozpočet se nepodařilo načíst.")
            #expect(model.data == nil)
            #expect(f.app.appSettings.budget == saved)

            // Once it is open again, the line goes and the split is the one saved.
            f.app.database = f.database
            await model.load()

            #expect(model.errorText == nil)
            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(f.app.appSettings.budget == saved)
        }
    }

    @Test func aLoadKeepsTheChangesThatWaitToBeSaved() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)
            model.slide(.savings, toPercent: 15)

            // A load that comes before the save, as after a write elsewhere, does not undo the change.
            await model.load()

            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(f.app.appSettings.budget == BudgetSettings())
            #expect(model.hasUnsavedInput)
            await model.saveNow()
            #expect(f.app.appSettings.budget.split.holding(of: .savings) == .share(decimal("0.15")))
        }
    }

    // MARK: Editing and saving

    @Test func aSlideIsSavedAfterTheDelayAndOnQuit() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)

            model.slide(.savings, toPercent: 10)
            model.slide(.savings, toPercent: 15)

            // The screen shows the share at once; only the remainder gives way.
            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(row(.savings, of: model)?.amountText == "28\u{00A0}067")
            #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")
            #expect(model.hasUnsavedInput)
            try await waitUntil { delay.started == 2 && delay.armed == 1 }
            #expect(f.app.appSettings.budget == BudgetSettings())

            // The end of the wait saves it.
            #expect(delay.fire())

            try await waitUntil { !model.hasUnsavedInput }
            #expect(f.app.appSettings.budget.split.holding(of: .savings) == .share(decimal("0.15")))
            #expect(try await storedHolding(.savings, in: f) == .share(decimal("0.15")))

            // A quit does not wait for the delay.
            model.slide(.investments, toPercent: 10)
            #expect(f.app.hasUnsavedInput)

            await f.app.flushUnsavedInput()

            #expect(!f.app.hasUnsavedInput)
            #expect(try await storedHolding(.investments, in: f) == .share(decimal("0.1")))
            #expect(try await storedHolding(.savings, in: f) == .share(decimal("0.15")))
        }
    }

    @Test func theEndOfASlideSavesWithoutTheDelay() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)
            model.slide(.savings, toPercent: 15)

            model.endSliding(.savings)

            try await waitUntil { !model.hasUnsavedInput }
            #expect(try await storedHolding(.savings, in: f) == .share(decimal("0.15")))
        }
    }

    @Test func typedKorunyOnAShareSaveTheShare() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)

            model.typeAmount("30 000", for: .savings)

            // The field keeps what was typed, the share follows it and the remainder gives way.
            #expect(row(.savings, of: model)?.amountText == "30 000")
            #expect(row(.savings, of: model)?.percentText == "16,0")
            #expect(row(.spending, of: model)?.amountText == "157\u{00A0}111\u{00A0}Kč")

            model.endEditing(.savings)
            await model.saveNow()

            // The share is stored so that exactly the amount typed comes out.
            #expect(row(.savings, of: model)?.amountText == "30\u{00A0}000")
            let share = Decimal(30_000) / Decimal(187_111)
            #expect(f.app.appSettings.budget.split.holding(of: .savings) == .share(share))
            let stored = try await storedHolding(.savings, in: f)
            #expect(stored == .share(share))
        }
    }

    @Test func junkInTheFieldsKeepsTheLastValueAndShowsAMessage() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            model.typePercent("15", for: .savings)
            #expect(row(.savings, of: model)?.hint == nil)

            for junk in ["abc", "-5", "15,55"] {
                model.typePercent(junk, for: .savings)

                #expect(row(.savings, of: model)?.percentText == junk)
                #expect(row(.savings, of: model)?.hint == percentHint)
                #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")
            }

            // An emptied field keeps the value and says nothing.
            model.typePercent("", for: .savings)
            #expect(row(.savings, of: model)?.percentText == "")
            #expect(row(.savings, of: model)?.hint == nil)
            #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")

            // The end of editing shows the value again.
            model.endEditing(.savings)
            #expect(row(.savings, of: model)?.percentText == "15,0")

            model.typeAmount("20 000", for: .costs)
            model.typeAmount("1e9", for: .costs)

            #expect(row(.costs, of: model)?.amountText == "1e9")
            #expect(row(.costs, of: model)?.hint == amountHint)
            #expect(row(.spending, of: model)?.amountText == "139\u{00A0}044\u{00A0}Kč")

            model.typeAmount("", for: .costs)
            #expect(row(.costs, of: model)?.hint == nil)
            #expect(row(.spending, of: model)?.amountText == "139\u{00A0}044\u{00A0}Kč")

            model.endEditing(.costs)
            #expect(row(.costs, of: model)?.amountText == "20\u{00A0}000")
            await model.saveNow()

            let stored = try await f.database.appSettings().budget.split
            #expect(stored.holding(of: .costs) == .fixed(20_000))
            #expect(stored.holding(of: .savings) == .share(decimal("0.15")))
        }
    }

    @Test func tickingTheCheckboxAndPickingTheRemainderChangeNoNumberAndAreSaved() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)
            model.slide(.savings, toPercent: 15)

            model.toggleFixed(.savings)

            #expect(row(.savings, of: model)?.mode == .fixed)
            #expect(row(.savings, of: model)?.amountText == "28\u{00A0}067")
            #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")

            model.chooseRemainder(.investments)

            let data = try #require(model.data)
            #expect(data.remainder == .investments)
            #expect(row(.spending, of: model)?.mode == .share)
            #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044")
            #expect(row(.investments, of: model)?.amountText == "0\u{00A0}Kč")
            #expect(f.app.appSettings.budget == BudgetSettings())

            // Both are changes like the others: they are saved when the wait is over.
            try await waitUntil { delay.armed == 1 }
            #expect(delay.fire())

            try await waitUntil { !model.hasUnsavedInput }
            let saved = try await f.database.appSettings().budget.split
            #expect(saved.remainder == .investments)
            #expect(saved.holding(of: .savings) == .fixed(28_067))
            #expect(saved.holding(of: .spending) == .share(Decimal(159_044) / Decimal(187_111)))
        }
    }

    // MARK: Sources

    @Test func switchingSourcesKeepsTheShares() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            model.slide(.savings, toPercent: 15)
            model.typeAmount("20 000", for: .costs)
            model.endEditing(.costs)

            await model.chooseSource(.invoice)

            // The choice and the changes before it are saved at once.
            #expect(model.data?.source == .invoice)
            #expect(f.app.appSettings.budget.source == .invoice)
            #expect(try await f.database.appSettings().budget.source == .invoice)
            #expect(!model.hasUnsavedInput)
            let chosen = try #require(try await f.app.budgetInvoices().first { $0.invoice.number == "20260902" })
            let net = max(0, try #require(chosen.incomeKc) - (chosen.leviesKc ?? 0))
            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(
                row(.savings, of: model)?.amountText
                    == CzechFormat.grouped(DecimalMath.halfUp(Decimal(net) * decimal("0.15"))))
            #expect(row(.costs, of: model)?.amountText == "20\u{00A0}000")

            await model.chooseSource(.prediction)

            #expect(model.data?.source == .prediction)
            #expect(f.app.appSettings.budget.source == .prediction)
            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(row(.costs, of: model)?.amountText == "20\u{00A0}000")

            await model.chooseSource(.actual)

            #expect(model.data?.source == .actual)
            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(row(.savings, of: model)?.amountText == "28\u{00A0}067")
            #expect(row(.spending, of: model)?.amountText == "139\u{00A0}044\u{00A0}Kč")
            let saved = try await f.database.appSettings().budget.split
            #expect(saved.holding(of: .savings) == .share(decimal("0.15")))
            #expect(saved.holding(of: .costs) == .fixed(20_000))
        }
    }

    @Test func aChosenInvoiceIsRemembered() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            let listed = try await f.app.budgetInvoices()
            let august = try #require(listed.first { $0.invoice.number == "20260801" })

            // Picking an invoice from Skutečnost goes to Faktura with it.
            await model.chooseInvoice(id: august.invoice.id)

            #expect(model.data?.source == .invoice)
            #expect(model.data?.invoicePicker?.number == "20260801")
            #expect(f.app.appSettings.budget.invoiceID == august.invoice.id)
            #expect(f.app.appSettings.budget.source == .invoice)
            #expect(try await f.database.appSettings().budget.invoiceID == august.invoice.id)

            // The screen opened again shows it.
            let again = await loadedModel(of: f)
            #expect(again.data?.invoicePicker?.number == "20260801")
        }
    }

    @Test(arguments: [false, true])
    func aChosenInvoiceThatLeavesTheListFallsBackWithoutForgettingTheChoice(deleted: Bool) async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            let listed = try await f.app.budgetInvoices()
            let august = try #require(listed.first { $0.invoice.number == "20260801" })
            await model.chooseInvoice(id: august.invoice.id)
            #expect(model.data?.invoicePicker?.number == "20260801")

            if deleted {
                try await f.database.deleteInvoice(id: august.invoice.id)
            } else {
                var invoice = try await f.stored(august.invoice.id)
                invoice.review = ReviewFlag(reason: "zrušeno ve Fakturoidu")
                try await f.database.saveInvoice(invoice)
            }
            await f.app.didWrite()
            await model.load()

            // The latest paid invoice is shown, and the choice stays for when the invoice comes back.
            #expect(model.data?.source == .invoice)
            #expect(model.data?.invoicePicker?.number == "20260902")
            #expect(f.app.appSettings.budget.invoiceID == august.invoice.id)
            #expect(try await f.database.appSettings().budget.invoiceID == august.invoice.id)

            // A change of the split keeps it too.
            model.slide(.savings, toPercent: 15)
            await model.saveNow()
            #expect(try await f.database.appSettings().budget.invoiceID == august.invoice.id)
        }
    }

    // MARK: Relaunch

    @Test func theSplitSurvivesARelaunch() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            let listed = try await f.app.budgetInvoices()
            let august = try #require(listed.first { $0.invoice.number == "20260801" })
            model.typeAmount("20 000", for: .costs)
            model.endEditing(.costs)
            model.slide(.savings, toPercent: 15)
            model.chooseRemainder(.investments)
            await model.chooseInvoice(id: august.invoice.id)
            let saved = f.app.appSettings.budget
            #expect(saved.split.remainder == .investments)

            await f.database.close()
            let reopened = makeAppModel(in: f.directory, clock: f.clock)
            await reopened.launch()

            #expect(reopened.appSettings.budget == saved)
            let again = BudgetModel(app: reopened)
            await again.load()
            let data = try #require(again.data)
            #expect(data.source == .invoice)
            #expect(data.invoicePicker?.number == "20260801")
            #expect(data.remainder == .investments)
            #expect(row(.costs, of: again)?.amountText == "20\u{00A0}000")
            #expect(row(.savings, of: again)?.percentText == "15,0")
        }
    }
}
