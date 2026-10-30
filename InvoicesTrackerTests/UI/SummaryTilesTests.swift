import Foundation
import Testing
@testable import InvoicesTracker

/// The three tiles above the table of Faktury: the texts of the builder, and the hint that invoices to check are left
/// out of the two totals in crowns. In every expected string `\u{00A0}` is the no-break space.
struct SummaryTilesTests {
    // MARK: Helpers

    private func crownInvoice(id: Int64, number: String, review: ReviewFlag? = nil) -> Invoice {
        var invoice = Invoice.fixture(number: number, review: review)
        invoice.id = id
        invoice.client = SampleYear2026.cetus
        return invoice
    }

    private func dollarInvoice(id: Int64, number: String, review: ReviewFlag? = nil) -> Invoice {
        var invoice = Invoice.fixture(
            number: number, currency: .usd,
            items: [InvoiceItem(description: "Software development", quantity: decimal("205"), unit: "h", unitPriceMinor: 7_000)],
            vatMode: .outsideCountry, review: review)
        invoice.id = id
        invoice.client = SampleYear2026.bravo
        return invoice
    }

    private func data(
        _ invoices: [Invoice], filter: InvoiceStatusFilter = .all, issueDayRates: [Int64: ExchangeRate] = [:],
        uniformRates: [UniformRate] = []
    ) -> InvoiceListData {
        InvoiceListBuilder.build(
            InvoiceListInput(
                year: 2026, asOf: civilDate("2026-10-17"), statusDay: civilDate("2026-10-17"), scope: .issued,
                filter: filter, invoices: invoices, searchText: "", matchingIDs: nil, otherYearCounts: [:],
                paymentDayRates: [:], issueDayRates: issueDayRates,
                uniformRates: Dictionary(uniqueKeysWithValues: uniformRates.map { ($0.currency, $0) })))
    }

    private let toCheck = ReviewFlag(reason: "chybí kurz faktury")

    // MARK: The tiles

    @Test func theTilesAreTheCountTheTotalInCrownsAndTheTotalAtTheUniformRate() {
        let tiles = SummaryTiles.make(from: data([crownInvoice(id: 1, number: "20260902")]))

        #expect(tiles.map(\.title) == ["Počet faktur", "Celkem bez DPH v Kč", "Celkem bez DPH jednotným kurzem"])
        #expect(tiles[0].value == "1")
        #expect(tiles[0].subtitle == "vystavené v roce 2026 · všechny stavy")
        #expect(tiles[1].value == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(tiles[1].subtitle == "bez faktur v cizí měně")
        #expect(tiles[2].value == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(tiles[2].subtitle == "bez faktur v cizí měně – jednotný kurz se nepoužije")
        #expect(tiles.map(\.isMuted) == [false, false, false])
    }

    @Test func aCurrencyWithoutAUniformRateLeavesADashAndSaysWhenItComes() {
        let rate = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.622"))
        let tiles = SummaryTiles.make(from: data([dollarInvoice(id: 2, number: "20261001")], issueDayRates: [2: rate]))

        #expect(tiles[1].value == "310\u{00A0}275,70\u{00A0}Kč")
        #expect(tiles[2].value == "—")
        #expect(tiles[2].subtitle == "Jednotný kurz USD za rok 2026 ještě není vyhlášený – GFŘ ho zveřejní v lednu 2027.")
        #expect(tiles[2].isMuted == true)
    }

    @Test func aKnownUniformRateIsNamedWithItsSource() {
        let uniform = UniformRate(
            year: 2026, currency: .usd, amount: 1, rate: decimal("21.84"), instruction: "GFŘ-D-75", sourceURL: nil,
            confirmedAt: nil, origin: .builtIn)
        let rate = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.622"))

        let tiles = SummaryTiles.make(
            from: data([dollarInvoice(id: 2, number: "20261001")], issueDayRates: [2: rate], uniformRates: [uniform]))

        #expect(tiles[2].value == "313\u{00A0}404,00\u{00A0}Kč")
        #expect(tiles[2].subtitle == "jednotný kurz 2026: 1\u{00A0}USD = 21,84\u{00A0}Kč · pokyn GFŘ-D-75")
        #expect(tiles[2].isMuted == false)
    }

