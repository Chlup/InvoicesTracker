import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The table of Faktury on its own: in a light window the row of the open invoice is tinted pale blue, with a blue edge
/// 3 points wide on its leading side, as the design draws it, and the rows around it are not; each cell takes the
/// colour of what it shows; what VoiceOver reads for a row names its columns and leaves out a column that is empty for
/// the invoice or repeats another; and the least width of a column holds the widest number, amount, date or pill of
/// its cells whole. (The window tests find the rows by what VoiceOver reads and press them; these tests make no
/// accessibility elements.)
@MainActor
struct InvoiceTableViewTests {
    /// The cells are measured in the font they are set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// An invoice in crowns that waits for its payment and has no net income.
    private let crowns = InvoiceRow(
        id: 1, number: "20261001", client: "Cetus Data s.r.o.", issued: "1.\u{00A0}10.", paidDate: "—",
        paidTone: .none, net: "4\u{00A0}500,00\u{00A0}Kč", czk: "4\u{00A0}500,00\u{00A0}Kč", czkKind: .actual,
        czkHelp: nil, hasReceivedPayment: false, netIncome: "—", netIncomeKind: .none, status: .awaitingPayment,
        listStatus: "Čeká na platbu", pillTone: .waiting, excerpt: nil)

    /// An invoice in dollars that is paid, with its value in crowns and no net income.
    private let dollars = InvoiceRow(
        id: 2, number: "20260901", client: "Bravo Labs, Inc.", issued: "30.\u{00A0}9.", paidDate: "2.\u{00A0}10.",
        paidTone: .received, net: "14\u{00A0}350,00\u{00A0}USD", czk: "305\u{00A0}726,75\u{00A0}Kč",
        czkKind: .actual, czkHelp: nil, hasReceivedPayment: true, netIncome: "—", netIncomeKind: .none,
        status: .paid(civilDate("2026-10-02")), listStatus: "Uhrazená", pillTone: .paid, excerpt: nil)

    /// An invoice in crowns that is paid and whose payment reduced the levies, with its net income.
    private let withNetIncome = InvoiceRow(
        id: 4, number: "2026-01-01", client: "Sierra, SE", issued: "31.\u{00A0}1.", paidDate: "3.\u{00A0}2.",
        paidTone: .received, net: "220\u{00A0}000,00\u{00A0}Kč", czk: "220\u{00A0}000,00\u{00A0}Kč",
        czkKind: .actual, czkHelp: nil, hasReceivedPayment: true, netIncome: "253\u{00A0}401\u{00A0}Kč",
        netIncomeKind: .paid, status: .paid(civilDate("2026-02-03")), listStatus: "Uhrazená", pillTone: .paid,
        excerpt: nil)

    /// A draft in dollars with the estimate of its net income and of its value in crowns.
    private let estimated = InvoiceRow(
        id: 5, number: "20261001", client: "Bravo Labs, Inc.", issued: "31.\u{00A0}10.", paidDate: "—",
        paidTone: .none, net: "12\u{00A0}040,00\u{00A0}USD", czk: "≈ 260\u{00A0}328,88\u{00A0}Kč",
        czkKind: .estimate, czkHelp: "Odhad kurzem ČNB ke dni vystavení: 21,622\u{00A0}Kč/USD",
        hasReceivedPayment: false, netIncome: "≈\u{00A0}159\u{00A0}636\u{00A0}Kč", netIncomeKind: .estimate,
        status: .draft, listStatus: "Koncept", pillTone: .draft, excerpt: nil)

    /// An invoice in dollars that is paid by a payment dated after today, which has not come yet, and whose rate of the
    /// day of issue is not known.
    private let later = InvoiceRow(
        id: 6, number: "20260801", client: "Bravo Labs, Inc.", issued: "31.\u{00A0}8.", paidDate: "20.\u{00A0}10.",
        paidTone: .later, net: "13\u{00A0}300,00\u{00A0}USD", czk: "—", czkKind: .unknown, czkHelp: nil,
        hasReceivedPayment: false, netIncome: "—", netIncomeKind: .none, status: .overdue,
        listStatus: "Po splatnosti", pillTone: .overdue, excerpt: nil)

