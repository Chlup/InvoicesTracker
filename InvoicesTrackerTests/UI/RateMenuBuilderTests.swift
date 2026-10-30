import Foundation
import Testing
@testable import InvoicesTracker

/// The rate capsule of the toolbar and its menu, as texts: the capsule names the method the year shown converts its
/// income in other currencies with, and the menu offers the daily ČNB rates and the uniform rate of the year, the
/// uniform rate only when the year has it, with the reason why not otherwise. When both can be chosen and the year has
/// payments in other currencies, each item shows the levies of the year with it and how they differ. A note under the
/// items says what the choice does. In every expected string `\u{00A0}` is the no-break space.
struct RateMenuBuilderTests {
    // MARK: Helpers

    /// The uniform rates of 2025 that ship with the app.
    private let rates2025 = UniformAvailability.ready(
        usd: decimal("21.84"), eur: decimal("24.66"), instruction: "GFŘ-D-75", origin: .builtIn)

    private func state(
        _ year: Int, chosen: IncomeFXMethod = .cnbDaily, effective: IncomeFXMethod = .cnbDaily,
        uniform: UniformAvailability, foreign: Bool = true
    ) -> YearFXState {
        YearFXState(year: year, chosen: chosen, effective: effective, uniform: uniform, hasForeignPayments: foreign)
    }

    private func content(
        of state: YearFXState, comparison: (daily: Int64, uniform: Int64)? = nil
    ) -> RateMenuContent {
        RateMenuBuilder.content(state: state, comparison: comparison)
    }

    // MARK: The items

