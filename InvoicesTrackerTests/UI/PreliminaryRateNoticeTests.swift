import Foundation
import Testing
@testable import InvoicesTracker

/// The notice under the banner of the screens the computed uniform rate affects, as a text: its title and the sentence
/// under it, which name the currencies the year was paid in, the months the rate averages and where the search for the
/// rate of the GFŘ stands. In every expected string `\u{00A0}` is the no-break space.
struct PreliminaryRateNoticeTests {
    // MARK: Helpers

    /// Pounds, a currency whose rate the app does not compute.
    private let gbp = CurrencyCode("GBP")!

    /// The uniform rates of 2026 the app computed from `months` months of ČNB rates.
    private func computed(months: Int) -> UniformAvailability {
        .ready(
            usd: decimal("21.35"), eur: decimal("24.35"), instruction: nil, origin: .computed, computedMonths: months)
    }

    /// The state of 2026 converted at the computed rate, paid in `paid`.
    private func state(
        months: Int, paid: [CurrencyCode] = [.usd], effective: IncomeFXMethod = .uniform, foreign: Bool = true
    ) -> YearFXState {
        YearFXState(
            year: 2026, chosen: .uniform, effective: effective, uniform: computed(months: months),
            hasForeignPayments: foreign, paidCurrencies: paid)
    }

    private func content(of state: YearFXState, today: String = "2026-10-17") -> (title: String, sentence: String)? {
        PreliminaryRateNoticeText.content(state: state, today: civilDate(today))
    }

    // MARK: The sentences

    @Test func aRateOfSomeMonthsSaysWhichMonthsItAveragesAndThatItGetsMoreExact() throws {
        let text = try #require(content(of: state(months: 9)))

        #expect(text.title == "Předběžný jednotný kurz 2026")
        #expect(
            text.sentence
                == "Platby v USD jsou přepočtené průměrem kurzů ČNB za leden–září (1\u{00A0}USD ≈ 21,35\u{00A0}Kč)."
                + " Po každém skončeném měsíci se kurz zpřesní; oficiální vyhlásí GFŘ v lednu 2027.")
    }

    @Test func aRateOfAllTwelveMonthsSaysItShouldMatchTheRateOfTheGFR() throws {
        let text = try #require(content(of: state(months: 12), today: "2027-01-10"))

        #expect(
            text.sentence
                == "Platby v USD jsou přepočtené kurzem, který aplikace spočítala ze všech 12 měsíců"
                + " (1\u{00A0}USD ≈ 21,35\u{00A0}Kč). Měl by se shodovat s kurzem GFŘ; až ho GFŘ vyhlásí,"
                + " aplikace vám ho dá potvrdit.")
    }

    @Test func aRateOfAllTwelveMonthsOnceTheSearchIsOverAsksToEnterTheRateByHand() throws {
        let text = try #require(content(of: state(months: 12), today: "2027-04-01"))

        #expect(
            text.sentence
                == "Platby v USD jsou přepočtené kurzem, který aplikace spočítala ze všech 12 měsíců"
                + " (1\u{00A0}USD ≈ 21,35\u{00A0}Kč). Aplikace kurz GFŘ nenašla – zadejte ho podle pokynu GFŘ"
                + " v Nastavení › Rok.")
    }

    @Test func aYearPaidInDollarsAndEurosNamesBothAndTheirRatesAfterOneAnother() throws {
        let text = try #require(content(of: state(months: 9, paid: [.usd, .eur])))

        #expect(
            text.sentence.hasPrefix(
                "Platby v USD a EUR jsou přepočtené průměrem kurzů ČNB za leden–září"
                    + " (1\u{00A0}USD ≈ 21,35\u{00A0}Kč, 1\u{00A0}EUR ≈ 24,35\u{00A0}Kč)."))
    }

    @Test func aCurrencyThatIsNotComputedIsLeftOutOfTheSentence() throws {
        let text = try #require(content(of: state(months: 9, paid: [.eur, gbp])))

        #expect(text.sentence.hasPrefix("Platby v EUR jsou přepočtené průměrem"))
        #expect(text.sentence.contains("(1\u{00A0}EUR ≈ 24,35\u{00A0}Kč)"))
    }

    // MARK: When there is none

    @Test func aYearPaidInCrownsAloneHasNoNotice() {
        #expect(content(of: state(months: 9, paid: [], foreign: false)) == nil)
    }

    @Test func aYearPaidInPoundsAloneHasNoNotice() {
        #expect(content(of: state(months: 9, paid: [gbp])) == nil)
    }

    @Test func aYearThatConvertsAtTheDailyRatesHasNoNotice() {
        #expect(content(of: state(months: 9, effective: .cnbDaily)) == nil)
    }

    @Test func aRateThatIsNotComputedHasNoNotice() {
        let entered = YearFXState(
            year: 2026, chosen: .uniform, effective: .uniform,
            uniform: .ready(
                usd: decimal("21.84"), eur: nil, instruction: "GFŘ-D-75", origin: .manual, computedMonths: nil),
            hasForeignPayments: true, paidCurrencies: [.usd])

        #expect(content(of: entered) == nil)
    }

    // MARK: The screens

    @Test func theNoticeIsOnTheScreensTheRateAffectsAndOnNoOther() {
        let shown = Screen.allCases.filter(\.showsPreliminaryRateNotice)

        #expect(shown == [.overview, .invoices, .advances, .computation, .prediction, .budget])
    }
}
