import Foundation
import Observation

/// Why the editor did not save the invoice.
nonisolated enum InvoiceEditorError: Error, Equatable {
    /// The invoice cannot be saved as it is; the text says what is wrong.
    case invalid(String)

    /// The invoice was changed after the editor loaded it (by another window, or by a payment), so saving it would undo
    /// that change.
    case invoiceChanged

    /// The button does not belong to this invoice: an invoice that is issued is neither saved as a draft nor issued
    /// again, and a new invoice has no changes to save.
    case notAvailable

    /// Another save of the editor is still running.
    case alreadySaving
}

/// The amounts under the items of the editor: the base, the VAT, the total, and for a foreign currency the total in
/// crowns at the rate of the DUZP.
nonisolated struct EditorTotals: Equatable, Sendable {
    var base: String

    /// "DPH 21 %".
    var vatLabel: String
    var vat: String
    var total: String

    /// "≈ 306 501,65 Kč kurzem ČNB k DUZP".
    var inCrowns: String?
}

/// The invoice editor: a new invoice, blank or from a template, or an invoice that exists, issued or not.
///
/// What the person types is held here as typed, text by text, and nothing is written to the database until a save:
/// "Uložit koncept" (`saveDraft()`), "Vystavit fakturu" (`issue()`) or "Uložit změny" (`saveChanges()`). Everything
/// the editor shows besides the fields (`document`, `validation`, the rate, the effect on the levies) is worked out
/// again by `recompute()` whenever one of them changes; the screen calls it, and every save works the invoice out
/// afresh.
///
/// - A new invoice: the client and its terms, the day of issue on the real today, the DUZP on the last day of the real
///   current month (the two dates are independent from then on), the number by the month of the DUZP, and one row of
///   items, or whatever the template says.
/// - An invoice that exists: its own data. An issued invoice keeps its number, its rate of the DUZP unless the DUZP or
///   the currency changes, and the data of its client unless another client is chosen; a payment is worked out again.
///   A draft takes the data of its client again whenever it is saved, and the rate of the day it is issued.
/// - Nothing that is typed can stop the app: a date outside the years of an invoice, a due time outside its range and
///   amounts too high to add up are problems of the invoice, not traps.
///
/// "Vystavit" in the detail of a draft in Faktury issues the draft with an editor that is never shown
/// (`issueDraft(_:app:)`): it opens the draft as the editor shown for it would and issues it with the work of "Vystavit
/// fakturu", but its save leaves the window as it is.
@MainActor
@Observable
final class InvoiceEditorModel {
    /// The units the unit field offers.
    nonisolated static let units = ["h", "hod", "den", "měs.", "ks"]

    // MARK: What the editor was opened for

    /// The invoice that is edited, as the editor loaded it, or nil for a new invoice. When the app converts its payment
    /// again and saves it, the editor takes the invoice as it is saved (`rebase(onto:replacing:)`): what the person
    /// typed stays, and the payment and a save are worked out from the stored invoice.
    private(set) var editing: Invoice?

    /// The template a new invoice starts from, or nil for a blank one (and for an invoice that exists).
    let template: InvoiceTemplate?

    /// The client a blank new invoice starts with, or nil for the first one. A client that was deleted meanwhile is the
    /// first one too.
    private let startingClientID: Int64?

    /// Whether the editor is never shown, as the one that issues a draft from its detail in Faktury
    /// (`issueDraft(_:app:)`): its save leaves the screen, the editor that is open and the detail as they are, and no
    /// banner says that it saved.
    private let isHeadless: Bool

    // MARK: What the person edits

    /// The client chosen, or 0 for none. An invoice whose client was deleted has none, and keeps the data it printed.
    var clientID: Int64
    var number: String

    /// The day of issue ("Datum vystavení"). The due date is this day plus the due days. It is independent of the DUZP:
    /// changing one never changes the other.
    var issueDate: CivilDate

    /// The DUZP. The number of a new invoice, the rate and the descriptions made from a template follow it.
    var duzp: CivilDate {
        didSet {
            duzpChanged(from: oldValue)
        }
    }

    /// The days from the day of issue to the due date, as typed. A text that is not a number of days is a problem of
    /// the invoice (`EditorText.invalidDueDays`), as it is for the quantity and the price of an item.
    var dueDaysText: String
    var vatMode: VatMode
    var items: [EditableItem]

    /// The checkbox "Přidat na fakturu QR kód pro platbu".
    var qrEnabled: Bool
    var note: String

    /// The due days the text says, or nil when it is not a whole number of days: digits only, around which spaces do
    /// not matter. A number outside `EditorLimits.dueDays` is read as it is, and refused by the check of the invoice.
    var dueDays: Int? {
        get { Self.days(in: dueDaysText) }
        set { dueDaysText = newValue.map { String($0) } ?? "" }
    }

    // MARK: What is loaded and worked out

    /// The clients to choose from, by name.
    private(set) var clients: [Client] = []

    /// The page of the invoice as it would print now, or nil while it cannot be made (no client, a date outside the
    /// years of an invoice, amounts too high). A draft's rate of the DUZP is marked provisional on it.
    private(set) var document: InvoiceDocument?