    @Test func aYearOnTheUniformRateOffersBothAndNamesTheRatesAndTheirInstruction() {
        let menu = content(of: state(2025, chosen: .uniform, effective: .uniform, uniform: rates2025))

        #expect(
            menu
                == RateMenuContent(
                    heading: "Cizí měny v roce 2025",
                    items: [
                        RateMenuItem(
                            method: .cnbDaily, title: "Denní kurz ČNB", detail: "kurz ke dni přijetí každé platby",
                            comparison: nil, isChecked: false, isEnabled: true),
                        RateMenuItem(
                            method: .uniform, title: "Jednotný kurz 2025",
                            detail: "1\u{00A0}USD = 21,84\u{00A0}Kč · 1\u{00A0}EUR = 24,66\u{00A0}Kč · pokyn GFŘ-D-75",
                            comparison: nil, isChecked: true, isEnabled: true),
                    ],
                    footer: "Platí pro všechny platby v cizí měně přijaté v roce 2025 – v Přehledu, Fakturách"
                        + " i Výpočtu. Každý rok si volbu pamatuje zvlášť."))
    }

    @Test func aRateEnteredByHandWithoutAnInstructionSaysSo() {
        let typed = UniformAvailability.ready(usd: decimal("21.9"), eur: nil, instruction: nil, origin: .manual)

        let uniform = content(of: state(2026, uniform: typed)).items[1]

        #expect(uniform.detail == "1\u{00A0}USD = 21,90\u{00A0}Kč · zadáno ručně")
        #expect(uniform.isEnabled)
    }

    /// A rate entered by hand says so also with its instruction, as the other screens say it.
    @Test func aRateEnteredByHandWithAnInstructionSaysSoToo() {
        let typed = UniformAvailability.ready(
            usd: decimal("21.9"), eur: decimal("24.8"), instruction: "GFŘ-D-80", origin: .manual)

        let uniform = content(of: state(2025, uniform: typed)).items[1]

        #expect(
            uniform.detail
                == "1\u{00A0}USD = 21,90\u{00A0}Kč · 1\u{00A0}EUR = 24,80\u{00A0}Kč · pokyn GFŘ-D-80, zadáno ručně")
    }

    @Test func theCurrentYearCannotChooseTheUniformRateYet() {
        let menu = content(of: state(2026, uniform: .notPublishedYet(year: 2026)))

        #expect(menu.heading == "Cizí měny v roce 2026")
        #expect(
            menu.items == [
                RateMenuItem(
                    method: .cnbDaily, title: "Denní kurz ČNB", detail: "kurz ke dni přijetí každé platby",
                    comparison: nil, isChecked: true, isEnabled: true),
                RateMenuItem(
                    method: .uniform, title: "Jednotný kurz 2026",
                    detail: "zatím nevyšel – GFŘ ho zveřejní v lednu 2027", comparison: nil, isChecked: false,
                    isEnabled: false),
            ])
        #expect(
            menu.footer
                == "Rok 2026 se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit, až bude pro rok 2026 známý.")
    }

    /// From 2 January to 31 March the app looks for the rate of the year just over: the January in which the GFŘ
    /// publishes it has come, so the reason says that the app looks for it instead.
    @Test func theYearJustOverSaysTheAppLooksForItsRate() {
        let menu = content(of: state(2025, uniform: .searchedFor(year: 2025)))

        #expect(menu.items[1].detail == "zatím nevyšel – aplikace ho jednou denně hledá")
        #expect(!menu.items[1].isEnabled)
        #expect(
            menu.footer
                == "Rok 2025 se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit, až bude pro rok 2025 známý.")
    }

    @Test func aMissingEuroRateIsNamed() {
        let uniform = content(of: state(2025, uniform: .missingCurrency(.eur))).items[1]

        #expect(uniform.detail == "chybí jednotný kurz EUR – zadáte ho v Nastavení › Rok 2025")
        #expect(!uniform.isEnabled)
    }

    /// Nastavení › Rok takes the rates of dollars and euros only, so a missing rate of any other currency does not
    /// promise that it can be typed there.
    @Test func aMissingRateOfACurrencyThatCannotBeTypedSaysSo() throws {
        let pounds = try #require(CurrencyCode("GBP"))
        let uniform = content(of: state(2025, uniform: .missingCurrency(pounds))).items[1]

        #expect(uniform.detail == "chybí jednotný kurz GBP – ručně ho zadat nelze")
        #expect(!uniform.isEnabled)
        #expect(
            content(of: state(2025, uniform: .missingCurrency(.usd))).items[1].detail
                == "chybí jednotný kurz USD – zadáte ho v Nastavení › Rok 2025")
    }

    @Test func aPastYearWithoutTheRateSaysItIsNotInTheApp() {
        let uniform = content(of: state(2024, uniform: .notInApp(year: 2024))).items[1]

        #expect(uniform.title == "Jednotný kurz 2024")
        #expect(uniform.detail == "v aplikaci není – zadáte ho v Nastavení › Rok 2024")
        #expect(!uniform.isEnabled)
    }

    // MARK: The levies of each method

    @Test func bothMethodsShowTheirLeviesAndTheDifference() {
        let year = state(2025, uniform: rates2025)

        #expect(
            content(of: year, comparison: (daily: 548_037, uniform: 551_100)).items.map(\.comparison) == [
                "odvody 548\u{00A0}037\u{00A0}Kč · o 3\u{00A0}063\u{00A0}Kč méně",
                "odvody 551\u{00A0}100\u{00A0}Kč · o 3\u{00A0}063\u{00A0}Kč více",
            ])
        #expect(
            content(of: year, comparison: (daily: 551_100, uniform: 548_037)).items.map(\.comparison) == [
                "odvody 551\u{00A0}100\u{00A0}Kč · o 3\u{00A0}063\u{00A0}Kč více",
                "odvody 548\u{00A0}037\u{00A0}Kč · o 3\u{00A0}063\u{00A0}Kč méně",
            ])
        #expect(
            content(of: year, comparison: (daily: 551_100, uniform: 551_100)).items.map(\.comparison) == [
                "odvody 551\u{00A0}100\u{00A0}Kč · stejně", "odvody 551\u{00A0}100\u{00A0}Kč · stejně",
            ])
    }

    /// The levies are compared only where both methods can be chosen: a comparison read for a year that has lost its
    /// uniform rate meanwhile, or that has no payment in another currency, is left out.
    @Test func theLeviesAreLeftOutWhereTheMethodsCannotBeCompared() {
        let comparison = (daily: Int64(548_037), uniform: Int64(551_100))

        let withoutRate = content(of: state(2025, uniform: .missingCurrency(.eur)), comparison: comparison)
        let withoutForeign = content(of: state(2025, uniform: rates2025, foreign: false), comparison: comparison)

        #expect(withoutRate.items.map(\.comparison) == [nil, nil])
        #expect(withoutForeign.items.map(\.comparison) == [nil, nil])
    }

    // MARK: The note

    @Test func aYearWithoutForeignPaymentsSaysTheChoiceChangesNothing() {
        let rates2024 = UniformAvailability.ready(
            usd: decimal("23.28"), eur: decimal("25.16"), instruction: "GFŘ-D-65", origin: .builtIn)

        let menu = content(of: state(2024, uniform: rates2024, foreign: false))

        #expect(menu.footer == "V roce 2024 nepřišla žádná platba v cizí měně – volba nic nemění.")
        // The year has its uniform rate, so it can be chosen all the same.
        #expect(menu.items.map(\.isEnabled) == [true, true])
    }

    /// A year set to the uniform rate that lacks it is computed at the daily rates, which are checked: they can be
    /// chosen, which drops the choice of the uniform rate.
    @Test func aChosenUniformWithoutItsRateExplainsTheDailyFallback() {
        let menu = content(of: state(2026, chosen: .uniform, uniform: .notPublishedYet(year: 2026)))

        #expect(
            menu.footer
                == "Rok 2026 se zatím počítá denními kurzy ČNB. Jednotným kurzem, který jste pro něj zvolili, se"
                + " přepočte, až bude kurz v aplikaci.")
        #expect(menu.items.map(\.isChecked) == [true, false])
        #expect(menu.items.map(\.isEnabled) == [true, false])
    }

    // MARK: The capsule

    @Test func theCapsuleNamesTheMethodTheYearUsesAndIsTintedForTheUniformRate() {
        #expect(
            RateMenuBuilder.capsule(year: 2025, effective: .uniform)
                == RateCapsuleContent(
                    title: "Jednotný kurz", accessibilityLabel: "Přepočet cizích měn v roce 2025: jednotný kurz",
                    isTinted: true))
        #expect(
            RateMenuBuilder.capsule(year: 2026, effective: .cnbDaily)
                == RateCapsuleContent(
                    title: "Denní kurz", accessibilityLabel: "Přepočet cizích měn v roce 2026: denní kurz ČNB",
                    isTinted: false))
    }
}
