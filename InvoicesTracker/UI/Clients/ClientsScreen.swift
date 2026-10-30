import SwiftUI

/// Odběratelé: a table with a row for every client, in the order of their names in Czech, with its city and IČO,
/// currency and VAT mode, invoice language, and what it did in the selected year (`ClientTableView`). A click on a row
/// opens the form of the client, where the rest of what is known of it is, Nová faktura at the end of the row starts an
/// invoice for the client, and Nový odběratel opens the form of a new one. The title and the line under it are the
/// shell's. The data is loaded again whenever what it depends on changes.
///
/// The page fills the room the window gives it and asks for no minimum size of its own: it scrolls, and the table
/// scrolls sideways in its card where the page is narrower than the table.
struct ClientsScreen: View {
    let app: AppModel
    @State private var model: ClientsModel

    /// The form that is open as a sheet.
    @State private var form: ClientFormModel?

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: ClientsModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topRow
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .sheet(item: $form) { form in
            ClientForm(model: form, cancel: { self.form = nil }, saved: { self.form = nil })
                .idleLockCover()
        }
    }

    /// What the defaults are for, and Nový odběratel.
    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                hint
                Spacer(minLength: 12)
                newClientButton
            }
            VStack(alignment: .leading, spacing: 10) {
                hint
                newClientButton
            }
        }
    }

    private var hint: some View {
        Text("Výchozí hodnoty odběratele se použijí při vystavení nové faktury.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var newClientButton: some View {
        Button {
            form = model.newClientForm()
        } label: {
            Label("Nový odběratel", systemImage: "plus")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    @ViewBuilder
    private var content: some View {
        if let rows = model.rows {
            if rows.isEmpty {
                Text("Zatím nemáte žádného odběratele.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                ClientTableView(
                    rows: rows, year: model.year,
                    edit: { form = model.form(editing: $0) },
                    newInvoice: { model.newInvoice(forClient: $0) })
            }
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }
}
