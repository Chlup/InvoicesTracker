import SwiftUI

/// One month of a client in the grid of the months: its short name, what the month holds in a few figures, and under it
/// what that means ("zaplaceno", "čekám", "→ 2027"), on a fill and with an edge that tell the six kinds of month apart
/// (`PredictionCellKind.style`), in a shape rounded by the radius of a control. A month that is open, where an invoice
/// is expected or not, is a toggle button that a tap switches, and VoiceOver reads whether it is on. A month that holds
/// invoices or is over, and a month of the invoices of a client the app does not know, are not buttons: the cell only
/// says what it holds.
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
                .font(Typography.subheadlineSemibold)
                .foregroundStyle(style.label)
            if !cell.value.isEmpty {
                Text(verbatim: cell.value)
                    .font(Typography.callout.weight(style.valueWeight))
                    .monospacedDigit()
                    .foregroundStyle(style.value)
            }
            if !cell.sub.isEmpty {
                Text(verbatim: cell.sub)
                    .font(Typography.subheadline)
                    .foregroundStyle(style.sub)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Self.minimumTextScale)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity, alignment: .topLeading)
        .background(style.fill, in: RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
        .overlay {
            if let edge = style.edge {
                RoundedRectangle(cornerRadius: DesignMetrics.controlRadius)
                    .strokeBorder(edge.color, style: StrokeStyle(lineWidth: edge.width, dash: edge.dash))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
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
    /// How a cell, and its swatch in the legend, of this kind is set. The colours are tokens of the design:
    /// - what is paid is on the green tint, in the green of text;
    /// - what is issued is on the accent tint, in the blue of text, and what is expected is the same, with a dashed
    ///   edge in the accent;
    /// - what is paid only next year is on the orange tint, in the orange of text, with a dashed orange edge;
    /// - what is over is on the inset background, in the faintest text;
    /// - what is not expected is on the card, in tertiary text and the faintest, with a thin dashed edge in the
    ///   stronger separator.
    var style: PredictionCellStyle {
        switch self {
        case .paid:
            PredictionCellStyle(fill: Palette.greenTint, text: Palette.greenText)
        case .waiting:
            PredictionCellStyle(fill: Palette.accentTint, text: Palette.accentText)
        case .past:
            PredictionCellStyle(
                fill: Palette.bgInset, label: Palette.text4, value: Palette.text4, sub: Palette.text4,
                valueWeight: .regular)
        case .expected:
            PredictionCellStyle(
                fill: Palette.accentTint, text: Palette.accentText,
                edge: PredictionCellStyle.Edge(color: Palette.accent, width: 1.5, dash: [4, 3]))
        case .expectedNextYear:
            PredictionCellStyle(
                fill: Palette.orangeTint, text: Palette.orangeText,
                edge: PredictionCellStyle.Edge(color: Palette.orange, width: 1.5, dash: [4, 3]))
        case .notExpected:
            PredictionCellStyle(
                fill: Palette.bgCard, label: Palette.text3, value: Palette.text4, sub: Palette.text4,
                valueWeight: .semibold,
                edge: PredictionCellStyle.Edge(color: Palette.sepStrong, width: 1, dash: [3, 3]))
        }
    }
}
