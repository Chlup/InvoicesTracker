import Charts
import SwiftUI

// MARK: - Numbers and texts of the chart

/// What the chart of the income is drawn from, apart from the columns themselves: its scale, the texts of its lines and
/// where the tooltip and the bars go. Pure, so that it is tested without a view. The amounts of the chart are in
/// haléře and become crowns only to be drawn; the tooltip tells them in whole Kč.
nonisolated enum IncomeChartLayout {
    /// The top of an empty chart, in haléře: 100 000 Kč.
    private static let emptyTop: Int64 = 10_000_000

    /// Amounts above this, in haléře, are not rounded to a scale: 10 trillion Kč is beyond any income.
    private static let roundingLimit: Int64 = 1_000_000_000_000_000

    /// The sizes of a step of the scale in tenths of a power of ten: 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6 and 8, then 10.
    private static let stepTenths: [Int64] = [10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100]

    /// The space between a column and its tooltip.
    private static let tooltipGap: CGFloat = 8

    /// The widest a bar is drawn, in points.
    private static let maximumBarWidth: CGFloat = 46

    /// The largest amount the chart has to hold, in haléře: of what was issued and what was received, with VAT or
    /// without as the chart is drawn, and of the net income, which is always without VAT. The line of the net income is
    /// drawn from zero, like the axis, so a net income below zero is drawn at zero and does not make the chart taller.
    /// A chart without columns holds nothing, 0.
    static func largestAmount(in columns: [ChartColumn], withVAT: Bool) -> Int64 {
        columns.map { column in
            let issued = withVAT ? column.issuedGrossHalere : column.issuedNetHalere
            let received = withVAT ? column.receivedGrossHalere : column.receivedNetHalere
            return max(issued, received, column.netIncomeHalere.map { max(0, $0) } ?? 0)
        }.max() ?? 0
    }

    /// The top of the chart for `largest`, the largest amount in it, in haléře. The chart has four equal steps, each a
    /// round size (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a power of ten), so that its lines fall on round amounts
    /// and the largest amount fits. A chart without an amount goes up to 100 000 Kč.
    static func top(forLargest largest: Int64) -> Int64 {
        guard largest > 0 else { return emptyTop }
        guard largest <= roundingLimit else { return largest }
        // A step is at least a quarter of the largest amount.
        let needed = (largest + 3) / 4
        var power: Int64 = 10
        while power * 10 <= needed {
            power *= 10
        }
        let tenths = stepTenths.first { $0 * power / 10 >= needed } ?? 100
        return tenths * power / 10 * 4
    }

    /// The text of a line of the chart at `kc` whole crowns, in thousands with up to one decimal ("12,5 tis.") and from
    /// a million in millions with up to two ("1,25 mil."). The base line is "0".
    static func label(forKc kc: Int64) -> String {
        guard kc != 0 else { return "0" }
        let sign = kc < 0 ? "\u{2212}" : ""
        let magnitude = kc.magnitude
        if magnitude >= 1_000_000 {
            let hundredths = (magnitude + 5_000) / 10_000
            return sign + decimalText(hundredths, fractionDigits: 2) + "\u{00A0}mil."
        }
        let tenths = (magnitude + 50) / 100
        return sign + decimalText(tenths, fractionDigits: 1) + "\u{00A0}tis."
    }

    /// `scaled` as a decimal with the comma, in units of 10^-`fractionDigits`, without trailing zeros: 125 with two
    /// digits is "1,25", 150 is "1,5" and 100 is "1".
    private static func decimalText(_ scaled: UInt64, fractionDigits: Int) -> String {
        var divisor: UInt64 = 1
        for _ in 0..<fractionDigits {
            divisor *= 10
        }
        let whole = scaled / divisor
        var fraction = String(scaled % divisor)
        fraction = String(repeating: "0", count: fractionDigits - fraction.count) + fraction
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        return fraction.isEmpty ? String(whole) : String(whole) + "," + fraction
    }

    /// Where the tooltip of column `column` of `count` starts, from the left edge of a plot `plotWidth` wide: right of
    /// the column in the left half of the plot, left of it in the right half, and always inside the plot. The tooltip
    /// is as wide as its lines are long, so `tooltipWidth` is the width it measures.
    static func tooltipLeading(column: Int, of count: Int, plotWidth: CGFloat, tooltipWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let columnWidth = plotWidth / CGFloat(count)
        let center = (CGFloat(column) + 0.5) * columnWidth
        let leading =
            center <= plotWidth / 2
            ? center + columnWidth / 2 + tooltipGap
            : center - columnWidth / 2 - tooltipGap - tooltipWidth
        return min(max(leading, 0), max(0, plotWidth - tooltipWidth))
    }

    /// The width of a bar: 56 % of its column, at most 46 points.
    static func barWidth(plotWidth: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        return min(maximumBarWidth, plotWidth * 56 / (100 * CGFloat(columns)))
    }

    /// The column under a pointer `x` points from the left edge of a plot `plotWidth` wide, or nil outside the plot.
    static func column(atX x: CGFloat, plotWidth: CGFloat, columns: Int) -> Int? {
        guard columns > 0, plotWidth > 0, x >= 0, x < plotWidth else { return nil }
        return min(columns - 1, Int(x * CGFloat(columns) / plotWidth))
    }
}

