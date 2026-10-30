import SwiftUI

/// The note above the cards about what the computation counts up to the day shown: a note of the information tone,
/// blue. Simulátor's note has a small secondary button at its end. VoiceOver reads a note without a button as one
/// phrase, and reaches the button of one that has it on its own.
struct ComputationBanner: View {
    let text: String

    /// The title and the action of the button at the end of the note, such as "Začít znovu", or nil for none.
    var button: (title: String, action: () -> Void)?

    var body: some View {
        if let button {
            Note(.info, text: text) {
                Button(button.title, action: button.action)
                    .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            }
        } else {
            Note(.info, text: text)
        }
    }
}

// MARK: - Zbývá zaplatit

/// The equation of what is left to pay: the shares of the three authorities in boxes, added up in a dark one, with the
/// sentence under them about where the sum goes.
struct EquationCard: View {
    let equation: ComputationEquation

    var body: some View {
        Card(spacing: 16, label: "Zbývá zaplatit") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    heading
                    Spacer(minLength: 8)
                    caption
                }
                VStack(alignment: .leading, spacing: 4) {
                    heading
                    caption
                }
            }
            FlowLayout(spacing: 10) {
                ForEach(equation.tiles) { tile in
                    EquationTile(tile: tile)
                }
            }
            Text(verbatim: equation.split)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heading: some View {
        Text(verbatim: equation.heading)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private var caption: some View {
        Text(verbatim: equation.caption)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A box of the equation with the sign in front of it. The sum is set apart: the colour of the text on the colour of
/// the background, the other way round.
private struct EquationTile: View {
    let tile: ComputationTile

    private var inverse: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        HStack(spacing: 10) {
            if tile.sign != .blank {
                Text(verbatim: tile.sign.rawValue)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: tile.label)
                    .font(.callout)
                    .foregroundStyle(tile.isResult ? AnyShapeStyle(inverse.opacity(0.8)) : AnyShapeStyle(.secondary))
                Text(verbatim: tile.value)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(tile.isResult ? AnyShapeStyle(inverse) : AnyShapeStyle(.primary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                tile.isResult ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mezní odvod

/// What the three levies take of the next crown, in big rounded digits, with a bar of the part of each authority and
/// the sentence that says it in crowns.
struct MarginalCard: View {
    let marginal: ComputationMarginal

    var body: some View {
        Card(label: "Mezní odvod", fillsHeight: true) {
            Text("Mezní odvod")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: marginal.total)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            AuthorityShareBar(shares: marginal.shares)
            Text(verbatim: marginal.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The parts of the three authorities one after the other on a track, each in its colour; nothing is drawn of an empty
/// bar. Mezní odvod draws the parts of the next crown so, and Simulátor the parts of what the year costs.
struct AuthorityShareBar: View {
    let shares: [MarginalShare]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(shares) { share in
                    Rectangle()
                        .fill(share.authority.color)
                        .frame(width: proxy.size.width * share.fraction)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}

// MARK: - Hranice roku

/// How far the year is from its limits: a line with the title and where the year stands, and a bar of the way, for
/// each of them.
struct ThresholdsCard: View {
    let thresholds: ComputationThresholds

    var body: some View {
        Card(label: "Hranice roku", fillsHeight: true) {
            Text(verbatim: thresholds.heading)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(thresholds.bars) { bar in
                ThresholdLine(bar: bar)
            }
        }
    }
}

private struct ThresholdLine: View {
    let bar: ThresholdBar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: bar.title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: bar.value)
                    .monospacedDigit()
                    .foregroundStyle(bar.isHighlighted ? AnyShapeStyle(Color(.bannerText)) : AnyShapeStyle(.secondary))
                    .fixedSize()
            }
            track
        }
        .accessibilityElement(children: .combine)
    }

    /// The way to the limit, in the colour of its authority, or a neutral one.
    private var track: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(bar.authority?.color ?? Color.secondary)
                .frame(width: proxy.size.width * bar.fraction)
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

// MARK: - Předpoklady výpočtu

/// What the computation takes for granted, with the way to the rules in Nastavení.
struct AssumptionsCard: View {
    let assumptions: ComputationAssumptions
    let showSettings: () -> Void

    var body: some View {
        Card(spacing: 10, label: "Předpoklady", fillsHeight: true) {
            Text("Předpoklady výpočtu")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(assumptions.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(verbatim: item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("Pravidla v Nastavení", action: showSettings)
                .buttonStyle(.link)
                .font(.callout)
        }
    }
}
