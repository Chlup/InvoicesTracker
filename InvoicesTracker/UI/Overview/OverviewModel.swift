import Foundation
import Observation

/// The model of Přehled: loads what the screen shows for the selected year as of the reporting cutoff (`asOf`) and
/// turns it into view data (`OverviewBuilder`), and keeps the choices of the chart in the settings.
///
/// A load reads the selected year from the data: its receipts and settings, the invoices of its newest receipts, the
/// invoices of the chart (those of all the years only when the chart groups by years), its VAT, its currencies, its
/// uniform rates and whether a receipt up to the day shown is converted at a provisional rate. From the receipts it
/// also works out what each payment of an invoice of the year adds to the levies on its own day, whatever the day shown
/// (`OverviewInput.invoicePaymentEffects`), for the net income of the months of the chart. Whichever way the chart
/// groups, a load also reads how each year to choose from (`AppModel.years`) converts its income in other currencies
/// (`Database.effectiveFXMethod(year:)`): the settings of the year, its uniform rates and the currencies it was paid
/// in. A chart that groups by years also reads the receipts, settings and family of every other year it shows that has
/// begun by the day the chart is cut at (`OverviewBuilder.chartCut(asOf:today:mode:)`), to work out its levies as of
/// the day its net income is counted to (`OverviewBuilder.netIncomeDay(ofYear:cut:)`). A chart that groups by months
/// reads no other year's receipts or family. The current year, except on its last day, also has the estimate of its
/// whole income and levies for its card, which is made from today's data whatever the day shown is
/// (`AppModel.predictionOutcome(year:)`). For the chart of the card a load also works out what each payment the
/// estimate expects adds to the levies on its own day (`PredictionOutcome.expectedPayments()`), which asks the engine
/// for them and so is done here and not by the builder. The levies of the current year as of today are also worked out
/// a second time with the unpaid invoices due by the end of the month counted as paid (`DueInvoices`), for the average
/// of its net income (`DueNetIncome`): from the year shown when that is the current year and the day shown is not
/// before today, and otherwise from the year as the chart by years has it. Nothing is read for it where the levies of
/// the current year are not worked out as of today, and no second calculation is made where no invoice counts. The
/// screen loads again whenever what the data depends on changes (`AppModel.reloadKey`), and when the day changes, which
/// the estimate follows, and so does the average that counts the invoices due (`DueNetIncome`, worked out as of today).
/// The model keeps the data of the last load until the next one has finished, so that the screen does not flash empty;
/// a load that fails shows a line instead. An estimate that fails does not: its card is left out and the rest of the
/// page loads. Nor does a year of the chart whose levies cannot be worked out: it has no net income in the chart. Nor
/// do the invoices due: when they cannot be read or counted, the average is the one of the money received.
@MainActor
@Observable
final class OverviewModel {
    /// What the screen says in place of its content when the data cannot be loaded.
    static let loadFailureText = "Přehled se nepodařilo načíst."

    /// What the screen shows: nil until the first load has finished, and after a load that failed.
    private(set) var data: OverviewData?

    /// The warning that the levies of the year are an estimate with the rules of another year, or nil when they are not.
    private(set) var rulesWarning: String?

    /// The line that part of the income of the year up to the day shown is converted at a provisional rate, or nil
    /// when none of it is.
    private(set) var provisionalNotice: String?

    /// What the screen says in place of its content when the last load failed, otherwise nil.
    private(set) var errorText: String?

    private let app: AppModel

    /// How many loads have started. Only the latest one may show its result: a load that was started for a year or a
    /// choice that has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading

    /// Loads the data of the selected year as of the day shown, and the choices of the chart from the settings. A
    /// failure is logged (the domain and the code of the error alone) and shows `errorText` in place of the data.
    /// Cancellation preserves the prior data, warnings and error without publishing this load.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        do {
            let loaded = try await assemble()
            guard thisLoad == loadsStarted, !Task.isCancelled else { return }
            data = loaded.data
            rulesWarning = loaded.rulesWarning
            provisionalNotice = loaded.provisionalNotice
            errorText = nil
        } catch is CancellationError {
            return
        } catch {
            guard thisLoad == loadsStarted, !Task.isCancelled else { return }
            AppModel.log("Loading Přehled", failedWith: error)
            data = nil
            rulesWarning = nil
            provisionalNotice = nil
            errorText = Self.loadFailureText
        }
    }

    /// Groups the chart by months or by years, remembers the choice in the settings and shows the chart that way.
    func setChartMode(_ mode: ChartMode) async {
        await app.updateAppSettings { $0.chartMode = mode }
        await load()
    }

    /// Shows the chart with VAT or without, remembers the choice in the settings and shows the chart that way.
    func setChartWithVAT(_ on: Bool) async {
        await app.updateAppSettings { $0.chartWithVAT = on }
        await load()
    }

    // MARK: Assembling

    private struct Loaded {
        var data: OverviewData
        var rulesWarning: String?
        var provisionalNotice: String?
    }

    /// Reads what the screen shows for the year shown as of the day shown and builds it, with the warnings that go with
    /// it. Throws `VaultError.locked` while the data is locked, and the error of any read or calculation that fails but
    /// for those of the extras of the page, which are left out instead: the estimate, the net income of a year of the
    /// chart and the average that counts the unpaid invoices due this month.
    private func assemble() async throws -> Loaded {
        guard let database = app.database else { throw VaultError.locked }
        // The year, the day, today and the choices as they are when the load starts: all of it is about them, however
        // they change meanwhile (a change starts a load of its own).
        let shown = app.asOf
        let day = app.receivedThrough
        let today = app.today
        let years = app.years.sorted()
        let settings = app.appSettings

        // The levies and the effects of the receipts are worked out from one read of the year, so that they agree
        // (`computeSelectedYear()` would read it again for itself). The current year is read once more, for the
        // estimate of its card (`loadEstimate(ofYear:)`), and, when it is not the year shown, for the average that
        // counts the invoices due (`loadDueNetIncome(shown:shownInput:result:netIncomeResults:today:in:)`).
        // The levies and the receipts are of the day the money is received by (`AppModel.receivedThrough`), while the
        // chart reports the invoices issued up to the reporting cutoff, the end of the current month.
        let yearInput = try await app.yearInput(for: shown.year).input
        let result = try AppModel.compute(yearInput, asOf: day)
        let invoicePaymentEffects = Self.invoicePaymentEffects(of: yearInput)
        let latest = try await latestReceipts(of: yearInput, asOf: day, in: database)

        let chartRows: [InvoiceChartRow]
        let netIncomeResults: [Int: TaxResult]
        switch settings.chartMode {
        case .months:
            chartRows = try await database.chartRows(fromYear: shown.year, throughYear: shown.year, today: today)
            netIncomeResults = [:]
        case .years:
            chartRows = try await database.chartRows(
                fromYear: years.first ?? shown.year, throughYear: years.last ?? shown.year, today: today)
            netIncomeResults = await loadNetIncomeResults(ofYears: years, shown: shown, result: result, today: today)
        }
        let vatByMonth = try await database.vatByDUZPMonth(year: shown.year)
        let vatToCheckMonths = try await database.monthsWithVATToCheck(year: shown.year)
        let foreignCurrencies = try await database.foreignCurrencies(year: shown.year)
        let uniformRates = try await database.uniformRates(year: shown.year)
        // The years of the chart that convert their income at their uniform rate, which the texts name.
        var yearsAtUniformRate: Set<Int> = []
        for year in Set(years + [shown.year]) {
            if try await database.effectiveFXMethod(year: year) == .uniform {
                yearsAtUniformRate.insert(year)
            }
        }
        let isProvisional = try await database.hasProvisionalReceipt(year: shown.year, through: day)
        let estimate = try await loadEstimate(ofYear: shown.year)
        let dueNetIncome = try await loadDueNetIncome(
            shown: shown, shownInput: yearInput, result: result, netIncomeResults: netIncomeResults, today: today,
            in: database)

        let input = OverviewInput(
            year: shown.year, asOf: shown.asOf, today: today, result: result, advances: yearInput.advances,
            latestReceipts: latest, chartMode: settings.chartMode, chartWithVAT: settings.chartWithVAT,
            chartRows: chartRows, chartYears: years, vatByMonth: vatByMonth, vatToCheckMonths: vatToCheckMonths,
            foreignCurrencies: foreignCurrencies, uniformRates: uniformRates, yearsAtUniformRate: yearsAtUniformRate,
            prediction: estimate, netIncomeResults: netIncomeResults, invoicePaymentEffects: invoicePaymentEffects,
            expectedPayments: estimate?.expectedPayments() ?? [], dueNetIncome: dueNetIncome
        )
        let warning =
            result.rulesAreEstimate ? RulesWarning.message(year: result.year, rulesYear: result.rules.year) : nil
        return Loaded(
            data: OverviewBuilder.build(input), rulesWarning: warning,
            provisionalNotice: isProvisional ? RulesWarning.provisionalIncome : nil)
    }

    /// The estimate of the whole of `year` for its card, or nil when the page has no card: an estimate that is closed,
    /// of a year other than the current one or of the current one on its last day, is not made
    /// (`PredictionInput.isClosed(year:today:)`), and one that cannot be made is left out. It is made from today's
    /// data, whatever day the page is shown as of. The card is an extra of the page: a failure is logged (the domain
    /// and the code of the error alone) and never keeps the rest of the page from showing. Cancellation propagates
    /// to the screen load so that an interrupted lookup cannot remove an already displayed card.
    private func loadEstimate(ofYear year: Int) async throws -> PredictionOutcome? {
        guard !PredictionInput.isClosed(year: year, today: app.today) else { return nil }
        do {
            return try await app.predictionOutcome(year: year)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppModel.log("Loading the estimate of Přehled", failedWith: error)
            return nil
        }
    }

    /// The levies of the current year as of today with the unpaid invoices due by the end of its month counted as paid
    /// on today (`DueNetIncome`), or nil when the page has no such figure: the year has no levies as of today on this
    /// page, no invoice counts, or the invoices cannot be read or counted. The current year's levies as of today are
    /// the ones the page shows when the year shown is the current one (`result`, `shownInput`), and otherwise the ones
    /// of its column in the chart by years (`netIncomeResults`); where they are of another day (the day shown is before
    /// today) there is no figure, as the average it would replace is of that day. The invoices are read by
    /// `Database.dueUnpaidRows(issuedFrom:dueThrough:today:)` and turned into receipts of today
    /// (`DueInvoices.receipts(of:on:)`), which are added to the receipts of the year as the data holds them. The
    /// figure is an extra of the page: a failure is logged (the domain and the code of the error alone) and never keeps
    /// the rest of the page from showing. Cancellation propagates to the screen load so that an interrupted lookup
    /// cannot remove an already displayed figure.
    private func loadDueNetIncome(
        shown: AsOfState, shownInput: YearInput, result: TaxResult, netIncomeResults: [Int: TaxResult],
        today: CivilDate, in database: Database
    ) async throws -> DueNetIncome? {
        let current = shown.year == today.year ? result : netIncomeResults[today.year]
        guard let current, current.asOf == today else { return nil }
        do {
            let dueThrough = DueInvoices.dueThrough(today: today)
            let rows = try await database.dueUnpaidRows(
                issuedFrom: DueInvoices.issuedFrom(today: today), dueThrough: dueThrough, today: today)
            let receipts = DueInvoices.receipts(of: rows, on: today)
            guard !receipts.isEmpty else { return nil }
            var input = shownInput
            if shown.year != today.year {
                input = try await app.yearInput(for: today.year).input
            }
            input.receipts += receipts
            return DueNetIncome(result: try AppModel.compute(input, asOf: today), dueThrough: dueThrough)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppModel.log("Loading the due invoices of Přehled", failedWith: error)
            return nil
        }
    }

    /// The levies of each year of the chart by years as of the day its net income is counted to
    /// (`OverviewBuilder.netIncomeDay(ofYear:cut:)`, from the day the chart is cut at), by year. The selected year is
    /// worked out already: `result` is of the day shown, and that is the day of its net income, whether the chart is
    /// cut at the day shown or, for a year that is over and shown as of its last day, at today. Any other year is read
    /// and worked out from its own data. A year after the cut has no entry, and neither has one that cannot be worked
    /// out: the net income is an extra of the chart, so a failure is logged (the domain and the code of the error
    /// alone) and never keeps the rest of the page from showing.
    private func loadNetIncomeResults(
        ofYears years: [Int], shown: AsOfState, result: TaxResult, today: CivilDate
    ) async -> [Int: TaxResult] {
        let cut = OverviewBuilder.chartCut(asOf: shown.asOf, today: today, mode: .years)
        var results: [Int: TaxResult] = [:]
        for year in years {
            guard let day = OverviewBuilder.netIncomeDay(ofYear: year, cut: cut) else { continue }
            if year == shown.year {
                results[year] = result
                continue
            }
            do {
                let input = try await app.yearInput(for: year).input
                results[year] = try AppModel.compute(input, asOf: day)
            } catch {
                AppModel.log("Loading the net income of a year of Přehled", failedWith: error)
            }
        }
        return results
    }

    /// What each payment of an invoice in the receipts of `input` adds to the levies of the year on its own day
    /// (`TaxEngine.effect(of:in:)`), in the order of the receipts and whatever the day shown: the chart by months cuts
    /// them at the day itself. An income adjustment is no payment of an invoice, so it has no effect of its own,
    /// although it counts in the effects of the payments after it. `input` must have been checked already
    /// (`AppModel.compute(_:asOf:)` checks it), as the engine stops the app on an input it does not take.
    private static func invoicePaymentEffects(of input: YearInput) -> [ReceiptEffect] {
        input.receipts.compactMap { receipt in
            guard case .invoice = receipt.source else { return nil }
            return TaxEngine.effect(of: receipt, in: input)
        }
    }

    /// The invoices of the newest payments of the year up to `asOf`, newest first, each with what its payment adds to
    /// the levies on its day. The receipts of the year are at hand, by day, so only the invoices of the newest ones are
    /// read; an income adjustment is not a payment of an invoice, and an invoice deleted meanwhile is left out.
    private func latestReceipts(
        of input: YearInput, asOf: CivilDate, in database: Database
    ) async throws -> [(invoice: Invoice, effect: ReceiptEffect)] {
        var latest: [(invoice: Invoice, effect: ReceiptEffect)] = []
        for receipt in input.receipts.reversed() where receipt.day <= asOf {
            guard latest.count < OverviewBuilder.latestReceiptCount else { break }
            guard case .invoice(let id) = receipt.source, let invoice = try await database.invoice(id: id) else {
                continue
            }
            let effect = TaxEngine.effect(of: receipt, in: input)
            latest.append((invoice: invoice, effect: effect))
        }
        return latest
    }
}
