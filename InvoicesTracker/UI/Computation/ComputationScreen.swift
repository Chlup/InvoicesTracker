import SwiftUI

/// Výpočet: every intermediate value of the computation of the selected year as of the day shown, so that each number
/// of the tax return and of the overviews can be checked. The result comes first, the equation of what is left to pay.
/// Under it come three cards of one height beside each other, as many as the window has room for: the marginal levy,
/// the thresholds of the year and the assumptions. Then comes the banner about the day the computation counts up to,
/// and under it the cards of the breakdown in two columns: the income and the tax on the left, the social and the
/// health insurance on the right with the net income under them, side by side where the window has room for two
/// columns and one under the other where it has not. The title and the line under it are the shell's; the warning that
/// the year is an estimate with the rules of another year is above all of it, and under it the line that part of the
/// income is converted at a provisional rate. The data is loaded again whenever what it depends on changes.
struct ComputationScreen: View {
    let app: AppModel
    @State private var model: ComputationModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: ComputationModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let warning = model.warning {
                    RulesWarning(text: warning)
                }
                if let notice = model.provisionalNotice {
                    RulesWarning(text: notice)
                }
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let page = model.page {
            EquationCard(equation: page.equation)
            AdaptiveColumns(minimumColumnWidth: 280, spacing: 16, equalRowHeights: true) {
                MarginalCard(marginal: page.marginal)
                ThresholdsCard(thresholds: page.thresholds)
                AssumptionsCard(assumptions: page.assumptions, showSettings: { app.showSettings(.year) })
            }
            ComputationBanner(text: page.banner)
            breakdown(page.sections)
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    /// The cards of the breakdown in two stacks, told apart by `ComputationSection.standsRight`: on the left the income
    /// and the tax, on the right the social and the health insurance, and under them the net income.
    private func breakdown(_ sections: [ComputationSection]) -> some View {
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
}
