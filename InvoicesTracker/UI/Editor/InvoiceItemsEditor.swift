import SwiftUI

/// The section "Položky" of the editor: a row for every item (Počet, MJ with its suggestions, Popis, Cena za MJ, the
/// VAT rate and the amount), the button that adds one, and under them the base, the VAT and the total, with the total
/// in crowns for a foreign currency. A quantity or a price that is not a number says so under its row.
struct InvoiceItemsEditor: View {
    @Bindable var model: InvoiceEditorModel

    /// The widths of the columns of the rows; the description takes the rest, and at least `description`. The rows
    /// scroll sideways where the card is narrower than they are.
    private enum Width {
        static let quantity: CGFloat = 64
        static let unit: CGFloat = 62
        static let description: CGFloat = 110
        static let price: CGFloat = 92
        static let vat: CGFloat = 44
        static let amount: CGFloat = 108
        static let remove: CGFloat = 22
        static let spacing: CGFloat = 6

        /// The narrowest the rows are laid out at.
        static let rows = quantity + unit + description + price + vat + amount + remove + spacing * 6
    }

    /// The width the card gives the rows, which they fill when it is more than `Width.rows`.
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Položky")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                grid
                    // A little room around the fields, so that their borders are not cut by the scroll view.
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
                    .frame(width: max(Width.rows, availableWidth), alignment: .leading)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                availableWidth = width
            }
            addButton
            Divider()
            totalsBlock
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: The rows

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: Width.spacing, verticalSpacing: 8) {
            GridRow {
                head("Počet", width: Width.quantity, alignment: .trailing)
                head("MJ", width: Width.unit, alignment: .leading)
                head("Popis", width: nil, alignment: .leading)
                head("Cena za MJ", width: Width.price, alignment: .trailing)
                head("DPH", width: Width.vat, alignment: .trailing)
                head("Celkem", width: Width.amount, alignment: .trailing)
                Color.clear
                    .frame(width: Width.remove, height: 0)
            }
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                row(binding(for: item), index: index)
                ForEach([item.quantityError, item.priceError].compactMap { $0 }, id: \.self) { message in
                    GridRow {
                        Text(verbatim: message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(7)
                    }
                }
            }
        }
    }

    private func head(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    /// A binding to the item that follows it where it is in the list, so that a row that is being removed is never read
    /// by a place it no longer has.
    private func binding(for item: EditableItem) -> Binding<EditableItem> {
        Binding(
            get: { model.items.first { $0.id == item.id } ?? item },
            set: { updated in
                if let index = model.items.firstIndex(where: { $0.id == item.id }) {
                    model.items[index] = updated
                }
            })
    }

    private func row(_ item: Binding<EditableItem>, index: Int) -> some View {
        GridRow {
            TextField("Počet", text: item.quantityText)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: Width.quantity)
                .accessibilityLabel("Počet, položka \(index + 1)")
            unitField(item.unit, index: index)
            TextField("Popis", text: item.description)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: Width.description, maxWidth: .infinity)
                .accessibilityLabel("Popis, položka \(index + 1)")
            TextField("Cena za MJ", text: item.unitPriceText)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: Width.price)
                .accessibilityLabel("Cena za MJ, položka \(index + 1)")
            Text(verbatim: "\(model.vatMode.ratePercent)\u{00A0}%")
                .monospacedDigit()
                .frame(width: Width.vat, alignment: .trailing)
            Text(verbatim: model.amountText(ofItem: index))
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Width.amount, alignment: .trailing)
            Button {
                model.removeItem(at: index)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Odebrat položku")
            .accessibilityLabel("Odebrat položku \(index + 1)")
            .frame(width: Width.remove)
        }
    }

    /// The unit is free text, with the usual ones to choose from beside it.
    private func unitField(_ unit: Binding<String>, index: Int) -> some View {
        HStack(spacing: 0) {
            TextField("MJ", text: unit)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: Width.unit - 18)
                .accessibilityLabel("Měrná jednotka, položka \(index + 1)")
            Menu {
                ForEach(InvoiceEditorModel.units, id: \.self) { suggestion in
                    Button(suggestion) {
                        unit.wrappedValue = suggestion
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Jednotky: \(InvoiceEditorModel.units.joined(separator: ", "))")
            .accessibilityLabel("Nabídka měrných jednotek, položka \(index + 1)")
        }
        .frame(width: Width.unit, alignment: .leading)
    }

    private var addButton: some View {
        HStack(spacing: 10) {
            Button {
                model.addItem()
            } label: {
                Label("Přidat položku", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(!model.canAddItem)
            if !model.canAddItem {
                Text("Nejvýše \(EditorLimits.items) položek.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: The totals

    @ViewBuilder
    private var totalsBlock: some View {
        if let totals = model.totals {
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    totalLine("Základ", totals.base)
                    totalLine(totals.vatLabel, totals.vat)
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Celkem")
                            .fontWeight(.bold)
                        Spacer(minLength: 8)
                        Text(verbatim: totals.total)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if let inCrowns = totals.inCrowns {
                        Text(verbatim: inCrowns)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: 320)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func totalLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .monospacedDigit()
        }
    }
}
