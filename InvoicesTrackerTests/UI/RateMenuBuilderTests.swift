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
        usd: decimal("21.84"), eur: decimal("24.66"), instruction: "GFŘ-D-75", origin: .builtIn, computedMonths: nil)

    private func state(
        _ year: Int, chosen: IncomeFXMethod = .cnbDaily, effective: IncomeFXMethod = .cnbDaily,
        uniform: UniformAvailability, foreign: Bool = true
    ) -> YearFXState {
        YearFXState(year: year, chosen: chosen, effective: effective, uniform: uniform, hasForeignPayments: foreign)
    }

    /// The day of the fixtures of the app, 17. 10. 2026, unless a test says another.
    private func content(
        of state: YearFXState, comparison: (daily: Int64, uniform: Int64)? = nil, today: String = "2026-10-17"
    ) -> RateMenuContent {
        RateMenuBuilder.content(state: state, comparison: comparison, today: civilDate(today))
    }

    /// The uniform rates of 2026 the app computed from `months` months of ČNB rates.
    private func computed(months: Int) -> UniformAvailability {
        .ready(
            usd: decimal("21.35"), eur: decimal("24.35"), instruction: nil, origin: .computed, computedMonths: months)
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
        let typed = UniformAvailability.ready(
            usd: decimal("21.9"), eur: nil, instruction: nil, origin: .manual, computedMonths: nil)

        let uniform = content(of: state(2026, uniform: typed)).items[1]

        #expect(uniform.detail == "1\u{00A0}USD = 21,90\u{00A0}Kč · zadáno ručně")
        #expect(uniform.isEnabled)
    }

    /// A rate entered by hand says so also with its instruction, as the other screens say it.
    @Test func aRateEnteredByHandWithAnInstructionSaysSoToo() {
        let typed = UniformAvailability.ready(
            usd: decimal("21.9"), eur: decimal("24.8"), instruction: "GFŘ-D-80", origin: .manual, computedMonths: nil)

        let uniform = content(of: state(2025, uniform: typed)).items[1]

        #expect(
            uniform.detail
                == "1\u{00A0}USD = 21,90\u{00A0}Kč · 1\u{00A0}EUR = 24,80\u{00A0}Kč · pokyn GFŘ-D-80, zadáno ručně")
    }

    /// A year that is not the current one waits for the GFŘ: 2025 on 1. 1. 2026, the day before the search starts.
    @Test func aYearThatWaitsForTheGFŘCannotChooseTheUniformRateYet() {
        let menu = content(of: state(2025, uniform: .notPublishedYet(year: 2025)), today: "2026-01-01")

        #expect(menu.heading == "Cizí měny v roce 2025")
        #expect(
            menu.items == [
                RateMenuItem(
                    method: .cnbDaily, title: "Denní kurz ČNB", detail: "kurz ke dni přijetí každé platby",
                    comparison: nil, isChecked: true, isEnabled: true),
                RateMenuItem(
                    method: .uniform, title: "Jednotný kurz 2025",
                    detail: "zatím nevyšel – GFŘ ho zveřejní v lednu 2026", comparison: nil, isChecked: false,
                    isEnabled: false),
            ])
        #expect(
            menu.footer
                == "Rok 2025 se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit, až bude pro rok 2025 známý.")
    }

    /// In January of the current year there is no month-end rate yet: the rate can be chosen from 1. 2.
    @Test func theCurrentYearInJanuaryCannotChooseTheUniformRateUntilFebruary() {
        let menu = content(of: state(2027, uniform: .notPublishedYet(year: 2027)), today: "2027-01-15")

        #expect(menu.items[1].detail == "zatím nejde spočítat – půjde zvolit od 1. 2. 2027, až skončí leden")
        #expect(!menu.items[1].isEnabled)
        #expect(
            menu.footer
                == "Rok 2027 se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit od 1. února, kdy ho aplikace"
                + " spočítá z kurzu ČNB za leden.")
    }

    /// In the other months the app lacks the ČNB rates of the month ends, and computes the rate once it has them.
    @Test func theCurrentYearWithoutTheMonthEndRatesCannotChooseTheUniformRateYet() {
        let menu = content(of: state(2026, uniform: .notPublishedYet(year: 2026)))

        #expect(
            menu.items[1].detail
                == "zatím nejde spočítat – aplikaci chybí kurzy ČNB ke konci měsíců; spočítá ho, až je stáhne")
        #expect(!menu.items[1].isEnabled)
        #expect(
            menu.footer
                == "Rok 2026 se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit, až aplikace stáhne chybějící"
                + " kurzy ČNB.")
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
            usd: decimal("23.28"), eur: decimal("25.16"), instruction: "GFŘ-D-65", origin: .builtIn,
            computedMonths: nil)

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

    // MARK: A computed rate

    @Test func aComputedRateIsWrittenWithAnApproximationAndSaysHowManyMonthsItAverages() {
        let menu = content(of: state(2026, chosen: .uniform, effective: .uniform, uniform: computed(months: 9)))

        #expect(
            menu.items[1].detail
                == "1\u{00A0}USD ≈ 21,35\u{00A0}Kč · 1\u{00A0}EUR ≈ 24,35\u{00A0}Kč · předběžný"
                + " · průměr kurzů ČNB za leden–září (9 z 12 měsíců)")
        #expect(menu.items[1].isEnabled)
        #expect(menu.items[1].isChecked)
    }

    @Test func aComputedRateOfAllTwelveMonthsSaysSo() {
        let menu = content(
            of: state(2026, chosen: .uniform, effective: .uniform, uniform: computed(months: 12)), today: "2027-01-10")

        #expect(
            menu.items[1].detail
                == "1\u{00A0}USD ≈ 21,35\u{00A0}Kč · 1\u{00A0}EUR ≈ 24,35\u{00A0}Kč · předběžný"
                + " · spočítaný ze všech 12 měsíců")
    }

    @Test func aComputedRateOfFewerThanTwelveMonthsSaysItGetsMoreExact() {
        let menu = content(of: state(2026, uniform: computed(months: 9)))

        #expect(
            menu.footer
                == "Platí pro všechny platby v cizí měně přijaté v roce 2026 – v Přehledu, Fakturách i Výpočtu."
                + " Každý rok si volbu pamatuje zvlášť."
                + " Předběžný kurz se po každém skončeném měsíci zpřesní; oficiální vyhlásí GFŘ v lednu 2027.")
    }

    @Test func aComputedRateOfAllTwelveMonthsSaysItShouldMatchTheGFŘRate() {
        let menu = content(of: state(2026, uniform: computed(months: 12)), today: "2027-01-10")

        #expect(
            menu.footer
                == "Platí pro všechny platby v cizí měně přijaté v roce 2026 – v Přehledu, Fakturách i Výpočtu."
                + " Každý rok si volbu pamatuje zvlášť."
                + " Kurz je spočítaný ze všech 12 měsíců, takže by se měl shodovat s kurzem GFŘ; až vyjde, aplikace"
                + " vám ho dá potvrdit.")
    }

    /// From 1 April of the next year the app no longer looks for the GFŘ rate: the person enters it by hand.
    @Test func aComputedRateOfAllTwelveMonthsAfterTheSearchIsOverAsksForTheGFŘRate() {
        let menu = content(of: state(2026, uniform: computed(months: 12)), today: "2027-04-01")

        #expect(
            menu.footer
                == "Platí pro všechny platby v cizí měně přijaté v roce 2026 – v Přehledu, Fakturách i Výpočtu."
                + " Každý rok si volbu pamatuje zvlášť."
                + " Kurz je spočítaný ze všech 12 měsíců. Aplikace kurz GFŘ nenašla – zadejte ho podle pokynu GFŘ"
                + " v Nastavení › Rok.")
    }

    // MARK: The capsule

    @Test func theCapsuleNamesTheMethodTheYearUsesAndIsTintedBlueForTheUniformRate() {
        #expect(
            RateMenuBuilder.capsule(year: 2025, effective: .uniform, computed: false)
                == RateCapsuleContent(
                    title: "Jednotný kurz", accessibilityLabel: "Přepočet cizích měn v roce 2025: jednotný kurz",
                    tone: .uniform))
        #expect(
            RateMenuBuilder.capsule(year: 2026, effective: .cnbDaily, computed: false)
                == RateCapsuleContent(
                    title: "Denní kurz", accessibilityLabel: "Přepočet cizích měn v roce 2026: denní kurz ČNB",
                    tone: .daily))
    }

    @Test func theCapsuleOfAComputedRateIsPreliminary() {
        #expect(
            RateMenuBuilder.capsule(year: 2026, effective: .uniform, computed: true)
                == RateCapsuleContent(
                    title: "Jednotný kurz · předběžný",
                    accessibilityLabel: "Přepočet cizích měn v roce 2026: jednotný kurz, předběžný",
                    tone: .preliminary))
    }

    /// A computed rate that the year does not use leaves the capsule on the daily rates.
    @Test func theCapsuleOfAYearOnTheDailyRatesIgnoresAComputedRate() {
        #expect(RateMenuBuilder.capsule(year: 2026, effective: .cnbDaily, computed: true).tone == .daily)
    }
}