    /// An invoice in crowns that the search found by its note.
    private func found() throws -> InvoiceRow {
        let note = "…Routing number…"
        return InvoiceRow(
            id: 3, number: "2026-03-01", client: "Alfa Systems s.r.o.", issued: "31.\u{00A0}3.",
            paidDate: "7.\u{00A0}4.", paidTone: .received, net: "210\u{00A0}000,00\u{00A0}Kč",
            czk: "210\u{00A0}000,00\u{00A0}Kč", czkKind: .actual, czkHelp: nil, hasReceivedPayment: true,
            netIncome: "—", netIncomeKind: .none, status: .paid(civilDate("2026-04-07")), listStatus: "Uhrazená",
            pillTone: .paid,
            excerpt: SearchExcerptResult(
                label: "Poznámka", text: note, highlight: try #require(note.range(of: "Routing"))))
    }

    /// What the list shows with `rows`: the summary of an empty list of 2026, with the rows put in.
    private func list(of rows: [InvoiceRow]) -> InvoiceListData {
        var data = InvoiceListBuilder.build(
            InvoiceListInput(
                year: 2026, asOf: civilDate("2026-10-17"), statusDay: civilDate("2026-10-17"), scope: .issued,
                filter: .all, invoices: [], searchText: "", matchingIDs: nil, otherYearCounts: [:],
                paymentDayRates: [:], issueDayRates: [:], uniformRates: [:]))
        data.rows = rows
        return data
    }

    // MARK: The open row

    @Test func theOpenRowIsTintedPaleBlueWithABlueEdgeOnItsLeadingSide() async throws {
        // The three rows, the middle one open, in a card 20 points inside a light window of 900 × 400 points.
        let table = InvoiceTableView(
            data: list(of: [crowns, dollars, try found()]), openID: dollars.id, click: { _ in }, move: { _ in })
        try await withPictureOf(table.padding(20), size: CGSize(width: 900, height: 400)) { picture in
            // Down the leading edge of the card, inside the 3 points of the edge of a row: one band of the blue of the
            // edge, as tall as a row less the hairline across its top, 39 points.
            let edge: CGFloat = 20 + 1.5
            let bands = picture.bands(atX: edge, from: 20, to: 380) { isClose($0, to: [0x00, 0x71, 0xE3]) }
            #expect(bands.count == 1, "the bands of blue down the edge on \(picture.screen): \(bands)")
            let band = try #require(bands.first)
            #expect((band.upperBound - band.lowerBound - 39).magnitude <= 1, "the band \(band) on \(picture.screen)")

            // The tint across the row, in the margin before the first column and in the one after the last.
            let middle = (band.lowerBound + band.upperBound) / 2
            for x in [20 + 10, 880 - 10] as [CGFloat] {
                let tint = try picture.bytes(at: CGPoint(x: x, y: middle))
                #expect(isClose(tint, to: [0xE8, 0xF1, 0xFD]), "the open row at \(x) on \(picture.screen) is \(tint)")
            }

            // The rows above and under it are not open: they have the white of the card, at their edge too.
            for y in [band.lowerBound - 21, band.upperBound + 21] {
                for x in [edge, 20 + 10] as [CGFloat] {
                    let white = try picture.bytes(at: CGPoint(x: x, y: y))
                    #expect(
                        isClose(white, to: [0xFF, 0xFF, 0xFF]),
                        "a row not open, at \(x), \(y) on \(picture.screen), is \(white)")
                }
            }
        }
    }

    /// Shows `view` in a light window with `size` points of content and gives `body` a picture of it, once for each
    /// screen of the Mac with the window on that screen, and under a window that covers it each time: neither the
    /// screen the window is on (its colour profile, its scale) nor what covers it may change what the window shows.
    /// The window is not made the key window: a picture needs none, and a window test of another suite that types needs
    /// its own window to stay the key one.
    private func withPictureOf<Content: View>(
        _ view: Content, size: CGSize, _ body: (Picture) async throws -> Void
    ) async throws {
        // A Mac with no screen shows the window where it is put.
        let screens: [NSScreen?] = NSScreen.screens.isEmpty ? [nil] : NSScreen.screens
        for screen in screens {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .resizable]
            // Never a tab of another test's window, whose size it would take (`withAppWindow`).
            window.tabbingMode = .disallowed
            window.appearance = NSAppearance(named: .aqua)
            window.setContentSize(size)
            if let area = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: area.minX + 80, y: area.minY + 80))
            }
            window.orderFront(nil)
            let cover = covering(window)
            defer {
                cover.close()
                window.close()
            }
            try await layOut(window)
            // The cover hides the window completely: the window server reports it as not seen at all (a window it
            // does not hide is reported as seen within the layout pass).
            try await waitUntil(timeout: .seconds(5)) { !window.occlusionState.contains(.visible) }
            try await body(try Picture(of: window))
        }
    }

    /// An ordinary window of the app, opaque and larger than `window` all round, ordered above it: `window` is then
    /// not seen at all.
    private func covering(_ window: NSWindow) -> NSWindow {
        let frame = window.frame.insetBy(dx: -40, dy: -40)
        let cover = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        cover.isReleasedWhenClosed = false
        cover.tabbingMode = .disallowed
        cover.setFrame(frame, display: false)
        cover.order(.above, relativeTo: window.windowNumber)
        return cover
    }

    // MARK: The colours of the cells

    /// Each cell is in the colour of what it shows, as the prototype draws the rows: Číslo, Odběratel and Vystaveno in
    /// the colour of text; Zaplaceno in it for a payment that came, in the grey of notes for one dated after today and
    /// as a dash in the faintest grey without one; V Kč bez DPH in the colour of text for what was received or an
    /// amount in crowns, in secondary grey for an estimate and as a faint dash where the rate is not known; Bez DPH in
    /// secondary grey; Čistý příjem in the green of text for a payment, in secondary grey for an estimate and as a
    /// faint dash without one; and the pill of Stav in the tint of its tone. A search match stands on the yellow of a
    /// highlight, after the client, in the grey of notes. The darkest pixels of a cell's text are its colour: none is
    /// darker, and some are that colour.
    @Test func everyCellTakesTheColourOfWhatItShows() throws {
        // A table wide enough for the match of the search to show after the name of the client.
        let widths = InvoiceTableColumns().columnWidths(inTableOf: 1_300)
        let rows = [dollars, estimated, later, withNetIncome, try found()]
        let picture = try OffscreenPicture(
            of: VStack(spacing: 0) {
                ForEach(rows) { row in
                    InvoiceRowCells(row: row, widths: widths)
                }
            }
            .frame(width: 1_300, alignment: .leading)
            .background(Palette.bgCard),
            in: .light)
        // Five rows of 40 points, which the regions below are measured in.
        try #require(picture.size == CGSize(width: 1_300, height: 200), "the rows are \(picture.size)")
        let green = try OffscreenPicture.bytes(of: Palette.greenText, in: .light)

        /// The region of the cell of `column` in the row `row`, from the top left of the picture.
        func cell(_ column: Int, ofRow row: Int) -> CGRect {
            let x = DataTableMetrics.margin + widths[..<column].reduce(0, +) + CGFloat(column) * DataTableMetrics.gap
            return CGRect(x: x, y: CGFloat(row) * 40 + 4, width: widths[column], height: 32)
        }
        /// What is wrong with the colour of the text in `region`, which is not one of the colours of text: a pixel
        /// darker than `colour`, or none of it.
        func problems(of region: CGRect, in colour: [Int], _ name: String) -> [String] {
            var found: [String] = []
            if picture.count(near: colour, in: region, by: 12) == 0 {
                found.append("\(name) has no pixel of \(colour)")
            }
            let darker = picture.count(darkerThan: colour, in: region, by: 16)
            if darker > 0 {
                found.append("\(name) has \(darker) pixels darker than \(colour)")
            }
            return found
        }
        /// What is wrong with the text in `region`, which `token` is the colour of: it is not set in it, with `least`
        /// pixels of it as the real window gives (`expectText`), or a pixel is darker than it.
        func expectCell(_ region: CGRect, in token: Color, atLeast least: Int, _ name: String) throws {
            try picture.expectText(in: region, setIn: token, atLeast: least, scheme: .light, name)
            let colour = try OffscreenPicture.bytes(of: token, in: .light)
            let darker = picture.count(darkerThan: colour, in: region, by: 16)
            #expect(darker == 0, "\(name) has \(darker) pixels darker than \(colour)")
        }

        // The paid invoice in dollars: everything in the colour of text but Bez DPH, and no net income.
        try expectCell(cell(0, ofRow: 0), in: Palette.text, atLeast: 250, "the number")
        try expectCell(cell(1, ofRow: 0), in: Palette.text, atLeast: 190, "the client")
        try expectCell(cell(2, ofRow: 0), in: Palette.text, atLeast: 65, "the day of issue")
        try expectCell(cell(3, ofRow: 0), in: Palette.text, atLeast: 55, "the day of the payment")
        try expectCell(cell(4, ofRow: 0), in: Palette.text, atLeast: 190, "what the payment brought")
        try expectCell(cell(5, ofRow: 0), in: Palette.text2, atLeast: 220, "the amount in dollars")
        try expectCell(cell(6, ofRow: 0), in: Palette.text4, atLeast: 20, "the dash for no net income")
        // The draft: no payment, the estimates in secondary grey.
        try expectCell(cell(3, ofRow: 1), in: Palette.text4, atLeast: 6, "the dash for no payment")
        try expectCell(cell(4, ofRow: 1), in: Palette.text2, atLeast: 235, "the estimate in crowns")
        try expectCell(cell(6, ofRow: 1), in: Palette.text2, atLeast: 270, "the estimated net income")
        // A payment dated after today, and a rate that is not known.
        try expectCell(cell(3, ofRow: 2), in: Palette.text3, atLeast: 90, "the day of a later payment")
        try expectCell(cell(4, ofRow: 2), in: Palette.text4, atLeast: 6, "the dash for a rate not known")
        // A paid invoice in crowns with its net income, in the green of text, which is not one of the colours of text.
        try expectCell(cell(4, ofRow: 3), in: Palette.text, atLeast: 220, "the amount in crowns")
        let net = problems(of: cell(6, ofRow: 3), in: green, "the net income of a payment")
        #expect(net.isEmpty, "\(net)")

        // The pills: green for paid, grey for a draft, red for overdue.
        let pills: [(row: Int, tint: Color)] = [(0, Palette.greenTint), (1, Palette.fill), (2, Palette.redTint)]
        for pill in pills {
            let tint = try OffscreenPicture.bytes(of: pill.tint, in: .light)
            #expect(picture.count(near: tint, in: cell(7, ofRow: pill.row), by: 2) > 100, "the pill of row \(pill.row)")
        }
        // The match of the search, on the yellow of a highlight, in the cell of the client after the name.
        let highlight = try OffscreenPicture.bytes(of: Palette.highlight, in: .light)
        #expect(picture.count(near: highlight, in: cell(1, ofRow: 4), by: 2) > 20)
        #expect(picture.count(near: highlight, in: cell(1, ofRow: 0), by: 2) == 0)
    }

    // MARK: The least widths of the columns

    /// Číslo holds both forms of the numbers in use, and the columns of amounts hold 999 999,99 with its currency: in
    /// crowns and as an estimate in crowns in V Kč bez DPH, in crowns and in the currencies in use in Bez DPH. Čistý
    /// příjem holds 999 999 Kč with the sign of an estimate, set as each kind of net income is. Vystaveno and Zaplaceno
    /// hold a date of the year shown, and a date of another year once they are widened for it. Stav holds the widest
    /// pill of the list. Every column holds its name. Each is measured as the table shows it, so that the table at its
    /// least width, as in the least window, shows none of them cut short.
    @Test func theLeastWidthOfAColumnHoldsTheWidestNumberAmountDateOrPillOfItsCellsWhole() {
        let columns = InvoiceTableColumns()
        let least = columns.widths.map(\.minimum)
        var found: [String] = []
        func check(_ needed: CGFloat, _ what: String, column: Int, in widths: [CGFloat] = least) {
            if needed > widths[column] {
                found.append("\(what) needs \(needed) points, column \(column) has \(widths[column])")
            }
        }

        for number in ["2026-05-01", "20260901"] {
            check(width(of: InvoiceNumberText(number: number)), number, column: 0)
        }
        let largest = { (currency: CurrencyCode) in CzechFormat.money(Money(minor: 99_999_999, currency: currency)) }
        for amount in [largest(.czk), "≈ " + largest(.czk)] {
            check(width(of: InvoiceAmountText(amount: amount)), amount, column: 4)
        }
        let currencies = [CurrencyCode.czk, .usd, .eur] + ["GBP", "CHF", "AUD", "NOK"].compactMap { CurrencyCode($0) }
        for currency in currencies {
            check(width(of: InvoiceAmountText(amount: largest(currency))), largest(currency), column: 5)
        }
        let netIncome = "≈\u{00A0}999\u{00A0}999\u{00A0}Kč"
        for kind in [NetIncomeKind.paid, .estimate, .none] {
            check(width(of: InvoiceNetIncomeText(text: netIncome, kind: kind)), "\(netIncome) as \(kind)", column: 6)
        }
        for column in [2, 3] {
            check(width(of: InvoiceDateText(text: "31.\u{00A0}12.")), "31. 12.", column: column)
        }
        let withYears = InvoiceTableColumns(issueDatesShowYear: true, paymentDatesShowYear: true).widths.map(\.minimum)
        for column in [2, 3] {
            let date = "28.\u{00A0}12.\u{00A0}2026"
            check(width(of: InvoiceDateText(text: date)), date, column: column, in: withYears)
        }
        let statuses: [InvoiceDisplayStatus] = [
            .draft, .awaitingPayment, .overdue, .paid(civilDate("2026-12-15")), .needsReview("Zrušeno"),
        ]
        for status in statuses {
            check(width(of: Pill(status.listLabel, tone: status.pillTone)), status.listLabel, column: 7)
        }
        let names = [
            "Číslo", "Odběratel", "Vystaveno", "Zaplaceno", "V Kč bez DPH", "Bez DPH", "Čistý příjem", "Stav",
        ]
        for (column, name) in names.enumerated() {
            check(width(of: InvoiceColumnTitle(title: LocalizedStringKey(name))), name, column: column)
        }
        #expect(found.isEmpty, "\(found)")
    }

    /// The width `view` asks for to show itself whole, on one line.
    private func width<Content: View>(of view: Content) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
    }

    // MARK: What VoiceOver reads

    @Test func aRowIsReadWithTheNamesOfItsColumns() {
        // V Kč bez DPH of an invoice in crowns repeats Bez DPH, so it is read once.
        let expected =
            "20261001, Cetus Data s.r.o., Vystaveno 1.\u{00A0}10.,"
            + " Bez DPH 4\u{00A0}500,00\u{00A0}Kč, Stav: Čeká na platbu"
        #expect(crowns.spokenText == expected)
    }

    @Test func aColumnThatIsEmptyForTheInvoiceIsNotRead() {
        // No net income, so no Čistý příjem; the value in crowns before the amount in dollars, as the columns stand.
        let expected =
            "20260901, Bravo Labs, Inc., Vystaveno 30.\u{00A0}9., Zaplaceno 2.\u{00A0}10.,"
            + " V Kč bez DPH 305\u{00A0}726,75\u{00A0}Kč, Bez DPH 14\u{00A0}350,00\u{00A0}USD, Stav: Uhrazená"
        #expect(dollars.spokenText == expected)
    }

    @Test func whyTheSearchFoundTheInvoiceIsReadAfterTheClient() throws {
        let expected =
            "2026-03-01, Alfa Systems s.r.o., Poznámka: …Routing number…, Vystaveno 31.\u{00A0}3.,"
            + " Zaplaceno 7.\u{00A0}4., Bez DPH 210\u{00A0}000,00\u{00A0}Kč, Stav: Uhrazená"
        #expect(try found().spokenText == expected)
    }

    @Test func aRowIsReadWithItsNetIncome() {
        // A payment: the net income, after the amounts.
        let paid =
            "2026-01-01, Sierra, SE, Vystaveno 31.\u{00A0}1., Zaplaceno 3.\u{00A0}2.,"
            + " Bez DPH 220\u{00A0}000,00\u{00A0}Kč, Čistý příjem 253\u{00A0}401\u{00A0}Kč, Stav: Uhrazená"
        #expect(withNetIncome.spokenText == paid)

        // An estimate is read with its sign.
        let estimate =
            "20261001, Bravo Labs, Inc., Vystaveno 31.\u{00A0}10., V Kč bez DPH ≈ 260\u{00A0}328,88\u{00A0}Kč,"
            + " Bez DPH 12\u{00A0}040,00\u{00A0}USD, Čistý příjem ≈\u{00A0}159\u{00A0}636\u{00A0}Kč, Stav: Koncept"
        #expect(estimated.spokenText == estimate)
    }

    @Test func aPaymentOfAnotherYearIsReadWithItsYear() {
        // The date of the payment is read as the column shows it, with the year of another year than the one shown.
        var row = dollars
        row.paidDate = "2.\u{00A0}1.\u{00A0}2026"
        #expect(row.spokenText.contains("Zaplaceno 2.\u{00A0}1.\u{00A0}2026,"))
        #expect(row.spokenText.hasSuffix("Stav: Uhrazená"))
    }
}

