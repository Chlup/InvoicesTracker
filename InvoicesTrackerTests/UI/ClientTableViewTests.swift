import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The cells of the table of Odběratelé at its least width: the least width of a column holds the widest of what its
/// cells say whole, and so does the room of the button Nová faktura, so that the table at its least width cuts short
/// only the name of a client and the line under it. Each is measured as its cell shows it, on one line.
@MainActor
struct ClientTableViewTests {
    /// The currencies the ČNB quotes, and the crown: the tags the cell of a client can carry.
    private static let currencies = [
        "CZK", "AUD", "BRL", "BGN", "CNY", "DKK", "EUR", "PHP", "HKD", "INR", "IDR", "ISK", "ILS", "JPY", "ZAR", "CAD",
        "KRW", "HUF", "MYR", "MXN", "XDR", "NOK", "NZD", "PLN", "RON", "SGD", "SEK", "CHF", "THB", "TRY", "USD", "GBP",
    ]

    /// Of those, the crown and the currencies of the member states of the EU. The reverse charge, the longest of the
    /// VAT texts, is for a client in another country of the EU, who is invoiced in the euro, in the currency of its
    /// country or in crowns.
    private static let euCurrencies: Set<String> = ["CZK", "BGN", "DKK", "EUR", "HUF", "PLN", "RON", "SEK"]

    /// The width `view` asks for to show itself whole, on one line.
    private func width<Content: View>(of view: Content) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
    }

    /// The row the builder makes of a client in `currency` with `mode` and `figures`, as the screen shows it.
    private func rowOf(currency: String, mode: VatMode, figures: ClientFigures? = nil) throws -> ClientRow {
        var client = Client(name: "Alfa")
        client.currency = try #require(CurrencyCode(currency))
        client.vatMode = mode
        return try #require(ClientRowBuilder.rows(clients: [client], figures: figures.map { [0: $0] } ?? [:]).first)
    }

    /// VoiceOver reads a row as a button that names its columns, and says what pressing it does; Nová faktura is a
    /// button of its own.
    @Test func aRowSaysThatItOpensTheFormOfItsClient() async throws {
        let row = try rowOf(currency: "EUR", mode: .euReverseCharge)
        let table = ClientTableView(rows: [row], year: 2026, edit: { _ in }, newInvoice: { _ in })

        try await withHostedView(table) { window in
            try await withAccessibilityElements {
                let spoken = row.spokenText(year: 2026)
                try await waitUntil { accessibilityButton(labelled: spoken, in: window) != nil }
                let button = try #require(accessibilityButton(labelled: spoken, in: window))

                // The hint is what macOS calls the help of an element.
                #expect(button.accessibilityHelp?() == "Otevře úpravu odběratele.")
            }
        }
    }

    /// Měna a DPH holds the widest tag with the longest VAT text: of every currency the ČNB quotes with every mode of
    /// VAT (the reverse charge with the currencies of the EU), whichever needs most.
    @Test func theLeastWidthOfMenaADphHoldsTheWidestCurrencyAndVatTextWhole() throws {
        var widest: (needs: CGFloat, text: String) = (0, "")
        for currency in Self.currencies {
            for mode in VatMode.allCases where mode != .euReverseCharge || Self.euCurrencies.contains(currency) {
                let row = try rowOf(currency: currency, mode: mode)
                let needs = width(of: ClientCurrencyCell(currency: row.currency, vat: row.vatShort))
                if needs > widest.needs {
                    widest = (needs, "\(row.currency) with \(row.vatShort)")
                }
            }
        }

        let least = ClientTableColumns.columns[1].minimum
        #expect(widest.needs <= least, "\(widest.text) needs \(widest.needs) points, Měna a DPH has \(least)")
    }

    /// Rok Y holds the longest of its lines: the most a client was paid in a year that anyone is likely to be, 12 345
    /// 678,90 Kč, and the most invoices, 100, the last on a day of two digits in a month of two, 30. 12.
    @Test func theLeastWidthOfRokYHoldsTheWidestAmountAndTheLongestCountLineWhole() throws {
        let figures = ClientFigures(
            invoiceCount: 100, receivedHalere: 1_234_567_890, lastIssueDate: civilDate("2026-12-30"))
        let row = try rowOf(currency: "CZK", mode: .domestic21, figures: figures)
        #expect(row.received == "přijato 12\u{00A0}345\u{00A0}678,90\u{00A0}Kč")
        #expect(row.countLine == "100 faktur · poslední 30.\u{00A0}12.")

        let needs = width(of: ClientYearCell(row: row))

        let least = ClientTableColumns.columns[3].minimum
        #expect(needs <= least, "\(row.received) and \(row.countLine) need \(needs) points, Rok Y has \(least)")
    }

    /// Each column holds its name whole, Jazyk faktury too, and Jazyk faktury the longer of the two languages.
    @Test func theLeastWidthOfAColumnHoldsItsNameWhole() {
        let names = [Text("Odběratel"), Text("Měna a DPH"), Text("Jazyk faktury"), Text(verbatim: "Rok 2026")]

        for (index, name) in names.enumerated() {
            let needs = width(of: name.clientColumnTitle())
            let least = ClientTableColumns.columns[index].minimum
            #expect(needs <= least, "the name of column \(index) needs \(needs) points, it has \(least)")
        }
        let language = ["česky", "anglicky"].map { width(of: Text(verbatim: $0).lineLimit(1)) }.max() ?? 0
        #expect(language <= ClientTableColumns.columns[2].minimum, "a language needs \(language) points")
    }

    @Test func theRoomOfTheButtonHoldsTheButtonNovaFakturaWhole() {
        let needs = width(of: ClientNewInvoiceLabel())

        #expect(needs <= ClientTableColumns.buttonRoom, "the button needs \(needs) points")
    }
}