    /// What stops the invoice from being issued (or from being saved, for a draft), one sentence each.
    private(set) var validation: [String] = []

    /// Whether the invoice can be saved as a draft: it can with problems that only an issued invoice is stopped by.
    private(set) var canSaveDraft = false

    /// What the effect on the levies says: for a paid invoice what its change does, otherwise what its payment would
    /// add, and under it the sentences that go with it. Nil where it cannot be worked out.
    private(set) var impactText: String?
    private(set) var impactDetail: String?

    private(set) var totals: EditorTotals?

    /// The ČNB rate of the DUZP that is fixed on the invoice when it is issued, and whether it is the one the invoice
    /// has already. Nil for crowns and where no rate is known.
    private(set) var rate: StoredRate?
    private(set) var rateIsFixed = false

    /// Why the page has no QR code, or nil when it can have one.
    private(set) var qrReason: String?

    /// Whether the amounts are too high to add up. Nothing is drawn or shown for such an invoice.
    private(set) var amountsTooHigh = false

    /// Whether the clients and the supplier could not be read.
    private(set) var loadFailed = false

    /// Whether a save is running. The buttons wait for it, and so does a second save.
    private(set) var isSaving = false

    /// What the last save that failed says, until the next edit.
    var failure: String? {
        guard let failedSave, failedSave.inputs == inputs else { return nil }
        return failedSave.text
    }

    /// A save that failed: the input it failed with, and what it says.
    private struct FailedSave {
        var inputs: Inputs
        var text: String
    }

    private var failedSave: FailedSave?

    // MARK: Bookkeeping

    /// The app holds the editor while an invoice is being written (`AppModel.editor`), so the editor does not hold the
    /// app. When the app is gone there is nothing to work with, and the editor does nothing.
    @ObservationIgnored weak var app: AppModel?

    @ObservationIgnored private var supplier = Supplier()
    @ObservationIgnored private var accounts: [BankAccount] = []

    /// Whether `load()` has applied the client the editor starts with.
    @ObservationIgnored private var started = false

    /// The number that was proposed last. A number that is the proposal follows the month of the DUZP.
    @ObservationIgnored private var proposedNumber = ""

    /// The numbers of the month the proposal was made for (`numbersPrefix` is its year and month).
    @ObservationIgnored private var numbersPrefix = ""
    @ObservationIgnored private var existingNumbers: [String] = []

    /// How many times the invoice has been worked out. Only the latest may publish its result.
    @ObservationIgnored private var computations = 0

    /// What is wrong with the invoice, as of the last time it was worked out.
    @ObservationIgnored private var problems: [EditorProblem] = []

    /// The years whose ČNB files were asked for.
    @ObservationIgnored private var askedYears: Set<Int> = []

    /// The version of the data of the app (`AppModel.dataVersion`) that the clients, the supplier, the accounts and the
    /// numbers of the month were read at.
    @ObservationIgnored private var dataVersion = 0

    /// The invoice as it would be saved, as of the last time it was worked out, with the status it has now.
    @ObservationIgnored private var assembled: Invoice?

    /// What the editor started with: the input once the client is applied and the number proposed.
    @ObservationIgnored private var starting: Inputs?

    /// `startingClientID` is the client a blank new invoice starts with, rather than the first one; it counts for
    /// nothing else. A `headless` editor is never shown (`isHeadless`).
    init(
        app: AppModel, template: InvoiceTemplate?, editing: Invoice?, startingClientID: Int64? = nil,
        headless: Bool = false
    ) {
        self.app = app
        self.template = template
        self.editing = editing
        self.startingClientID = startingClientID
        isHeadless = headless
        if let invoice = editing {
            clientID = invoice.clientID ?? 0
            number = invoice.number
            // The number of a draft that has the year and month of its DUZP follows the DUZP until it is typed over.
            if invoice.status == .draft,
                InvoiceNumbering.digits(of: invoice.number).hasPrefix(Self.monthPrefix(of: invoice.duzp))
            {
                proposedNumber = invoice.number
            }
            duzp = invoice.duzp
            issueDate = invoice.issueDate
            dueDaysText = String(max(0, invoice.dueDate.days(since: invoice.issueDate)))
            vatMode = invoice.vatMode
            items = invoice.items.map { EditableItem(item: $0) }
            qrEnabled = invoice.qrEnabled
            note = invoice.note
        } else {
            // A new invoice is issued on the real today and supplied on the last day of the real current month,
            // whichever year is shown and whatever a template says: the two days are the person's to change.
            let today = app.today
            let supply = today.endOfMonth
            clientID = template?.clientID ?? 0
            number = ""
            duzp = supply
            issueDate = today
            dueDaysText = String(template?.dueDays ?? 14)
            vatMode = template?.vatMode ?? .domestic21
            if let template {
                items = template.items.map { EditableItem(templateItem: $0, duzp: supply) }
            } else {
                items = [EditableItem.blank()]
            }
            qrEnabled = false
            note = template?.note ?? ""
        }
    }

