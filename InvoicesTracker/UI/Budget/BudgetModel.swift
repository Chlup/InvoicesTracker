import Foundation
import Observation

/// The model of Rozpočet: loads the net income the budget divides and turns it, with the choices of the person, into
/// view data (`BudgetBuilder`), and keeps those choices – the split, the source and the chosen invoice – in the
/// settings of the app (`AppSettings.budget`), which every year shares. The app holds the one model of the screen
/// (`AppModel.budgetModel`), and the model holds the app weakly.
///
/// - A load reads only the source the screen shows (`BudgetBuilder.source(of:)`): for Skutečnost Přehled's average
///   net income of the selected year (`AppModel.averageNetIncome()`), for Odhad za rok the prediction of the year
///   (`AppModel.predictionOutcome(year:)`, which only the current year has: a past year shows Skutečnost, so its
///   average is read instead), and for Faktura the invoices of the year (`AppModel.budgetInvoices()`). It takes the
///   choices as the settings hold them, unless changes made on the screen wait to be saved, which win. The screen
///   loads again whenever what the data depends on changes (`AppModel.reloadKey`). Only the newest load shows its
///   result, and the data of the last one stays until then, so that the screen does not flash empty. A figure that
///   cannot be worked out – the average or the prediction – is logged (the domain and the code of the error alone)
///   and leaves nothing to divide: the amounts are "—" and the split can still be changed. A load that fails
///   otherwise – the data is locked, or the invoices cannot be listed – is logged too and shows a line in place of
///   the data, under the row of the sources as the choices are (`failedSourceRow`), so that another source can be
///   chosen. A load that is cancelled keeps what was shown.
/// - A change of the split – the slider, a typed percentage or amount, the checkbox "pevná částka" and "Zbytek
///   dostane" – changes the choices the screen holds and shows them at once. It is saved `saveDelay` after the last
///   change, at once when a slide ends or a field is left, and when the app quits (`saveNow()`). A save writes the
///   whole of the choices into the settings (`AppModel.updateAppSettings(_:)`); the settings are not data the screens
///   show, so a save starts no reload.
/// - A typed text stays in its field until editing ends, also one that was taken, and is read key by key: a text that
///   can be read changes the split at once. A text that is no amount in whole Kč, or no percentage with at most one
///   decimal (a negative one included), keeps the value the category had, and once the typing has paused for
///   `saveDelay` the field says what it takes (`BudgetInput.refusedFields`): what is typed on the way to a valid
///   text ("30 0" of "30 000", "15," of "15,5") never shows the hint. An emptied field keeps the value too and says
///   nothing. A percentage or an amount above what the category can have is held at that limit while the field
///   keeps the text. A field that hands back the text it shows, with no key typed into it, changes nothing: SwiftUI
///   hands a field's text to the model as its editing ends, and that text is the value rounded as the field writes
///   it.
/// - Choosing the source or an invoice is saved at once, with any change that waits, and the screen loads again. Until
///   that load lands, the screen shows and changes the split with the figures it has and the source they were read
///   for, never with the new source and the figures of the old one. An invoice shown in place of a chosen one that has
///   left the list is only shown: the choice stays until the person picks another invoice.
@MainActor
@Observable
final class BudgetModel: SavesTypedInput {
    /// What the screen says in place of its content when the data cannot be loaded.
    static let loadFailureText = "Rozpočet se nepodařilo načíst."

    /// What the screen shows: nil until the first load has finished, and after a load that failed.
    private(set) var data: BudgetData?

    /// What the screen says in place of its content when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// The row of the sources that the screen shows above `errorText` while the last load failed, built from the
    /// choices it holds, so that another source can be chosen. Nil while the screen shows data, and when the app has
    /// gone and there is nothing to choose.
    private(set) var failedSourceRow: BudgetSourceRowData?

    /// The app, held weakly: it holds this model (`AppModel.budgetModel`).
    @ObservationIgnored private weak var app: AppModel?

    /// How long after the last change of the split it is saved.
    private let saveDelay: Duration

    /// The wait before a save.
    private let saveTimer: DebounceTimer

    /// The choices as the screen has them: those of the settings, with the changes made on the screen and not saved yet
    /// on top of them.
    @ObservationIgnored private var settings: BudgetSettings

    /// What the last load read, the year and the day with the net income of the source; the choices and the typed texts
    /// in it are replaced by those of the model whenever the data is built. Nil before the first load and after a load
    /// that failed, when there is nothing to change.
    @ObservationIgnored private var loaded: BudgetInput?

    /// The text of each field that is being edited, and those of them that could not be read and say so.
    @ObservationIgnored private var typedTexts: [BudgetField: String] = [:]
    @ObservationIgnored private var refusedFields: Set<BudgetField> = []

