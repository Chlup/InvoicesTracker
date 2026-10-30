import SwiftUI

/// One month of a client in the grid of the months: its short name, what the month holds in a few figures, and under it
/// what that means ("zaplaceno", "čekám", "→ 2027"), on a fill and with an edge that tell the six kinds of month apart
/// (`PredictionCellKind.style`). A month that is open, where an invoice is expected or not, is a toggle button that a
/// tap switches, and VoiceOver reads whether it is on. A month that holds invoices or is over, and a month of the
/// invoices of a client the app does not know, are not buttons: the cell only says what it holds.
///
/// The texts stand on one line each, in a cell that is only 64 points wide where the grid has just room for its columns
/// (twelve in a row from 834 points, six from 414), so that they shrink as far as `minimumTextScale` before they would
/// be cut. In the cells of the least window, which has six columns, they need not shrink.
struct PredictionMonthCell: View {
    /// How far the texts of a cell shrink to stay on one line.
    static let minimumTextScale: CGFloat = 0.6

    let cell: PredictionCell

    /// What a tap does. A cell that is not a toggle ignores it.
    let toggle: () -> Void

    var body: some View {
        if cell.isToggle {
            Button(action: toggle) {
                face
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cell.accessibilityLabel)
            .accessibilityValue(cell.isOn ? "zapnuto" : "vypnuto")
            .accessibilityAddTraits(.isToggle)
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cell.accessibilityLabel)
        }
    }

    /// The name of the month, and under it the figure and the line under that, each only when the cell has it: a month
    /// that is not expected has "nečekám" right under its name.
    private var face: some View {
        let style = cell.kind.style
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: cell.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.label)
            if !cell.value.isEmpty {
                Text(verbatim: cell.value)
                    .font(.callout.weight(style.valueWeight))
                    .monospacedDigit()
                    .foregroundStyle(style.value)
            }
            if !cell.sub.isEmpty {
                Text(verbatim: cell.sub)
                    .font(.subheadline)
                    .foregroundStyle(style.sub)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Self.minimumTextScale)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity, alignment: .topLeading)
        .background(style.fill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if let edge = style.edge {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(edge.color, style: StrokeStyle(lineWidth: edge.width, dash: edge.dash))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - The six kinds

/// How a kind of month is set: the fill, the colours of the three texts of a cell, the weight of its figure, and the
/// edge, if it has one.
struct PredictionCellStyle {
    /// A dashed or solid line round a cell.
    struct Edge {
        var color: Color
        var width: CGFloat
        var dash: [CGFloat]
    }

    var fill: Color
    var label: Color
    var value: Color
    var sub: Color
    var valueWeight: Font.Weight
    var edge: Edge?

    /// A style whose three texts are all in `text`, the figure in semibold.
    init(fill: Color, text: Color, edge: Edge? = nil) {
        self.fill = fill
        label = text
        value = text
        sub = text
        valueWeight = .semibold
        self.edge = edge
    }

    /// A style whose texts are each in a colour of their own.
    init(fill: Color, label: Color, value: Color, sub: Color, valueWeight: Font.Weight, edge: Edge? = nil) {
        self.fill = fill
        self.label = label
        self.value = value
        self.sub = sub
        self.valueWeight = valueWeight
        self.edge = edge
    }
}

extension PredictionCellKind {
    /// How a cell, and its swatch in the legend, of this kind is set. The colours are those the app already has:
    /// - what is paid is in the green of the status of a paid invoice, with its dark green text;
    /// - what is issued is in the blue of a banner, and what is expected in the same blue, paler, with a dashed edge in
    ///   the blue of the issued money in the chart, both with the dark blue text of the rate capsule;
    /// - what is paid only next year is on the cream and in the brown of the day in the future and the simulation,
    ///   with an orange dashed edge;
    /// - what is over, and what is not expected, is in the greys of secondary text, the latter with a thin edge.
    var style: PredictionCellStyle {
        switch self {
        case .paid:
            PredictionCellStyle(fill: Color.green.opacity(0.15), text: Color(.bannerText))
        case .waiting:
            PredictionCellStyle(fill: Color.blue.opacity(0.12), text: Color(.uniformRateText))
        case .past:
            PredictionCellStyle(
                fill: Color.secondary.opacity(0.1), label: Color.secondary, value: Color(nsColor: .tertiaryLabelColor),
                sub: Color.secondary, valueWeight: .regular)
        case .expected:
            PredictionCellStyle(
                fill: Color.blue.opacity(0.05), text: Color(.uniformRateText),
                edge: PredictionCellStyle.Edge(color: Color(.chartIssued), width: 1.5, dash: [4, 3]))
        case .expectedNextYear:
            PredictionCellStyle(
                fill: Color(.futureDateBackground), text: Color(.simulationText),
                edge: PredictionCellStyle.Edge(color: Color.orange, width: 1.5, dash: [4, 3]))
        case .notExpected:
            PredictionCellStyle(
                fill: Color.clear, text: Color.secondary,
                edge: PredictionCellStyle.Edge(color: Color.secondary.opacity(0.5), width: 1, dash: [3, 3]))
        }
    }
}