    /// The editor for what `request` asks for, or nil when there is nothing to edit: the invoice was deleted meanwhile,
    /// or the request is the chooser. A template deleted meanwhile is a blank invoice. Throws `VaultError.locked`, and
    /// what the database throws.
    static func opening(_ request: EditorRequest, in app: AppModel) async throws -> InvoiceEditorModel? {
        guard let database = app.database else { throw VaultError.locked }
        switch request {
        case .chooser:
            return nil
        case .new(let templateID, let clientID):
            var template: InvoiceTemplate?
            if let templateID {
                template = try await database.templates().first { $0.id == templateID }
            }
            return InvoiceEditorModel(app: app, template: template, editing: nil, startingClientID: clientID)
        case .edit(let id):
            guard let invoice = try await database.invoice(id: id) else { return nil }
            return InvoiceEditorModel(app: app, template: nil, editing: invoice)
        }
    }

    // MARK: Loading

    /// Reads the clients, the supplier and the accounts, applies the client a new invoice starts with, and works the
    /// invoice out. A failure to read is logged and shown (`loadFailed`).
    func load() async {
        do {
            try await readReferenceData()
        } catch {
            AppModel.log("Loading the invoice editor", failedWith: error)
            loadFailed = true
            return
        }
        if !started {
            started = true
            applyStartingClient()
        }
        // The screen asks for missing rates once it shows the invoice: the editor does not wait for a download.
        await recompute(asking: false)
        if starting == nil {
            starting = inputs
        }
    }

    /// Reads the clients, the supplier and the accounts, which the invoice takes its parties and its terms from. Throws
    /// `VaultError.locked`, and what the database throws; what the editor has stays then.
    private func readReferenceData() async throws {
        guard let app, let database = app.database else { throw VaultError.locked }
        let version = app.dataVersion
        let clients = try await database.clients()
        let supplier = try await database.supplier()
        let accounts = try await database.bankAccounts()
        self.clients = clients
        self.supplier = supplier
        self.accounts = accounts
        dataVersion = version
    }

    /// The editor stays open while the person is on other screens, where clients, the supplier, the accounts and the
    /// invoices change, and ČNB rates come. When the data of the app has been written since, what the invoice is
    /// made of is read again, and the numbers of the month are looked up again.
    private func refreshIfDataChanged() async {
        guard let app, dataVersion != app.dataVersion else { return }
        numbersPrefix = ""
        do {
            try await readReferenceData()
        } catch {
            AppModel.log("Reading the data of an invoice editor again", failedWith: error)
            dataVersion = app.dataVersion
        }
    }

    /// A blank invoice starts with the client it was asked for, or with the first client, and what it says; a template
    /// keeps what it says, and the QR box follows the currency of its client.
    private func applyStartingClient() {
        guard editing == nil else { return }
        if template != nil {
            qrEnabled = Self.qrIsOnByDefault(for: pickedClient?.currency ?? .czk)
        } else if let asked = clients.first(where: { $0.id == startingClientID }) ?? clients.first {
            pickClient(asked.id)
        }
    }

    // MARK: The client

    /// Chooses the client: its VAT mode and due days apply, and the QR box goes back to what is usual for its currency
    /// (on for crowns and euros). Choosing the client that is chosen already changes nothing.
    func pickClient(_ id: Int64) {
        guard id != clientID, let client = clients.first(where: { $0.id == id }) else { return }
        clientID = id
        vatMode = client.vatMode
        dueDaysText = String(client.dueDays)
        qrEnabled = Self.qrIsOnByDefault(for: client.currency)
    }

    var pickedClient: Client? {
        clients.first { $0.id == clientID }
    }

    /// Whether an invoice that exists is still written for the client it was written for, and is issued: then it keeps
    /// all it printed of the client, whatever has become of the client since.
    private var keepsStoredClient: Bool {
        guard let editing else { return false }
        return editing.status == .issued && clientID == (editing.clientID ?? 0)
    }

    /// What the invoice takes of its client: the data it prints, and its currency, language and way of payment.
    struct ClientTerms {
        var snapshot: ClientSnapshot
        var currency: CurrencyCode
        var language: InvoiceLanguage
        var paymentMethod: String

        init(invoice: Invoice) {
            snapshot = invoice.client
            currency = invoice.currency
            language = invoice.language
            paymentMethod = invoice.paymentMethod
        }

        init(client: Client) {
            snapshot = ClientSnapshot(client: client)
            currency = client.currency
            language = client.language
            paymentMethod = client.paymentMethod
        }
    }

    var terms: ClientTerms? {
        if let editing, keepsStoredClient {
            return ClientTerms(invoice: editing)
        }
        if let client = pickedClient {
            return ClientTerms(client: client)
        }
        // The client of a draft that exists no more: the draft has the data it printed.
        if let editing, clientID == (editing.clientID ?? 0) {
            return ClientTerms(invoice: editing)
        }
        return nil
    }

    // MARK: The items

    /// Adds a row of one unit of the kind of the row above, with no description and no price, up to the limit.
    func addItem() {
        guard canAddItem else { return }
        items.append(EditableItem.blank(unit: items.last?.unit ?? "h"))
    }

    func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    // MARK: What the app converts again

