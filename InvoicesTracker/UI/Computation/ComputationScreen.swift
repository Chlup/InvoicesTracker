import SwiftUI

/// The sizes of the page of Výpočet that its parts do not set themselves, in points.
private nonisolated enum ComputationScreenMetrics {
    /// The space at the sides of the heading "Rozpis výpočtu".
    static let headingInset: CGFloat = 4

    /// The least width of the two cards under the result, Mezní odvod and Hranice roku.
    static let cardColumnWidth: CGFloat = 380
}

/// Výpočet: every intermediate value of the computation of the selected year as of the day shown, so that each number
/// of the tax return and of the overviews can be checked. The result comes first, in a card: what is left to pay as the
/// key figure, with the sentence that says where it goes, and the bar of the levies by authority beside it (or under
/// it, where the card is too narrow for two columns), the bar's popovers hanging out over what follows. Under it come
/// the marginal levy and the thresholds of the year, two cards of one height beside each other, and the note about the
/// day the computation counts up to. Then comes "Rozpis výpočtu", the cards of the breakdown in two columns: the income
/// and the tax on the left, the social and the health insurance on the right with the net income under them, side by
/// side where the window has room for two columns and one under the other where it has not. The assumptions end the
/// page as a footnote. The title and the line under it are the shell's; the warning that the year is an estimate with
/// the rules of another year is above all of it, and under it the line that part of the income is converted at a
/// provisional rate. The data is loaded again whenever what it depends on changes.
struct ComputationScreen: View {
    let app: AppModel
    @State private var model: ComputationModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: ComputationModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignMetrics.cardSpacing) {
                if let warning = model.warning {
                    RulesWarning(text: warning)
                }
                if let notice = model.provisionalNotice {
                    RulesWarning(text: notice)
                }
                content
            }
            .pagePadding()
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let page = model.page {
            result(page)
            AdaptiveColumns(
                minimumColumnWidth: ComputationScreenMetrics.cardColumnWidth, spacing: DesignMetrics.cardSpacing,
                equalRowHeights: true
            ) {
                MarginalCard(marginal: page.marginal)
                ThresholdsCard(thresholds: page.thresholds)
            }
            ComputationBanner(text: page.banner)
            breakdown(page.sections)
            AssumptionsFootnote(assumptions: page.assumptions, showSettings: { app.showSettings(.year) })
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    /// The result card: what is left to pay at the left and the bar of the levies at the right. Výpočet sets the parts
    /// 28 points apart in both directions, like the gap between its columns. The card is drawn above everything under
    /// it, because the popover of the bar hangs out of the card over the cards that follow.
    private func result(_ page: ComputationPage) -> some View {
        ResultCard(label: "Výsledek", rowGap: ResultCardLayout.columnGap) {
            KeyFigureView(page.keyFigure)
        } trailing: {
            LevyBarView(page.levies)
        }
        .zIndex(1)
    }

    /// "Rozpis výpočtu": its heading, and under it the cards of the breakdown in two stacks, told apart by
    /// `ComputationSection.standsRight`: on the left the income and the tax, on the right the social and the health
    /// insurance, and under them the net income. VoiceOver reads the lot as a group under the heading.
    private func breakdown(_ sections: [ComputationSection]) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.innerSpacing) {
            Text("Rozpis výpočtu")
                .font(Typography.title3)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, ComputationScreenMetrics.headingInset)
                .accessibilityAddTraits(.isHeader)
            TwoColumnStack {
                ForEach(sections.filter { !$0.standsRight }) { section in
                    ComputationCard(section: section)
                }
            } right: {
                ForEach(sections.filter(\.standsRight)) { section in
                    ComputationCard(section: section)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rozpis výpočtu")
    }
}
