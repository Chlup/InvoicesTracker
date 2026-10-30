import Foundation

/// A row of the card Kurzy: what it is about, its state, and a line under them.
nonisolated struct RateStatusRow: Hashable, Sendable {
    /// How the state is shown.
    enum Tone: Hashable, Sendable {
        /// Up to date: green.
        case current

        /// A fact, such as the rates of a year: in the colour of the text.
        case plain

        /// Nothing yet, and nothing to do: in the secondary colour.
        case quiet

        /// Something is behind or needs the person: orange.
        case warning
    }

    /// What the row offers to do.
    enum Action: Hashable, Sendable {
        /// Zobrazit: the sheet that asks to confirm the rates that were found, shown again after it was put off.
        case showFinding
    }

    var label: String
    var value: String
    var detail: String
    var tone: Tone

    /// What the row offers, or nil.
    var action: Action?
}

/// Where the search for the uniform rate of the finished year stands while none is stored.
nonisolated enum UniformSearchState: Hashable, Sendable {
    /// Not out yet, or not looked for yet: the app looks for it from 2 January.
    case notOut

    /// Found, and waiting for the person to confirm it.
    case waitingForConfirmation(instruction: String)

    /// The page or the PDF of the Finanční zpravodaj could not be read.
    case unreadable

    /// Not found by 31 March: it has to be entered by hand.
    case gaveUp
}

/// What the rows of the card Kurzy are made from.
nonisolated struct RatesStatusFacts: Sendable {
    var now: Date

    /// The time zone of the Mac, in which the time of a download is said.
    var timeZone: TimeZone

    /// The year of today in the time zone of the Mac.
    var currentYear: Int

    /// The newest day the cache has ČNB rates of, and when the latest download that brought newer rates ended.
    var newestDeclaration: CivilDate?
    var lastDownload: Date?

    /// The uniform rates stored for the year before the current one, and for the current one.
    var finishedYearRates: [UniformRate]
    var currentYearRates: [UniformRate]

    /// Where the search for the rate of the finished year stands, while none is stored.
    var finishedYearSearch: UniformSearchState
}

