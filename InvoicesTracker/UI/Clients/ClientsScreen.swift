import SwiftUI

/// Odběratelé: Nový odběratel at the trailing side of the row above the card of the table, which opens the form of a
/// new client; the table of the clients with its summary row on top (`ClientTableView`); and beside the table the
/// detail of the selected client, with its name, Nová faktura, which starts an invoice for the client, and Upravit,
/// which opens the form of the client. A click on a row selects its client and opens the detail, and a second click or
/// the ✕ of the detail closes it; a client saved in its form becomes the selected one. The title and the line under it
/// are the shell's. The data is loaded again whenever what it depends on changes.
///
/// The page is laid out as Faktury is: it fills the room the window gives it and asks for no minimum size of its own,
/// the card of the table reaches down to the bottom of the page and its rows scroll in it, and the detail stands beside
/// the card at the top, as high as its content and no higher than the card. Where the card is narrower than the table,
/// as in the least window with the detail open, the table scrolls sideways in its card.
struct ClientsScreen: View {
    /// The width of the detail beside the table: 300 points, as the design's panel beside a table, and as the detail of
    /// an invoice.
    private static let detailWidth: CGFloat = 300

    let app: AppModel
    @State private var model: ClientsModel

    /// The form that is open as a sheet.
    @State private var form: ClientFormModel?

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

    /// The detail of the selected client, once its row is in `data`; nothing while no client is selected. It has the
    /// name of the client and the buttons for what can be done with it: Nová faktura, which VoiceOver reads with the
    /// name of the client, as the toolbar has a Nová faktura of its own, and Upravit.
    @ViewBuilder
    private func detailCard(in data: ClientsData) -> some View {
        if let id = model.selectedClientID, let row = data.rows.first(where: { $0.id == id }) {
            DetailPanel(title: row.name, pill: nil, close: { model.closeDetail() }, scrolls: true) {
                Button("Nová faktura") {
                    model.newInvoice(forClient: row.id)
                }
                .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
                .accessibilityLabel(Text(verbatim: "Nová faktura pro \(row.name)"))
                Button("Upravit") {
                    form = model.form(editing: row.id)
                }
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            } content: {
                EmptyView()
            }
            .frame(width: Self.detailWidth)
            .accessibilityLabel("Detail odběratele")
        }
    }
}
