import Foundation
import Observation

/// The model of the menu of the rate capsule (`RateCapsule`): how the year shown converts its income in other
/// currencies, with the levies of the year with each conversion, and the choice between the daily ČNB rates and the
/// uniform rate of the year (`RateMenuBuilder`).
///
/// The menu is made when it opens. It shows at once what the window has read of the year (`AppModel.shownYearFX`), then
/// reads the year itself with the levies of each conversion (`AppModel.levyComparison(year:)`), which are worked out
/// whenever the menu opens and never stored, and again whenever what they depend on changes while it is open. A choice
/// is made by the app (`AppModel.setFXMethod(_:year:)`), which converts the payments of the year again; the menu stays
/// open, saying what went wrong, when it could not be saved or the payments could not be converted.
@MainActor
@Observable
final class RateMenuModel {
    /// What the menu says under its heading when how the year converts its income cannot be read.
    nonisolated static let loadFailureText = "Přepočet cizích měn se nepodařilo načíst."

    /// The year the menu is about: the year shown, as the last load found it.
    private(set) var year: Int

    /// The heading, the choices and the note, or nil until the year has been read (the window had not read it yet
    /// when the menu opened) and after a load that failed.
    private(set) var content: RateMenuContent?

    /// What the menu says in place of its choices when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// What the menu says under its choices when the last choice could not be saved, or its payments could not be
    /// converted again, otherwise nil.
    private(set) var choiceFailure: String?

    /// Whether a choice made in the menu is being stored and the payments of the year converted: the choices of the
    /// menu wait for it.
    private(set) var isChoosing = false

    private let app: AppModel

    /// How many loads have started. Only the latest one may show its result.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
        year = app.asOf.year
        if let known = app.shownYearFX, known.year == year {
            content = RateMenuBuilder.content(state: known, comparison: nil)
        }
    }

    /// "Cizí měny v roce 2025": the heading of the menu, also while it has no choices to show.
    var heading: String {
        content?.heading ?? RateMenuBuilder.heading(year: year)
    }

    /// Reads how the year shown converts its income in other currencies, and the levies of the year with each
    /// conversion. Levies that cannot be worked out are left out, and the failure is logged; a year that cannot be read
    /// shows `errorText` in place of the choices.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        let shownYear = app.asOf.year
        let state: YearFXState
        do {
            state = try await app.fxState(year: shownYear)
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Reading the conversion of the year for its menu", failedWith: error)
            year = shownYear
            content = nil
            errorText = Self.loadFailureText
            return
        }
        var comparison: (daily: Int64, uniform: Int64)?
        do {
            comparison = try await app.levyComparison(year: shownYear)
        } catch {
            AppModel.log("Comparing the levies of the conversions of a year", failedWith: error)
        }
        guard thisLoad == loadsStarted else { return }
        year = shownYear
        content = RateMenuBuilder.content(state: state, comparison: comparison)
        errorText = nil
    }

    /// Chooses `method` for the year of the menu, and returns whether the menu may close: it stays open, with
    /// `choiceFailure`, when the choice could not be saved or the payments of the year could not be converted again.
    ///
    /// A stored choice has the year shown read again (`AppModel.loadShownYearFX()`) before the menu closes, so that the
    /// capsule names the method at once, whether or not the window's own read after the write has run by then. A
    /// diagnostic test that changed the year while the popover was still closing saw the window not start its read of
    /// the new year in about half of its runs; this read does not depend on that.
    func choose(_ method: IncomeFXMethod) async -> Bool {
        isChoosing = true
        defer { isChoosing = false }
        let change = await app.setFXMethod(method, year: year)
        if change.isStored {
            await app.loadShownYearFX()
        }
        choiceFailure = change.failureText
        return choiceFailure == nil
    }
}
