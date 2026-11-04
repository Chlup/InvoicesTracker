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

    /// Writes the months of 2026 without the health insurance minimum as the text the table keeps them in, which is how
    /// the data is changed outside the app: "13", a month no form saves, makes the computation of the year refuse it.
    private nonisolated func storeHealthExemptMonths(_ text: String, in database: Database) async throws {
        try await database.write { connection in
            try connection.run(
                "UPDATE year_settings SET health_exempt_months = ? WHERE year = ?", [.text(text), .integer(2026)])
        }
    }

    /// Ends the wait of the hint of a refused text, which must be the only wait there is, and waits until `model`
    /// shows `hint` under the row of `category`.
    private func pauseTyping(
        _ delay: ManualDelay, until hint: BudgetHint, under category: BudgetCategory, of model: BudgetModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await waitUntil(sourceLocation: sourceLocation) { delay.armed == 1 }
        #expect(delay.fire(), sourceLocation: sourceLocation)
        try await waitUntil(sourceLocation: sourceLocation) { row(category, of: model)?.hint == hint }
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

    @Test func aFigureThatCannotBeWorkedOutLeavesNothingToDivideAndTheSplitEditable() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            // The computation of 2026 refuses what the data holds now, so neither its average nor its estimate can be
            // worked out, while its invoices can still be listed.
            try await storeHealthExemptMonths("13", in: f.database)

            await model.load()

            let data = try #require(model.data)
            #expect(model.errorText == nil)
            #expect(data.source == .actual)
            #expect(data.keyFigure.figure == "—")
            #expect(row(.spending, of: model)?.amountText == "—")

            // The shares can still be set; there is no amount to show for them.
            model.slide(.savings, toPercent: 15)

            #expect(row(.savings, of: model)?.percentText == "15,0")
            #expect(row(.savings, of: model)?.amountText == "—")
            await model.saveNow()
            let stored = try await storedHolding(.savings, in: f)
            #expect(stored == .share(decimal("0.15")))

            // Odhad za rok has no figure either.
            await model.chooseSource(.prediction)

            #expect(model.errorText == nil)
            #expect(model.data?.source == .prediction)
            #expect(model.data?.keyFigure.figure == "—")
            #expect(row(.savings, of: model)?.percentText == "15,0")
        }
    }

    /// Only the newest load shows what it read. Here the older one, for Odhad za rok, waits for the rates of the year
    /// from the server while Skutečnost is chosen and loaded; when it ends after all, it leaves the screen as the newer
    /// load made it.
    @Test func aLoadThatEndsLateNeverReplacesANewerOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let app = makeAppModel(in: directory, http: GatedHTTPClient(base: StubHTTPClient(), gate: gate))
        try await startFresh(app)
        try await PredictionSample.store(in: app)
        let database = try #require(app.database)
        // Without the rates the estimate asks the server for them, and the gate holds the request.
        try await database.execute("DELETE FROM cnb_rate")
        await app.updateAppSettings { $0.budget.source = .prediction }
        let model = BudgetModel(app: app)
        let older = Task { await model.load() }
        await gate.untilARequestWaits()

        let newer = Task { await model.chooseSource(.actual) }
        try await waitUntil { model.data != nil }
        let shown = try #require(model.data)
        #expect(shown.source == .actual)
        await gate.open()
        await older.value
        await newer.value

        #expect(model.data == shown)
        #expect(model.errorText == nil)
        #expect(app.appSettings.budget.source == .actual)
    }

    /// A choice of the source is saved at once and then loads the figures of the new source. Until they come, the
    /// screen builds and changes the split from the figures it has and the source they were read for, so that a change
    /// made in the meantime works out from what the screen shows: ticking "pevná částka" keeps the amount shown.
    @Test func aChangeWhileAnotherSourceLoadsWorksFromTheFiguresShown() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            model.slide(.savings, toPercent: 15)
            #expect(row(.savings, of: model)?.amountText == "28\u{00A0}067")

            // The choice runs until it waits for its save, before it loads.
            let choice = Task.immediate { await model.chooseSource(.invoice) }
            model.toggleFixed(.savings)

            #expect(row(.savings, of: model)?.mode == .fixed)
            #expect(row(.savings, of: model)?.amountText == "28\u{00A0}067")
            #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")

            await choice.value

            #expect(model.data?.source == .invoice)
            #expect(row(.savings, of: model)?.amountText == "28\u{00A0}067")
            await model.saveNow()
            let saved = try await f.database.appSettings().budget
            #expect(saved.source == .invoice)
            #expect(saved.split.holding(of: .savings) == .fixed(28_067))
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

    /// SwiftUI hands the text of a field to the model as its editing ends, also when nothing was typed into it. That
    /// text is the value as the field shows it, rounded, and changes nothing: a share set from koruny keeps its exact
    /// share when its % field and then its Kč field hand their texts back, a share set in percent keeps it when its Kč
    /// field does, and so does a fixed amount.
    @Test func theTextAFieldShowsChangesNothingWhenItIsHandedBack() async throws {
        try await EditorFixture.with { f in
            let model = await loadedModel(of: f)
            model.typeAmount("30 000", for: .savings)
            model.endEditing(.savings)
            model.typePercent("15", for: .investments)
            model.endEditing(.investments)
            model.typeAmount("20 000", for: .costs)
            model.endEditing(.costs)
            await model.saveNow()
            let saved = f.app.appSettings.budget
            #expect(saved.split.holding(of: .savings) == .share(Decimal(30_000) / Decimal(187_111)))
            #expect(row(.savings, of: model)?.percentText == "16,0")

            for field in [
                BudgetField.percent(.savings), .amount(.savings), .amount(.investments), .amount(.costs),
            ] {
                let shown = try #require(row(field.category, of: model))
                if case .percent = field {
                    model.typePercent(shown.percentText, for: field.category)
                } else {
                    model.typeAmount(shown.amountText, for: field.category)
                }
                model.endEditing(field.category)

                #expect(!model.hasUnsavedInput, "\(field)")
                #expect(row(field.category, of: model) == shown, "\(field)")
            }
            await model.saveNow()
            #expect(f.app.appSettings.budget == saved)
            #expect(try await f.database.appSettings().budget == saved)
        }
    }

    @Test func junkInTheFieldsKeepsTheLastValueAndShowsAMessage() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)
            model.typePercent("15", for: .savings)
            #expect(row(.savings, of: model)?.hint == nil)
            // Nothing waits to be saved, so the only wait from now on is the one of the hint.
            await model.saveNow()

            for junk in ["abc", "-5", "15,55"] {
                model.typePercent(junk, for: .savings)

                #expect(row(.savings, of: model)?.percentText == junk)
                #expect(row(.savings, of: model)?.hint == nil)
                #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")

                // Once the typing pauses, the field says what it takes; the value is still the last valid one.
                try await pauseTyping(delay, until: percentHint, under: .savings, of: model)

                #expect(row(.savings, of: model)?.percentText == junk)
                #expect(row(.spending, of: model)?.amountText == "159\u{00A0}044\u{00A0}Kč")

                // A valid text takes the hint away at once.
                model.typePercent("15", for: .savings)
                #expect(row(.savings, of: model)?.hint == nil)
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
            await model.saveNow()
            model.typeAmount("1e9", for: .costs)
            try await pauseTyping(delay, until: amountHint, under: .costs, of: model)

            #expect(row(.costs, of: model)?.amountText == "1e9")
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

    @Test func aRefusedTextSaysSoOnlyOnceTheTypingPauses() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)

            model.typeAmount("30 0", for: .savings)

            #expect(row(.savings, of: model)?.amountText == "30 0")
            #expect(row(.savings, of: model)?.hint == nil)
            #expect(row(.spending, of: model)?.amountText == "187\u{00A0}111\u{00A0}Kč")
            try await waitUntil { delay.started == 1 && delay.armed == 1 }

            // Every key starts the wait again.
            model.typeAmount("30 00", for: .savings)

            try await waitUntil { delay.started == 2 && delay.cancelled == 1 && delay.armed == 1 }
            #expect(row(.savings, of: model)?.hint == nil)

            // The pause ends the wait: now the field says what it takes, and the value is the one it had.
            #expect(delay.fire())

            try await waitUntil { row(.savings, of: model)?.hint == amountHint }
            #expect(row(.savings, of: model)?.amountText == "30 00")
            #expect(row(.spending, of: model)?.amountText == "187\u{00A0}111\u{00A0}Kč")
            #expect(f.app.appSettings.budget == BudgetSettings())
        }
    }

    @Test func aRefusedTextOnTheWayToAValidOneNeverShowsTheHint() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)
            model.typeAmount("30 0", for: .savings)
            try await waitUntil { delay.armed == 1 }

            model.typeAmount("30 000", for: .savings)

            // The valid text is taken at once, and the wait of the hint goes: only the one of the save is left.
            #expect(row(.savings, of: model)?.hint == nil)
            #expect(row(.spending, of: model)?.amountText == "157\u{00A0}111\u{00A0}Kč")
            try await waitUntil { delay.started == 2 && delay.cancelled == 1 && delay.armed == 1 }
            #expect(delay.fire())

            try await waitUntil { !model.hasUnsavedInput }
            #expect(row(.savings, of: model)?.hint == nil)
            #expect(delay.armed == 0)
            let stored = try await storedHolding(.savings, in: f)
            #expect(stored == .share(Decimal(30_000) / Decimal(187_111)))
        }
    }

    @Test func leavingAFieldDropsTheHintThatWaits() async throws {
        try await EditorFixture.with { f in
            let delay = ManualDelay()
            let model = await loadedModel(of: f, delay: delay)
            model.typeAmount("30 0", for: .savings)
            try await waitUntil { delay.armed == 1 }

            model.endEditing(.savings)

            try await waitUntil { delay.cancelled == 1 && delay.armed == 0 }
            #expect(row(.savings, of: model)?.amountText == "0")
            #expect(row(.savings, of: model)?.hint == nil)
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

    // MARK: The app

    /// The app holds the model of Rozpočet (`AppModel.budgetModel`), which so holds the app weakly: the app and its
    /// data go when nothing else holds them, also while a change of the split waits to be saved. What is left of the
    /// model has no data to read, and says so.
    @Test func theAppIsNotKeptAliveByTheBudgetItHolds() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        weak var released: AppModel?
        var held: BudgetModel?
        do {
            let app = makeAppModel(in: directory)
            try await startFresh(app)
            held = app.budgetModel
            await held?.load()
            // A change that waits to be saved does not hold the app either.
            held?.slide(.savings, toPercent: 15)
            released = app
            await app.database?.close()
        }

        #expect(released == nil)
        let orphan = try #require(held)
        await orphan.load()
        #expect(orphan.errorText == BudgetModel.loadFailureText)
        await orphan.saveNow()
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