    /// The app converted the payment of the invoice again and saved it as `stored`, in place of `replaced`
    /// (`AppModel.recomputePayments(of:in:)`). An editor that holds the invoice as `replaced` was takes `stored` as the
    /// invoice it edits and works it out again: what the person typed stays, the payment it saves is worked out from
    /// the new one, and its save compares with what is stored, so the app's own conversion does not make it refuse the
    /// invoice as changed meanwhile. An editor that held the invoice as it was before another change, such as a
    /// payment recorded in another window, takes nothing: its save is refused, as it would undo that change.
    func rebase(onto stored: Invoice, replacing replaced: Invoice) async {
        guard let editing, editing.id == stored.id, editing == replaced else { return }
        self.editing = stored
        await recompute(asking: false)
    }

    // MARK: Leaving

    /// Zrušit and the back arrow: the editor closes without saving, and Faktury shows (the detail of the invoice that
    /// was edited open). The person is asked first when something typed would be lost.
    func cancel() {
        app?.leaveEditor()
    }

    /// Vybrat jinou: the chooser opens in place of the editor.
    func chooseAnotherTemplate() {
        app?.editorRequest = .chooser
    }

    // MARK: What the screen works out again

    /// What a change of the editor is worked out again for.
    struct Inputs: Hashable, Sendable {
        var clientID: Int64
        var number: String
        var issueDate: CivilDate
        var duzp: CivilDate
        var dueDaysText: String
        var vatMode: VatMode
        var qrEnabled: Bool
        var note: String
        var items: [Row]

        struct Row: Hashable, Sendable {
            var description: String
            var quantity: String
            var unit: String
            var price: String
        }
    }

    /// What the screen works the invoice out again for: what is typed or chosen, and a write of the data of the app
    /// (a client changed, a number taken, new ČNB rates).
    struct RefreshKey: Hashable, Sendable {
        var inputs: Inputs
        var dataVersion: Int
    }

    var refreshKey: RefreshKey {
        RefreshKey(inputs: inputs, dataVersion: app?.dataVersion ?? 0)
    }

    /// Whether something was typed or chosen since the editor started: what closing the editor would throw away. What
    /// the editor itself starts with (the first client, the proposed number, and where that moves) is no change, and
    /// neither is what was typed and typed back.
    var hasChanges: Bool {
        guard let starting else { return false }
        var current = inputs
        // A number that is still the proposal of the editor moves on by itself when another invoice takes it: that is
        // not the person's doing.
        if !proposedNumber.isEmpty, number == proposedNumber {
            current.number = starting.number
        }
        return current != starting
    }

    /// Everything that is typed or chosen, to tell when `recompute()` is due.
    var inputs: Inputs {
        Inputs(
            clientID: clientID, number: number, issueDate: issueDate, duzp: duzp, dueDaysText: dueDaysText,
            vatMode: vatMode, qrEnabled: qrEnabled, note: note,
            items: items.map {
                Inputs.Row(
                    description: $0.description, quantity: $0.quantityText, unit: $0.unit, price: $0.unitPriceText)
            })
    }

    /// The descriptions that are still what a template made of them follow the DUZP. The day of issue stays as it is.
    private func duzpChanged(from old: CivilDate) {
        guard duzp != old else { return }
        for index in items.indices where items[index].isFilledFromTemplate {
            items[index].fillFromTemplate(for: duzp)
        }
    }

    // MARK: Working the invoice out

    /// What is typed or chosen as of one moment, with the terms of the client it names. One run of the work is about
    /// one draft, so that what is typed while the run waits for the database is not mixed into it.
    struct Draft {
        var number: String
        var duzp: CivilDate
        var issueDate: CivilDate

        /// Nil when the text is not a number of days.
        var dueDays: Int?
        var vatMode: VatMode
        var items: [EditableItem]
        var qrEnabled: Bool
        var note: String
        var clientID: Int64
        var terms: ClientTerms?

        /// Whether the DUZP and the day of issue are in the years of an invoice.
        var dateIsUsable: Bool {
            EditorLimits.years.contains(duzp.year) && EditorLimits.years.contains(issueDate.year)
        }

        /// The due date, once the date and the days are usable.
        var usableDueDate: CivilDate? {
            guard dateIsUsable, let dueDays, EditorLimits.dueDays.contains(dueDays) else { return nil }
            return issueDate.adding(days: dueDays)
        }

        /// The due date the page is drawn with: the days kept within their range, and none where the text is no number.
        var previewDueDate: CivilDate {
            let range = EditorLimits.dueDays
            return issueDate.adding(days: min(max(dueDays ?? 0, range.lowerBound), range.upperBound))
        }
    }

    var draft: Draft {
        Draft(
            number: number, duzp: duzp, issueDate: issueDate, dueDays: dueDays, vatMode: vatMode, items: items,
            qrEnabled: qrEnabled, note: note, clientID: clientID, terms: terms)
    }

    /// Why the invoice has no rate that may be fixed on it.
    enum RateGap: Sendable {
        /// The rate should be in the cache and is not (yet): the files of the ČNB may bring it.
        case notDownloaded

        /// The ČNB does not quote the currency that day: nothing will come.
        case notQuoted
    }

    /// What one run of the work found out.
    struct Computed {
        /// The rate of the DUZP, and whether it is the one the invoice has already.
        var rate: StoredRate?
        var rateIsFixed = false