// MARK: - The chart

/// The card "Příjmy": under its header, with the segmented control that groups the chart by months or by years and the
/// checkbox for VAT, the strip with the net income of the year up to the day shown and its average per month, then
/// what was issued (bars, by the day of issue) and what was received (a line with points, by the day of payment) by
/// month or by year, with or without VAT, and under it the uniform rate of the year. The chart also has a green line
/// with points for the net income, always without VAT: by month that of the invoices paid in each month up to the day
/// shown, by year that of each year that has been worked out. Hovering over a column highlights it and shows a tooltip
/// with the series with and without VAT, all in whole Kč, the net income of the column where it has it, with the words
/// that say what it covers, and, under a hairline, the average net income per month. A year that the engine worked
/// out with the rules of another year is marked as an estimate there, with the sentence that says so, while its point
/// stays in the chart. VoiceOver reads each column in the words of the tooltip, but for the words under the net
/// income.
struct IncomeChart: View {
    let columns: [ChartColumn]
    let subtitle: String

    /// The net income of the year up to the day shown and its average per month, which the strip under the header
    /// tells. They do not depend on the way the chart is grouped or drawn.
    let netIncome: OverviewNetIncome
    let uniformLine: UniformLine?
    let mode: ChartMode
    let withVAT: Bool

    /// Měsíce or Roky was chosen.
    let setMode: (ChartMode) -> Void

    /// S DPH was ticked or cleared.
    let setWithVAT: (Bool) -> Void

    /// The column the pointer is over.
    @State private var hovered: Int?

    /// The width of the chart, which the width of the bars follows.
    @State private var chartWidth: CGFloat = 0

    /// The width of the labels of the vertical axis, which the plot lacks.
    private static let axisLabelWidth: CGFloat = 56

    var body: some View {
        Card(label: "Příjmy") {
            header
            NetIncomeStrip(netIncome: netIncome)
            legend
            chart
            if let uniformLine {
                UniformRateLine(line: uniformLine)
            }
        }
    }

    // MARK: Header and legend

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Příjmy")
                    .font(Typography.title3)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                SegmentedControl(
                    "Seskupit", selection: modeSelection,
                    segments: [(value: ChartMode.months, title: "Měsíce"), (value: ChartMode.years, title: "Roky")]
                )
                .fixedSize()
                Toggle("S DPH", isOn: vatSelection)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var modeSelection: Binding<ChartMode> {
        Binding(get: { mode }, set: { setMode($0) })
    }

    private var vatSelection: Binding<Bool> {
        Binding(get: { withVAT }, set: { setWithVAT($0) })
    }

