import Charts
import SwiftUI

/// The chart of the year under the figures of the card of the estimate in Přehled, by months and without VAT: what was
/// issued in each month (bars, by the day of issue), what was received in it (an orange line with points, by the day of
/// payment) and what the payments received in it left after the levies they added (a green line with points). The
/// months up to today are what the data holds, drawn solid; the rest of the year is what the prediction expects, drawn
/// hatched and dashed. The month of today has both: its bar stacks the hatched part on top of the solid one, its points
/// are the sums of both parts, and the solid lines end and the dashed ones begin there. The point of a month to come is
/// filled with a light tint of its line. The scale is that of the chart of Příjmy (`IncomeChartLayout`), and the net
/// income is drawn from zero like the axis. Hovering over a month highlights it and shows a tooltip with its actual
/// figures and its estimates, all in whole Kč; the chart has a hover of its own, apart from that of the chart of
/// Příjmy. VoiceOver reads each month in the words of its tooltip.
struct PredictionChart: View {
    /// The twelve months of the year, January first (`PredictionChartBuilder.months`).
    let months: [PredictionChartMonth]

    /// The month the pointer is over.
    @State private var hovered: Int?

    /// The width of the chart, which the width of the bars follows.
    @State private var chartWidth: CGFloat = 0

    /// What the colours of the hatching are worked out in, so that it follows the appearance of the window.
    @Environment(\.self) private var environment

    /// The width of the labels of the vertical axis, which the plot lacks.
    private static let axisLabelWidth: CGFloat = 56

    /// The dashes of the lines of the estimate: 6 points drawn and 5 left out.
    private static let estimateDash: [CGFloat] = [6, 5]

    /// How strongly the point of a month to come is tinted with the colour of its line.
    private static let futurePointTint = 0.2

    var body: some View {
        let hatching = self.hatching
        VStack(alignment: .leading, spacing: 12) {
            legend(hatching: hatching)
            chart(hatching: hatching)
        }
    }

    // MARK: Legend

