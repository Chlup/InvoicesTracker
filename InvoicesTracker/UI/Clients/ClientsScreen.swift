import SwiftUI

/// Odběratelé: Nový odběratel at the trailing side of the row above the card of the table, which opens the form of a
/// new client; the table of the clients with its summary row on top (`ClientTableView`); and beside the table the
/// detail of the selected client (`ClientDetailCard`), with Nová faktura, which starts an invoice for the client,
/// Upravit, which opens the form of the client, and its templates: Nová šablona opens the form of a new template for
/// the client, and the panel of a template starts an invoice from it or opens its form. A click on a row selects its
/// client and opens the detail, and a second click or the ✕ of the detail closes it; a client saved in its form becomes
/// the selected one, and a template saved or deleted in its form leaves the selection as it is. The title and the line
/// under it are the shell's. The data is loaded again whenever what it depends on changes.
///
/// The page is laid out as Faktury is: it fills the room the window gives it and asks for no minimum size of its own,
/// the card of the table reaches down to the bottom of the page and its rows scroll in it, and the detail stands beside
/// the card at the top, as high as its content and no higher than the card. Where the card is narrower than the table,
/// as in the least window with the detail open, the table scrolls sideways in its card.
struct ClientsScreen: View {
    let app: AppModel
    @State private var model: ClientsModel

    /// The form of a client that is open as a sheet.
    @State private var form: ClientFormModel?

    /// The form of a template that is open as a sheet.
    @State private var templateForm: TemplateFormModel?

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: ClientsModel(app: app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            content
        }
        .pagePadding()
        // The page fills the room the window gives it and asks for no minimum size of its own, as the other screens
        // do; the minimum size of the window keeps that room enough (`InvoicesScreen`).
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .task(id: app.reloadKey) {
            await model.load()
        }
        .sheet(item: $form) { form in
            ClientForm(
                model: form,
                cancel: { self.form = nil },
                saved: { id in
                    self.form = nil
                    model.didSaveClient(id)
                }
            )
            .idleLockCover()
        }
        .sheet(item: $templateForm) { templateForm in
            TemplateForm(
                model: templateForm, cancel: { self.templateForm = nil }, finished: { self.templateForm = nil }
            )
            .idleLockCover()
        }
    }

    /// Nový odběratel, at the trailing side of the row above the card, on the background of the window.
    private var topRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                form = model.newClientForm()
            } label: {
                Label("Nový odběratel", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(CapsuleButtonStyle(.onWindow))
        }
        .frame(minHeight: DesignMetrics.regularControlHeight)
    }

    /// The card of the table with the detail beside it, or why there is no table.
    @ViewBuilder
    private var content: some View {
        if let data = model.data {
            // The detail stands beside the card of the table, from its top as far down as its content goes and no
            // further than the bottom of the card, where it scrolls, and the card takes the rest; below its least
            // width the table scrolls sideways in the card.
            HStack(alignment: .top, spacing: DesignMetrics.cardSpacing) {
                ClientTableView(data: data, selectedID: model.selectedClientID, click: { model.click($0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                detailCard(in: data)
            }
            .frame(maxHeight: .infinity)
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: The detail

    /// The detail of the selected client, once the client is in `data`; nothing while no client is selected. Its
    /// buttons open the forms as sheets of the page, and start an invoice on Faktury.
    @ViewBuilder
    private func detailCard(in data: ClientsData) -> some View {
        if let detail = data.detail {
            ClientDetailCard(
                detail: detail,
                close: { model.closeDetail() },
                newInvoice: { model.newInvoice(forClient: detail.id) },
                edit: { form = model.form(editing: detail.id) },
                newTemplate: { templateForm = model.newTemplateForm(forClient: detail.id) },
                useTemplate: { model.newInvoice(fromTemplate: $0) },
                editTemplate: { templateForm = model.templateForm(editing: $0) })
        }
    }
}
