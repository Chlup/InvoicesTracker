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
/// figures and its estimates; the chart has a hover of its own, apart from that of the chart of Příjmy. VoiceOver reads
/// each month in the words of its tooltip.
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
    /// secondary colour. The keys stand side by side where the card has room for them and on a further row where it has
    /// not, so that no key breaks in two.
    private func legend(hatching: ImagePaint) -> some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.chartIssued))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("Vystaveno")
            }
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color(.chartReceived))
                    .frame(width: 16, height: 3)
                    .accessibilityHidden(true)
                Text("Přijato")
            }
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color(.netIncome))
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
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2.5, dash: Self.estimateDash))
                .frame(width: 16, height: 3)
                .accessibilityHidden(true)
                Text("odhad (šrafovaně a čárkovaně)")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
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
                    .foregroundStyle(isBaseLine ? Color.secondary.opacity(0.5) : Color(nsColor: .separatorColor))
                AxisValueLabel {
                    if let kc = value.as(Double.self) {
                        Text(verbatim: IncomeChartLayout.label(forKc: Int64(kc.rounded())))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: months.map(\.label)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self), let month = months.first(where: { $0.label == label }) {
                        Text(verbatim: label)
                            .font(.callout)
                            .fontWeight(month.part == .current ? .bold : .medium)
                            .foregroundStyle(month.part == .current ? Color(.chartIssued) : Color.secondary)
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
                .foregroundStyle(Color.primary.opacity(0.06))
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
                .foregroundStyle(Color(.chartIssued))
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
            lineMarks(of: month, series: "Přijato", at: receivedPoint(of: month), color: Color(.chartReceived))
            lineMarks(of: month, series: "Čistý příjem", at: netPoint(of: month), color: Color(.netIncome))
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
            pointMark(of: month, line: "Přijato", at: receivedPoint(of: month), color: Color(.chartReceived))
            pointMark(of: month, line: "Čistý příjem", at: netPoint(of: month), color: Color(.netIncome))
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

    /// The paint of the part of a bar that is still to be issued, and of its key in the legend: stripes of two light
    /// tints of the blue of the bars (`hatchTile(blue:background:)`), on the background of the card, both as the
    /// appearance of the window has them.
    private var hatching: ImagePaint {
        ImagePaint(
            image: Self.hatchTile(
                blue: Color(.chartIssued).resolve(in: environment),
                background: Color(nsColor: .controlBackgroundColor).resolve(in: environment)))
    }

    /// The tile that the hatching repeats: `background` tinted with a fifth of `blue`, and stripes of half of `blue`
    /// rising to the right, 8 points apart along a side and as wide as the gaps between them, that run on into the
    /// stripes of the tiles beside it and under it. The pattern starts at the corner of each bar, and the tile is wider
    /// than a bar (46 points at most) and taller than the chart (220 points), so that one tile paints a whole bar:
    /// where tiles met, the backdrop showed through in specks. The tile is opaque, and the image says so. The image
    /// draws it whenever it is drawn, so it is made apart from the main actor.
    nonisolated private static func hatchTile(blue: Color.Resolved, background: Color.Resolved) -> Image {
        let period: CGFloat = 8
        let width: CGFloat = 48
        let height: CGFloat = 224
        return Image(size: CGSize(width: width, height: height), opaque: true) { context in
            let tile = Path(CGRect(x: 0, y: 0, width: width, height: height))
            context.fill(tile, with: .color(Color(background)))
            context.fill(tile, with: .color(Color(blue).opacity(0.2)))
            // A stripe is where x + y, from the top left corner, is in the first half of a period: a band between the
            // lines x + y = start and x + y = start + period / 2, drawn past the edges of the tile and cut by them.
            var stripes = Path()
            var start = -period
            while start < width + height {
                stripes.addLines([
                    CGPoint(x: start + 1, y: -1), CGPoint(x: start + period / 2 + 1, y: -1),
                    CGPoint(x: start + period / 2 - height - 1, y: height + 1),
                    CGPoint(x: start - height - 1, y: height + 1),
                ])
                stripes.closeSubpath()
                start += period
            }
            context.clip(to: tile)
            context.fill(stripes, with: .color(Color(blue).opacity(0.5)))
        }
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
/// under "odhad", in the texts the month gives ("—" where a part does not apply to the month). The estimates are in the
/// secondary colour, and the figures of the net income in bold. Under them stand the notes of the month, which wrap
/// (`PredictionChartMonth.notes`): that what was issued is of the whole current month while the money received stops
/// at today, and why an amount is approximate. The tooltip is as wide as its lines are long, so that none of them
/// wraps. It is in a material, as a popover is.
struct PredictionChartTooltip: View {
    /// The width of the notes under the figures, in points: they are long, so they wrap at this width and the tooltip
    /// does not grow as wide as they are long.
    static let notesWidth: CGFloat = 240

    let month: PredictionChartMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: month.title)
                .fontWeight(.bold)
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Color.clear
                        .frame(width: 0, height: 0)
                    Text("skutečnost")
                    Text("odhad")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                GridRow {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.chartIssued))
                            .frame(width: 10, height: 10)
                        Text("Vystaveno")
                    }
                    .gridColumnAlignment(.leading)
                    Text(verbatim: month.issuedActualText)
                    Text(verbatim: month.issuedEstimateText)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    HStack(spacing: 6) {
                        ChartRing(color: Color(.chartReceived))
                        Text("Přijato")
                    }
                    Text(verbatim: month.receivedActualText)
                    Text(verbatim: month.receivedEstimateText)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    HStack(spacing: 6) {
                        ChartRing(color: Color(.netIncome))
                        Text("Čistý příjem")
                    }
                    Text(verbatim: month.netActualText)
                        .fontWeight(.semibold)
                    Text(verbatim: month.netEstimateText)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            ForEach(month.notes, id: \.self) { note in
                Text(verbatim: note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.notesWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        // The month itself speaks the same words for VoiceOver.
        .accessibilityHidden(true)
    }
}
