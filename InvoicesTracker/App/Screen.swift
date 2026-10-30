import Foundation

/// A screen of the window: an item of the sidebar.
nonisolated enum Screen: String, CaseIterable, Hashable, Sendable {
    case overview
    case invoices
    case advances
    case computation
    case prediction
    case clients
    case templates
    case simulator
    case settings
    case importer

    /// The name of the screen in the sidebar.
    var title: String {
        switch self {
        case .overview: "Přehled"
        case .invoices: "Faktury"
        case .advances: "Zálohy a odpočty"
        case .computation: "Výpočet"
        case .prediction: "Odhad odvodů"
        case .clients: "Odběratelé"
        case .templates: "Šablony faktur"
        case .simulator: "Simulátor"
        case .settings: "Nastavení"
        case .importer: "Import"
        }
    }

    /// Whether the screen shows the green banner of its actions itself, under its tabs, rather than the window above
    /// it: Nastavení, whose banner belongs to a tab.
    var showsItsOwnBanner: Bool {
        self == .settings
    }

    /// The title and the line under it at the top of the screen, when it shows `year` with the reporting cutoff `asOf`
    /// and the year converts its income in other currencies by `incomeFX` (`YearFXState.effective`), which Faktury
    /// names. `today` is the day Odhad odvodů makes its estimate as of: it names it, whatever `asOf` is. The money
    /// of the current year is received up to `today` even though the cutoff reaches the end of the month, so the lines
    /// that name the day of the income name `min(asOf, today)` there.
    func header(year: Int, asOf: CivilDate, today: CivilDate, incomeFX: IncomeFXMethod) -> ScreenHeader {
        let ofYear = "Rok \(year) · "
        let received = asOf.year == today.year ? min(asOf, today) : asOf
        switch self {
        case .overview:
            return ScreenHeader(
                title: "Přehled", subtitle: ofYear + "příjmy od 1.\u{00A0}1. do " + CzechFormat.date(received))
        case .invoices:
            let conversion = incomeFX == .uniform ? "platby roku \(year) jednotným kurzem" : "kurzem ČNB ke dni platby"
            return ScreenHeader(
                title: "Faktury",
                subtitle: ofYear + "bez DPH a v Kč (" + conversion + ") · čistý příjem po dani a pojistném")
        case .advances:
            return ScreenHeader(
                title: "Zálohy a odpočty", subtitle: ofYear + "zálohy po měsících, odpočty a slevy na dani")
        case .computation:
            return ScreenHeader(
                title: "Rozpis výpočtu",
                subtitle: ofYear + "k " + CzechFormat.date(received) + " · " + Self.rulesText(year: year))
        case .prediction:
            // A year is over for the prediction from its last day on: then nothing is estimated any more.
            let isOver = PredictionInput.isClosed(year: year, today: today)
            let line =
                isOver
                ? "skutečnost za celý rok"
                : "odhad příjmů, daně a pojistného za celý rok z faktur do " + CzechFormat.date(today)
            return ScreenHeader(title: "Odhad odvodů", subtitle: ofYear + line)
        case .clients:
            return ScreenHeader(title: "Odběratelé", subtitle: "Výchozí měna, DPH, platba a splatnost pro nové faktury")
        case .templates:
            return ScreenHeader(title: "Šablony faktur", subtitle: "Opakované faktury jedním klikem")
        case .simulator:
            return ScreenHeader(title: "Simulátor", subtitle: "Kolik zaplatíte na dani a pojistném při zvoleném příjmu")
        case .settings:
            return ScreenHeader(title: "Nastavení", subtitle: "Aplikace, moje údaje, zabezpečení a rok \(year)")
        case .importer:
            return ScreenHeader(
                title: "Import faktur",
                subtitle: "CSV export z Fakturoidu · obvykle jen jednou, při přechodu do aplikace")
        }
    }

    /// "verze 2026.1 · ověřeno 20. 10. 2026": the rules `year` is computed with — its own, or those of the nearest year
    /// that has rules — and when they were checked. Výpočet and Nastavení › Rok name them so.
    static func rulesText(year: Int) -> String {
        let rules = TaxRules.forYear(year).rules
        return "verze \(rules.year).1 · " + rules.verification
    }
}

/// The title of a screen and the line under it, at the top of the window.
nonisolated struct ScreenHeader: Hashable, Sendable {
    var title: String
    var subtitle: String
}
