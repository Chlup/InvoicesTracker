import SwiftUI

/// Odhad odvodů: the estimate of the selected year's whole income, client by client, and of its tax and insurance. At
/// the top stands the warning that the year is an estimate with the rules of another year, and under that the line that
/// part of the income is converted at a provisional rate, each only when it applies. Then comes the summary card, with
/// the sum of the levies, what is left to settle beyond the year's advances (the doplatek, or the přeplatek when the
/// advances pay more than the levies), the income with its bar and the net income of the year, and under it the banner
/// that says what the estimate counts. Then come the months of the clients ("Kdy čekám faktury"), folded until the
/// person opens them, where a tap on a month says whether an invoice is expected in it, and the breakdown of the
/// levies in two columns: the income and the tax on the left, the social and the health insurance with the net income
/// under them on the right, side by side where the window has room for two columns and one under the other where it
/// has not. The title and the line under it are the shell's. The screen only lays out the page the model builds. The
/// data is loaded again whenever what it depends on changes, and when the day changes: the estimate is made as of
/// today, whatever "K datu" shows.
struct PredictionScreen: View {
    let app: AppModel
    @State private var model: PredictionModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: PredictionModel(app: app))
    }

    /// What the page depends on: what every screen loads for, and today, because the estimate counts the invoices up to
    /// today: when midnight passes while "K datu" is on another day, nothing else changes and the page is out of date.
    private nonisolated struct LoadTrigger: Hashable {
        var key: ReloadKey
        var today: CivilDate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .pagePadding()
        }
        .task(id: LoadTrigger(key: app.reloadKey, today: app.today)) {
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let page = model.page {
            if let warning = model.rulesWarning {
                RulesWarning(text: warning)
            }
            if let notice = model.provisionalNotice {
                RulesWarning(text: notice)
            }
            PredictionSummaryCard(page: page)
            ComputationBanner(text: page.banner)
            PredictionMonthsSection(
                page: page, saveFailure: model.saveFailure, isOpen: Bindable(app).predictionMonthsOpen,
                othersAreOpen: Bindable(app).predictionOthersOpen,
                toggle: { clientID, month in
                    Task { await model.toggle(clientID: clientID, month: month) }
                },
                reset: { clientID in
                    Task { await model.reset(clientID: clientID) }
                })
            breakdown(page)
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    /// "Rozpis výpočtu": the cards of the income and the tax on the left, and of the social insurance and the health
    /// insurance with the net income under them on the right.
    private func breakdown(_ page: PredictionPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rozpis výpočtu")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            TwoColumnStack {
                ForEach(page.left) { section in
                    card(of: section)
                }
            } right: {
                ForEach(page.right) { section in
                    card(of: section)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rozpis odhadu odvodů")
    }

    /// A card of the breakdown, which VoiceOver reads under the title of its section.
    private func card(of section: ComputationSection) -> some View {
        ComputationCard(section: section)
            .accessibilityLabel(section.title)
    }
}