    /// The fields whose text could not be read and that say so once the typing has paused (`refusalTimer`).
    @ObservationIgnored private var refusalsDue: Set<BudgetField> = []

    /// The wait before a field whose text could not be read says so.
    private let refusalTimer: DebounceTimer

    /// Whether `settings` holds a change that is not written yet.
    @ObservationIgnored private var hasChanges = false

    /// The write that runs.
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// How many loads have started. Only the latest one may show its result: a load that was started for a source or a
    /// year that has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    /// A model of `app` that saves `saveDelay` after the last change of the split, and says that a typed text cannot be
    /// read `saveDelay` after the last key, waiting both out with `wait`, which a test replaces with a wait that it
    /// ends itself. It starts with the choices the settings hold.
    init(
        app: AppModel, saveDelay: Duration = .milliseconds(500),
        wait: @escaping DebounceTimer.Wait = { try await Task.sleep(for: $0) }
    ) {
        self.app = app
        self.saveDelay = saveDelay
        saveTimer = DebounceTimer(wait: wait)
        refusalTimer = DebounceTimer(wait: wait)
        settings = app.appSettings.budget
    }

    // MARK: Loading

    /// Loads the net income of the source the screen shows for the selected year, and the choices from the settings
    /// unless changes wait to be saved, and shows them. A figure that cannot be worked out leaves nothing to divide
    /// (`readSource()`); any other failure is logged (the domain and the code of the error alone) and shows
    /// `errorText` in place of the data, with the row of the sources above it (`failedSourceRow`). Cancellation keeps
    /// what was shown without publishing this load. The model is known to the app from its first load on, so that a
    /// quit saves what waits (`hasUnsavedInput`). A model whose app has gone has nothing to read, and shows
    /// `errorText`.
    func load() async {
        app?.quitFlushes.register(self)
        loadsStarted += 1
        let thisLoad = loadsStarted
        if !hasUnsavedInput, let app {
            settings = app.appSettings.budget
        }
        do {
            let read = try await readSource()
            guard thisLoad == loadsStarted, !Task.isCancelled else { return }
            loaded = read
            errorText = nil
            failedSourceRow = nil
            rebuild()
        } catch is CancellationError {
            return
        } catch {
            guard thisLoad == loadsStarted, !Task.isCancelled else { return }
            AppModel.log("Loading Rozpočet", failedWith: error)
            loaded = nil
            data = nil
            errorText = Self.loadFailureText
            failedSourceRow = app.map { app in
                BudgetBuilder.sourceRow(
                    of: BudgetInput(
                        year: app.asOf.year, today: app.today, settings: settings, actual: nil, prediction: nil,
                        invoices: []))
            }
        }
    }

    /// Reads the year, today and the net income of the source the screen shows with the choices of now, and nothing of
    /// the other sources. The average or the prediction that cannot be worked out is logged and left out, so that
    /// there is nothing to divide (`figure(_:_:)`). Throws `VaultError.locked` while the data is locked or the app has
    /// gone, what listing the invoices throws, and `CancellationError` when the reading was cancelled.
    private func readSource() async throws -> BudgetInput {
        guard let app, app.database != nil else { throw VaultError.locked }
        var input = BudgetInput(
            year: app.asOf.year, today: app.today, settings: settings, actual: nil, prediction: nil, invoices: [])
        switch BudgetBuilder.source(of: input) {
        case .actual:
            input.actual = try await figure("Loading the average of Rozpočet") {
                try await app.averageNetIncome()
            }
        case .prediction:
            let year = input.year
            input.prediction = try await figure("Loading the estimate of Rozpočet") {
                try await app.predictionOutcome(year: year)
            }
        case .invoice:
            input.invoices = try await app.budgetInvoices()
        }
        return input
    }

    /// What `read` gives, or nil when it fails: the failure is logged under `action` (the domain and the code of the
    /// error alone), and the screen then has nothing to divide. A cancellation and a lock of the data are thrown on,
    /// for the load to keep what was shown or to show its line.
    private func figure<Figure>(_ action: String, _ read: () async throws -> Figure) async throws -> Figure? {
        do {
            return try await read()
        } catch is CancellationError {
            throw CancellationError()
        } catch VaultError.locked {
            throw VaultError.locked
        } catch {
            AppModel.log(action, failedWith: error)
            return nil
        }
    }

    // MARK: Choosing what is divided

    /// Divides the net income of `source`, saves the choice at once with any change that waits, and loads the screen
    /// again. Until the load lands, the screen keeps the source of the figures it has (`currentInput()`).
    func chooseSource(_ source: BudgetSource) async {
        if settings.source != source {
            settings.source = source
            hasChanges = true
        }
        await saveNow()
        await load()
    }

