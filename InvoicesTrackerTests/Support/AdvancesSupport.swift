import Foundation
import Testing
@testable import InvoicesTracker

/// The message under a field of whole crowns whose text is not one: it says how a whole amount is written, because the
/// common message of the amounts would invite haléře, which these fields refuse.
let advancesWholeKcMessage = "Zadejte částku v celých korunách, například 13 340."

/// The sizes of the window that the tests of Zálohy a odpočty try besides the least and the large window of the app
/// (`AppWindowSize`).
enum AdvancesWindowSize {
    /// The least window in which the impact panel stands beside the cards instead of under them: 1 150 points wide and
    /// as high as the least window. The page of the app is the window less 272 points (the sidebar of 232 and the
    /// padding of the page, 24 and 16), and the panel stands beside the cards from a page of 876 points, which are the
    /// least width of the cards, 520, the gap of 16 and the panel, 340 (`DetailPanelMetrics.width`). The first round
    /// width that gives it is 1 150 points: a page of 878, the cards 2 points over their least. In the least window,
    /// 1 100 points, the page is 828 and the panel stands under the cards.
    static let impactPanelBeside = CGSize(width: 1_150, height: AppWindowSize.minimum.height)
}

/// An app model on a new folder, as of 17. 10. 2026, with the sample year 2026 stored: the regression plan of advances
/// (13 340 Kč and 6 920 Kč until April, 12 150 Kč and 5 480 Kč after it, 23 000 Kč of income tax in June and December)
/// and its deductions.
@MainActor
func makeAdvancesApp(in directory: URL) async throws -> AppModel {
    let app = makeAppModel(in: directory)
    try await startFresh(app)
    let database = try #require(app.database)
    try await SampleYear2026.store(in: database)
    await app.didWriteAndBackUp()
    return app
}

/// A model of `app` that has loaded, as the screen loads it. It saves `saveDelay` after the last change: at once by
/// default.
@MainActor
func loadedAdvancesModel(of app: AppModel, saveDelay: Duration = .zero) async -> AdvancesModel {
    let model = AdvancesModel(app: app, saveDelay: saveDelay)
    await model.load()
    return model
}

/// The settings of `year` as the data of `app` holds them.
@MainActor
func storedYear(_ year: Int, in app: AppModel) async throws -> YearSettings {
    let database = try #require(app.database)
    return try await database.yearSettings(year)
}

/// Stores `settings` and tells the app, as a screen that wrote them would.
@MainActor
func storeYear(_ settings: YearSettings, in app: AppModel) async throws {
    let database = try #require(app.database)
    try await database.saveYearSettings(settings)
    await app.didWriteAndBackUp()
}

/// The year 2025 with invented advances (9 450 Kč and 4 700 Kč, the income tax in June and December), secondary
/// activity in February to April, and an expense rate and deductions that are not those of 2026.
func advancesYear2025() -> YearSettings {
    var settings = YearSettings(year: 2025)
    settings.expensePercent = 80
    settings.secondaryMonths = [2, 3, 4]
    settings.advances = AdvancePlan(
        social: [Int64](repeating: 9_450, count: 12),
        health: [Int64](repeating: 4_700, count: 12),
        tax: (1...12).map { [6, 12].contains($0) ? Int64(19_000) : Int64(0) })
    settings.deductions = Deductions(mortgageInterestPaid: 228_000, lifeInsurance: 5_000)
    return settings
}

/// Makes every write of `database` fail while its reads go on working, or lets it write again. This is how a save that
/// fails is made without closing the data, which a screen could not load from either.
func setDatabaseReadOnly(_ readOnly: Bool, _ database: Database) async throws {
    try await database.read { connection in
        try connection.run("PRAGMA query_only = \(readOnly ? "ON" : "OFF")")
    }
}
