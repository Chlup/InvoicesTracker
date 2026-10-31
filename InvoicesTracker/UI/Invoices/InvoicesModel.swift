import Foundation
import Observation

/// The model of Faktury: loads what the screen shows for the selected year as of the day of "K datu", in the chosen
/// scope, status chip and search, and turns it into view data (`InvoiceListBuilder`); keeps the detail of one invoice
/// open or closed; issues a draft from its detail in one click, without the editor; and deletes an invoice, or removes
/// its payment, once its number is typed.
///
/// The money is as of the day of "K datu", but the status of an invoice is as of today, whatever year or day is shown:
/// it drives the pill, the chips and their counts, the chosen chip and the detail with its buttons. A payment of
/// January makes an invoice of the year before paid in the list of that year too.
///
/// A load reads the invoices of the selected year in the scope, what the search found among them and the rates the
/// list converts with, in one call on the database (`Database.invoiceListSource`), and then works out what each of the
/// invoices leaves after the levies its payment adds, or would add, as of the day shown (`AppModel.invoiceNetIncomes`).
/// An invoice whose net income cannot be worked out shows a dash, and the rest of the list shows as usual. The screen
/// loads again whenever what the data depends on changes (`AppModel.reloadKey`), and whenever the scope or the chip
/// changes. The model keeps the data of the last load until the next one has finished, so that the table does not
/// flash empty; a load that fails shows a line instead.
///
/// The detail is closed when the screen is entered (a new model starts closed). It opens on a click on a row, on the
/// arrow keys of the table, and on arrival when another screen asks for an invoice (`AppModel.pendingDetailInvoiceID`:
/// Přehled, a new invoice, a payment that was recorded). A second click on the open row closes it. A change of the
/// chip, the scope or the year closes it when its invoice is not in the new list. A search closes it only when its
/// invoice stops matching: an invoice that is outside the list for another reason (it was opened from another screen)
/// stays open while the search finds it. Any other reload of the data leaves it as it is. A chip of the invoices to
/// check that has none left in the year goes back to every status; a search that finds none of them leaves it chosen.
@MainActor
@Observable
final class InvoicesModel {
    /// What the screen says in place of the table when the data cannot be loaded.
    static let loadFailureText = "Faktury se nepodařilo načíst."

    /// The invoices issued in the year, or those paid in it. A scope starts with every status.
    var scope = InvoiceScope.issued {
        didSet {
            if scope != oldValue {
                filter = .all
            }
        }
    }

    /// The status chip that is chosen.
    var filter = InvoiceStatusFilter.all

    /// What the screen shows: nil until the first load has finished, and after a load that failed.
    private(set) var data: InvoiceListData?

    /// The day `data` is shown as of, which the detail of an invoice opened from the list is worked out for until its
    /// own load has finished: its money, and its pill, which writes a payment with its year when that is another than
    /// the year of this day (`InvoiceDisplayStatus.label(asOf:)`). The status itself is as of today. The rows write
    /// the dates with their year themselves (`InvoiceRow`).
    private(set) var shownDay: CivilDate?

    /// What the screen says in place of the table when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// What the screen says in an alert when an action cannot be done, until it is closed: the invoice that an action
    /// was asked for is gone (`invoiceIsGone(_:)`), or the action failed.
    var actionFailure: String?

    /// What the alert says when the invoice that an action was asked for was deleted meanwhile.
    nonisolated static let invoiceGoneText = "Faktura mezitím byla smazána."

    /// What the detail of a draft says when the ČNB rate of its DUZP is not in the cache, also once the file of its
    /// year was asked for: the reason of the editor (`EditorText.ratesNotDownloaded`) without its advice to save the
    /// draft, which is saved already.
    nonisolated static let rateNotDownloadedText =
        "Kurz ČNB k DUZP zatím není stažený. Fakturu vystavíte, až se kurzy stáhnou."

