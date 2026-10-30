import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The table of Faktury on its own: in a light window the row of the open invoice is tinted pale blue, with a blue edge
/// 3 points wide on its leading side, as the design draws it, and the rows around it are not; what VoiceOver reads for
/// a row names its columns and leaves out a column that is empty for the invoice; and the least width of a column holds
/// the widest number or amount of its cells whole. (The window tests find the rows by what VoiceOver reads and press
/// them; these tests make no accessibility elements.)
@MainActor
struct InvoiceTableViewTests {
    /// The cells are measured in the font they are set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The day the rows are shown as of.
    private let shownDay = civilDate("2026-10-20")

    /// An invoice in crowns that waits for its payment and has no net income.
    private let crowns = InvoiceRow(
        id: 1, number: "20261001", client: "Cetus Data s.r.o.", issued: "1.\u{00A0}10.", paid: nil,
        net: "4\u{00A0}500,00\u{00A0}Kč", czk: "", czkNote: "", hasReceivedPayment: false, netIncome: "—",
        netIncomeNote: "", netIncomeKind: .none, status: .awaitingPayment, excerpt: nil)

    /// An invoice in dollars that is paid, with its value in crowns and no net income.
    private let dollars = InvoiceRow(
        id: 2, number: "20260901", client: "Bravo Labs, Inc.", issued: "30.\u{00A0}9.", paid: "2.\u{00A0}10.",
        net: "14\u{00A0}350,00\u{00A0}USD", czk: "305\u{00A0}726,75\u{00A0}Kč",
        czkNote: "ČNB 21,305 · 2.\u{00A0}10.", hasReceivedPayment: true, netIncome: "—", netIncomeNote: "",
        netIncomeKind: .none, status: .paid(civilDate("2026-10-02")), excerpt: nil)

    /// An invoice in crowns that is paid and whose payment reduced the levies, with its net income.
    private let withNetIncome = InvoiceRow(
        id: 4, number: "2026-01-01", client: "Sierra, SE", issued: "31.\u{00A0}1.", paid: "3.\u{00A0}2.",
        net: "220\u{00A0}000,00\u{00A0}Kč", czk: "", czkNote: "", hasReceivedPayment: true,
        netIncome: "253\u{00A0}401\u{00A0}Kč", netIncomeNote: "odvody snížila", netIncomeKind: .paid,
        status: .paid(civilDate("2026-02-03")), excerpt: nil)

    /// A draft in dollars with the estimate of its net income and of its value in crowns.
    private let estimated = InvoiceRow(
        id: 5, number: "20261001", client: "Bravo Labs, Inc.", issued: "31.\u{00A0}10.", paid: nil,
        net: "12\u{00A0}040,00\u{00A0}USD", czk: "≈ 260\u{00A0}328,88\u{00A0}Kč", czkNote: "ČNB k vystavení 21,622",
        hasReceivedPayment: false, netIncome: "≈\u{00A0}159\u{00A0}636\u{00A0}Kč", netIncomeNote: "odhad",
        netIncomeKind: .estimate, status: .draft, excerpt: nil)

