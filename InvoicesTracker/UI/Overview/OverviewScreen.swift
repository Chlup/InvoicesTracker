import SwiftUI

/// Přehled: the result card with what is left to pay, the bar of the levies of the three authorities and the tiles
/// under them, the income chart with the net income of the year above it, the card with the estimate of the whole year
/// and the chart of its months (for the current year while it is in progress), the latest payments and the upcoming
/// ones, with the banner that reminds of a uniform rate to enter by hand, the New Year banner, the warning about rules
/// that are only an estimate and the line about income converted at a provisional rate above them. The title and the
/// line under it are the shell's. The data is loaded again whenever what it depends on changes, and when the day
/// changes.
struct OverviewScreen: View {
    let app: AppModel
    @State private var model: OverviewModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: OverviewModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let year = app.uniformRateReminderYear {
                    UniformRateReminderBanner(
                        year: year,
                        enterManually: { app.enterUniformRateManually(year: year) },
                        close: { app.uniformRateReminderYear = nil })
                }
                if let finished = finishedYearToAnnounce {
                    NewYearBanner(
                        finishedYear: finished,
                        showFinishedYear: {
                            app.selectYear(finished)
                            app.newYearBanner = nil
                        },
                        close: { app.newYearBanner = nil })
                }
                if let warning = model.rulesWarning {
                    RulesWarning(text: warning)
                }
                if let notice = model.provisionalNotice {
                    RulesWarning(text: notice)
                }
                content
            }
            .pagePadding()
        }
        .task(id: LoadTrigger(key: app.reloadKey, years: app.years, today: app.today)) {
            await model.load()
        }
    }

    /// What the data of the screen depends on: what every screen loads for, the years to choose from, which the chart
    /// by years shows and which a write changes only after it has changed the key, and today, because the estimate
    /// counts the invoices up to today: when midnight passes while the reporting cutoff stays where it is, nothing else
    /// changes and the estimate is out of date.
    private struct LoadTrigger: Hashable {
        var key: ReloadKey
        var years: [Int]
        var today: CivilDate
    }

    /// The year that finished, while Přehled shows the year that began after it.
    private var finishedYearToAnnounce: Int? {
        guard let finished = app.newYearBanner, app.asOf.year == finished + 1 else { return nil }
        return finished
    }

    @ViewBuilder
    private var content: some View {
        if let data = model.data {
            // The popover of the bar hangs out of the card over the cards that follow it, so the card is drawn above
            // them, and nothing clips it.
            OverviewResultCard(
                keyFigure: data.keyFigure, levies: data.levies, tiles: data.tiles,
                showComputation: { app.screen = .computation }, editAdvances: { app.screen = .advances }
            )
            .zIndex(1)
            IncomeChart(
                columns: data.columns, subtitle: data.chartSubtitle, netIncome: data.netIncome,
                uniformLine: data.uniformLine, mode: app.appSettings.chartMode, withVAT: app.appSettings.chartWithVAT,
                setMode: { mode in
                    Task { await model.setChartMode(mode) }
                },
                setWithVAT: { on in
                    Task { await model.setChartWithVAT(on) }
                })
            if let prediction = data.prediction {
                PredictionCard(card: prediction, showPrediction: { app.screen = .prediction })
            }
            AdaptiveColumns(minimumColumnWidth: 400, spacing: 16) {
                LatestReceiptsList(
                    receipts: data.latestReceipts, open: { app.openInvoice($0) },
                    showInvoices: { app.screen = .invoices })
                UpcomingList(
                    items: data.upcoming, showAdvances: { app.screen = .advances },
                    showInvoices: { app.screen = .invoices })
            }
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }
}