    /// What the detail of a draft says when the draft was changed while it was being issued, in another window: the
    /// reason of the editor (`InvoiceEditorError.invoiceChanged`) with advice that fits the detail in place of closing
    /// the editing, as each press of "Vystavit" loads the draft afresh.
    nonisolated static let changedMeanwhileText = "Faktura se mezitím změnila. Zkuste ji vystavit znovu."

    /// The invoice whose detail is open, or nil when it is closed. Setting it shows that invoice's detail as far as
    /// the list can tell, until `loadDetail()` has the rest; why the draft of the detail before could not be issued
    /// goes with that detail.
    var openInvoiceID: Int64? {
        didSet {
            guard openInvoiceID != oldValue else { return }
            openInvoice = nil
            detail = nil
            issueProblem = nil
            if let id = openInvoiceID, let invoice = loadedInvoices[id] {
                openInvoice = invoice
                detail = InvoiceDetailBuilder.build(
                    InvoiceDetailInput(
                        invoice: invoice, asOf: shownDay ?? app.receivedThrough, statusDay: app.today, duzpRate: nil,
                        paymentEffect: nil, estimate: nil))
            }
        }
    }

    /// The open invoice as it is stored.
    private(set) var openInvoice: Invoice?

    /// What the detail says about the open invoice.
    private(set) var detail: InvoiceDetail?

    /// Why the draft whose detail is open could not be issued in one click (`issue(_:)`): the reason the editor gives,
    /// without the advice that only fits the editor (`issueProblemText(for:)`), or nil. It goes when the detail moves
    /// to another invoice or closes, and when the draft is issued after all.
    private(set) var issueProblem: String?

    /// Whether a draft is being issued in one click (`issue(_:)`), the file of the ČNB it may ask for included:
    /// "Vystavit" is off meanwhile, and a press of it does nothing.
    private(set) var isIssuing = false

    private let app: AppModel

    /// The invoices of the last load, by id, which a click on a row opens without waiting for the database.
    @ObservationIgnored private var loadedInvoices: [Int64: Invoice] = [:]

    /// How many loads of the list, and of the detail, have started. Only the latest may show its result: one that was
    /// started for a year, a chip or an invoice that has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0
    @ObservationIgnored private var detailLoadsStarted = 0

    /// What the list was last built for, to tell a change of what is chosen from a reload of the same.
    @ObservationIgnored private var appliedSelection: Selection?

    /// What decides which invoices the list holds.
    private struct Selection: Equatable {
        var year: Int
        var scope: InvoiceScope
        var filter: InvoiceStatusFilter
        var words: [String]

        /// Whether `other` is the same but for the words of the search.
        func differsOnlyInTheSearch(from other: Selection) -> Bool {
            year == other.year && scope == other.scope && filter == other.filter && words != other.words
        }
    }

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading the list

