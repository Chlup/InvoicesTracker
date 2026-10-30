import Foundation
import Observation

/// What the refresh has to say in Nastavení › Aplikace: how current the ČNB rates are, where the uniform rate stands,
/// and what went wrong last. `RefreshCoordinator` keeps it up to date after every run.
@MainActor
@Observable
final class RefreshStatus {
    /// The newest day the cache has ČNB rates of, or nil when it has none.
    var cnbUpToDate: CivilDate?

    /// When the latest download that brought newer ČNB rates ended, as the refresh keeps it in its state, so that it
    /// is known after a relaunch too. Nil when there was none.
    var cnbFetchedAt: Date?

    /// What went wrong in the latest runs, in Czech, or nil when nothing did.
    var lastError: String?

    /// The year `uniformText` is about: the finished year while it has no stored rate (looked for, or given up on after
    /// 31 March), otherwise the current year. Nil until the first run.
    var uniformYear: Int?

    /// The line of the uniform rate, such as "Jednotný kurz 2026: zatím nevyšel (kontrola od 2. 1. 2027)". Empty until
    /// the first run.
    var uniformText: String

    /// The time zone in which the time of a download is shown: the time zone of the Mac, as of the latest run.
    var timeZone: TimeZone

    init(timeZone: TimeZone = .autoupdatingCurrent) {
        self.timeZone = timeZone
        uniformText = ""
    }

    /// The line of the ČNB rates, such as "Kurzy ČNB: aktuální k 17. 10. 2026 (staženo 14:36)". Without a known
    /// download it has no time, and without any rates it says that none have been downloaded.
    var cnbText: String {
        Self.cnbText(upToDate: cnbUpToDate, fetchedAt: cnbFetchedAt, timeZone: timeZone)
    }

    // MARK: Texts

    nonisolated static func cnbText(upToDate: CivilDate?, fetchedAt: Date?, timeZone: TimeZone) -> String {
        guard let upToDate else { return "Kurzy ČNB: zatím nestaženy" }
        let text = "Kurzy ČNB: aktuální k " + CzechFormat.date(upToDate)
        guard let fetchedAt else { return text }
        return text + " (staženo " + time(fetchedAt, in: timeZone) + ")"
    }

    /// The uniform rate of `year` is not out yet, and the app looks for it from 2 January of the next year
    /// (`UniformRateSearch`).
    nonisolated static func uniformNotOutText(year: Int) -> String {
        let firstCheck = UniformRateSearch.firstDay(of: year).map { CzechFormat.date($0) } ?? ""
        return "Jednotný kurz \(year): zatím nevyšel (kontrola od \(firstCheck))"
    }

    /// The uniform rate of `year` was found and waits for the person to confirm it.
    nonisolated static func uniformFoundText(year: Int, instruction: String) -> String {
        "Jednotný kurz \(year): vyšel (pokyn \(instruction)), čeká na potvrzení"
    }

    /// The uniform rate of `year` was not found by 31 March of the next year, and none is stored: it has to be entered
    /// by hand.
    nonisolated static func uniformNotFoundText(year: Int) -> String {
        "Jednotný kurz \(year): nenalezen, zadejte ho ručně v Nastavení › Rok"
    }

    /// The page or the PDF at `url` of the Finanční zpravodaj that should have the uniform rate of `year` cannot be
    /// read. The person can open it and enter the rate by hand.
    nonisolated static func uniformUnreadableText(year: Int, url: URL) -> String {
        "Jednotný kurz \(year): Finanční zpravodaj se nepodařilo přečíst (\(url.absoluteString))"
    }

    /// `14:36`, `9:05`: the hour without a leading zero and the minutes with one, in `timeZone`.
    private nonisolated static func time(_ instant: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        let minute = parts.minute ?? 0
        return "\(parts.hour ?? 0):" + (minute < 10 ? "0" : "") + "\(minute)"
    }
}
