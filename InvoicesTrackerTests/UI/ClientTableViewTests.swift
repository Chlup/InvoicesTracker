import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The table of Odběratelé on its own: VoiceOver reads each row as a button that names its columns, the whole VAT text
/// too, and the row of the selected client as selected. At the least width of Měna a DPH, the prototype's, the chip of
/// the currency stays whole and the VAT text after it is cut at its tail, on its line and inside its column, as the
/// prototype draws the cell. The least width of each other column holds the widest of what its cells say, and each
/// column holds its name, whole. Each is measured as the table shows it, on one line.
@MainActor
struct ClientTableViewTests {
    /// The currencies the ČNB quotes, and the crown: the chips the cell of a client can carry.
    private static let currencies = [
        "CZK", "AUD", "BRL", "BGN", "CNY", "DKK", "EUR", "PHP", "HKD", "INR", "IDR", "ISK", "ILS", "JPY", "ZAR", "CAD",
        "KRW", "HUF", "MYR", "MXN", "XDR", "NOK", "NZD", "PLN", "RON", "SGD", "SEK", "CHF", "THB", "TRY", "USD", "GBP",
    ]

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

    /// Where its cell cuts the VAT text, as at the least width of the table, VoiceOver still reads the row with the
    /// whole text (`ClientRow.spokenText(receivedHeader:)`): a client in leva with the reverse charge, in a window as
    /// wide as the least width of the table, where Měna a DPH has its least width.
    @Test func aRowWhoseVatTextIsCutIsReadWithTheWholeText() async throws {
        var client = Client(id: 1, name: "Delta Import GmbH")
        client.currency = try #require(CurrencyCode("BGN"))
        client.vatMode = .euReverseCharge
        let data = ClientsBuilder.build(ClientsInput(year: 2026, clients: [client], templates: [], figures: [:]))
        let table = ClientTableView(data: data, selectedID: nil, click: { _ in })
        let size = CGSize(width: ClientTableColumns.minimumWidth, height: 300)

        try await withHostedView(table, size: size) { window in
            try await withAccessibilityElements {
                let label = "Delta Import GmbH, Měna a DPH BGN, přenesená povinnost, Šablony žádná"
                try await waitUntil { accessibilityButton(labelled: label, in: window) != nil }

                let columns = ClientTableColumns.columnWidths(inTableOf: window.contentLayoutRect.width)
                #expect(columns[1] == ClientTableColumns.columns[1].minimum, "\(columns)")
            }
        }
    }

    // MARK: Měna a DPH at its least width

    /// At the least width of Měna a DPH the chip of the currency keeps its whole width, and the VAT text after it is
    /// cut at its tail where the column is narrower than the two, as the prototype draws the cell: the text stays on
    /// its one line and inside the column, and does not push out of it. The cell is laid out twice, with the room it
    /// asks for and at the least width, with the widest chip of a currency the ČNB quotes and the longest VAT text. A
    /// mark right after the column of the second says where the column ends: VoiceOver's frame of a group is that of
    /// what it holds, which is narrower than the column where the text is cut.
    @Test func atItsLeastWidthMenaADphKeepsTheChipWholeAndCutsTheVatText() async throws {
        let currency = try #require(
            Self.currencies.max { width(of: chipText($0)) < width(of: chipText($1)) })
        let vats = try VatMode.allCases.map { try rowOf(mode: $0).vatShort }
        let vat = try #require(vats.max { width(of: vatText($0)) < width(of: vatText($1)) })
        let least = ClientTableColumns.columns[1].minimum
        let mark = "Konec sloupce"
        let cells = VStack(alignment: .leading, spacing: 20) {
            ClientCurrencyCell(currency: currency, vat: vat)
                .fixedSize()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Celá buňka")
            HStack(spacing: 0) {
                ClientCurrencyCell(currency: currency, vat: vat)
                    .frame(width: least, alignment: .leading)
                Text(verbatim: mark)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Měna a DPH")
        }

        try await withHostedView(cells) { window in
            try await withAccessibilityElements {
                try await waitUntil { textFrames(inGroupLabelled: "Měna a DPH", in: window).count == 3 }
                let whole = textFrames(inGroupLabelled: "Celá buňka", in: window)
                let cut = textFrames(inGroupLabelled: "Měna a DPH", in: window)
                let end = try #require(cut[mark]).minX
                let wholeChip = try #require(whole[currency])
                let cutChip = try #require(cut[currency])
                let wholeVat = try #require(whole.first { $0.key != currency }?.value)
                let cutVat = try #require(cut.first { $0.key != currency && $0.key != mark }?.value)

                #expect((cutChip.width - wholeChip.width).magnitude < 0.5, "the chip \(cutChip), whole \(wholeChip)")
                #expect(cutChip.minX >= end - least - 0.5, "the chip \(cutChip) in the column ending at \(end)")
                #expect(cutVat.width < wholeVat.width - 1, "\(vat) is not cut: \(cutVat), whole \(wholeVat)")
                #expect((cutVat.height - wholeVat.height).magnitude < 0.5, "\(vat) wraps: \(cutVat), \(wholeVat)")
                #expect(cutVat.maxX <= end + 0.5, "\(vat) runs out of the column ending at \(end): \(cutVat)")
            }
        }
    }

    /// The code of a currency as its chip sets it.
    private func chipText(_ code: String) -> some View {
        Text(verbatim: code).font(Typography.calloutSemibold)
    }

    /// A VAT text as its cell sets it.
    private func vatText(_ text: String) -> some View {
        Text(verbatim: text).font(Typography.body)
    }

    /// The frames of the texts in the group of `window` that VoiceOver reads under `label`, by the words of each, in
    /// the coordinates of the screen. Empty while the window has no such group, and while its views make no
    /// accessibility elements.
    private func textFrames(inGroupLabelled label: String, in window: NSWindow) -> [String: CGRect] {
        guard let group = accessibilityElement(labelled: label, in: window) else { return [:] }
        var frames: [String: CGRect] = [:]
        for element in descendants(of: group) {
            // The value is asked for as a function of its type, because the protocols of accessibility declare
            // `accessibilityValue()` with more than one type.
            let value: (() -> Any?)? = element.accessibilityValue
            guard element.accessibilityRole?() == .staticText, let words = (value?() ?? nil) as? String,
                let frame = element.accessibilityFrame?()
            else {
                continue
            }
            frames[words] = frame
        }
        return frames
    }

    /// The elements under `element`, in the order of the tree.
    private func descendants(of element: AnyObject) -> [AnyObject] {
        let children = (element.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return children.flatMap { [$0] + descendants(of: $0) }
    }

    // MARK: The least widths of the other columns

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