    /// Divides what the invoice `id` leaves, in Faktura mode, saves the choice at once with any change that waits, and
    /// loads the screen again.
    func chooseInvoice(id: Int64) async {
        if settings.source != .invoice || settings.invoiceID != id {
            settings.source = .invoice
            settings.invoiceID = id
            hasChanges = true
        }
        await saveNow()
        await load()
    }

    // MARK: Changing the split

    /// Makes `category` the remainder, which gets what the others leave. No number changes: the old remainder keeps the
    /// share it has now (`BudgetSplit.withRemainder(_:net:)`).
    func chooseRemainder(_ category: BudgetCategory) {
        forgetTyping(of: category)
        change { $0.withRemainder(category, net: $1) }
    }

    /// The slider of `category` is at `percent` whole percent: the share becomes that, held to what the category can
    /// have (`BudgetSplit.settingShare(_:of:net:)`). Only a category held by a share has a slider; the fields of the
    /// category show the share that results.
    func slide(_ category: BudgetCategory, toPercent percent: Int) {
        guard takesShare(category) else { return }
        forgetTyping(of: category)
        change { $0.settingShare(Decimal(percent) / 100, of: category, net: $1) }
    }

    /// The slider of `category` has been let go: what waits is saved now, not at the end of the delay.
    func endSliding(_ category: BudgetCategory) {
        saveWithoutDelay()
    }