    /// What the bars and the lines are, a key for each, and a key for the estimate: its hatching and its dashes, in the
    /// faint grey of text. The keys stand side by side where the card has room for them and on a further row where it
    /// has not, so that no key breaks in two.
    private func legend(hatching: ImagePaint) -> some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.accent)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("Vystaveno")
            }
            HStack(spacing: 6) {
                Capsule()
                    .fill(Palette.orange)
                    .frame(width: 16, height: 3)
                    .accessibilityHidden(true)
                Text("Přijato")
            }
            HStack(spacing: 6) {
                Capsule()
                    .fill(Palette.green)
                    .frame(width: 16, height: 3)
                    .accessibilityHidden(true)
                Text("Čistý příjem (součet za platby v měsíci)")
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(hatching)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1.5))
                    path.addLine(to: CGPoint(x: 16, y: 1.5))
                }
                .stroke(Palette.text4, style: StrokeStyle(lineWidth: 2.5, dash: Self.estimateDash))
                .frame(width: 16, height: 3)
                .accessibilityHidden(true)
                Text("odhad (šrafovaně a čárkovaně)")
            }
        }
        .font(Typography.callout)
        .foregroundStyle(Palette.text2)
    }

    // MARK: The plot

    /// The plot, 220 points high: the bars and the lines of the twelve months on the scale of the chart of Příjmy, the
    /// labels of the axes with the month of today in bold, and over it the targets of the months and the tooltip of
    /// the one under the pointer.
    private func chart(hatching: ImagePaint) -> some View {
        let top = IncomeChartLayout.top(forLargest: PredictionChartBuilder.largestAmount(in: months))
        let step = Double(top) / 400
        return Chart {
            highlight
            bars(hatching: hatching)
            lines
            points
        }
        .chartLegend(.hidden)
        // The order of the months is the order of the data, not that of the first mark to mention a month: the
        // highlight of a month is the first mark while the pointer is over it.
        .chartXScale(domain: months.map(\.label))
        .chartYScale(domain: 0...(Double(top) / 100))
        .chartYAxis {
            AxisMarks(position: .leading, values: (0...4).map { Double($0) * step }) { value in
                let isBaseLine = value.as(Double.self) == 0
                AxisGridLine()
                    .foregroundStyle(isBaseLine ? Palette.sepStrong : Palette.fill)
                AxisValueLabel {
                    if let kc = value.as(Double.self) {
                        Text(verbatim: IncomeChartLayout.label(forKc: Int64(kc.rounded())))
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.text3)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: months.map(\.label)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self), let month = months.first(where: { $0.label == label }) {
                        let isCurrent = month.part == .current
                        Text(verbatim: label)
                            .font(isCurrent ? Typography.callout.bold() : Typography.callout.weight(.medium))
                            .foregroundStyle(isCurrent ? Palette.accentText : Palette.text2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                interaction(proxy: proxy, geometry: geometry)
            }
        }
        .frame(height: 220)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { chartWidth = $0 })
    }

    /// The month under the pointer, if it is one of those drawn.
    private var hoveredMonth: Int? {
        hovered.flatMap { months.indices.contains($0) ? $0 : nil }
    }

    /// The faint band behind the month under the pointer.
    @ChartContentBuilder
    private var highlight: some ChartContent {
        if let hoveredMonth {
            RectangleMark(x: .value("Měsíc", months[hoveredMonth].label), width: .ratio(1))
                .foregroundStyle(Palette.text.opacity(0.05))
                .accessibilityHidden(true)
        }
    }

    /// What was issued: a bar for each month, what was issued by today solid at the bottom and what is still to be
    /// issued painted with `hatching` on top of it. The top corners of the bar are rounded, on the part that is on top.
    @ChartContentBuilder
    private func bars(hatching: ImagePaint) -> some ChartContent {
        let width = IncomeChartLayout.barWidth(plotWidth: chartWidth - Self.axisLabelWidth, columns: months.count)
        let barWidth: MarkDimension = width > 0 ? .fixed(width) : .ratio(0.56)
        ForEach(months) { month in
            let actual = max(0, month.issuedActualHalere)
            let estimate = max(0, month.issuedEstimateHalere)
            if actual > 0 {
                BarMark(
                    x: .value("Měsíc", month.label), yStart: .value("Vystaveno", 0),
                    yEnd: .value("Vystaveno", crowns(actual)), width: barWidth
                )
                .foregroundStyle(Palette.accent)
                .clipShape(Self.barShape(roundedOnTop: estimate == 0))
                .accessibilityHidden(true)
            }
            if estimate > 0 {
                BarMark(
                    x: .value("Měsíc", month.label), yStart: .value("Vystaveno", crowns(actual)),
                    yEnd: .value("Vystaveno", crowns(actual + estimate)), width: barWidth
                )
                .foregroundStyle(hatching)
                .clipShape(Self.barShape(roundedOnTop: true))
                .accessibilityHidden(true)
            }
        }
    }

    /// The shape a part of a bar is cut to: with its top corners rounded for the part on top, square for a part that
    /// another stands on.
    private static func barShape(roundedOnTop: Bool) -> UnevenRoundedRectangle {
        let radius: CGFloat = roundedOnTop ? 4 : 0
        return UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
    }

    /// What was received, in orange, and what the payments left after the levies, in green: a line of each through
    /// the points of the months (`receivedPoint(of:)`, `netPoint(of:)`). Each line is solid from January to the month
    /// of today and dashed from it to December, so that the two parts meet at the point of the month of today. Each
    /// part names its series, or Swift Charts joins the marks of the lines into one.
    @ChartContentBuilder
    private var lines: some ChartContent {
        ForEach(months) { month in
            lineMarks(of: month, series: "Přijato", at: receivedPoint(of: month), color: Palette.orange)
            lineMarks(of: month, series: "Čistý příjem", at: netPoint(of: month), color: Palette.green)
        }
    }

    /// The marks of `month` on the line `series` in `color`, at `drawn` crowns: one on the solid part of the line up to
    /// the month of today, and one on the dashed part of the estimate, the series `series` with " odhad", from it on.
    /// The month of today has both.
    @ChartContentBuilder
    private func lineMarks(
        of month: PredictionChartMonth, series: String, at drawn: Double, color: Color
    ) -> some ChartContent {
        if month.part != .future {
            LineMark(x: .value("Měsíc", month.label), y: .value(series, drawn), series: .value("Řada", series))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                .interpolationMethod(.linear)
                .accessibilityHidden(true)
        }
        if month.part != .past {
            LineMark(
                x: .value("Měsíc", month.label), y: .value(series, drawn), series: .value("Řada", series + " odhad")
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round, dash: Self.estimateDash))
            .interpolationMethod(.linear)
            .accessibilityHidden(true)
        }
    }

    /// The points of the two lines, a ring at each, drawn over both lines. The ring of a month to come is filled with a
    /// light tint of the colour of its line, the others with the background of the card.
    @ChartContentBuilder
    private var points: some ChartContent {
        ForEach(months) { month in
            pointMark(of: month, line: "Přijato", at: receivedPoint(of: month), color: Palette.orange)
            pointMark(of: month, line: "Čistý příjem", at: netPoint(of: month), color: Palette.green)
        }
    }

    /// The point of `month` on the line `line` in `color`, at `drawn` crowns.
    private func pointMark(
        of month: PredictionChartMonth, line: String, at drawn: Double, color: Color
    ) -> some ChartContent {
        PointMark(x: .value("Měsíc", month.label), y: .value(line, drawn))
            .symbol {
                month.part == .future
                    ? ChartRing(color: color, fill: color.opacity(Self.futurePointTint)) : ChartRing(color: color)
            }
            .accessibilityHidden(true)
    }

    /// Where the point of `month` stands on the line of what was received, in crowns: what it received by today and
    /// what it still expects, together.
    private func receivedPoint(of month: PredictionChartMonth) -> Double {
        crowns(month.receivedActualHalere + month.receivedEstimateHalere)
    }

    /// Where the point of `month` stands on the line of the net income, in crowns: what its payments left by today and
    /// what those it still expects will leave, together. The axis starts at zero, so a sum below it is drawn at zero;
    /// the tooltip tells the figures.
    private func netPoint(of month: PredictionChartMonth) -> Double {
        crowns(max(0, month.netActualHalere + month.netEstimateHalere))
    }

    /// Haléře as crowns to be drawn.
    private func crowns(_ halere: Int64) -> Double {
        Double(halere) / 100
    }

    // MARK: The hatching

    /// The paint of the part of a bar that is still to be issued, and of its key in the legend: the hatching that marks
    /// an estimate everywhere (`Hatching`), in the colours the appearance of the window gives it.
    private var hatching: ImagePaint {
        Hatching.paint(in: environment)
    }

    // MARK: Hover and VoiceOver

    /// Over the plot: a target for each month, which the pointer lands on and VoiceOver reads, and the tooltip of the
    /// one under the pointer.
    @ViewBuilder
    private func interaction(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let anchor = proxy.plotFrame {
            let plot = geometry[anchor]
            ZStack(alignment: .topLeading) {
                monthTargets(plotWidth: plot.width)
                    .frame(width: plot.width, height: plot.height)
                    .offset(x: plot.minX, y: plot.minY)
                if let hoveredMonth {
                    TooltipPlacement(column: hoveredMonth, count: months.count) {
                        PredictionChartTooltip(month: months[hoveredMonth])
                    }
                    .frame(width: plot.width, height: plot.height)
                    .offset(x: plot.minX, y: plot.minY)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// A clear target for each month, side by side across a plot `plotWidth` wide: VoiceOver reads each in the words of
    /// its tooltip (`PredictionChartMonth.accessibilityLabel`), and the pointer over them picks the month whose tooltip
    /// shows.
    private func monthTargets(plotWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(months) { month in
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel(month.accessibilityLabel)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovered = IncomeChartLayout.column(atX: location.x, plotWidth: plotWidth, columns: months.count)
            case .ended:
                hovered = nil
            }
        }
    }
}

/// The popover of a month of the chart of the estimate: its title in bold, and what was issued, what was received and
/// what the payments left after the levies, each in a row with its actual figure under "skutečnost" and its estimate
/// under "odhad", in the texts the month gives, all in whole Kč ("—" where a part does not apply to the month). The
/// estimates are in the grey of secondary text, and the figures of the net income in semibold. Under them stand the
/// notes of the month, which wrap (`PredictionChartMonth.notes`): that what was issued is of the whole current month
/// while the money received stops at today, and why an amount is approximate. The tooltip is as wide as its lines are
/// long, so that none of them wraps. It is a panel of the colour of a card, raised off the chart as a popover is.
struct PredictionChartTooltip: View {
    /// The width of the notes under the figures, in points: they are long, so they wrap at this width and the tooltip
    /// does not grow as wide as they are long.
    static let notesWidth: CGFloat = 240

    let month: PredictionChartMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: month.title)
                .font(Typography.bodyBold)
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Color.clear
                        .frame(width: 0, height: 0)
                    Text("skutečnost")
                    Text("odhad")
                }
                .font(Typography.subheadline)
                .foregroundStyle(Palette.text3)
                GridRow {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.accent)
                            .frame(width: 10, height: 10)
                        Text("Vystaveno")
                            .fixedSize()
                    }
                    .gridColumnAlignment(.leading)
                    Text(verbatim: month.issuedActualText)
                    Text(verbatim: month.issuedEstimateText)
                        .foregroundStyle(Palette.text2)
                }
                GridRow {
                    HStack(spacing: 6) {
                        ChartRing(color: Palette.orange)
                        Text("Přijato")
                            .fixedSize()
                    }
                    Text(verbatim: month.receivedActualText)
                    Text(verbatim: month.receivedEstimateText)
                        .foregroundStyle(Palette.text2)
                }
                GridRow {
                    HStack(spacing: 6) {
                        ChartRing(color: Palette.green)
                        Text("Čistý příjem")
                            .fixedSize()
                    }
                    Text(verbatim: month.netActualText)
                        .font(Typography.bodySemibold)
                    Text(verbatim: month.netEstimateText)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text2)
                }
            }
            .monospacedDigit()
            ForEach(month.notes, id: \.self) { note in
                Text(verbatim: note)
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.text3)
                    .frame(width: Self.notesWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Typography.body)
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
                .surface(Palette.bgCard, elevation: .pop)
        }
        // The month itself speaks the same words for VoiceOver.
        .accessibilityHidden(true)
    }
}