/// The rows of the card Kurzy of Nastavení › Aplikace: how current the ČNB rates are and when the next ones come out,
/// the uniform rate of the finished year with its instruction, and that of the current year, which comes out in
/// January of the next one, with what the app does about it. Every day and time is in Czech; the ČNB declares its
/// rates after 14:30 Prague time.
nonisolated enum RatesStatus {
    static func rows(_ facts: RatesStatusFacts) -> [RateStatusRow] {
        [
            cnbRow(facts),
            uniformRow(
                year: facts.currentYear - 1, rates: facts.finishedYearRates, search: facts.finishedYearSearch,
                facts: facts),
            uniformRow(year: facts.currentYear, rates: facts.currentYearRates, search: .notOut, facts: facts),
        ]
    }

    /// What the banner says after Zkontrolovat teď: "Kurzy ČNB jsou aktuální k 16. 10. 2026. Další vyjdou v pondělí
    /// 19. 10. po 14:30."
    static func checkedText(newest: CivilDate, now: Date) -> String {
        "Kurzy ČNB jsou aktuální k \(CzechFormat.date(newest)). Další vyjdou \(nextDeclaration(now: now)) po 14:30."
    }

    // MARK: ČNB

    private static func cnbRow(_ facts: RatesStatusFacts) -> RateStatusRow {
        var details: [String] = []
        if let download = facts.lastDownload {
            let day = CivilDate.today(now: download, timeZone: facts.timeZone)
            let today = CivilDate.today(now: facts.now, timeZone: facts.timeZone)
            let dayText =
                day == today
                ? "dnes" : SettingsTexts.weekdayWithPreposition(day) + " " + CzechFormat.dayMonth(day)
            details.append("staženo \(dayText) " + SettingsTexts.atClockTime(download, timeZone: facts.timeZone))
        }
        details.append("další vyjdou \(nextDeclaration(now: facts.now)) po 14:30")
        let detail = details.joined(separator: " · ")
        guard let newest = facts.newestDeclaration else {
            return RateStatusRow(label: "Kurzy ČNB", value: "zatím nestaženy", detail: detail, tone: .warning)
        }
        let isCurrent = newest >= RefreshPlanner.expectedNewestDeclaration(now: facts.now)
        return RateStatusRow(
            label: "Kurzy ČNB", value: "aktuální k " + CzechFormat.date(newest), detail: detail,
            tone: isCurrent ? .current : .warning)
    }

    /// "v pondělí 19. 10.", or "dnes" when the ČNB declares the next rates later today: the business day after the
    /// latest declaration that should be out by `now`.
    private static func nextDeclaration(now: Date) -> String {
        let latest = RefreshPlanner.expectedNewestDeclaration(now: now)
        let next = CzechCalendar.nextBusinessDay(onOrAfter: latest.adding(days: 1))
        if next == CzechCalendar.pragueDate(now) {
            return "dnes"
        }
        return SettingsTexts.weekdayWithPreposition(next) + " " + CzechFormat.dayMonth(next)
    }

    // MARK: Uniform rates

    /// The row of the uniform rate of `year`: the rates of dollars and euros with where they are from, or what the app
    /// does while there are none. While nothing came of the search (`UniformSearchState.notOut`), the row follows where
    /// the search of the app for the rate stands on the day of the Mac (`UniformRateSearch`), as the card of
    /// Nastavení › Rok and the toolbar do: before it starts it names its first day, while it runs it says the app looks
    /// for the rate, and once it is over the rate was not found and is entered by hand.
    private static func uniformRow(
        year: Int, rates: [UniformRate], search: UniformSearchState, facts: RatesStatusFacts
    ) -> RateStatusRow {
        let label = "Jednotný kurz \(year)"
        let shown = YearTabModel.dollarAndEuroRates(rates)
        guard shown.isEmpty else {
            return RateStatusRow(
                label: label, value: shown.map(BuilderText.uniformRate).joined(separator: " · "),
                detail: uniformSource(of: shown, year: year), tone: .plain)
        }
        let notFound = RateStatusRow(
            label: label, value: "nenalezen",
            detail: "Do \(day(UniformRateSearch.lastDay(of: year))) se ho najít nepodařilo – zadejte ho ručně na kartě"
                + " Rok \(year).",
            tone: .warning)
        switch search {
        case .waitingForConfirmation(let instruction):
            return RateStatusRow(
                label: label, value: "vyšel, čeká na potvrzení", detail: "pokyn \(instruction) · čeká, až ho potvrdíte",
                tone: .warning, action: .showFinding)
        case .unreadable:
            return RateStatusRow(
                label: label, value: "nepodařilo se ho přečíst",
                detail: "Finanční zpravodaj se nepodařilo přečíst – kurz zadejte ručně na kartě Rok \(year).",
                tone: .warning)
        case .gaveUp:
            return notFound
        case .notOut:
            let today = CivilDate.today(now: facts.now, timeZone: facts.timeZone)
            let detail: String
            switch UniformRateSearch(year: year, today: today) {
            case .notStarted:
                detail =
                    "GFŘ ho vydá v lednu \(year + 1). Aplikace ho od \(day(UniformRateSearch.firstDay(of: year)))"
                    + " jednou denně hledá a dá vám ho potvrdit."
            case .looking:
                detail = "GFŘ ho vydává v lednu. Aplikace ho jednou denně hledá a dá vám ho potvrdit."
            case .over:
                return notFound
            }
            return RateStatusRow(label: label, value: "zatím nevyšel", detail: detail, tone: .quiet)
        }
    }

    /// "2. 1. 2027": a day of the search, or nothing for a year at the end of the calendar.
    private static func day(_ day: CivilDate?) -> String {
        day.map { CzechFormat.date($0) } ?? ""
    }

    /// Where the rates of `year` that the row shows, `shown`, are from (`BuilderText.uniformSource(of:)`), and for
    /// rates entered by hand what they mean for the official rate: they replace the table that ships with the app for
    /// its years, and for another year the app does not look for the official rate while they are stored.
    private static func uniformSource(of shown: [UniformRate], year: Int) -> String {
        let source = BuilderText.uniformSource(of: shown) ?? ""
        guard shown.contains(where: { $0.origin == .manual }) else { return source }
        let official =
            BuiltInUniformRates.uniformRates(year: year).isEmpty
            ? "oficiální kurz aplikace nehledá, dokud ručně zadaný neodstraníte"
            : "nahrazuje kurz, který má aplikace od vydání"
        return source + " · " + official
    }
}
