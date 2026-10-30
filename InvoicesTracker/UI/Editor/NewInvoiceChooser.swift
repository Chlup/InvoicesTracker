import Observation
import SwiftUI

/// A line of the chooser: the blank invoice (id 0) or a template.
nonisolated struct ChooserRow: Identifiable, Equatable, Sendable {
    /// The id of the template, or 0 for the blank invoice.
    var id: Int64
    var title: String

    /// What the invoice starts with: "bez předvyplnění · odběratel …", or the client and the item of the template.
    var subtitle: String

    /// The amount without VAT of the template, or nothing for the blank invoice.
    var amount: String

    var templateID: Int64? {
        id == 0 ? nil : id
    }
}

/// The chooser "Nová faktura": a blank invoice or one of the templates. Choosing opens the editor on Faktury (after the
/// question "Zahodit rozepsanou fakturu?" if it would throw away an invoice that is being written), Zrušit closes the
/// chooser, and Spravovat šablony goes to the templates and leaves that invoice where it is.
@MainActor
@Observable
final class NewInvoiceChooserModel {
    let title = "Nová faktura"
    let subtitle = "Vyberte šablonu, nebo začněte s prázdnou fakturou."

    /// The blank invoice, then the templates in the order they were made. Empty until `load()` has run.
    private(set) var rows: [ChooserRow] = []

    /// What the chooser says when the templates cannot be read.
    private(set) var errorText: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// Reads the clients and the templates. A failure is logged and said, and the blank invoice is still offered.
    func load() async {
        do {
            guard let database = app.database else { throw VaultError.locked }
            let clients = try await database.clients()
            let templates = try await database.templates()
            rows = Self.rows(templates: templates, clients: clients)
            errorText = nil
        } catch {
            AppModel.log("Loading the chooser of a new invoice", failedWith: error)
            rows = [Self.blankRow(firstClient: nil)]
            errorText = "Šablony se nepodařilo načíst."
        }
    }

    /// The editor opens on Faktury, on a blank invoice or on one made from the template of `row`.
    func choose(_ row: ChooserRow) {
        app.startNewInvoice(templateID: row.templateID)
    }

    /// Zrušit: the chooser closes, and shows the editor it was open over again.
    func cancel() {
        app.cancelChooser()
    }

    /// Spravovat šablony: the chooser closes and the templates are shown. An invoice that is being written stays, and
    /// is there when Faktury is shown again.
    func manageTemplates() {
        app.cancelChooser()
        app.screen = .templates
    }

    // MARK: Rows

    /// The blank invoice, then a row for every template, with its client when it has one: the two reads that make the
    /// rows can come apart, and the editor asks for a client where a template has none.
    nonisolated static func rows(templates: [InvoiceTemplate], clients: [Client]) -> [ChooserRow] {
        [blankRow(firstClient: clients.first)]
            + templates.map { template in
                row(for: template, client: clients.first { $0.id == template.clientID })
            }
    }

    private nonisolated static func blankRow(firstClient: Client?) -> ChooserRow {
        let named = firstClient.map { " · odběratel \($0.name)" } ?? ""
        return ChooserRow(id: 0, title: "Prázdná faktura", subtitle: "bez předvyplnění" + named, amount: "")
    }

    /// The row of `template`, written for `client`: its name, the client with the item ("172 h × 70,00 USD") or the
    /// number of items, and the amount without VAT in the currency of the client. A template without a client has no
    /// currency, so it has the number of items and no amount.
    nonisolated static func row(for template: InvoiceTemplate, client: Client?) -> ChooserRow {
        guard let client else {
            return ChooserRow(
                id: template.id, title: template.name, subtitle: "bez odběratele · " + positions(template.items.count),
                amount: "")
        }
        let detail: String
        switch template.items.count {
        case 1:
            let item = template.items[0]
            detail = ItemLine.text(
                quantity: item.quantity, unit: item.unit, unitPriceMinor: item.unitPriceMinor, currency: client.currency
            )
        default:
            detail = positions(template.items.count)
        }
        return ChooserRow(
            id: template.id, title: template.name, subtitle: "\(client.name) · \(detail)",
            amount: netAmount(of: template, in: client.currency))
    }

    /// "bez položek", "1 položka", "2 položky", "5 položek".
    private nonisolated static func positions(_ count: Int) -> String {
        switch count {
        case ..<1: "bez položek"
        case 1: "1 položka"
        case 2...4: "\(count) položky"
        default: "\(count) položek"
        }
    }

    /// The items of the template added up, rounded the way an invoice rounds them, or "—" where the amount is beyond
    /// what an invoice carries.
    private nonisolated static func netAmount(of template: InvoiceTemplate, in currency: CurrencyCode) -> String {
        let total = InvoiceEditorChecks.total(
            of: template.items.map {
                InvoiceEditorChecks.amount(quantity: $0.quantity, unitPriceMinor: $0.unitPriceMinor)
            })
        guard total.magnitude < EditorLimits.amount else { return "—" }
        return CzechFormat.money(Money(minor: DecimalMath.halfUp(total), currency: currency))
    }
}

/// The sheet "Nová faktura": the blank invoice and every template as a button, with the link to the templates and
/// Zrušit under them. A choice that would throw away the invoice that is being written asks "Zahodit rozepsanou
/// fakturu?" in a box in place of the link and Zrušit, and the choices wait for the answer.
struct NewInvoiceChooser: View {
    let app: AppModel
    @State private var model: NewInvoiceChooserModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: NewInvoiceChooserModel(app: app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 17, weight: .bold))
                Text(model.subtitle)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.rows) { row in
                        RowButton(row: row) {
                            model.choose(row)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(asksToDiscard)
            if let errorText = model.errorText {
                Text(verbatim: errorText)
                    .foregroundStyle(.red)
            }
            if asksToDiscard {
                DiscardQuestionBox(keepEditing: { app.cancelDiscard() }, discard: { app.confirmDiscard() })
            } else {
                footer
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 620)
        .task {
            await model.load()
        }
    }

    /// Whether the chooser asks "Zahodit rozepsanou fakturu?" for a choice made in it.
    private var asksToDiscard: Bool {
        DiscardQuestion.isAskedByChooser(app)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Spravovat šablony") {
                model.manageTemplates()
            }
            .buttonStyle(.link)
            Spacer()
            Button("Zrušit") {
                model.cancel()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
        }
    }
}

/// One choice: the name and the amount on the first line, what it starts with on the second.
private struct RowButton: View {
    let row: ChooserRow
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text(verbatim: row.title)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: row.amount)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                GridRow {
                    Text(verbatim: row.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(width: 0, height: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
