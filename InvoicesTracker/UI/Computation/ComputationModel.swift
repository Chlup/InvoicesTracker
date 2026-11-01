import Foundation
import Observation

/// The model of Výpočet: loads the selected year as of the reporting cutoff (`asOf`), computes it with the validated
/// computation and turns the result into the page of the screen (`ComputationBuilder`): the cards between the result
/// and the banner, the banner and the sections of the breakdown.
///
/// The screen loads again whenever what the data depends on changes (`AppModel.reloadKey`). The model keeps the page
/// of the last load until the next one has finished, so that the screen does not flash empty; a load that fails shows a
/// line in its place.
@MainActor
@Observable
final class ComputationModel {
    /// What the screen says in place of the page when the year cannot be loaded or computed.
    static let loadFailureText = "Výpočet se nepodařilo načíst."

    /// What the screen shows: nil until the first load has finished, and after a load that failed.
    private(set) var page: ComputationPage?

    /// The sections of the breakdown: empty until the first load has finished, and after a load that failed.
    var sections: [ComputationSection] {
        page?.sections ?? []
    }

    /// The warning that the levies of the year are an estimate with the rules of another year, or nil when they are
    /// not.
    private(set) var warning: String?

    /// The line that part of the income of the year up to the day shown is converted at a provisional rate, or nil
    /// when none of it is.
    private(set) var provisionalNotice: String?

    /// What the screen says in place of the page when the last load failed, otherwise nil.
    private(set) var errorText: String?

    private let app: AppModel

    /// How many loads have started. Only the latest one may show its result: a load that was started for a year or a
    /// day that has been replaced since must not undo the newer one.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Loading

    /// Loads the selected year as of the day shown. A failure is logged (the domain and the code of the error alone)
    /// and shows `errorText` in place of the page.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        do {
            let loaded = try await assemble()
            guard thisLoad == loadsStarted else { return }
            page = loaded.page
            warning = loaded.warning
            provisionalNotice = loaded.provisionalNotice
            errorText = nil
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading Výpočet", failedWith: error)
            page = nil
            warning = nil
            provisionalNotice = nil
            errorText = Self.loadFailureText
        }
    }

    private struct Loaded {
        var page: ComputationPage
        var warning: String?
        var provisionalNotice: String?
    }

    private func assemble() async throws -> Loaded {
        guard let database = app.database else { throw VaultError.locked }
        // The year, the day and today as they are when the load starts: all of it is about them, however they change
        // meanwhile (a change starts a load of its own).
        let shown = app.asOf
        let day = app.receivedThrough
        let today = app.today
        // The input is kept for the builder, so the year is read once and the computation is the validated one. The
        // money counts up to the day it is received by, not up to the end of the month the cutoff reaches.
        let input = try await app.yearInput(for: shown.year).input
        let result = try AppModel.compute(input, asOf: day)
        let isProvisional = try await database.hasProvisionalReceipt(year: shown.year, through: day)
        // The texts name the conversion the year uses, and where its uniform rate is from: the rates of dollars and
        // euros, which Nastavení › Rok shows.
        let conversion = try await app.fxState(year: shown.year)
        let rates = try await database.uniformRates(year: shown.year)
        let source = BuilderText.uniformSource(of: YearTabModel.dollarAndEuroRates(rates))
        let warning =
            result.rulesAreEstimate
            ? RulesWarning.message(year: result.year, rulesYear: result.rules.year) : nil
        return Loaded(
            page: ComputationBuilder.buildPage(
                result, input: input, today: today, incomeFXMethod: conversion.effective, uniformSource: source),
            warning: warning, provisionalNotice: isProvisional ? RulesWarning.provisionalIncome : nil)
    }
}