    /// Loads the list of the selected year as of the day shown, and the detail of the open invoice. A failure is logged
    /// (the domain and the code of the error alone) and shows `errorText` in place of the table.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        // Another screen asked for an invoice: it is open on arrival, whatever the list holds, and asked for once.
        if let pending = app.pendingDetailInvoiceID {
            app.pendingDetailInvoiceID = nil
            openInvoiceID = pending
        }
        // The year, the day and the choices as they are when the load starts: all of it is about them, however they
        // change meanwhile (a change starts a load of its own). The status is about today, whatever day is shown, and
        // so is the money: the list counts a payment as received up to today (`AppModel.receivedThrough`), not up to
        // the end of the month that the reporting cutoff reaches.
        let shown = app.asOf
        let day = app.receivedThrough
        let today = app.today
        let searchText = app.searchText
        var selection = Selection(
            year: shown.year, scope: scope, filter: filter, words: SearchFolding.words(searchText))
        do {
            guard let database = app.database else { throw VaultError.locked }
            let source = try await database.invoiceListSource(
                scope: selection.scope, year: shown.year, asOf: day, searchText: searchText)
            guard thisLoad == loadsStarted else { return }
            let netIncomes = await app.invoiceNetIncomes(of: source.invoices, asOf: day)
            guard thisLoad == loadsStarted else { return }
            func list(of filter: InvoiceStatusFilter, searching search: String) -> InvoiceListData {
                InvoiceListBuilder.build(
                    InvoiceListInput(
                        year: shown.year, asOf: day, statusDay: today, scope: selection.scope, filter: filter,
                        invoices: source.invoices, searchText: search, matchingIDs: source.matchingIDs,
                        otherYearCounts: source.otherYearCounts, paymentDayRates: source.paymentDayRates,
                        issueDayRates: source.issueDayRates, uniformRates: source.uniformRates,
                        netIncomes: netIncomes))
            }
            var built = list(of: selection.filter, searching: searchText)
            // The chip of the invoices to check has none left in the year (the last one was resolved): every status is
            // shown again. A search that finds none of them keeps the chip.
            if selection.filter == .review, built.chipCounts[.review, default: 0] == 0,
                list(of: .all, searching: "").chipCounts[.review, default: 0] == 0
            {
                selection.filter = .all
                built = list(of: .all, searching: searchText)
            }
            // A change of what is chosen closes the detail of an invoice that is not in the new list, unless only the
            // search changed and the invoice matches it still.
            var closesDetail = false
            if let applied = appliedSelection, applied != selection, let open = openInvoiceID,
                !built.rows.contains(where: { $0.id == open })
            {
                let staysOpen: Bool
                if selection.differsOnlyInTheSearch(from: applied) {
                    staysOpen = try await invoiceMatchesSearch(open, searchText: searchText, in: database)
                    guard thisLoad == loadsStarted else { return }
                } else {
                    staysOpen = false
                }
                closesDetail = !staysOpen
            }
            loadedInvoices = Dictionary(source.invoices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            data = built
            shownDay = day
            errorText = nil
            if filter != selection.filter {
                filter = selection.filter
            }
            if closesDetail {
                closeDetail()
            }
            appliedSelection = selection
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading Faktury", failedWith: error)
            data = nil
            errorText = Self.loadFailureText
            return
        }
        await loadDetail()
    }

    // MARK: The detail

    /// Loads the detail of the open invoice as it is stored: the rate of its DUZP, and what its payment adds to the
    /// levies, or what a payment would add, with what the invoice leaves after them. The levies are those of the net
    /// income the list shows for the invoice as of the day shown (`AppModel.invoiceNetIncomes(of:asOf:)`), so the
    /// detail and the list always agree: an invoice that is paid and counts as income gets the effect of its payment,
    /// and one that is not paid and not in review gets the estimate of a payment on the day its money is expected. An
    /// invoice that is not there any more (deleted meanwhile) closes the detail. A figure that cannot be worked out is
    /// logged and left out; the rest of the detail shows.
    func loadDetail() async {
        detailLoadsStarted += 1
        let thisLoad = detailLoadsStarted
        guard let id = openInvoiceID else { return }
        let asOf = app.receivedThrough
        let today = app.today
        do {
            guard let database = app.database else { throw VaultError.locked }
            guard let invoice = try await database.invoice(id: id) else {
                if thisLoad == detailLoadsStarted, openInvoiceID == id {
                    closeDetail()
                }
                return
            }
            var input = InvoiceDetailInput(
                invoice: invoice, asOf: asOf, statusDay: today,
                duzpRate: try await rateOfTheDUZP(of: invoice, in: database), paymentEffect: nil, estimate: nil)
            // An invoice has a net when its payment counts as income, or when it is not paid and not in review: issued,
            // or a draft that would be once it is issued, but not one to check, which does not count until it is
            // resolved.
            if let net = await app.invoiceNetIncomes(of: [invoice], asOf: asOf)[invoice.id] {
                if net.isEstimate {
                    input.estimate = LevyEstimate(day: net.day, incomeHalere: net.incomeHalere, effect: net.effect)
                } else {
                    input.paymentEffect = net.effect
                }
            }
            guard thisLoad == detailLoadsStarted, openInvoiceID == id else { return }
            openInvoice = invoice
            detail = InvoiceDetailBuilder.build(input)
        } catch {
            guard thisLoad == detailLoadsStarted else { return }
            AppModel.log("Loading the detail of an invoice", failedWith: error)
        }
    }

