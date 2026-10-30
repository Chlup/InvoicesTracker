import SwiftUI

/// The headline card of Odhad odvodů: the tax and the insurance of the whole year in big rounded numerals, with the
/// sentence under it that says what they are made from and, under a divider, what is left to settle beyond the year's
/// advances: its amount in the same big numerals, with a sentence that names the advances. Beside it or under it in a
/// narrow window stands the year's income: its total over a bar of what has been received, what waits for its payment
/// and what is only expected (hatched), with the legend of the bar. Under a divider come the net income of the year,
/// shown as its average per month with the sum of the whole year under it, and the note about the money that comes next
/// year.
struct PredictionSummaryCard: View {
    let page: PredictionPage

    var body: some View {
        AdaptiveColumns(minimumColumnWidth: 360, spacing: 28) {
            headline
            income
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(page.label)
    }

    // MARK: The headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HeadlineLabel(text: page.label, color: Color(.simulationText))
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: page.hero)
                        .figureStyle()
                    if let share = page.heroShare {
                        Text(verbatim: share)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                FlowLayout(spacing: 16, lineSpacing: 6) {
                    ForEach(page.levies) { levy in
                        LevyItem(levy: levy)
                    }
                }
                Text(verbatim: page.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: sentenceWidth, alignment: .leading)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                SettlementBlock(settlement: page.settlement)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: The income

    private var income: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    incomeHead
                    Spacer(minLength: 8)
                    incomeTotal
                }
                VStack(alignment: .leading, spacing: 4) {
                    incomeHead
                    incomeTotal
                }
            }
            IncomeBar(parts: page.parts)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(page.incomeHead): \(page.incomeTotal)")
                .accessibilityAddTraits(.isImage)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(page.parts) { part in
                    PartLine(part: part)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                NetIncomeBlock(netIncome: page.netIncome)
                    .padding(.top, 14)
            }
            if let note = page.nextYearNote {
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(Color(.simulationText))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.futureDateBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var incomeHead: some View {
        Text(verbatim: page.incomeHead)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var incomeTotal: some View {
        Text(verbatim: page.incomeTotal)
            .font(.system(size: 20, weight: .bold))
            .monospacedDigit()
            .fixedSize()
    }
}

// MARK: - Parts of the headline

/// One of the three levies under the hero figure: the dot of its authority, its name and what it comes to.
private struct LevyItem: View {
    let levy: PredictionLevy

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(levy.authority.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(verbatim: levy.title)
                .foregroundStyle(.secondary)
            Text(verbatim: levy.value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// What is left to settle beyond the advances: its caption, its amount in the big numerals of the sum of the levies
/// and the sentence that names the advances in bold. VoiceOver reads the three as one, in this order.
private struct SettlementBlock: View {
    let settlement: PredictionSettlement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeadlineLabel(
                text: settlement.label, color: settlement.kind == .owed ? Color(.simulationText) : Color(.bannerText))
            Text(verbatim: settlement.amount)
                .figureStyle()
            Text(sentence)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: sentenceWidth, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The sentence under the amount, with the advances in bold.
    private var sentence: AttributedString {
        var advances = AttributedString(settlement.advances)
        advances.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(settlement.lead) + advances + AttributedString(settlement.tail)
    }
}

/// The caption of a part of the headline: the label of the card, or of what is left to settle. Bold capitals, spaced
/// out, in `color`.
private struct HeadlineLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(verbatim: text)
            .font(.callout.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

/// How wide a sentence of the headline may be, in points: the line that says what the sum of the levies is made from,
/// and the one under what is left to settle.
private let sentenceWidth: CGFloat = 442

extension Text {
    /// The style of the big figures of the headline: 52 points, rounded and bold, in digits of one width, set a little
    /// closer. A figure stays in one line, and shrinks down to half its size where the room is narrow.
    fileprivate func figureStyle() -> some View {
        font(.system(size: 52, weight: .bold, design: .rounded))
            .monospacedDigit()
            .tracking(-1)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - The bar

/// The fill of a part of the income: the money received is dark, what waits for its payment is the blue of the issued
/// money, and what is only expected is hatched.
private struct PartFill: View {
    let kind: PredictionPartKind

    var body: some View {
        switch kind {
        case .received:
            Rectangle().fill(Color.primary.opacity(0.9))
        case .waiting:
            Rectangle().fill(Color(.chartIssued))
        case .expected:
            HatchedFill()
        }
    }
}

/// The parts of the income one after the other on a track, each as wide as its part of the whole; nothing is drawn of
/// what is not there.
private struct IncomeBar: View {
    let parts: [PredictionPart]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(parts) { part in
                    PartFill(kind: part.kind)
                        .frame(width: proxy.size.width * part.fraction)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 14)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// Stripes at 135 degrees, 3 points across each, from the top left corner: the blue of the issued money mixed with the
/// card at half strength and at a fifth. The colours are opaque, so they are the same over whatever lies under them,
/// and nothing adds up where the stripes meet.
private struct HatchedFill: View {
    var body: some View {
        Canvas { context, size in
            let strong = Color(.chartIssued).mix(with: Color(nsColor: .controlBackgroundColor), by: 0.5, in: .device)
            let faint = Color(.chartIssued).mix(with: Color(nsColor: .controlBackgroundColor), by: 0.8, in: .device)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(faint))
            // A stripe of 3 points across is 3 points times the square root of 2 along the top edge. The pair of a
            // strong and a faint stripe is twice that.
            let stripe = 3 * 2.0.squareRoot()
            var start: CGFloat = 0
            while start < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: start, y: 0))
                path.addLine(to: CGPoint(x: start + stripe, y: 0))
                path.addLine(to: CGPoint(x: start + stripe - size.height, y: size.height))
                path.addLine(to: CGPoint(x: start - size.height, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(strong))
                start += 2 * stripe
            }
        }
    }
}

/// A line of the legend of the bar: the swatch of the part, what it is and how much it is.
private struct PartLine: View {
    let part: PredictionPart

    var body: some View {
        HStack(spacing: 10) {
            PartFill(kind: part.kind)
                .frame(width: 10, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 12)
                .accessibilityHidden(true)
            Text(verbatim: part.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: part.value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The net income

/// The net income of the year under the parts of the income: the dot in the colour of the net income with its caption,
/// the average per month in bold numerals at the right of the caption where the column has room for both and under it
/// where it has not, and the sum of the whole year under them. VoiceOver reads the three as one, in this order.
private struct NetIncomeBlock: View {
    let netIncome: PredictionNetIncome

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    caption
                    Spacer(minLength: 8)
                    amount
                }
                VStack(alignment: .leading, spacing: 4) {
                    caption
                    amount
                }
            }
            Text(verbatim: netIncome.sub)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The dot in the colour of the net income and the caption.
    private var caption: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(.netIncome))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: netIncome.label)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The average per month, as big as the total of the income above the bar, kept in one line.
    private var amount: some View {
        Text(verbatim: netIncome.amount)
            .font(.system(size: 20, weight: .bold))
            .monospacedDigit()
            .fixedSize()
    }
}
