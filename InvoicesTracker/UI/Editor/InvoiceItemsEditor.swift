import SwiftUI

/// The section "Položky" of the editor, a card: a row for every item (Počet, MJ with its suggestions, Popis, Cena za
/// MJ, the VAT rate and the amount), the button that adds one, and under them, past a hairline, the base, the VAT and
/// the total, with the total in crowns for a foreign currency. A quantity or a price that is not a number says so under
/// its row.
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
        Card(title: "Položky") {
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
            Hairline()
            totalsBlock
        }
    }

    // MARK: The rows

    /// The names of the columns over a row for every item, and under a row what is wrong with its numbers.
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
                            .font(Typography.callout)
                            .foregroundStyle(Palette.redText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(7)
                    }
                }
            }
        }
    }

    /// The name of a column in callout and secondary text, `width` points wide, or as wide as the room for the
    /// description.
    private func head(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(title)
            .font(Typography.callout)
            .foregroundStyle(Palette.text2)
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

    /// The row of item number `index` + 1: its fields, the VAT rate, the amount and the button that removes it.
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
                .font(Typography.body)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
                .frame(width: Width.vat, alignment: .trailing)
            Text(verbatim: model.amountText(ofItem: index))
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Width.amount, alignment: .trailing)
            Button {
                model.removeItem(at: index)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Palette.text2)
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
                    .font(Typography.subheadline)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Jednotky: \(InvoiceEditorModel.units.joined(separator: ", "))")
            .accessibilityLabel("Nabídka měrných jednotek, položka \(index + 1)")
        }
        .frame(width: Width.unit, alignment: .leading)
    }

    /// Přidat položku, a capsule of a card, and, once the invoice has as many items as it may, the line that says so.
    private var addButton: some View {
        HStack(spacing: 10) {
            Button {
                model.addItem()
            } label: {
                Label("Přidat položku", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            .disabled(!model.canAddItem)
            if !model.canAddItem {
                Text("Nejvýše \(EditorLimits.items) položek.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
            }
        }
    }

    // MARK: The totals

    /// The base, the VAT and the total, 320 points wide at the trailing side: the total in title under a stronger rule,
    /// and, for a foreign currency, what it comes to in crowns under it.
    @ViewBuilder
    private var totalsBlock: some View {
        if let totals = model.totals {
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    totalLine("Základ", totals.base)
                    totalLine(totals.vatLabel, totals.vat)
                    VStack(spacing: 8) {
                        Rectangle()
                            .fill(Palette.sepStrong)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Celkem")
                                .font(Typography.bodyBold)
                                .foregroundStyle(Palette.text)
                            Spacer(minLength: 8)
                            Text(verbatim: totals.total)
                                .font(Typography.title)
                                .foregroundStyle(Palette.text)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    if let inCrowns = totals.inCrowns {
                        Text(verbatim: inCrowns)
                            .font(Typography.body)
                            .foregroundStyle(Palette.text2)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: 320)
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// A line of the totals: the name in secondary text, and the amount at the trailing end.
    private func totalLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(Typography.body)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
        }
    }
}
