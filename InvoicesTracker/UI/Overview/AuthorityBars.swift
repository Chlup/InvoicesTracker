import SwiftUI

/// The right half of the headline card: what the authorities want from the income so far, with what part of the income
/// that is written under it, and one bar for each. The whole bar is what the authority wants, its solid part what the
/// advances paid, and the rest, in the same colour at a reduced opacity, what is still to pay; after the name of the
/// authority stands what part of the income it takes. An authority owed nothing so far has a neutral bar, empty until
/// advances are paid to it, which then draw it full in the authority's colour. So has the tax office with a tax bonus:
/// its bar names the bonus instead of the tax and, once tax advances are paid, is drawn full in the colour of the tax.
/// While the income is not above zero there is no part of it to write, and the card has no shares.
struct AuthorityBars: View {
    let hero: OverviewHero
    let bars: [AuthorityBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hero.head)
                        .fontWeight(.semibold)
                    Text("plná část pruhu je zaplacená zálohami, světlá zbývá zaplatit")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                total
            }
            ForEach(bars, id: \.authority) { bar in
                AuthorityBarRow(bar: bar)
            }
        }
    }

    /// What the authorities want in all, at the right, with what part of the income that is under it. VoiceOver reads
    /// the two as one phrase.
    private var total: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(CzechFormat.wholeKc(hero.totalLiabilityKc))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            if let shareText = hero.shareText {
                Text(verbatim: shareText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bar of one authority, with its name, what part of the income it takes and what it wants above it, and the two
/// texts under it.
private struct AuthorityBarRow: View {
    let bar: AuthorityBar

    /// Whether the advances paid so far leave something to pay. When they do not, the text of what remains is green.
    private var hasRemainder: Bool {
        bar.liability > bar.paid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(bar.authority.color)
                        .frame(width: 10, height: 10)
                    Text(bar.title)
                        .fontWeight(.semibold)
                }
                if let shareText = bar.shareText {
                    Text(verbatim: shareText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text(bar.liabilityText)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            track
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(bar.paidText)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(bar.remainingText)
                    .fontWeight(.semibold)
                    .foregroundStyle(hasRemainder ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.bannerText)))
            }
            .font(.callout)
            .monospacedDigit()
        }
        // VoiceOver reads the bar with the authority and all its numbers in one phrase, not the texts around it again.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.accessibilityLabel)
    }

    /// The bar itself: the authority's colour at a reduced opacity, or a neutral grey for an authority owed nothing,
    /// with the paid part solid on top.
    private var track: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(bar.liability > 0 ? bar.authority.color.opacity(0.25) : Color.secondary.opacity(0.15))
            .frame(height: 14)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(bar.authority.color)
                        .frame(width: proxy.size.width * bar.paidFraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
