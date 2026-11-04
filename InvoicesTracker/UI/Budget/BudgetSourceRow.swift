import SwiftUI

/// The sizes of the row that chooses what Rozpočet divides and of the menu of its invoices, in points.
private nonisolated enum BudgetSourceRowMetrics {
    /// The space between the segmented control and the button of the invoice.
    static let spacing: CGFloat = 12

    /// The space between the number, the client and the chevron on the button of the invoice.
    static let buttonSpacing: CGFloat = 8

    /// The width of the menu of the invoices.
    static let menuWidth: CGFloat = 400

    /// The tallest the list of the invoices in the menu grows before it scrolls: the 380 of the menu without its
    /// heading.
    static let listMaximumHeight: CGFloat = 340

    /// The space around the content of the menu.
    static let menuPadding: CGFloat = 6

    /// The space between the choices of the menu.
    static let itemSpacing: CGFloat = 2

    /// The width of the column of the check mark of a choice.
    static let checkWidth: CGFloat = 16

    /// The space between the parts of a choice.
    static let itemColumnSpacing: CGFloat = 8

    /// The space between the first line of a choice and its status.
    static let itemLineSpacing: CGFloat = 1
}

/// The row at the top of Rozpočet: the segmented control "Z čeho rozpočet počítat" with Skutečnost, Odhad za rok and
/// Faktura, of which Odhad za rok cannot be chosen in a past year and says why on hover, and in Faktura mode, while
/// the year has an invoice, the button of the invoice the budget divides, which opens the menu of the invoices of the
/// year. A choice is handed to `chooseSource` or `chooseInvoice`.
struct BudgetSourceRow: View {
    let row: BudgetSourceRowData
    let chooseSource: @MainActor (BudgetSource) -> Void
    let chooseInvoice: @MainActor (Int64) -> Void

    var body: some View {
        HStack(spacing: BudgetSourceRowMetrics.spacing) {
            SegmentedControl(
                "Z čeho rozpočet počítat",
                selection: Binding(get: { row.source }, set: chooseSource),
                segments: row.sources.map { (value: $0.value, title: $0.title) },
                disabled: Set(row.sources.filter { !$0.isEnabled }.map(\.value)),
                help: Dictionary(
                    uniqueKeysWithValues: row.sources.compactMap { choice in choice.help.map { (choice.value, $0) } })
            )
            .fixedSize()
            if let picker = row.invoicePicker {
                BudgetInvoiceButton(picker: picker, choose: chooseInvoice)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The button of the invoice in Faktura mode: a capsule of the height of a button inside a card, raised off the page,
/// with the number of the invoice in semibold, its client in secondary text, cut short where the row has no room for
/// it, and a chevron. A click opens the menu of the invoices of the year under it (`BudgetInvoiceMenu`); a choice in it
/// closes the menu and is handed to `choose`. VoiceOver reads the button as "Faktura 20260905, Alfa Systems s.r.o.".
private struct BudgetInvoiceButton: View {
    let picker: BudgetInvoicePicker
    let choose: @MainActor (Int64) -> Void

    /// Whether the menu is open.
    @State private var menuShown = false

    var body: some View {
        Button {
            menuShown = true
        } label: {
            HStack(spacing: BudgetSourceRowMetrics.buttonSpacing) {
                Text(verbatim: picker.number)
                    .monospacedDigit()
                Text(verbatim: picker.client)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(Typography.subheadlineSemibold)
                    .foregroundStyle(Palette.text2)
            }
        }
        .buttonStyle(CapsuleButtonStyle(.onWindow, size: .small))
        .accessibilityLabel(picker.accessibilityLabel)
        .popover(isPresented: $menuShown, arrowEdge: .bottom) {
            BudgetInvoiceMenu(picker: picker) { id in
                menuShown = false
                choose(id)
            }
        }
    }
}

/// The menu of the invoices of the year, in a popover under the button of the invoice: the heading "Faktury roku Y" and
/// a choice for each invoice, newest number first, with a check mark at the one the budget divides. The list scrolls
/// where it is taller than 340 points. VoiceOver reads the menu as a group under its heading.
private struct BudgetInvoiceMenu: View {
    let picker: BudgetInvoicePicker
    let choose: @MainActor (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BudgetSourceRowMetrics.itemSpacing) {
            Text(verbatim: picker.menuTitle)
                .font(Typography.calloutSemibold)
                .foregroundStyle(Palette.text2)
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: BudgetSourceRowMetrics.itemSpacing) {
                    ForEach(picker.items) { item in
                        BudgetInvoiceMenuItem(item: item) {
                            choose(item.id)
                        }
                    }
                }
            }
            // As tall as the choices, up to the most the list grows to.
            .frame(maxHeight: BudgetSourceRowMetrics.listMaximumHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BudgetSourceRowMetrics.menuPadding)
        .frame(width: BudgetSourceRowMetrics.menuWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(picker.menuTitle)
    }
}

/// A choice of the menu of the invoices: a check mark where it is the invoice the budget divides, the number in
/// semibold with " · " and the client in secondary text on one line, cut short where it is too long, the status under
/// it in the colour of what it says, and at the right the amount that reaches the account, in secondary text while it
/// is not paid. The pointer over it highlights it. VoiceOver reads its first line, then the status and the amount, and
/// whether it is chosen.
private struct BudgetInvoiceMenuItem: View {
    let item: BudgetInvoiceItem
    let choose: () -> Void

    /// Whether the pointer is over the choice.
    @State private var hovered = false

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline, spacing: BudgetSourceRowMetrics.itemColumnSpacing) {
                Image(systemName: "checkmark")
                    .font(Typography.calloutSemibold)
                    .opacity(item.isChosen ? 1 : 0)
                    .frame(width: BudgetSourceRowMetrics.checkWidth)
                VStack(alignment: .leading, spacing: BudgetSourceRowMetrics.itemLineSpacing) {
                    HStack(spacing: 0) {
                        Text(verbatim: item.number)
                            .font(Typography.bodySemibold)
                            .monospacedDigit()
                            .fixedSize()
                        Text(verbatim: " · " + item.client)
                            .font(Typography.body)
                            .foregroundStyle(Palette.text2)
                    }
                    .lineLimit(1)
                    Text(verbatim: item.status)
                        .font(Typography.callout)
                        .foregroundStyle(item.statusTone.color)
                }
                Spacer(minLength: 0)
                Text(verbatim: item.amount)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(item.statusTone == .received ? Palette.text : Palette.text2)
                    .fixedSize()
            }
            .foregroundStyle(Palette.text)
            .padding(EdgeInsets(top: 7, leading: 6, bottom: 8, trailing: 10))
            .contentShape(Rectangle())
            .background(
                hovered ? Palette.fillStrong : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(item.title)
        .accessibilityValue(item.status + ", " + item.amount)
        .accessibilityAddTraits(item.isChosen ? .isSelected : [])
    }
}

extension BudgetInvoiceStatusTone {
    /// The colour of the status line of an invoice in the menu: secondary text when the money came, the accent's text
    /// while it waits, and the red of text past its due date.
    var color: Color {
        switch self {
        case .received: Palette.text2
        case .awaiting: Palette.accentText
        case .overdue: Palette.redText
        }
    }
}
