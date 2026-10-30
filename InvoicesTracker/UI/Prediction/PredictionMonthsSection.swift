import SwiftUI

/// "Kdy čekám faktury": the months of the clients, in a card of its own on Odhad odvodů. The heading is a button that
/// unfolds the card (it starts folded, and folded it keeps the heading and its subtitle), with the legend of the cells
/// beside it or under it once it is unfolded. Unfolded, the card has a block for each client that is expected to
/// invoice: its name and how it invoices, what it still adds to the year, a button to take its months back to the app's
/// choice where the person changed them, the twelve months in a grid of equal cells, and a note. The other clients are
/// in a group of their own that is folded, with the number of clients and their names beside its button.
///
/// The card reads the page and nothing else. Whether it is unfolded, and whether the group of the other clients is,
/// belong to the caller, who also keeps the change that could not be saved (`saveFailure`), which is said under the
/// heading, and writes the changes `toggle` and `reset` ask for.
struct PredictionMonthsSection: View {
    let page: PredictionPage

    /// The line that says the last change could not be saved, or nil.
    let saveFailure: String?
    @Binding var isOpen: Bool
    @Binding var othersAreOpen: Bool

    /// A tap on the cell of a month, 1 to 12, of the client with this id.
    let toggle: (Int64, Int) -> Void

    /// A tap on the button that takes the months of the client with this id back to the app's choice.
    let reset: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let saveFailure {
                SettingsFailureLine(text: saveFailure)
            }
            if isOpen {
                months
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(page.monthsHead)
    }

    // MARK: The heading

    /// The button of the heading with the legend: beside each other at the end of the line when the card has room for
    /// the heading at 320 points and the legend in one row, otherwise the legend under the heading. Beside the heading
    /// the legend keeps its one row, which the heading would otherwise squeeze into two just above that width.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                headingButton
                if isOpen {
                    legend
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                headingButton
                if isOpen {
                    legend
                }
            }
        }
    }

    private var headingButton: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                DisclosureChevron(isOpen: isOpen, size: 14)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: page.monthsHead)
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: page.monthsSub)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 320, idealWidth: 320, maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.monthsHead)
        .accessibilityValue(isOpen ? "rozbaleno" : "sbaleno")
        .accessibilityHint(page.monthsSub)
        .accessibilityAddTraits(.isHeader)
    }

    /// What the cells mean, one swatch of each kind of cell that the year has.
    private var legend: some View {
        FlowLayout(spacing: 12, lineSpacing: 6) {
            ForEach(page.legend) { item in
                HStack(spacing: 5) {
                    CellSwatch(kind: item.kind)
                    Text(verbatim: item.text)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    // MARK: The clients

    @ViewBuilder
    private var months: some View {
        if let text = page.noActiveText {
            Text(verbatim: text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(page.activeRows) { row in
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                ClientMonths(row: row, toggle: toggle, reset: reset)
                    .padding(.top, 12)
            }
        }
        if !page.otherRows.isEmpty {
            others
        }
    }

    /// The group of the clients that are not expected to invoice: a button with their number and names, and, unfolded,
    /// the blocks of them, set in from the left.
    private var others: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Button {
                othersAreOpen.toggle()
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        DisclosureChevron(isOpen: othersAreOpen, size: 12)
                        othersTitle
                        othersSub
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            DisclosureChevron(isOpen: othersAreOpen, size: 12)
                            othersTitle
                        }
                        othersSub
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .accessibilityLabel(page.othersTitle)
            .accessibilityValue(othersAreOpen ? "rozbaleno" : "sbaleno")
            .accessibilityHint(page.othersSub)
            if othersAreOpen {
                ForEach(page.otherRows) { row in
                    ClientMonths(row: row, toggle: toggle, reset: reset)
                        .padding(.top, 12)
                        .padding(.leading, 22)
                }
            }
        }
    }

    private var othersTitle: some View {
        Text(verbatim: page.othersTitle)
            .fontWeight(.semibold)
    }

    private var othersSub: some View {
        Text(verbatim: page.othersSub)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - A client

/// The block of a client: its name and how it invoices, what it adds to the year, the button to take its months back to
/// the app's choice (only where the person changed them), the twelve months, and the note.
private struct ClientMonths: View {
    let row: PredictionClientRow
    let toggle: (Int64, Int) -> Void
    let reset: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            MonthCellGrid {
                ForEach(row.cells) { cell in
                    PredictionMonthCell(cell: cell, toggle: { toggle(row.id, cell.month) })
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Měsíce – \(row.name)")
            if let note = row.note {
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The name with how the client invoices under it, and at the end of the line what it adds: on a line of their
    /// own where the card is too narrow for both.
    private var heading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                identity
                Spacer(minLength: 12)
                trailing
            }
            VStack(alignment: .leading, spacing: 4) {
                identity
                trailing
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: row.name)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: row.how)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trailing: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if row.isEdited {
                Button("Vrátit odhad aplikace") {
                    reset(row.id)
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color(.uniformRateText))
            }
            Text(verbatim: row.adds)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(row.addsIsMuted ? Color.secondary : Color.primary)
        }
    }
}

// MARK: - Parts

/// The chevron of a button that unfolds something: it points to the right, and down once it is unfolded.
private struct DisclosureChevron: View {
    let isOpen: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size - 3, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The swatch of a kind of cell in the legend: its fill and its edge, a little smaller than the cell.
private struct CellSwatch: View {
    let kind: PredictionCellKind

    var body: some View {
        let style = kind.style
        RoundedRectangle(cornerRadius: 3)
            .fill(style.fill)
            .overlay {
                if let edge = style.edge {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(edge.color, style: StrokeStyle(lineWidth: edge.width, dash: edge.dash))
                }
            }
            .frame(width: style.edge == nil ? 12 : 13, height: style.edge == nil ? 10 : 11)
    }
}
