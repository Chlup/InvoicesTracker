import SwiftUI

// MARK: - The screen

/// Faktury: the choice of the invoices (the scope and the status chips, with the search field at the end of the same
/// row), the line about the search, the three tiles, the table with the detail of the open invoice beside it, and the
/// sheets that mark an invoice paid and show its PDF. Deleting an invoice is asked in a dialog inside the window, which
/// the window shows (`AppModel.invoiceDeletion`) and which goes when the screen does. ⌘F focuses the search field
/// (`AppModel.focusSearch()`), Esc or × clears it, and the text stays until it is cleared, also across screens and
/// years. The toolbar is the shell's, the same on every screen, as are the title and the line under it. The data is
/// loaded again whenever what it depends on changes.
struct InvoicesScreen: View {
    let app: AppModel
    @State private var model: InvoicesModel

    @State private var paying: PaymentSheetModel?
    @State private var pdf: InvoiceDocument?

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: InvoicesModel(app: app))
    }

    /// What the list depends on: what every screen loads for, today (the status of an invoice is as of today, so the
    /// list loads again when the day changes even if "K datu" stays on another day), the choices of this screen, and an
    /// invoice that another screen asked to open.
    private struct LoadTrigger: Hashable {
        var key: ReloadKey
        var today: CivilDate
        var scope: InvoiceScope
        var filter: InvoiceStatusFilter
        var pending: Int64?
    }

    private var loadTrigger: LoadTrigger {
        LoadTrigger(
            key: app.reloadKey, today: app.today, scope: model.scope, filter: model.filter,
            pending: app.pendingDetailInvoiceID)
    }

    var body: some View {
        content
            .task(id: loadTrigger) {
                await model.load()
            }
            .task(id: model.openInvoiceID) {
                await model.loadDetail()
            }
            .onChange(of: sheetOpen, initial: true) {
                // Hledat (⌘F) has nothing to reach while a sheet or a dialog is over the search field.
                app.invoiceSheetOpen = sheetOpen
            }
            .onDisappear {
                app.invoiceSheetOpen = false
                // The dialog asks about an invoice of this screen.
                app.invoiceDeletion = nil
            }
            .sheet(item: $paying) { payment in
                MarkPaidSheet(
                    model: payment, timeZone: app.dependencies.timeZone(),
                    cancel: { paying = nil },
                    saved: { paying = nil }
                )
                .idleLockCover()
            }
            .sheet(isPresented: pdfShown) {
                if let pdf {
                    PDFPreviewSheet(document: pdf)
                        .idleLockCover()
                }
            }
            .alert(
                "Akci se nepodařilo provést", isPresented: actionFailureShown,
                presenting: model.actionFailure
            ) { _ in
                Button("Zavřít", role: .cancel) {}
            } message: { text in
                Text(text)
            }
    }

    // MARK: The page

    @ViewBuilder
    private var content: some View {
        if let data = model.data {
            VStack(alignment: .leading, spacing: 14) {
                FilterRowLayout(spacing: 12, lineSpacing: 10) {
                    scopePicker
                    chips(of: data)
                    searchField
                }
                if let line = data.searchLine {
                    SearchLineView(
                        line: line, showYear: { model.switchToYear($0) }, clear: { model.clearSearch() })
                }
                InvoiceTilesView(tiles: SummaryTiles.make(from: data))
                // The detail stands beside the table, from its top to its bottom, and the table takes the rest.
                HStack(alignment: .top, spacing: 16) {
                    InvoiceTableView(
                        rows: data.rows, shownDay: model.shownDay ?? app.receivedThrough, openID: model.openInvoiceID,
                        emptyText: data.emptyText, click: { model.click($0) }, move: { model.moveSelection(by: $0) })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    detailCard
                }
                .frame(maxHeight: .infinity)
            }
            .pagePadding()
            // The page fills the room the window gives it and asks for no minimum size of its own, as the other
            // screens do; the minimum size of the window keeps that room enough. The page's own minimum is more than
            // the window has: the tiles, measured at no width, are thousands of points high. AppKit lays out a window
            // whose page asks for more room than it has again and again, the toolbar and the sidebar covering a
            // different part of the page each time, until it stops the app.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        } else if let errorText = model.errorText {
            Text(errorText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    private var scopePicker: some View {
        ScopePicker(year: app.asOf.year, scope: $model.scope)
    }

    private func chips(of data: InvoiceListData) -> some View {
        StatusChipsView(chips: data.visibleChips, counts: data.chipCounts, selection: $model.filter)
    }

    private var searchField: some View {
        InvoiceSearchField(text: Bindable(app).searchText, focusRequests: app.searchFocusRequests)
    }

    // MARK: The detail

    /// The card of the open invoice, once its detail is there; nothing while no invoice is open.
    @ViewBuilder
    private var detailCard: some View {
        if let detail = model.detail, detail.invoiceID == model.openInvoiceID {
            InvoiceDetailCard(
                detail: detail,
                close: { model.closeDetail() },
                pay: { markPaid() },
                issue: { app.editorRequest = .edit(detail.invoiceID) },
                edit: { app.editorRequest = .edit(detail.invoiceID) },
                showPDF: { showPDF(of: detail.invoiceID) },
                delete: { askToDelete(detail.invoiceID) })
        }
    }

    /// Whether a sheet, the dialog that deletes an invoice or the alert of a failed action is open over the screen.
    private var sheetOpen: Bool {
        paying != nil || app.invoiceDeletion != nil || pdf != nil || model.actionFailure != nil
    }

    // MARK: Actions

    /// Opens the sheet that records the payment of the open invoice.
    private func markPaid() {
        guard let invoice = model.openInvoice else { return }
        paying = PaymentSheetModel(app: app, invoice: invoice)
    }

    /// Opens the page of the invoice as it prints.
    private func showPDF(of id: Int64) {
        Task {
            do {
                pdf = try await model.pdfDocument(for: id)
            } catch {
                AppModel.log("Making the PDF of an invoice", failedWith: error)
                model.actionFailure = "PDF faktury se nepodařilo připravit."
            }
        }
    }

    /// Asks the window for the dialog that deletes the invoice, with what deleting it does, unless the screen has gone
    /// meanwhile.
    private func askToDelete(_ id: Int64) {
        Task {
            do {
                guard let summary = try await model.deletionSummary(for: id),
                    app.screen == .invoices, app.shownEditorRequest == nil
                else { return }
                app.invoiceDeletion = InvoiceDeletionRequest(
                    invoiceID: id, summary: summary,
                    delete: { typed in try await model.delete(id, typed: typed) })
            } catch {
                AppModel.log("Preparing to delete an invoice", failedWith: error)
                model.actionFailure = "Fakturu se nepodařilo načíst."
            }
        }
    }

    private var pdfShown: Binding<Bool> {
        Binding(
            get: { pdf != nil },
            set: { shown in
                if !shown {
                    pdf = nil
                }
            }
        )
    }

    private var actionFailureShown: Binding<Bool> {
        Binding(
            get: { model.actionFailure != nil },
            set: { shown in
                if !shown {
                    model.actionFailure = nil
                }
            }
        )
    }
}