    /// Whether the invoice `id` matches the words of `searchText`, wherever it is: its search document is looked at in
    /// the list of the year it was issued in, whichever year, scope and chip the list shows. A text without words
    /// matches every invoice. An invoice that is not there does not match.
    private func invoiceMatchesSearch(_ id: Int64, searchText: String, in database: Database) async throws -> Bool {
        guard !SearchFolding.words(searchText).isEmpty else { return true }
        guard let invoice = try await database.invoice(id: id) else { return false }
        let found = try await database.searchInvoiceIDs(
            searchText, scope: .issued, year: invoice.issueDate.year, asOf: invoice.issueDate)
        return found.contains(id)
    }

    /// The ČNB rate that stands for the DUZP of `invoice`, for a draft (the rate that would be fixed on it now, by the
    /// rule of the editor: a draft never shows a rate that the editor would not issue it with) and for an invoice in a
    /// foreign currency that has none of its own; nil for any other invoice, and when no rate may be fixed yet.
    private func rateOfTheDUZP(of invoice: Invoice, in database: Database) async throws -> StoredRate? {
        guard !invoice.currency.isCZK, invoice.status == .draft || invoice.invoiceRate == nil else { return nil }
        let lookup = try await database.cnbRate(invoice.currency, on: invoice.duzp)
        let latestBefore = try await database.latestCNBRate(invoice.currency, onOrBefore: invoice.duzp.adding(days: -1))
        let newestCached = try await database.newestCNBDeclaration()
        return InvoiceRateFixing.rateToFix(
            currency: invoice.currency, duzp: invoice.duzp, lookup: lookup, latestBefore: latestBefore,
            expectedNewestDeclaration: RefreshPlanner.expectedNewestDeclaration(now: app.dependencies.clock.now()),
            newestCachedDeclaration: newestCached)
    }

    /// What the payment of `invoice` adds to the levies of its year, or nil when that cannot be worked out: the figure
    /// the dialog that deletes the invoice names (`deletionSummary(for:)`), and the step that removes its payment
    /// (`paymentRemovalSummary(for:)`).
    private func effect(of payment: Payment, for invoice: Invoice) async -> ReceiptEffect? {
        let receipt = Receipt(
            day: payment.date, czkNetHalere: payment.czkNetHalere, czkVatHalere: payment.czkVatHalere,
            source: .invoice(invoice.id))
        do {
            return try await app.effect(of: receipt)
        } catch {
            AppModel.log("Working out what a payment adds to the levies", failedWith: error)
            return nil
        }
    }

    /// A click on a row: opens the detail of that invoice, and closes it when it is the invoice that is open already.
    func click(_ id: Int64) {
        openInvoiceID = InvoiceListBuilder.toggleDetail(open: openInvoiceID, clicked: id)
    }

    /// The × of the detail, or anything else that closes it.
    func closeDetail() {
        openInvoiceID = nil
    }

    /// ↓ (`step` 1) or ↑ (`step` −1) in the table: opens the invoice of the row under or above the open one. With no
    /// row of the list open (none is, or the open invoice is not in the list), ↓ opens the first row and ↑ the last. At
    /// either end of the list the open row stays open; an empty list opens nothing.
    func moveSelection(by step: Int) {
        guard let rows = data?.rows, !rows.isEmpty else { return }
        let index: Int
        if let open = openInvoiceID, let current = rows.firstIndex(where: { $0.id == open }) {
            index = min(max(current + step, 0), rows.count - 1)
        } else {
            index = step > 0 ? 0 : rows.count - 1
        }
        openInvoiceID = rows[index].id
    }

    // MARK: The year and the search

    /// The link to another year that has matches of the search: shows that year, with every status chip and the search
    /// kept, and closes the detail. The scope stays.
    func switchToYear(_ year: Int) {
        app.selectYear(year)
        filter = .all
        closeDetail()
    }

    /// Zrušit hledání: the search of the app is empty, and the list is the whole category.
    func clearSearch() {
        app.searchText = ""
    }