/// What a window shows, as a picture of its content, which is drawn from the top left. The content view draws itself
/// into a bitmap of ours, in sRGB at 2 pixels to the point, and never into the one that AppKit makes for a window
/// (`bitmapImageRepForCachingDisplay`): that one is in the colour space of the screen the window is on, and a screen
/// whose profile cannot hold a colour gives back another one (the blue of the edge of the open row came back 16 too
/// red from a Dell P2415Q).
@MainActor
private struct Picture {
    private let bitmap: NSBitmapImageRep
    private let scale: CGFloat = 2

    /// The name of the screen the window was on, for what a failure says.
    let screen: String

    init(of window: NSWindow) throws {
        screen = window.screen?.localizedName ?? "no screen"
        let view = try #require(window.contentView)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int((view.bounds.width * scale).rounded()),
                height: Int((view.bounds.height * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    /// The colour at `point`, in points from the top left of the content of the window, as its sRGB bytes: red, green
    /// and blue.
    func bytes(at point: CGPoint) throws -> [Int] {
        try #require(bytesIfAny(at: point), "no colour at \(point)")
    }

    /// The colour at `point` as its sRGB bytes, or nil outside the picture. The bitmap gives the colour of a pixel in
    /// a calibrated space of no screen, though it holds it in its own space, sRGB, so the colour is read in that space
    /// before it is turned into sRGB.
    private func bytesIfAny(at point: CGPoint) -> [Int]? {
        guard let pixel = bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)) else { return nil }
        var components = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent, pixel.alphaComponent]
        let drawn = NSColor(colorSpace: bitmap.colorSpace, components: &components, count: components.count)
        guard let color = drawn.usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    /// The bands down the column `x`, between `top` and `bottom`, whose colour `matches`: each from its first point
    /// to the point after its last, in points from the top.
    func bands(
        atX x: CGFloat, from top: CGFloat, to bottom: CGFloat, where matches: ([Int]) -> Bool
    ) -> [Range<CGFloat>] {
        var bands: [Range<CGFloat>] = []
        var start: CGFloat?
        for row in Int(top * scale)..<Int(bottom * scale) {
            let y = CGFloat(row) / scale
            let inBand = bytesIfAny(at: CGPoint(x: x, y: y)).map(matches) ?? false
            if inBand, start == nil {
                start = y
            } else if !inBand, let first = start {
                bands.append(first..<y)
                start = nil
            }
        }
        if let first = start {
            bands.append(first..<bottom)
        }
        return bands
    }
}

/// Whether the sRGB bytes `found` are those of `expected`, to 4 of 255 in each.
private func isClose(_ found: [Int], to expected: [Int]) -> Bool {
    found.count == expected.count && zip(found, expected).allSatisfy { abs($0 - $1) <= 4 }
}