        /// Why the invoice has no rate that may be fixed on it (a foreign currency without one), and the yearly files
        /// of the ČNB that may bring it.
        var rateGap: RateGap?
        var rateYears: [Int] = []

        /// The number proposed for a new invoice, when its number is the proposal.
        var proposal: String?

        var problems: [EditorProblem] = []

        /// The invoice as it would be saved, and its page, once the invoice can be made.
        var invoice: Invoice?
        var document: InvoiceDocument?
        var totals: EditorTotals?
        var qrReason: String?
        var tooHigh = false
        var impact: EditorLevyImpact.Sentences?
    }

    /// Works the invoice out again from what is typed: the number to propose, the rate of the DUZP, the invoice as it
    /// would be saved and its page, what is wrong with it, the payment of an invoice that was paid and the effect on
    /// the levies. A run that has been overtaken by a later one publishes nothing.
    func recompute() async {
        await recompute(asking: true)
    }

    /// The work of `recompute()`. When the invoice needs a ČNB rate that is not in the cache, the files of the years
    /// that may hold it are asked for once (`asking`), and the invoice is worked out again if they brought rates.
    private func recompute(asking: Bool) async {
        await refreshIfDataChanged()
        computations += 1
        let run = computations
        let computed = await compute(draft)
        guard run == computations else { return }
        publish(computed)
        if asking, await askForRates(inYears: computed.rateYears) {
            await recompute()
        }
    }

    /// Asks for the yearly files of the ČNB of `years` that were not asked for yet, and says whether rates were stored.
    /// A year is asked for once while the editor is open: a gap that stays is a download that failed, and the person
    /// is told what to do (the refresh of the app goes on as it does). The download is not cut short when the person
    /// types on, which cancels the task that waits for it.
    private func askForRates(inYears years: [Int]) async -> Bool {
        let new = years.filter { !askedYears.contains($0) }
        guard !new.isEmpty, let refresh = app?.refresh else { return false }
        askedYears.formUnion(new)
        return await Task { await refresh.fetchYears(new) }.value
    }

    private func publish(_ computed: Computed) {
        if let proposal = computed.proposal, number == proposedNumber {
            number = proposal
            proposedNumber = proposal
        }
        rate = computed.rate
        rateIsFixed = computed.rateIsFixed
        problems = computed.problems
        validation = computed.problems.map(\.text)
        canSaveDraft = computed.invoice != nil && !computed.problems.contains { $0.blocksDraft }
        assembled = computed.invoice
        document = computed.document
        totals = computed.totals
        qrReason = computed.qrReason
        amountsTooHigh = computed.tooHigh
        impactText = computed.impact?.heading
        impactDetail = computed.impact?.detail
    }

    private func compute(_ start: Draft) async -> Computed {
        var draft = start
        var computed = Computed()
        var failed = false
        if let database = app?.database, draft.dateIsUsable {
            do {
                if let proposal = try await proposeNumber(for: draft, in: database) {
                    computed.proposal = proposal
                    draft.number = proposal
                }
                let outcome = try await rateOfTheDUZP(for: draft, in: database)
                computed.rate = outcome.rate
                computed.rateIsFixed = outcome.isFixed
                computed.rateGap = outcome.gap
                computed.rateYears = outcome.years
            } catch {
                AppModel.log("Looking up the number and the rate of an invoice", failedWith: error)
                failed = true
            }
        }
        work(draft, failed: failed, into: &computed)
        if var invoice = computed.invoice {
            await finishPayment(of: &invoice, estimating: draft.usableDueDate != nil, into: &computed)
            computed.invoice = invoice
        }
        return computed
    }

    /// Builds the invoice and its page from `draft`, with the rate in `computed`, and finds what is wrong with it.
    private func work(_ draft: Draft, failed: Bool, into computed: inout Computed) {
        var found: [EditorProblem] = []
        if draft.terms == nil {
            found.append(EditorProblem(text: EditorText.chooseClient, blocksDraft: true))
        }
        // The number of an invoice that is issued is not the person's to type, so it is not their problem either.
        if numberIsEditable, InvoiceNumbering.digits(of: draft.number).isEmpty {
            found.append(EditorProblem(text: EditorText.numberWithoutDigit, blocksDraft: true))
        }
        if !draft.dateIsUsable {
            found.append(EditorProblem(text: EditorText.invalidDate, blocksDraft: true))
        }
        if draft.dueDays.map({ !EditorLimits.dueDays.contains($0) }) ?? true {
            found.append(EditorProblem(text: EditorText.invalidDueDays, blocksDraft: true))
        }
        if failed {
            found.append(EditorProblem(text: EditorText.notPrepared, blocksDraft: true))
        }
        let checked = InvoiceEditorChecks.check(draft.items, vatMode: draft.vatMode)
        found += checked.problems
        // A draft is saved without a rate, an invoice is issued with one.
        if let gap = computed.rateGap {
            found.append(EditorProblem(text: text(of: gap), blocksDraft: false))
        }
        if InvoiceEditorChecks.lineCount(of: draft.note) > EditorLimits.noteLines {
            found.append(EditorProblem(text: EditorText.noteTooLong, blocksDraft: true))
        }
        computed.problems = found
        computed.tooHigh = checked.tooHigh
        guard let terms = draft.terms, draft.dateIsUsable, !checked.tooHigh else { return }
        let invoice = assemble(draft, terms: terms, items: checked.items, rate: computed.rate)
        let page = InvoiceDocument.make(invoice: invoice, supplier: supplier, accounts: accounts)
        if !InvoicePDFRenderer.fitsOnOnePage(page) {
            computed.problems.append(EditorProblem(text: InvoicePDFRenderer.doesNotFitMessage, blocksDraft: true))
        }
        computed.invoice = invoice
        computed.document = page
        computed.totals = Self.totals(of: invoice, rate: computed.rate)
        if case .unavailable(let reason) = QRPayload.payload(for: invoice, supplier: supplier, accounts: accounts) {
            computed.qrReason = reason
        }
    }

