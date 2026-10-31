import Foundation
import Testing
@testable import InvoicesTracker

/// The line that says an item on the detail of an invoice, on the panel of a template in the detail of its client and
/// in the chooser of a new invoice.
struct ItemLineTests {
    @Test func anItemIsSaidWithItsQuantityUnitPriceAndDescription() {
        let line = ItemLine.text(
            quantity: decimal("205"), unit: "h", unitPriceMinor: 7_000, currency: .usd,
            description: "Software development")

        #expect(line == "205\u{00A0}h × 70,00\u{00A0}USD · Software development")
    }

    @Test(arguments: [("6.5", "6,5"), ("1.250", "1,25"), ("176", "176"), ("0.5", "0,5")])
    func aQuantityHasADecimalCommaAndNoTrailingZeros(quantity: String, text: String) {
        let line = ItemLine.text(quantity: decimal(quantity), unit: "hod", unitPriceMinor: 60_000, currency: .czk)

        #expect(line == "\(text)\u{00A0}hod × 600,00\u{00A0}Kč")
    }

    @Test func withoutAUnitOrADescriptionTheLineIsShorter() {
        let line = ItemLine.text(quantity: decimal("2"), unit: "", unitPriceMinor: 12_345, currency: .czk)

        #expect(line == "2 × 123,45\u{00A0}Kč")
    }

    @Test func theDescriptionIsGivenWithoutTheWhiteSpaceAroundItAndLeftOutWhenThereIsNoneButWhiteSpace() {
        let described = ItemLine.text(
            quantity: decimal("1"), unit: "ks", unitPriceMinor: 100, currency: .eur, description: "  Hosting\n")
        let blank = ItemLine.text(
            quantity: decimal("1"), unit: "ks", unitPriceMinor: 100, currency: .eur, description: " \n ")

        #expect(described == "1\u{00A0}ks × 1,00\u{00A0}EUR · Hosting")
        #expect(blank == "1\u{00A0}ks × 1,00\u{00A0}EUR")
    }
}
