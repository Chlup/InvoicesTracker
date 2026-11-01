import Foundation
import Observation

/// The model of Odhad odvodů: loads the prediction of the selected year and turns it into the page of the screen
/// (`PredictionBuilder`), and writes the person's choices of the months an invoice is expected in.
///
/// The prediction is made from today's data, whatever the reporting cutoff is: the model follows the selected year and
/// nothing else of it (`AppModel.predictionOutcome(year:)`). The screen loads again whenever what the data depends on
/// changes (`AppModel.reloadKey`). The model keeps the page of the last load until the next one has finished, so that
/// the screen does not flash empty; a load that fails shows a line in its place.
///
/// Two warnings stand above the page, and are loaded and dropped with it: that the levies of the year are an estimate
/// with the rules of another year (`rulesWarning`), and that part of the income up to the day of the prediction is
/// converted at a provisional rate (`provisionalNotice`). While the page has the second, the banner of a year that is
/// over no longer says that nothing is estimated.
///
/// A tap on a month switches it on or off. Only what differs from the app's own choice is stored, so a month taken
/// back to what the app chooses leaves no row; "Vrátit odhad aplikace" clears the rows of a client. A change is written
/// for the year of the page that was tapped, then the app is told and the page is loaded again. A tap or a reset that
/// comes meanwhile is ignored: it would work from the page of before the change.
@MainActor
@Observable
final class PredictionModel {
    /// What the screen says in place of the page when the year cannot be loaded.
    static let loadFailureText = "Odhad odvodů se nepodařilo načíst."

    /// What the screen says when the last change could not be saved.
    static let saveFailureText = "Změnu se nepodařilo uložit."

    /// What the screen shows: nil until the first load has finished, and after a load that failed.
    private(set) var page: PredictionPage?

    /// The warning that the levies of the year are an estimate with the rules of another year, or nil when they are
    /// not. It goes with `page`: nil until the first load has finished, and after a load that failed.
    private(set) var rulesWarning: String?

    /// The line that part of the income of the year up to the day of the prediction is converted at a provisional rate,
    /// or nil when none of it is. It goes with `page`: nil until the first load has finished, and after a load that
    /// failed.
    private(set) var provisionalNotice: String?

    /// What the screen says in place of the page when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// What the screen says when the last change of a month could not be saved, otherwise nil.
    private(set) var saveFailure: String?

    private let app: AppModel

    /// The prediction the page was made from, which has the app's own choice of each month.
    @ObservationIgnored private var prediction: IncomePrediction?

    /// How many loads have started. Only the latest one may show its result: a load that was started for a year that
    /// has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    /// Whether a change of the months is being written: from the start of its write until the page is loaded again
    /// after it.
    @ObservationIgnored private var isWriting = false

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading

    /// Loads the prediction of the selected year and makes the page of it, with the warnings that go with it. A failure
    /// is logged (the domain and the code of the error alone) and shows `errorText` in place of the page and its
    /// warnings. Cancellation preserves the prior page, warnings and error without publishing this load.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        // The year as it is when the load starts, however it changes meanwhile (a change starts a load of its own).
        let year = app.asOf.year
        do {
            guard let database = app.database else { throw VaultError.locked }
            let outcome = try await app.predictionOutcome(year: year)
            // The payments the page counts as received are those up to the day it is made as of, not those up to the
            // reporting cutoff.
            let isProvisional = try await database.hasProvisionalReceipt(year: year, through: outcome.prediction.now)
            guard thisLoad == loadsStarted, !Task.isCancelled else { return }
            prediction = outcome.prediction
            page = PredictionBuilder.page(outcome, hasProvisionalIncome: isProvisional)
            rulesWarning =
                outcome.result.rulesAreEstimate
                ? RulesWarning.message(year: outcome.result.year, rulesYear: outcome.result.rules.year) : nil
            provisionalNotice = isProvisional ? RulesWarning.provisionalIncome : nil
            errorText = nil
        } catch is CancellationError {
            return
        } catch {
            guard thisLoad == loadsStarted, !Task.isCancelled else { return }
            AppModel.log("Loading Předpověď", failedWith: error)
            prediction = nil
            page = nil
            rulesWarning = nil
            provisionalNotice = nil
            errorText = Self.loadFailureText
        }
    }

    // MARK: Changing the months

    /// Switches the invoice expected in `month` (1 to 12) of the client with `clientID` on if it is off, or off if it
    /// is on. The new choice is stored when it differs from the app's own, otherwise the stored choice of the month is
    /// deleted. Does nothing for a client the page does not have or whose months cannot be chosen, for a month that is
    /// over or has an issued invoice, while there is no page, and while another change is being written.
    func toggle(clientID: Int64, month: Int) async {
        guard let prediction, let client = prediction.clients.first(where: { $0.id == clientID }),
            client.allowsChoices, let shown = client.months.first(where: { $0.month == month }), shown.kind.isOpen
        else { return }
        let expected = !shown.isOn
        await write { database in
            try await database.setExpectedInvoiceMonth(
                year: prediction.year, clientID: clientID, month: month,
                expected: expected == shown.isAutomatic ? nil : expected)
        }
    }

    /// Takes every month of the client with `clientID` back to the app's own choice. Does nothing for a client the page
    /// does not have or whose months cannot be chosen, while there is no page, and while another change is being
    /// written.
    func reset(clientID: Int64) async {
        guard let prediction, prediction.clients.contains(where: { $0.id == clientID && $0.allowsChoices }) else {
            return
        }
        await write { database in
            try await database.clearExpectedInvoiceMonths(year: prediction.year, clientID: clientID)
        }
    }

    /// Writes with `change`, then tells the app, which loads the screens again, and loads the page. A change that
    /// cannot be saved is logged and said in `saveFailure`, and the page stays as it was. Does nothing while another
    /// change is being written.
    private func write(_ change: (Database) async throws -> Void) async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        saveFailure = nil
        do {
            guard let database = app.database else { throw VaultError.locked }
            try await change(database)
        } catch {
            AppModel.log("Saving the months of Předpověď", failedWith: error)
            saveFailure = Self.saveFailureText
            return
        }
        await app.didWrite()
        await load()
    }
}
