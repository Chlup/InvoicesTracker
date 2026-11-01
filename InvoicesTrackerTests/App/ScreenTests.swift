import Foundation
import Testing
@testable import InvoicesTracker

/// The screens of the window: their names in the sidebar and the title and the line under it at the top of each.
struct ScreenTests {
    private let today = civilDate("2026-10-30")

    @Test func theSidebarNamesTheScreens() {
        #expect(
            Screen.allCases.map(\.title) == [
                "Přehled", "Faktury", "Zálohy a odpočty", "Výpočet", "Odhad odvodů", "Odběratelé", "Simulátor",
                "Nastavení", "Import",
            ])
    }

    /// The templates have no page of their own: a client's templates are kept in the detail of Odběratelé, so there is
    /// no screen for them, in the sidebar or anywhere else.
    @Test func thereIsNoScreenForTheTemplates() {
        #expect(!Screen.allCases.map(\.rawValue).contains("templates"))
        #expect(!Screen.allCases.map(\.title).contains("Šablony faktur"))
    }

    @Test func eachScreenNamesItsCashCutoffEvenWhenReportingReachesMonthEnd() {
        let headers = Screen.allCases.map {
            $0.header(year: 2026, asOf: civilDate("2026-10-31"), today: today, incomeFX: .cnbDaily)
        }

        #expect(
            headers == [
                ScreenHeader(
                    title: "Přehled", subtitle: "Rok 2026 · příjmy od 1.\u{00A0}1. do 30.\u{00A0}10.\u{00A0}2026"),
                ScreenHeader(
                    title: "Faktury",
                    subtitle:
                        "Rok 2026 · částky bez DPH, v Kč kurzem ČNB ke dni platby, nezaplacené ke dni vystavení"),
                ScreenHeader(
                    title: "Zálohy a odpočty", subtitle: "Rok 2026 · zálohy po měsících, odpočty a slevy na dani"),
                ScreenHeader(
                    title: "Výpočet",
                    subtitle:
                        "Rok 2026 · k 30.\u{00A0}10.\u{00A0}2026 · verze 2026.1 · ověřeno 20.\u{00A0}10.\u{00A0}2026"),
                ScreenHeader(
                    title: "Odhad odvodů",
                    subtitle: "Rok 2026 · odhad příjmů a odvodů za celý rok z faktur do 30.\u{00A0}10.\u{00A0}2026"),
                ScreenHeader(title: "Odběratelé", subtitle: "Výchozí údaje a šablony pro nové faktury"),
                ScreenHeader(title: "Simulátor", subtitle: "Kolik zaplatíte na odvodech při zvoleném příjmu"),
                ScreenHeader(title: "Nastavení", subtitle: "Aplikace, moje údaje, zabezpečení a rok 2026"),
                ScreenHeader(
                    title: "Import faktur",
                    subtitle: "CSV export z Fakturoidu · obvykle jen jednou, při přechodu do aplikace"),
            ])
    }

    /// A past year is shown as of its last day, and a year without rules of its own names the rules it is estimated
    /// with: those of the nearest year that has them. The title is "Výpočet", whichever year is shown.
    @Test func theComputationNamesTheRulesOfItsYear() {
        let past = Screen.computation.header(
            year: 2024, asOf: civilDate("2024-12-31"), today: today, incomeFX: .cnbDaily)
        let estimate = Screen.computation.header(
            year: 2027, asOf: civilDate("2027-01-01"), today: today, incomeFX: .cnbDaily)

        #expect(past.title == "Výpočet")
        #expect(
            past.subtitle
                == "Rok 2024 · k 31.\u{00A0}12.\u{00A0}2024 · verze 2024.1 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        #expect(estimate.title == "Výpočet")
        #expect(
            estimate.subtitle
                == "Rok 2027 · k 1.\u{00A0}1.\u{00A0}2027 · verze 2026.1 · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        #expect(
            Screen.overview.header(year: 2025, asOf: civilDate("2025-12-31"), today: today, incomeFX: .cnbDaily)
                .subtitle == "Rok 2025 · příjmy od 1.\u{00A0}1. do 31.\u{00A0}12.\u{00A0}2025")
    }

    /// Odhad odvodů names the day its estimate is made as of, which is today and never the day of "K datu": a year in
    /// progress is an estimate from the invoices up to today, a year that is over is what it was.
    @Test func thePredictionNamesTodayForAYearInProgressAndTheFactForAPastYear() {
        let inProgress = Screen.prediction.header(
            year: 2026, asOf: civilDate("2026-07-15"), today: today, incomeFX: .cnbDaily)
        let past = Screen.prediction.header(
            year: 2025, asOf: civilDate("2025-12-31"), today: today, incomeFX: .cnbDaily)

        #expect(inProgress.title == "Odhad odvodů")
        #expect(
            inProgress.subtitle
                == "Rok 2026 · odhad příjmů a odvodů za celý rok z faktur do 30.\u{00A0}10.\u{00A0}2026")
        #expect(past.title == "Odhad odvodů")
        #expect(past.subtitle == "Rok 2025 · skutečnost za celý rok")
    }

    /// On the last day of the year the year is over for the prediction, so it says so, though it is the year of today.
    @Test func onTheLastDayOfTheYearThePredictionSaysFact() {
        let lastDay = civilDate("2026-12-31")

        let header = Screen.prediction.header(year: 2026, asOf: lastDay, today: lastDay, incomeFX: .cnbDaily)
        let dayBefore = Screen.prediction.header(
            year: 2026, asOf: lastDay, today: civilDate("2026-12-30"), incomeFX: .cnbDaily)

        #expect(header.subtitle == "Rok 2026 · skutečnost za celý rok")
        #expect(
            dayBefore.subtitle
                == "Rok 2026 · odhad příjmů a odvodů za celý rok z faktur do 30.\u{00A0}12.\u{00A0}2026")
    }

    /// The line under the title of Faktury names how the year converts its income in other currencies: the method it
    /// uses, which is the uniform rate only while the year has it. With the daily rates it says too that an invoice
    /// that is not paid yet is converted as of the day it was issued.
    @Test func fakturyNamesTheConversionTheYearUses() {
        #expect(
            Screen.invoices.header(year: 2026, asOf: today, today: today, incomeFX: .cnbDaily).subtitle
                == "Rok 2026 · částky bez DPH, v Kč kurzem ČNB ke dni platby, nezaplacené ke dni vystavení")
        #expect(
            Screen.invoices.header(year: 2026, asOf: today, today: today, incomeFX: .uniform).subtitle
                == "Rok 2026 · částky bez DPH, v Kč jednotným kurzem")
        #expect(
            Screen.invoices.header(year: 2025, asOf: civilDate("2025-12-31"), today: today, incomeFX: .uniform).subtitle
                == "Rok 2025 · částky bez DPH, v Kč jednotným kurzem")
        // The other screens do not depend on it.
        for screen in Screen.allCases where screen != .invoices {
            #expect(
                screen.header(year: 2025, asOf: civilDate("2025-12-31"), today: today, incomeFX: .uniform)
                    == screen.header(year: 2025, asOf: civilDate("2025-12-31"), today: today, incomeFX: .cnbDaily))
        }
    }

    /// The lines under the titles of Odběratelé and Simulátor say what the screen is for and do not depend on the year.
    @Test func theLinesUnderOdberateleAndSimulatorAreTheSameInEveryYear() {
        for year in [2024, 2026, 2027] {
            let asOf = civilDate("\(year)-12-31")
            #expect(
                Screen.clients.header(year: year, asOf: asOf, today: today, incomeFX: .cnbDaily).subtitle
                    == "Výchozí údaje a šablony pro nové faktury")
            #expect(
                Screen.simulator.header(year: year, asOf: asOf, today: today, incomeFX: .cnbDaily).subtitle
                    == "Kolik zaplatíte na odvodech při zvoleném příjmu")
        }
    }
}
