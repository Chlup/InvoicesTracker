import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The table of Odběratelé on its own: VoiceOver reads each row as a button that names its columns, and the row of the
/// selected client as selected; and the least width of each column holds the widest of what its cells say, and its
/// name, whole, so that the table at its least width cuts short only the name of a client. Each is measured as the
/// table shows it, on one line.
@MainActor
struct ClientTableViewTests {
    /// The currencies the ČNB quotes, and the crown: the chips the cell of a client can carry.
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

    /// The row the builder makes of a client in `currency` with `mode`, `templates` templates and `figures`, as the
    /// table shows it.
    private func rowOf(
        currency: String = "CZK", mode: VatMode = .domestic21, templates: Int = 0, figures: ClientFigures? = nil
    ) throws -> ClientRow {
        var client = Client(name: "Alfa")
        client.currency = try #require(CurrencyCode(currency))
        client.vatMode = mode
        let own = (0..<templates).map { ClientsFixture.template(for: client.id, name: "Šablona \($0)") }
        let data = ClientsBuilder.build(
            ClientsInput(
                year: 2026, clients: [client], templates: own, figures: figures.map { [client.id: $0] } ?? [:]))
        return try #require(data.rows.first)
    }

    // MARK: What VoiceOver reads

    /// VoiceOver reads each row as a button that names its columns (`ClientRow.spokenText(receivedHeader:)`), the row
    /// of the selected client as selected and the others as not, and presses a row as a click does.
    @Test func aRowIsReadAsAButtonThatNamesItsColumnsAndTheSelectedOneAsSelected() async throws {
        let clients = [Client(id: 1, name: "Alfa Systems s.r.o."), Client(id: 2, name: "Bravo Labs, Inc.")]
        let data = ClientsBuilder.build(ClientsInput(year: 2026, clients: clients, templates: [], figures: [:]))
        var clicked: [Int64] = []
        let table = ClientTableView(data: data, selectedID: 2, click: { clicked.append($0) })

        try await withHostedView(table) { window in
            try await withAccessibilityElements {
                let alfa = "Alfa Systems s.r.o., Měna a DPH CZK, DPH 21 %, Šablony žádná"
                let bravo = "Bravo Labs, Inc., Měna a DPH CZK, DPH 21 %, Šablony žádná"
                try await waitUntil { accessibilityButton(labelled: bravo, in: window) != nil }

                #expect(accessibilityButton(labelled: bravo, in: window)?.isAccessibilitySelected?() == true)
                let alfaRow = try #require(accessibilityButton(labelled: alfa, in: window))
                #expect(alfaRow.isAccessibilitySelected?() == false)
                #expect(alfaRow.accessibilityPerformPress?() == true)
                #expect(clicked == [1])
            }
        }
    }

    // MARK: The least widths of the columns

    /// Měna a DPH holds the widest chip with the longest VAT text: of every currency the ČNB quotes with every mode of
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

    /// Šablony holds "žádná" and the count of up to 99 templates, whichever needs most.
    @Test func theLeastWidthOfSablonyHoldsTheLongestCountOfTemplatesWhole() throws {
        var widest: (needs: CGFloat, text: String) = (0, "")
        for count in 0...99 {
            let row = try rowOf(templates: count)
            let needs = width(of: ClientTemplatesCell(row: row))
            if needs > widest.needs {
                widest = (needs, row.templates)
            }
        }

        let least = ClientTableColumns.columns[2].minimum
        #expect(widest.needs <= least, "\(widest.text) needs \(widest.needs) points, Šablony has \(least)")
    }

    /// Přijato Y holds the most a client is likely to pay in a year, 12 345 678 Kč, and the dash of a client that paid
    /// nothing.
    @Test func theLeastWidthOfPrijatoHoldsTheWidestAmountWhole() throws {
        let figures = ClientFigures(invoiceCount: 100, receivedHalere: 1_234_567_890, lastIssueDate: nil)
        let paid = try rowOf(figures: figures)
        #expect(paid.received == "12\u{00A0}345\u{00A0}679\u{00A0}Kč")

        let least = ClientTableColumns.columns[3].minimum
        for row in [paid, try rowOf()] {
            let needs = width(of: ClientReceivedCell(row: row))
            #expect(needs <= least, "\(row.received) needs \(needs) points, Přijato has \(least)")
        }
    }

    /// Each column holds its name whole, Přijato Y with a year of four digits.
    @Test func theLeastWidthOfAColumnHoldsItsNameWhole() {
        let names = [Text("Odběratel"), Text("Měna a DPH"), Text("Šablony"), Text(verbatim: "Přijato 2026")]

        for (index, name) in names.enumerated() {
            let needs = width(of: name.tableHeaderStyle())
            let least = ClientTableColumns.columns[index].minimum
            #expect(needs <= least, "the name of column \(index) needs \(needs) points, it has \(least)")
        }
    }
}