    /// What the bars and the lines are, a key for each: side by side where the card has room for them and on a second
    /// row where it has not, so that no key breaks in two. The third one is for the green line of the net income, which
    /// says what the line is by months and by years.
    private var legend: some View {
        FlowLayout(spacing: 16, lineSpacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.accent)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("Vystaveno (podle data vystavení)")
            }
            HStack(spacing: 6) {
                Capsule()
                    .fill(Palette.orange)
                    .frame(width: 16, height: 3)
                    .accessibilityHidden(true)
                Text("Přijato (podle data platby – z toho se platí daň)")
            }
            HStack(spacing: 6) {
                Capsule()
                    .fill(Palette.green)
                    .frame(width: 16, height: 3)
                    .accessibilityHidden(true)
                switch mode {
                case .months:
                    Text("Čistý příjem (součet za faktury zaplacené v měsíci, bez DPH)")
                case .years:
                    Text("Čistý příjem za rok (po odvodech, vždy bez DPH)")
                }
            }
        }
        .font(Typography.callout)
        .foregroundStyle(Palette.text2)
    }

    // MARK: The plot

    private var chart: some View {
        let top = IncomeChartLayout.top(forLargest: IncomeChartLayout.largestAmount(in: columns, withVAT: withVAT))
        let step = Double(top) / 400
        return Chart {
            highlight
            bars
            line
            netLine
        }
        .chartLegend(.hidden)
        // The order of the columns is the order of the data, not that of the first mark to mention a column: the
        // highlight of a column is the first mark while the pointer is over it.
        .chartXScale(domain: columns.map(\.label))
        .chartYScale(domain: 0...(Double(top) / 100))
        .chartYAxis {
            AxisMarks(position: .leading, values: (0...4).map { Double($0) * step }) { value in
                let isBaseLine = value.as(Double.self) == 0
                AxisGridLine()
                    .foregroundStyle(isBaseLine ? Palette.sepStrong : Palette.fill)
                AxisValueLabel {
                    if let kc = value.as(Double.self) {
                        Text(IncomeChartLayout.label(forKc: Int64(kc.rounded())))
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.text3)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: columns.map(\.label)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self), let column = columns.first(where: { $0.label == label }) {
                        Text(label)
                            .font(column.isCurrent ? Typography.callout.bold() : Typography.callout.weight(.medium))
                            .foregroundStyle(column.isCurrent ? Palette.accentText : Palette.text2)
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

    /// The column under the pointer, if it is one of those drawn.
    private var hoveredColumn: Int? {
        hovered.flatMap { columns.indices.contains($0) ? $0 : nil }
    }

    /// The faint band behind the column under the pointer.
    @ChartContentBuilder
    private var highlight: some ChartContent {
        if let hoveredColumn {
            RectangleMark(x: .value("Období", columns[hoveredColumn].label), width: .ratio(1))
                .foregroundStyle(Palette.text.opacity(0.05))
                .accessibilityHidden(true)
        }
    }

    /// What was issued: a bar for each column, faded for a month that has not come yet.
    @ChartContentBuilder
    private var bars: some ChartContent {
        let width = IncomeChartLayout.barWidth(plotWidth: chartWidth - Self.axisLabelWidth, columns: columns.count)
        ForEach(columns.indices, id: \.self) { index in
            BarMark(
                x: .value("Období", columns[index].label),
                y: .value("Vystaveno", crowns(issued(columns[index]))),
                width: width > 0 ? .fixed(width) : .ratio(0.56)
            )
            .foregroundStyle(Palette.accent)
            .opacity(columns[index].isFuture ? 0.35 : 1)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            .accessibilityHidden(true)
        }
    }

    /// What was received: a line through the points of the columns that have one, each point a ring. Each line of the
    /// chart names its series, or Swift Charts joins the marks of the two lines into one.
    @ChartContentBuilder
    private var line: some ChartContent {
        ForEach(columns.indices.filter { columns[$0].hasLinePoint }, id: \.self) { index in
            LineMark(
                x: .value("Období", columns[index].label),
                y: .value("Přijato", crowns(received(columns[index]))),
                series: .value("Řada", "Přijato")
            )
            .foregroundStyle(Palette.orange)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            .interpolationMethod(.linear)
            .accessibilityHidden(true)
            PointMark(
                x: .value("Období", columns[index].label),
                y: .value("Přijato", crowns(received(columns[index])))
            )
            .symbol {
                ChartRing(color: Palette.orange)
            }
            .accessibilityHidden(true)
        }
    }

    /// What is left of the income after the tax and the insurance: a green line through the points of the columns that
    /// have a net income and a point on the line (a month after the day shown has none), each point a ring. Each year
    /// has what it leaves after them, and each month what the invoices paid in it leave. The axis starts at zero, so a
    /// net income below it is drawn at zero; the tooltip tells the figure.
    @ChartContentBuilder
    private var netLine: some ChartContent {
        let points = columns.indices.filter { columns[$0].netIncomeHalere != nil && columns[$0].hasLinePoint }
        ForEach(points, id: \.self) { index in
            let drawn = crowns(max(0, columns[index].netIncomeHalere ?? 0))
            LineMark(
                x: .value("Období", columns[index].label),
                y: .value("Čistý příjem", drawn),
                series: .value("Řada", "Čistý příjem")
            )
            .foregroundStyle(Palette.green)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            .interpolationMethod(.linear)
            .accessibilityHidden(true)
            PointMark(
                x: .value("Období", columns[index].label),
                y: .value("Čistý příjem", drawn)
            )
            .symbol {
                ChartRing(color: Palette.green)
            }
            .accessibilityHidden(true)
        }
    }

    private func issued(_ column: ChartColumn) -> Int64 {
        withVAT ? column.issuedGrossHalere : column.issuedNetHalere
    }

    private func received(_ column: ChartColumn) -> Int64 {
        withVAT ? column.receivedGrossHalere : column.receivedNetHalere
    }

    /// Haléře as crowns to be drawn.
    private func crowns(_ halere: Int64) -> Double {
        Double(halere) / 100
    }

    // MARK: Hover and VoiceOver

    /// Over the plot: a target for each column, which the pointer lands on and VoiceOver reads, and the tooltip of the
    /// one under the pointer.
    @ViewBuilder
    private func interaction(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let anchor = proxy.plotFrame {
            let plot = geometry[anchor]
            ZStack(alignment: .topLeading) {
                columnTargets(plotWidth: plot.width)
                    .frame(width: plot.width, height: plot.height)
                    .offset(x: plot.minX, y: plot.minY)
                if let hoveredColumn {
                    TooltipPlacement(column: hoveredColumn, count: columns.count) {
                        ChartTooltip(column: columns[hoveredColumn])
                    }
                    .frame(width: plot.width, height: plot.height)
                    .offset(x: plot.minX, y: plot.minY)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func columnTargets(plotWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel(columns[index].accessibilityLabel)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovered = IncomeChartLayout.column(atX: location.x, plotWidth: plotWidth, columns: columns.count)
            case .ended:
                hovered = nil
            }
        }
    }
}

/// A ring in `color`, filled with `fill` on the background of the card: the mark of a point of a line of a chart in the
/// plot, and the mark of that line in the rows of a tooltip. The fill is the background of the card unless it is given,
/// such as a light tint of `color` for a point of the estimate. The background of the card lies under it, so that a
/// fill that is not opaque is a tint and the line under the point does not show through it.
struct ChartRing: View {
    let color: Color
    var fill: Color = Palette.bgCard

    var body: some View {
        Circle()
            .fill(fill)
            .background(Circle().fill(Palette.bgCard))
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .frame(width: 10, height: 10)
    }
}

/// The popover of a column: its title, and what was issued and received without and with VAT, all in whole Kč, the
/// values without VAT in semibold. A column that has a net income also has a row for it, in the text the column gives
/// (`netIncomeText`): the net income is always without VAT, so the column with VAT has a dash. Under the row stand the
/// words that say what the figure covers (`netIncomeNote`), across the grid in a smaller grey type. A column that has
/// an average net income per month ends with it, under a hairline, and when the year is computed with the rules of
/// another year, with the sentence that says so under it, in the orange of the warnings. The rows are as wide as their
/// amounts are long, so that none of them wraps; only the words under the net income, the words of the footer and
/// that sentence wrap, at a fixed width, and the amount of the footer does not. It is a panel of the colour of a card,
/// raised off the chart as a popover is.
struct ChartTooltip: View {
    /// The width of the words under the net income row, of the words of the footer and of the sentence under it, in
    /// points. The note, the label and the sentence are long, so they wrap at this width and the tooltip does not grow
    /// as wide as they are long.
    static let footerWordsWidth: CGFloat = 220

    let column: ChartColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: column.title)
                .font(Typography.bodyBold)
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Color.clear
                        .frame(width: 0, height: 0)
                    Text("bez DPH")
                    Text("s DPH")
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
                    Text(verbatim: column.issuedNetText)
                        .font(Typography.bodySemibold)
                    Text(verbatim: column.issuedGrossText)
                }
                if column.issuedIsApproximate {
                    GridRow {
                        note(ChartColumn.approximateIssuedNote)
                    }
                }
                GridRow {
                    HStack(spacing: 6) {
                        ChartRing(color: Palette.orange)
                        Text("Přijato")
                            .fixedSize()
                    }
                    Text(verbatim: column.receivedNetText)
                        .font(Typography.bodySemibold)
                    Text(verbatim: column.receivedGrossText)
                }
                if let netIncomeText = column.netIncomeText {
                    GridRow {
                        HStack(spacing: 6) {
                            ChartRing(color: Palette.green)
                            Text("Čistý příjem")
                            .fixedSize()
                        }
                        Text(verbatim: netIncomeText)
                            .font(Typography.bodySemibold)
                        Text(verbatim: "—")
                            .foregroundStyle(Palette.text4)
                    }
                    if let netIncomeNote = column.netIncomeNote {
                        GridRow {
                            note(netIncomeNote)
                        }
                    }
                }
            }
            .monospacedDigit()
            if let netAverage = column.netAverage {
                Hairline()
                footer(netAverage)
                if let note = netAverage.note {
                    Text(verbatim: note)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.orangeText)
                        .frame(width: Self.footerWordsWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        // The column itself speaks the same words for VoiceOver.
        .accessibilityHidden(true)
    }

    /// `text` across the three columns of the grid, in the small grey type of a note, wrapping at the width of the
    /// words of the footer.
    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Typography.subheadline)
            .foregroundStyle(Palette.text3)
            .frame(width: Self.footerWordsWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .gridCellColumns(3)
            .gridCellAnchor(.leading)
    }

    /// The average net income per month: its words, which wrap in `footerWordsWidth`, and its amount at the right in
    /// bold, which never wraps.
    private func footer(_ netAverage: ChartNetAverage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: netAverage.label)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .frame(width: Self.footerWordsWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 14)
            Text(verbatim: netAverage.value)
                .font(Typography.bodyBold)
                .monospacedDigit()
                .fixedSize()
        }
    }
}

/// Stands the tooltip, its one subview, in the plot it fills: where `IncomeChartLayout.tooltipLeading` puts the tooltip
/// of column `column` of `count`, and 4 points under the top of the plot. The tooltip is as wide as its lines are long,
/// which only its own size tells, so it is placed by the width it has.
struct TooltipPlacement: Layout {
    let column: Int
    let count: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let tooltip = subviews.first else { return }
        let size = tooltip.sizeThatFits(.unspecified)
        let leading = IncomeChartLayout.tooltipLeading(
            column: column, of: count, plotWidth: bounds.width, tooltipWidth: size.width)
        tooltip.place(
            at: CGPoint(x: bounds.minX + leading, y: bounds.minY + 4), anchor: .topLeading,
            proposal: ProposedViewSize(size))
    }
}