    /// An invoice in crowns that the search found by its note.
    private func found() throws -> InvoiceRow {
        let note = "…Routing number…"
        return InvoiceRow(
            id: 3, number: "2026-03-01", client: "Alfa Systems s.r.o.", issued: "31.\u{00A0}3.", paid: "7.\u{00A0}4.",
            net: "210\u{00A0}000,00\u{00A0}Kč", czk: "", czkNote: "", hasReceivedPayment: true, netIncome: "—",
            netIncomeNote: "", netIncomeKind: .none, status: .paid(civilDate("2026-04-07")),
            excerpt: SearchExcerptResult(
                label: "Poznámka", text: note, highlight: try #require(note.range(of: "Routing"))))
    }

    // MARK: The open row

    @Test func theOpenRowIsTintedPaleBlueWithABlueEdgeOnItsLeadingSide() async throws {
        // The three rows, the middle one open, in a card 20 points inside a light window of 900 × 400 points.
        let table = InvoiceTableView(
            rows: [crowns, dollars, try found()], shownDay: shownDay, openID: dollars.id, emptyText: nil,
            click: { _ in }, move: { _ in })
        try await withPictureOf(table.padding(20), size: CGSize(width: 900, height: 400)) { picture in
            // Down the leading edge of the card, inside the 3 points of the edge of a row: one band of the blue of the
            // edge, as tall as a row.
            let edge: CGFloat = 20 + 1.5
            let bands = picture.bands(atX: edge, from: 20, to: 380) { isClose($0, to: [0x00, 0x71, 0xE3]) }
            #expect(bands.count == 1, "the bands of blue down the edge on \(picture.screen): \(bands)")
            let band = try #require(bands.first)
            #expect((band.upperBound - band.lowerBound - 52).magnitude <= 1.5, "the band \(band) on \(picture.screen)")

            // The tint across the row, in the margin before the first column and in the one after the last.
            let middle = (band.lowerBound + band.upperBound) / 2
            for x in [20 + 10, 880 - 10] as [CGFloat] {
                let tint = try picture.bytes(at: CGPoint(x: x, y: middle))
                #expect(isClose(tint, to: [0xE8, 0xF1, 0xFD]), "the open row at \(x) on \(picture.screen) is \(tint)")
            }

            // The rows above and under it are not open: they have the white of the card, at their edge too.
            for y in [band.lowerBound - 26, band.upperBound + 26] {
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

    // MARK: The least widths of the columns

    /// Číslo holds both forms of the numbers in use, and the columns of amounts hold 999 999,99 with its currency: in
    /// crowns, in dollars and in euros in Bez DPH, and as an estimate in crowns in V Kč. Čistý příjem holds 999 999 Kč
    /// with the sign of an estimate, set as each kind of net income is, and the three lines that go under it.
    /// Vystaveno, Zaplaceno and Čistý příjem hold their names, and V Kč the line under an estimate, "ČNB k vystavení
    /// 21,622". Each is measured as the table shows it, so that the table at its least width, as in the least window,
    /// shows none of them cut short. The line under a payment at the uniform rate, "jednotný kurz 21,840 · 2. 10.", is
    /// longer and may be cut there.
    @Test func theLeastWidthOfAColumnHoldsTheWidestNumberOrAmountOfItsCellsWhole() {
        let columns = InvoiceTableColumns.widths
        for number in ["2026-05-01", "20260901"] {
            let needed = width(of: InvoiceNumberText(number: number))
            #expect(needed <= columns[0].minimum, "\(number) needs \(needed) points, Číslo has \(columns[0].minimum)")
        }
        let largest = [CurrencyCode.czk, CurrencyCode.usd, CurrencyCode.eur].map { currency in
            CzechFormat.money(Money(minor: 99_999_999, currency: currency))
        }
        for amount in largest {
            let needed = width(of: InvoiceAmountText(amount: amount))
            let least = columns[4].minimum
            #expect(needed <= least, "\(amount) needs \(needed) points, Bez DPH has \(least)")
        }
        let estimate = "≈ " + CzechFormat.money(Money(minor: 99_999_999, currency: CurrencyCode.czk))
        let needed = width(of: InvoiceAmountText(amount: estimate))
        #expect(needed <= columns[5].minimum, "\(estimate) needs \(needed) points, V Kč has \(columns[5].minimum)")
        for (index, name) in [(2, "Vystaveno"), (3, "Zaplaceno"), (6, "Čistý příjem")] {
            let title = width(of: InvoiceColumnTitle(title: LocalizedStringKey(name)))
            #expect(title <= columns[index].minimum, "\(name) needs \(title) points, it has \(columns[index].minimum)")
        }
        let caption = "ČNB k vystavení 21,622"
        let line = width(of: InvoiceCaptionText(text: caption))
        #expect(line <= columns[5].minimum, "\(caption) needs \(line) points, V Kč has \(columns[5].minimum)")
        let netIncome = "≈\u{00A0}999\u{00A0}999\u{00A0}Kč"
        for kind in [NetIncomeKind.paid, .estimate, .none] {
            let needed = width(of: InvoiceNetIncomeText(text: netIncome, kind: kind))
            let least = columns[6].minimum
            #expect(needed <= least, "\(netIncome) as \(kind) needs \(needed) points, Čistý příjem has \(least)")
        }
        for note in ["odvody snížila", "odvody 100,0\u{00A0}%", "odhad"] {
            let needed = width(of: InvoiceCaptionText(text: note))
            let least = columns[6].minimum
            #expect(needed <= least, "\(note) needs \(needed) points, Čistý příjem has \(least)")
        }
    }

    /// The width `view` asks for to show itself whole, on one line.
    private func width<Content: View>(of view: Content) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
    }

    // MARK: What VoiceOver reads

    @Test func aRowIsReadWithTheNamesOfItsColumns() {
        let expected =
            "20261001, Cetus Data s.r.o., Vystaveno 1.\u{00A0}10.,"
            + " Bez DPH 4\u{00A0}500,00\u{00A0}Kč, Stav: Čeká na platbu"
        #expect(crowns.spokenText(asOf: shownDay) == expected)
    }

    @Test func aColumnThatIsEmptyForTheInvoiceIsNotRead() {
        // No net income, so no Čistý příjem; the value in crowns with the line under it.
        let expected =
            "20260901, Bravo Labs, Inc., Vystaveno 30.\u{00A0}9., Zaplaceno 2.\u{00A0}10.,"
            + " Bez DPH 14\u{00A0}350,00\u{00A0}USD, V Kč 305\u{00A0}726,75\u{00A0}Kč, ČNB 21,305 · 2.\u{00A0}10.,"
            + " Stav: Uhrazená 2.\u{00A0}10."
        #expect(dollars.spokenText(asOf: shownDay) == expected)
    }

    @Test func whyTheSearchFoundTheInvoiceIsReadAfterTheClient() throws {
        let expected =
            "2026-03-01, Alfa Systems s.r.o., Poznámka: …Routing number…, Vystaveno 31.\u{00A0}3.,"
            + " Zaplaceno 7.\u{00A0}4., Bez DPH 210\u{00A0}000,00\u{00A0}Kč, Stav: Uhrazená 7.\u{00A0}4."
        #expect(try found().spokenText(asOf: shownDay) == expected)
    }

    @Test func aRowIsReadWithItsNetIncome() {
        // A payment: the net income and what the levies took of it, after the value in crowns when there is one.
        let paid =
            "2026-01-01, Sierra, SE, Vystaveno 31.\u{00A0}1., Zaplaceno 3.\u{00A0}2.,"
            + " Bez DPH 220\u{00A0}000,00\u{00A0}Kč, Čistý příjem 253\u{00A0}401\u{00A0}Kč, odvody snížila,"
            + " Stav: Uhrazená 3.\u{00A0}2."
        #expect(withNetIncome.spokenText(asOf: shownDay) == paid)

        // An estimate is read with its sign and says so.
        let estimate =
            "20261001, Bravo Labs, Inc., Vystaveno 31.\u{00A0}10.,"
            + " Bez DPH 12\u{00A0}040,00\u{00A0}USD, V Kč ≈ 260\u{00A0}328,88\u{00A0}Kč, ČNB k vystavení 21,622,"
            + " Čistý příjem ≈\u{00A0}159\u{00A0}636\u{00A0}Kč, odhad, Stav: Koncept"
        #expect(estimated.spokenText(asOf: shownDay) == estimate)
    }

    @Test func aPaymentOfAnotherYearThanTheDayShownIsReadWithItsYear() {
        // The text of the pill, which names the year of a payment of another year than that of the day shown.
        #expect(dollars.spokenText(asOf: civilDate("2025-12-31")).hasSuffix("Stav: Uhrazená 2.\u{00A0}10.\u{00A0}2026"))
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
