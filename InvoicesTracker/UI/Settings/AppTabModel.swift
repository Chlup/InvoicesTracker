import Foundation
import Observation

// MARK: - Licences

/// A third-party part of the app whose licence the app shows: its name, what it is for and under which licence, and
/// the text of the licence, bundled with the app.
nonisolated struct Licence: Identifiable, Hashable, Sendable {
    var name: String
    var detail: String

    /// The name of the text file in the bundle, without its extension.
    var fileName: String

    var id: String {
        fileName
    }

    /// The text of the licence, or nil when the file is not in the bundle or cannot be read, which is logged.
    func text() -> String? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "txt") else {
            AppModel.log("Finding a licence", failedWith: CocoaError(.fileNoSuchFile))
            return nil
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            AppModel.log("Reading a licence", failedWith: error)
            return nil
        }
    }
}

// MARK: - The model

/// The model of Nastavení › Aplikace: the appearance, the rows of the rates with Zkontrolovat teď, and the licences.
///
/// The rows are loaded from the data — the newest cached ČNB rates, the stored uniform rates of the finished and the
/// current year and the state of the refresh — whenever the screen loads again, and the last error of the refresh is
/// read live from its status.
@MainActor
@Observable
final class AppTabModel {
    /// The licences shown, with their texts bundled with the app.
    nonisolated static let licences = [
        Licence(name: "IBM Plex Sans", detail: "písmo faktur · SIL Open Font License 1.1", fileName: "IBMPlexSans-OFL"),
        Licence(
            name: "SQLCipher Community Edition", detail: "šifrování databáze · licence BSD",
            fileName: "SQLCipher-LICENSE"),
    ]

    /// What the card says when the rates cannot be loaded.
    nonisolated static let loadFailureText = "Stav kurzů se nepodařilo načíst."

    /// The rows of the card Kurzy: empty until the first load.
    private(set) var rateRows: [RateStatusRow] = []

    /// What the card says in place of the rows when the last load failed, otherwise nil.
    private(set) var errorText: String?

    /// Whether Zkontrolovat teď runs.
    private(set) var isChecking = false

    private let app: AppModel

    /// How many loads have started. Only the latest may show its result.
    @ObservationIgnored private var loadsStarted = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Vzhled

    var appearance: Appearance {
        app.appSettings.appearance
    }

    /// The appearance of the app, saved at once.
    func setAppearance(_ appearance: Appearance) async {
        await app.updateAppSettings { $0.appearance = appearance }
    }

    /// What the card says of `appearance`.
    nonisolated static func appearanceNote(_ appearance: Appearance) -> String {
        switch appearance {
        case .system: "Aplikace se řídí vzhledem macOS a přepne se spolu se systémem."
        case .light: "Aplikace zůstane světlá, i když má systém tmavý vzhled."
        case .dark: "Aplikace bude tmavá, i když má systém světlý vzhled."
        }
    }

    /// The name of `appearance` under its picture.
    nonisolated static func appearanceName(_ appearance: Appearance) -> String {
        switch appearance {
        case .system: "Podle systému"
        case .light: "Světlý"
        case .dark: "Tmavý"
        }
    }

    // MARK: Kurzy

    /// What went wrong in the latest runs of the refresh, in Czech, or nil.
    var lastError: String? {
        app.refresh?.status.lastError
    }

    /// Loads the facts of the rows. A failure is logged and shows `errorText`.
    func load() async {
        loadsStarted += 1
        let thisLoad = loadsStarted
        do {
            let facts = try await loadFacts()
            guard thisLoad == loadsStarted else { return }
            rateRows = RatesStatus.rows(facts)
            errorText = nil
        } catch {
            guard thisLoad == loadsStarted else { return }
            AppModel.log("Loading the state of the rates", failedWith: error)
            errorText = Self.loadFailureText
        }
    }

    private func loadFacts() async throws -> RatesStatusFacts {
        guard let database = app.database else { throw VaultError.locked }
        let now = app.dependencies.clock.now()
        let timeZone = app.dependencies.timeZone()
        let currentYear = CivilDate.today(now: now, timeZone: timeZone).year
        let state: RefreshState?
        do {
            state = try await database.refreshState()
        } catch {
            // The state is bookkeeping of the refresh, which starts it afresh when it cannot read it.
            AppModel.log("Reading the state of the refresh", failedWith: error)
            state = nil
        }
        let finishedYear = currentYear - 1
        var search = UniformSearchState.notOut
        if let finding = app.pendingUniformRate, finding.year == finishedYear {
            search = .waitingForConfirmation(instruction: finding.instruction)
        } else if state?.gaveUpUniform.contains(finishedYear) == true {
            search = .gaveUp
        } else if state?.unreadableUniformPages[finishedYear] != nil {
            search = .unreadable
        }
        return RatesStatusFacts(
            now: now, timeZone: timeZone, currentYear: currentYear,
            newestDeclaration: try await database.newestCNBDeclaration(), lastDownload: state?.lastCNBDownload,
            finishedYearRates: try await database.uniformRates(year: finishedYear),
            currentYearRates: try await database.uniformRates(year: currentYear), finishedYearSearch: search)
    }

    /// Zobrazit on the row of a rate that was found and waits for the person: the sheet that asks to confirm it comes
    /// again, after it was put off. Does nothing when no finding waits.
    func showPendingFinding() {
        guard let finding = app.pendingUniformRate else { return }
        app.uniformRateOffer = finding
    }

    /// Zkontrolovat teď: a run of the refresh that does not wait out a back-off and looks for a uniform rate that is
    /// due (`RefreshTrigger.manual`), then the rows again and, when the run went well, the banner that says how current
    /// the rates are. When it did not, the card shows what went wrong.
    func checkNow() async {
        guard !isChecking, let refresh = app.refresh else { return }
        isChecking = true
        defer { isChecking = false }
        await refresh.refresh(.manual)
        await load()
        guard refresh.status.lastError == nil, let database = app.database else { return }
        do {
            if let newest = try await database.newestCNBDeclaration() {
                app.showBanner(RatesStatus.checkedText(newest: newest, now: app.dependencies.clock.now()))
            }
        } catch {
            AppModel.log("Reading the cached rates", failedWith: error)
        }
    }

    // MARK: Licence

    /// "InvoicesTracker 1.0 · data jen v tomto Macu".
    nonisolated static func versionLine(_ version: String) -> String {
        "InvoicesTracker \(version) · data jen v tomto Macu"
    }

    /// The line of the version of this app.
    var versionLine: String {
        Self.versionLine(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }
}