    /// `text` has been typed into the % field of `category`, which only a category held by a share has. The field keeps
    /// the text until editing ends. A percentage with at most one decimal, not negative, becomes the share at once,
    /// held to what the category can have. An empty field keeps the share as it is; any other text keeps it too, and
    /// the field says what it takes once the typing has paused (`refuse(_:)`). The text the field shows while nothing
    /// is typed into it changes nothing (`isShownValue(_:of:)`).
    func typePercent(_ text: String, for category: BudgetCategory) {
        guard takesShare(category) else { return }
        let field = BudgetField.percent(category)
        guard !isShownValue(text, of: field) else { return }
        typedTexts[field] = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            accept(field)
            rebuild()
        } else if let percent = AmountParser.decimal(text, maxFractionDigits: 1), percent >= 0 {
            accept(field)
            change { $0.settingShare(percent / 100, of: category, net: $1) }
        } else {
            refuse(field)
            rebuild()
        }
    }

    /// `text` has been typed into the Kč field of `category`, which every category but the remainder has. The field
    /// keeps the text until editing ends. An amount in whole Kč becomes the fixed amount of a fixed category, or the
    /// share that gives exactly that amount of the net income of a share-held one, held to what it can have
    /// (`BudgetSplit.settingAmount(_:of:net:)`), at once. An empty field keeps the value as it is; any other text keeps
    /// it too, and the field says what it takes once the typing has paused (`refuse(_:)`). The text the field shows
    /// while nothing is typed into it changes nothing (`isShownValue(_:of:)`).
    func typeAmount(_ text: String, for category: BudgetCategory) {
        guard loaded != nil, category != settings.split.remainder else { return }
        let field = BudgetField.amount(category)
        guard !isShownValue(text, of: field) else { return }
        typedTexts[field] = text
        switch TypedKc(text) {
        case .blank:
            accept(field)
            rebuild()
        case .value(let kc):
            accept(field)
            change { $0.settingAmount(kc, of: category, net: $1) }
        case .refused:
            refuse(field)
            rebuild()
        }
    }

    /// The person has left the fields of `category`: they show its value again in place of what was typed, without
    /// the hints of the text, and what waits is saved now.
    func endEditing(_ category: BudgetCategory) {
        forgetTyping(of: category)
        rebuild()
        saveWithoutDelay()
    }

    /// Ticks or unticks "pevná částka" of `category`: a share becomes the amount it gives a month now, a fixed amount
    /// the share it is now, so no number changes (`BudgetSplit.togglingFixed(_:net:)`).
    func toggleFixed(_ category: BudgetCategory) {
        forgetTyping(of: category)
        change { $0.togglingFixed(category, net: $1) }
    }

    /// Whether `text` is what `field` shows of the value of its category while nothing is typed into it. SwiftUI hands
    /// a field its text as its editing ends, also when the field was only focused and left; that text is the value
    /// rounded as the field writes it, "16,0" for a share of 16,03 % and "28 067" for one of 15 % of 187 111 Kč, so
    /// taking it as typed would move the share it stands for.
    private func isShownValue(_ text: String, of field: BudgetField) -> Bool {
        guard typedTexts[field] == nil, let row = data?.rows.first(where: { $0.category == field.category }) else {
            return false
        }
        return switch field {
        case .percent: text == row.percentText
        case .amount: text == row.amountText
        }
    }

    /// Whether `category` is held by a share, so that its slider and its % field set it, once the screen has loaded.
    private func takesShare(_ category: BudgetCategory) -> Bool {
        guard loaded != nil, category != settings.split.remainder else { return false }
        if case .share = settings.split.holding(of: category) {
            return true
        }
        return false
    }

    /// Changes the split with `edit`, which is given the split and the amount the screen divides
    /// (`BudgetBuilder.net(of:)`, nil when there is none), shows the result and saves it `saveDelay` after the last
    /// change. A change that leaves the split as it was saves nothing. Nothing changes before the screen has loaded.
    private func change(_ edit: (BudgetSplit, Int64?) -> BudgetSplit) {
        guard let input = currentInput() else { return }
        let split = edit(settings.split, BudgetBuilder.net(of: input))
        if split != settings.split {
            settings.split = split
            hasChanges = true
            saveTimer.restart(after: saveDelay) {
                await self.saveNow()
            }
        }
        rebuild()
    }

    /// Drops what was typed into the fields of `category`, and the hints of it, also those that wait for the typing to
    /// pause.
    private func forgetTyping(of category: BudgetCategory) {
        for field in [BudgetField.percent(category), BudgetField.amount(category)] {
            typedTexts[field] = nil
            accept(field)
        }
    }

    // MARK: Texts that cannot be read

    /// The text of `field` can be read, or is empty: the field says nothing, and nothing waits to say it.
    private func accept(_ field: BudgetField) {
        refusedFields.remove(field)
        refusalsDue.remove(field)
        if refusalsDue.isEmpty {
            refusalTimer.cancel()
        }
    }

    /// The text of `field` cannot be read. A field that says so already goes on saying it; any other one says it once
    /// the typing has paused for `saveDelay` (`showRefusals()`), so that a text on its way to a valid one, which a
    /// key reads again before the pause, never says it. Every key starts the wait again.
    private func refuse(_ field: BudgetField) {
        guard !refusedFields.contains(field) else { return }
        refusalsDue.insert(field)
        refusalTimer.restart(after: saveDelay) {
            self.showRefusals()
        }
    }

    /// The typing has paused: the fields whose text could not be read, and which still hold it, say what they take.
    private func showRefusals() {
        for field in refusalsDue where typedTexts[field] != nil {
            refusedFields.insert(field)
        }
        refusalsDue = []
        rebuild()
    }

    // MARK: Building

    /// What was loaded with the choices and the typed texts of now, or nil before a load has shown anything. The source
    /// is the one the loaded figures were read for until the next load lands: a source just chosen is saved before its
    /// figures are loaded (`chooseSource(_:)`), and with the figures of another source it would have nothing to divide,
    /// so that a change made in the meantime would work out from nothing.
    private func currentInput() -> BudgetInput? {
        guard var input = loaded else { return nil }
        let source = input.settings.source
        input.settings = settings
        input.settings.source = source
        input.typedTexts = typedTexts
        input.refusedFields = refusedFields
        return input
    }

    /// Builds the data of the screen again from what was loaded and the choices and texts of now.
    private func rebuild() {
        guard let input = currentInput() else { return }
        let built = BudgetBuilder.build(input)
        if built != data {
            data = built
        }
    }

    // MARK: Saving

    /// Whether a change of the choices is not written yet: one that waits to be saved, or a save that runs.
    var hasUnsavedInput: Bool {
        hasChanges || writeTask != nil
    }

    /// Saves what waits as soon as it can, without waiting out the delay.
    private func saveWithoutDelay() {
        guard hasChanges else { return }
        saveTimer.restart(after: .zero) {
            await self.saveNow()
        }
    }

    /// Writes the choices into the settings of the app when a change waits, and returns when it is written. The end of
    /// the wait calls this, as do a slide that ends, a field that is left, the choice of a source or an invoice, and a
    /// quit. When a save already runs, this waits for it and then saves what has come since. A save that cannot be
    /// written is logged by the app (`AppModel.updateAppSettings(_:)`), and the next load shows what the settings hold.
    /// A model whose app has gone writes nothing.
    func saveNow() async {
        saveTimer.cancel()
        while let running = writeTask {
            await running.value
        }
        guard hasChanges else { return }
        hasChanges = false
        let budget = settings
        let task = Task {
            await self.app?.updateAppSettings { $0.budget = budget }
            self.writeTask = nil
        }
        writeTask = task
        await task.value
    }
}