    // MARK: Issuing

    /// What the detail of a draft says when issuing it in one click failed with `error`: the reason the editor gives
    /// (`InvoiceEditorModel.failureText(for:)`), without the advice that only fits the editor. A rate of the DUZP that
    /// is not downloaded says it without the advice to save the draft (`rateNotDownloadedText`), and a draft changed
    /// meanwhile says that it can be issued again instead of closing the editing (`changedMeanwhileText`). Every other
    /// reason is the editor's, word for word; the editor keeps its own texts.
    static func issueProblemText(for error: any Error) -> String {
        switch error {
        case InvoiceEditorError.invalid(let text) where text == EditorText.ratesNotDownloaded:
            rateNotDownloadedText
        case InvoiceEditorError.invoiceChanged:
            changedMeanwhileText
        default:
            InvoiceEditorModel.failureText(for: error)
        }
    }

    /// "Vystavit" in the detail of a draft: issues the draft `id` in one click, as "Vystavit fakturu" in the editor
    /// would, without showing the editor, after asking the ČNB for the file of its year where the rate of its DUZP is
    /// not in the cache (`InvoiceEditorModel.issueDraft(_:app:)`). The detail stays where it is, and once the draft is
    /// issued it shows the invoice as issued, without a notice; the app is told of the write, so the list loads again.
    /// A draft that cannot be issued stays a draft: the reason the editor gives, in the words of the detail
    /// (`issueProblemText(for:)`), is kept for its detail (`issueProblem`) and told to VoiceOver, as long as the detail
    /// is still on it. A draft that is issued already, meanwhile in another window, is what was asked for, and its
    /// detail shows it so; a draft deleted meanwhile closes its detail, and the screen says so (`invoiceIsGone(_:)`).
    /// One draft is issued at a time: a press while one is being issued does nothing (`isIssuing`), and the detail is
    /// loaded again before the next press can come.
    func issue(_ id: Int64) async {
        guard !isIssuing else { return }
        isIssuing = true
        defer { isIssuing = false }
        do {
            try await InvoiceEditorModel.issueDraft(id, app: app)
            issueProblem = nil
            await loadDetail()
        } catch InvoiceError.notFound {
            invoiceIsGone(id)
        } catch InvoiceEditorError.notAvailable {
            issueProblem = nil
            await loadDetail()
        } catch {
            AppModel.log("Issuing a draft from its detail", failedWith: error)
            guard openInvoiceID == id else { return }
            let problem = Self.issueProblemText(for: error)
            issueProblem = problem
            app.announceWhenUnlocked(problem)
        }
    }

    // MARK: Deleting

    /// What the dialog that deletes the invoice with `id` says, with what its payment adds to the levies, or nil when
    /// there is no such invoice: its detail closes then and the screen says so (`invoiceIsGone(_:)`). Throws
    /// `VaultError.locked` while the data is locked, and what the database throws.
    func deletionSummary(for id: Int64) async throws -> InvoiceDeletionSummary? {
        guard let database = app.database else { throw VaultError.locked }
        guard let invoice = try await database.invoice(id: id) else {
            invoiceIsGone(id)
            return nil
        }
        var levies: ReceiptEffect?
        if let payment = invoice.payment, InvoiceDetailBuilder.countsAsIncome(invoice) {
            levies = await effect(of: payment, for: invoice)
        }
        return InvoiceDetailBuilder.deletion(of: invoice, effect: levies)
    }

    /// Deletes the invoice with `id` when `typed` is its number (or the digits of it), in one call on the database; the
    /// detail of the invoice closes, the app is told of the write, and a banner says so. Returns false and changes
    /// nothing when the text typed is not the number or the invoice is not there. The year of its payment is converted
    /// again by the method it uses then, as the payment may have been its only one in a currency it has no uniform rate
    /// of (`AppModel.recomputePaymentsAfterChanges(inYears:)`); nothing else is worked out again. Throws
    /// `VaultError.locked` while the data is locked, and what the database throws.
    @discardableResult
    func delete(_ id: Int64, typed: String) async throws -> Bool {
        guard let database = app.database else { throw VaultError.locked }
        let paymentYear = try await database.invoice(id: id)?.payment?.date.year
        guard let number = try await database.deleteInvoice(id: id, confirmedBy: typed) else { return false }
        if openInvoiceID == id {
            closeDetail()
        }
        await app.recomputePaymentsAfterChanges(inYears: Set([paymentYear].compactMap { $0 }))
        app.showBanner("Faktura \(number) byla smazána.")
        await app.didWrite()
        return true
    }