    // MARK: Invoices to check

    @Test func whenOnlyInvoicesToCheckAreInForeignCurrencyTheTotalsSayTheyAreLeftOut() {
        // The dollar invoice is held for review, so neither total counts it, and both would say that the category
        // has no invoice in a foreign currency while the table lists one.
        let list = data([crownInvoice(id: 1, number: "20260902"), dollarInvoice(id: 2, number: "20261001", review: toCheck)])

        let tiles = SummaryTiles.make(from: list)

        #expect(list.chipCounts[.review] == 1)
        #expect(tiles[1].subtitle == "bez faktur v cizí měně · mimo součet: 1 faktura ke kontrole")
        #expect(
            tiles[2].subtitle
                == "bez faktur v cizí měně – jednotný kurz se nepoužije · mimo součet: 1 faktura ke kontrole")
        // The count tile counts what the table lists.
        #expect(tiles[0].value == "2")
        #expect(tiles[0].subtitle == "vystavené v roce 2026 · všechny stavy")
    }

    @Test func theHintCountsEveryInvoiceToCheckOfTheCategoryWithTheRightWord() {
        let invoices = [
            dollarInvoice(id: 1, number: "20261001", review: toCheck),
            dollarInvoice(id: 2, number: "20261002", review: toCheck),
            dollarInvoice(id: 3, number: "20261003", review: toCheck),
            crownInvoice(id: 4, number: "20261004", review: toCheck),
            crownInvoice(id: 5, number: "20261005", review: toCheck),
        ]

        let tiles = SummaryTiles.make(from: data(invoices))

        #expect(tiles[1].subtitle == "bez faktur v cizí měně · mimo součet: 5 faktur ke kontrole")
        let few = SummaryTiles.make(from: data(Array(invoices.prefix(2))))
        #expect(few[1].subtitle == "bez faktur v cizí měně · mimo součet: 2 faktury ke kontrole")
    }

    @Test func noHintWhenTheTableListsNoForeignInvoiceToCheck() {
        // A crown invoice to check changes nothing the tile says: no invoice in a foreign currency is hidden.
        let list = data([crownInvoice(id: 1, number: "20260902"), crownInvoice(id: 2, number: "20260903", review: toCheck)])

        let tiles = SummaryTiles.make(from: list)

        #expect(tiles[1].subtitle == "bez faktur v cizí měně")
        #expect(tiles[2].subtitle == "bez faktur v cizí měně – jednotný kurz se nepoužije")
    }

    @Test func noHintWhenAnotherForeignInvoiceIsCounted() {
        let rate = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.622"))
        let list = data(
            [dollarInvoice(id: 1, number: "20261001"), dollarInvoice(id: 2, number: "20261002", review: toCheck)],
            issueDayRates: [1: rate])

        let tiles = SummaryTiles.make(from: list)

        #expect(tiles[1].subtitle == "přijaté kurzem ČNB ke dni přijetí, nezaplacené ke dni vystavení")
    }

    @Test func theChipOfTheInvoicesToCheckListsOnlyThemAndStillHintsAtTheTotal() {
        let list = data(
            [crownInvoice(id: 1, number: "20260902"), dollarInvoice(id: 2, number: "20261001", review: toCheck)],
            filter: .review)

        let tiles = SummaryTiles.make(from: list)

        #expect(tiles[0].value == "1")
        #expect(tiles[0].subtitle == "vystavené v roce 2026 · ke kontrole")
        #expect(tiles[1].value == "0,00\u{00A0}Kč")
        #expect(tiles[1].subtitle == "bez faktur v cizí měně · mimo součet: 1 faktura ke kontrole")
    }
}
