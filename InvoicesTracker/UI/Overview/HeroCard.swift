import SwiftUI

/// The headline card of Přehled: what is left to pay, in big rounded numerals, with the sentence under it, the way on
/// to the computation and to the plan of advances and the three numbers under the headline, and beside it, or under it
/// in a narrow window, the bars of the three authorities.
struct HeroCard: View {
    let hero: OverviewHero
    let mini: [MiniStat]
    let bars: [AuthorityBar]

    /// Jak se to počítá.
    let showComputation: () -> Void

    /// Upravit plán záloh.
    let editAdvances: () -> Void

    var body: some View {
        AdaptiveColumns(minimumColumnWidth: 360, spacing: 28) {
            headline
            AuthorityBars(hero: hero, bars: bars)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .screenCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kolik zbývá zaplatit")
    }

    // MARK: The headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(hero.label)
                    .font(.callout.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(hero.amountKc > 0 ? Color(.attentionText) : Color(.bannerText))
                Text(CzechFormat.wholeKc(hero.amountKc))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(hero.text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460, alignment: .leading)
                    .padding(.top, 4)
            }
            HStack(spacing: 8) {
                Button(action: showComputation) {
                    HStack(spacing: 6) {
                        Text("Jak se to počítá")
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Upravit plán záloh", action: editAdvances)
                    .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            Divider()
                .padding(.top, 2)
            AdaptiveColumns(minimumColumnWidth: 140, spacing: 12) {
                ForEach(mini, id: \.label) { stat in
                    MiniStatView(stat: stat)
                }
            }
        }
    }
}

/// One of the three numbers under the headline.
private struct MiniStatView: View {
    let stat: MiniStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(stat.value)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(stat.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