    // MARK: Removing a payment

    /// What the step of the payment sheet that removes the payment of the invoice with `id` says, read as the invoice
    /// is stored now, with what its payment adds to the levies of its year: the figure the dialog that deletes the
    /// invoice names, which is the "Dopad na odvody" of the detail, left out when it cannot be worked out. Nil when
    /// there is nothing to remove: no invoice has the id, or it has no payment. The sheet that asks for it says so
    /// itself, so the screen raises no alert of its own over the sheet. A failure to read the invoice is logged and
    /// gives nil too.
    func paymentRemovalSummary(for id: Int64) async -> PaymentRemovalSummary? {
        do {
            guard let database = app.database else { throw VaultError.locked }
            guard let invoice = try await database.invoice(id: id), let payment = invoice.payment else { return nil }
            var levies: ReceiptEffect?
            if InvoiceDetailBuilder.countsAsIncome(invoice) {
                levies = await effect(of: payment, for: invoice)
            }
            return InvoiceDetailBuilder.paymentRemoval(of: invoice, effect: levies)
        } catch {
            AppModel.log("Preparing to remove a payment", failedWith: error)
            return nil
        }
    }

    /// Removes the payment of the invoice with `id` when `typed` is its number (or the digits of it), in one call on
    /// the database (`Database.removePayment(ofInvoice:confirmedBy:)`): the invoice is issued and unpaid again, and can
    /// be edited. The year of the payment is converted again by the method it uses then, as the payment may have been
    /// its only one in a currency it has no uniform rate of (`AppModel.recomputePaymentsAfterChanges(inYears:)`); a
    /// banner says what happened, the app is told of the write, which schedules the backups, and the detail stays open
    /// on the invoice and shows it unpaid at once. Returns false and changes nothing when the text typed is not the
    /// number, or the invoice is not there or has no payment. Throws `VaultError.locked` while the data is locked, and
    /// what the database throws.
    @discardableResult
    func removePayment(_ id: Int64, typed: String) async throws -> Bool {
        guard let database = app.database else { throw VaultError.locked }
        guard let removed = try await database.removePayment(ofInvoice: id, confirmedBy: typed) else { return false }
        await app.recomputePaymentsAfterChanges(inYears: Set([removed.payment?.date.year].compactMap { $0 }))
        app.showBanner("Platba faktury \(removed.number) byla odebrána – faktura je znovu nezaplacená.")
        await app.didWrite()
        if openInvoiceID == id {
            await loadDetail()
        }
        return true
    }

    // MARK: The PDF

    /// The page of the invoice with `id` as it prints: the invoice with the supplier and the bank account of its
    /// currency, as stored. Nil when there is no such invoice: its detail closes then and the screen says so
    /// (`invoiceIsGone(_:)`). Throws `VaultError.locked` while the data is locked, and what the database throws.
    func pdfDocument(for id: Int64) async throws -> InvoiceDocument? {
        guard let database = app.database else { throw VaultError.locked }
        guard let invoice = try await database.invoice(id: id) else {
            invoiceIsGone(id)
            return nil
        }
        return InvoiceDocument.make(
            invoice: invoice, supplier: try await database.supplier(), accounts: try await database.bankAccounts())
    }

    /// The invoice that an action was asked for is not there any more: its detail, if it is open, closes, and the
    /// screen says that it was deleted meanwhile.
    private func invoiceIsGone(_ id: Int64) {
        if openInvoiceID == id {
            closeDetail()
        }
        actionFailure = Self.invoiceGoneText
    }
}