    /// The invoice as it would be saved now, with the status it has (a new invoice is a draft until it is issued).
    private func assemble(_ draft: Draft, terms: ClientTerms, items: [InvoiceItem], rate: StoredRate?) -> Invoice {
        let number = editing?.status == .issued ? editing?.number ?? "" : Self.trimmed(draft.number)
        return Invoice(
            id: editing?.id ?? 0, number: number, clientID: draft.clientID == 0 ? nil : draft.clientID,
            client: terms.snapshot, currency: terms.currency, issueDate: draft.issueDate, duzp: draft.duzp,
            dueDate: draft.previewDueDate, items: items, vatMode: draft.vatMode,
            invoiceRate: terms.currency.isCZK ? nil : rate,
            qrEnabled: draft.qrEnabled && Self.qrIsOnByDefault(for: terms.currency), note: Self.trimmed(draft.note),
            language: terms.language, paymentMethod: terms.paymentMethod, status: editing?.status ?? .draft,
            review: editing?.review, payment: editing?.payment, source: editing?.source ?? .app)
    }

    /// The year and the month of the DUZP as the first six digits of every number of the month, and of the first one.
    private static func monthPrefix(of duzp: CivilDate) -> String {
        String(InvoiceNumbering.next(forDUZP: duzp, existingNumbers: []).prefix(6))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The whole number of days that `text` says: digits only, around which spaces do not matter.
    private static func days(in text: String) -> Int? {
        let digits = trimmed(text)
        guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return Int(digits)
    }

    private static func totals(of invoice: Invoice, rate: StoredRate?) -> EditorTotals {
        func money(_ minor: Int64) -> String {
            CzechFormat.money(Money(minor: minor, currency: invoice.currency))
        }
        var inCrowns: String?
        if invoice.isForeignCurrency, let rate, rate.rate.currency == invoice.currency {
            inCrowns =
                "≈ " + CzechFormat.halere(rate.rate.czkHalere(fromMinor: invoice.totalMinor)) + " kurzem ČNB k DUZP"
        }
        return EditorTotals(
            base: money(invoice.netMinor), vatLabel: "DPH \(invoice.vatMode.ratePercent)\u{00A0}%",
            vat: money(invoice.vatMinor), total: money(invoice.totalMinor), inCrowns: inCrowns)
    }

    // MARK: The number and the rate

    /// The number proposed for a new invoice whose number is the proposal: the year and the month of the DUZP and one
    /// more than the highest of the numbers of that month, drafts included. The same goes for a draft that exists whose
    /// number has the year and the month of its DUZP, once the DUZP moves to another month; back in the month of its
    /// number it has its number again. Nil for any other number, such as one that was typed, and for an invoice that is
    /// issued.
    private func proposeNumber(for draft: Draft, in database: Database) async throws -> String? {
        guard editing?.status != .issued, draft.number == proposedNumber else { return nil }
        let prefix = Self.monthPrefix(of: draft.duzp)
        if let editing, InvoiceNumbering.digits(of: editing.number).hasPrefix(prefix) {
            return editing.number
        }
        if prefix != numbersPrefix {
            existingNumbers = try await database.invoiceNumbers(withDigitsPrefix: prefix)
            numbersPrefix = prefix
        }
        return InvoiceNumbering.next(forDUZP: draft.duzp, existingNumbers: existingNumbers)
    }

    /// What the editor says of a rate that is missing. An invoice that is issued has no draft to save, so its changes
    /// wait.
    private func text(of gap: RateGap) -> String {
        switch gap {
        case .notQuoted: EditorText.currencyNotQuoted
        case .notDownloaded: editing?.status == .issued ? EditorText.changesWaitForRates : EditorText.ratesNotDownloaded
        }
    }

    /// The rate the invoice would have, and whether it is the one the invoice has fixed already.
    private struct RateOutcome {
        var rate: StoredRate?
        var isFixed = false

        /// Why the invoice has no rate that may be fixed, and the yearly files of the ČNB that may bring it: none
        /// where nothing can be fetched, as for a currency the ČNB does not quote.
        var gap: RateGap?
        var years: [Int] = []
    }

    /// The rate that is fixed on the invoice: none in crowns; the rate the invoice has, while it is issued and its DUZP
    /// and currency are what they were (also when it has none); otherwise the ČNB rate of the DUZP, or, while the
    /// declaration of the DUZP is still to come and the cache is current, the last declared rate
    /// (`InvoiceRateFixing.rateToFix`). Without a rate the invoice has a gap: the rate may come with the files of the
    /// ČNB, or never, for a currency the ČNB does not quote.
    private func rateOfTheDUZP(for draft: Draft, in database: Database) async throws -> RateOutcome {
        guard let app else { throw VaultError.locked }
        let currency = draft.terms?.currency ?? .czk
        guard !currency.isCZK else { return RateOutcome() }
        if let editing, editing.status == .issued, editing.currency == currency, editing.duzp == draft.duzp {
            return RateOutcome(rate: editing.invoiceRate, isFixed: editing.invoiceRate != nil)
        }
        let day = draft.duzp
        let expectedNewest = RefreshPlanner.expectedNewestDeclaration(now: app.dependencies.clock.now())
        let lookup = try await database.cnbRate(currency, on: day)
        let latestBefore = try await database.latestCNBRate(currency, onOrBefore: day.adding(days: -1))
        let newestCached = try await database.newestCNBDeclaration()
        if let rate = InvoiceRateFixing.rateToFix(
            currency: currency, duzp: day, lookup: lookup, latestBefore: latestBefore,
            expectedNewestDeclaration: expectedNewest, newestCachedDeclaration: newestCached)
        {
            return RateOutcome(rate: rate)
        }
        if case .notPublished = lookup {
            return RateOutcome(gap: .notQuoted)
        }
        let years = InvoiceRateFixing.yearsToFetch(duzp: day, expectedNewestDeclaration: expectedNewest)
        return RateOutcome(gap: .notDownloaded, years: years)
    }

    // MARK: Saving

    /// "Uložit koncept": stores the invoice as a draft, for a new invoice and for a draft. Returns its id.
    ///
    /// The invoice is saved in one call on the database. Throws `InvoiceEditorError.invalid` when a draft cannot be
    /// saved as it is, `InvoiceEditorError.notAvailable` for an invoice that is issued, `InvoiceError.duplicateNumber`
    /// when the number exists, `InvoiceError.notFound` when the invoice was deleted meanwhile (it is never brought
    /// back), `InvoiceEditorError.invoiceChanged` when it was changed, and what the database throws.
    @discardableResult
    func saveDraft() async throws -> Int64 {
        guard editing == nil || editing?.status == .draft else { throw InvoiceEditorError.notAvailable }
        return try await save(as: .draft)
    }

    /// "Vystavit fakturu": issues a new invoice or a draft. The rate of the DUZP is fixed on it, and so is the data of
    /// its client, as they are now. Returns its id. Throws what `saveDraft()` throws, with `invalid` for any problem
    /// the invoice has.
    @discardableResult
    func issue() async throws -> Int64 {
        guard editing == nil || editing?.status == .draft else { throw InvoiceEditorError.notAvailable }
        return try await save(as: .issued)
    }

    /// "Vystavit" in the detail of a draft in Faktury: makes the editor of the draft `id` as `opening(_:in:)` makes it
    /// for `.edit(id)` and loads it as the window does (`load()`), without showing it, and issues the draft with the
    /// work of "Vystavit fakturu" (`issue()`): the invoice worked out afresh with the data of its client as they are
    /// then, the ČNB rate of the DUZP fixed on it, the same checks, the same refusal of an invoice that was changed
    /// meanwhile, and the same writes, conversions and reloads after it. The window stays as it is: the screen, the
    /// editor that is open and the detail, and no banner says that it saved. The files of the ČNB that a rate missing
    /// in the cache may be in are not asked for here; the editor asks for them once it is shown.
    ///
    /// Returns the id. Throws `InvoiceError.notFound` when there is no such invoice, `InvoiceEditorError.invalid` with
    /// `EditorText.notPrepared` when what the invoice is made of cannot be read, and what `issue()` throws: among it
    /// `InvoiceEditorError.notAvailable` for an invoice that is issued already, and `InvoiceEditorError.invalid` with
    /// the first problem of a draft that cannot be issued.
    @discardableResult
    static func issueDraft(_ id: Int64, app: AppModel) async throws -> Int64 {
        guard let database = app.database else { throw VaultError.locked }
        guard let invoice = try await database.invoice(id: id) else { throw InvoiceError.notFound }
        let model = InvoiceEditorModel(app: app, template: nil, editing: invoice, headless: true)
        await model.load()
        if model.loadFailed {
            throw InvoiceEditorError.invalid(EditorText.notPrepared)
        }
        return try await model.issue()
    }

    /// "Uložit změny": stores the changes of an invoice that exists, which stays what it is, a draft or issued. The
    /// number, the rate of the DUZP (unless the DUZP or the currency changed), the data of the client (unless another
    /// client was chosen) and the payment (worked out again) of an issued invoice stay. Returns its id. Throws what
    /// `saveDraft()` throws, and `InvoiceEditorError.notAvailable` for a new invoice.
    @discardableResult
    func saveChanges() async throws -> Int64 {
        guard let editing else { throw InvoiceEditorError.notAvailable }
        return try await save(as: editing.status)
    }

    /// Saves what is typed now. The invoice is worked out afresh for the purpose (the rate of the DUZP and the data of
    /// the client as they are now) and saved as that run found it, whatever is typed while it is saved. One save runs
    /// at a time. A failure is kept for the screen to show until the next edit (`failure`).
    private func save(as status: InvoiceStatus) async throws -> Int64 {
        guard !isSaving else { throw InvoiceEditorError.alreadySaving }
        isSaving = true
        defer { isSaving = false }
        let attempted = inputs
        do {
            return try await write(as: status)
        } catch {
            if case InvoiceError.duplicateNumber = error {
                // An import or another window took the number since the numbers of the month were looked up.
                numbersPrefix = ""
            }
            failedSave = FailedSave(inputs: attempted, text: Self.failureText(for: error))
            throw error
        }
    }

    private func write(as status: InvoiceStatus) async throws -> Int64 {
        guard let app, let database = app.database else { throw VaultError.locked }
        await refreshIfDataChanged()
        computations += 1
        let run = computations
        let baseline = editing
        let computed = await compute(draft)
        if run == computations {
            publish(computed)
        }
        // The app converted the payment again while the invoice was worked out (`rebase(onto:replacing:)`): the
        // invoice is worked out again from the one that is stored now.
        guard editing == baseline else { return try await write(as: status) }
        let blocking = status == .issued ? computed.problems.first : computed.problems.first { $0.blocksDraft }
        guard blocking == nil, var invoice = computed.invoice else {
            throw InvoiceEditorError.invalid(blocking?.text ?? EditorText.notPrepared)
        }
        invoice.status = status
        let id: Int64
        if let editing {
            if invoice == editing {
                // Nothing changed: nothing is written, and an invoice of the import stays as the import left it. The
                // invoice has to be there as the editor knows it all the same, as it is for a save that writes.
                guard let current = try await database.invoice(id: editing.id) else { throw InvoiceError.notFound }
                guard current == editing else {
                    // The app's own conversion came meanwhile, and the editor took it: the save starts again with it.
                    guard self.editing == editing else { return try await write(as: status) }
                    throw InvoiceEditorError.invoiceChanged
                }
                await finishSaving(editing.id, of: invoice, wrote: false)
                return editing.id
            }
            if case .imported(let fakturoidID, let fingerprint, _) = invoice.source {
                // Any change made in the app to an invoice of the import keeps a later import away from it.
                invoice.source = .imported(fakturoidID: fakturoidID, fingerprint: fingerprint, changedInApp: true)
            }
            guard try await database.saveInvoice(invoice, ifUnchangedFrom: editing) else {
                if try await database.invoice(id: editing.id) == nil {
                    throw InvoiceError.notFound
                }
                // The app's own conversion was saved first, and the editor took it: the save starts again with it.
                guard self.editing == editing else { return try await write(as: status) }
                throw InvoiceEditorError.invoiceChanged
            }
            id = editing.id
        } else {
            id = try await database.saveInvoice(invoice)
        }
        await finishSaving(id, of: invoice, wrote: true)
        return id
    }

    /// After a save: Faktury shows the invoice with its detail open. A new invoice switches the year shown to the year
    /// of its day of issue, which is the year of the list it is in, when that is not in the future; a change of an
    /// invoice says so in a banner. The app is told of the write, when there was one, and the years of the payment the
    /// invoice has and had are converted again by the method each uses then, as a change of its currency may change
    /// what they have the uniform rate for (`AppModel.recomputePaymentsAfterChanges(inYears:)`). An editor that is
    /// never shown (`isHeadless`) leaves the window as it is, the editor that is open, the screen and the detail, and
    /// shows no banner; the rest is the same.
    private func finishSaving(_ id: Int64, of invoice: Invoice, wrote: Bool) async {
        guard let app else { return }
        let paymentYears = Set([invoice.payment?.date.year, editing?.payment?.date.year].compactMap { $0 })
        if !isHeadless {
            app.editorRequest = nil
            app.openInvoice(id)
        }
        guard wrote else { return }
        await app.recomputePaymentsAfterChanges(inYears: paymentYears)
        if editing == nil, invoice.issueDate.year != app.asOf.year, invoice.issueDate.year <= app.today.year {
            app.selectYear(invoice.issueDate.year)
        }
        if editing != nil, !isHeadless {
            app.showBanner("Změny faktury \(invoice.number) jsou uložené.")
        }
        await app.didWrite()
    }

    /// What to tell the person when saving failed with `error`.
    static func failureText(for error: any Error) -> String {
        switch error {
        case InvoiceError.duplicateNumber:
            return "Číslo faktury už existuje."
        case InvoiceError.notFound:
            return "Faktura mezitím byla smazána."
        case InvoiceEditorError.invoiceChanged:
            return "Faktura se mezitím změnila. Zavřete úpravy a otevřete ji znovu."
        case InvoiceEditorError.invalid(let text):
            return text
        default:
            return "Fakturu se nepodařilo uložit."
        }
    }

    // MARK: QR

    /// The box is ticked by default for the currencies that have a code to print: crowns (QR Platba) and euros (EPC).
    static func qrIsOnByDefault(for currency: CurrencyCode) -> Bool {
        currency == .czk || currency == .eur
    }
}
