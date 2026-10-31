import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The card of the detail of an invoice on its own, in a window: its header and its buttons for each state of an
/// invoice, its size, the parts that stand on the tokens of the design, and the row "Čistý příjem", which is in the
/// grey box of the payment, under the day and the amount received, and is there exactly when the section "Dopad na
/// odvody" is. The tests read the card as VoiceOver does, through the accessibility tree, and take a picture of its
/// window where they look at colours. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized)
@MainActor
struct InvoiceDetailCardTests {
    // MARK: Helpers

    /// What the payment of the first invoice of the prediction sample adds to the levies: the invoice of 220 000,00 Kč
    /// is paid on 3. 2. 2026, and the payment brings the tax bonus, so the tax falls by 37 524 Kč and the social
    /// insurance rises by 4 123 Kč.
    private let levies = ReceiptEffect(
        receipt: Receipt(day: civilDate("2026-02-03"), czkNetHalere: 22_000_000, czkVatHalere: 0, source: .invoice(1)),
        tax: -37_524, social: 4_123, health: 0, total: -33_401)

    /// What a payment of 4 500,00 Kč adds to the levies of its year, 1 702 Kč.
    private func effect(on day: String) -> ReceiptEffect {
        ReceiptEffect(
            receipt: Receipt(day: civilDate(day), czkNetHalere: 450_000, czkVatHalere: 94_500, source: .invoice(1)),
            tax: 675, social: 723, health: 304, total: 1_702)
    }

    /// The detail of that invoice as the builder makes it, with `paymentEffect` for what the payment adds to the levies
    /// when it is known.
    private func detail(paymentEffect: ReceiptEffect?) -> InvoiceDetail {
        var invoice = Invoice.fixture(
            number: "2026-01-01", duzp: "2026-01-31", dueDate: "2026-02-15", items: [.fixture("1", at: 22_000_000)],
            vatMode: .none, payment: .fixture(on: "2026-02-03", net: 22_000_000, vat: 0))
        invoice.id = 1
        return InvoiceDetailBuilder.build(
            InvoiceDetailInput(
                invoice: invoice, asOf: civilDate("2026-10-17"), statusDay: civilDate("2026-10-17"), duzpRate: nil,
                paymentEffect: paymentEffect, estimate: nil))
    }

    /// The detail of `invoice` as the builder makes it for today, 17. 10. 2026, with what the payment adds to the
    /// levies or what a payment would add where there is one.
    private func detail(
        of invoice: Invoice, paymentEffect: ReceiptEffect? = nil, estimate: LevyEstimate? = nil
    ) -> InvoiceDetail {
        InvoiceDetailBuilder.build(
            InvoiceDetailInput(
                invoice: invoice, asOf: civilDate("2026-10-17"), statusDay: civilDate("2026-10-17"), duzpRate: nil,
                paymentEffect: paymentEffect, estimate: estimate))
    }

    /// The names of the buttons of a card that were pressed, in the order they were.
    @MainActor
    final class Presses {
        var names: [String] = []
    }

    /// The card of `detail`, with buttons that do nothing, or that record the name of what they do in `presses`.
    private func card(of detail: InvoiceDetail, presses: Presses = Presses()) -> InvoiceDetailCard {
        InvoiceDetailCard(
            detail: detail, close: { presses.names.append("close") }, pay: { presses.names.append("pay") },
            issue: { presses.names.append("issue") }, edit: { presses.names.append("edit") },
            showPDF: { presses.names.append("showPDF") }, delete: { presses.names.append("delete") })
    }

    /// The states of an invoice that the buttons of the detail depend on.
    enum State: CaseIterable, Sendable {
        case draft, unpaid, paid, paidAfterToday, unpaidToCheck, paidToCheck
    }

    /// An invoice of the fixtures in `state`, as of today, 17. 10. 2026.
    private func invoice(in state: State) -> Invoice {
        var invoice: Invoice
        switch state {
        case .draft:
            invoice = Invoice.fixture(dueDate: "2026-10-30", status: .draft)
        case .unpaid:
            invoice = Invoice.fixture(dueDate: "2026-10-30")
        case .paid:
            invoice = Invoice.fixture(payment: .fixture(on: "2026-10-15"))
        case .paidAfterToday:
            invoice = Invoice.fixture(dueDate: "2026-10-30", payment: .fixture(on: "2026-10-20"))
        case .unpaidToCheck:
            invoice = Invoice.fixture(dueDate: "2026-10-30", review: ReviewFlag(reason: "záporná částka"))
        case .paidToCheck:
            invoice = Invoice.fixture(
                review: ReviewFlag(reason: "zrušeno ve Fakturoidu"), payment: .fixture(on: "2026-10-15"))
        }
        invoice.id = 1
        return invoice
    }

    /// The names of the buttons that can stand under the header, which each card has some of.
    private static let actionNames = [
        "Označit jako uhrazenou", "Vystavit", "Upravit", "Upravit platbu", "Zobrazit PDF",
    ]

    /// What each button does, by its name: the button that marks an invoice paid and the one that changes its payment
    /// both open the payment.
    private static let actionOf = [
        "Označit jako uhrazenou": "pay", "Vystavit": "issue", "Upravit": "edit", "Upravit platbu": "pay",
        "Zobrazit PDF": "showPDF",
    ]

    /// Whether `second` stands after `first` in the order of reading: on a row below it, or after it on the same row.
    /// The frames are in the coordinates of the screen, whose origin is at the bottom left.
    private func reads(_ second: CGRect, after first: CGRect) -> Bool {
        second.maxY <= first.minY + 0.5 || (abs(second.midY - first.midY) < 1 && second.minX >= first.maxX)
    }

    /// The frame of the card in `window`, in the coordinates of the screen: the element VoiceOver reads as "Detail
    /// faktury".
    private func cardFrame(in window: NSWindow) -> CGRect? {
        accessibilityElement(labelled: "Detail faktury", in: window)?.accessibilityFrame?()
    }

    /// The first scroll view of AppKit in `window`, the one the card scrolls its content in.
    private func scrollView(in window: NSWindow) -> NSScrollView? {
        func first(under view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            return view.subviews.lazy.compactMap { first(under: $0) }.first
        }
        return window.contentView.flatMap { first(under: $0) }
    }

    // MARK: The buttons

    /// Each state of an invoice has the buttons of the design, in its order, and no other: a draft is issued, edited
    /// and shown as a PDF; an invoice that waits for its payment is marked paid, edited and shown; one that has a
    /// payment has the payment changed and is shown, and "Upravit" is not there at all, not even disabled, as a paid
    /// invoice is not edited, only its payment (also when the payment is dated after today). An invoice to check keeps
    /// the buttons of its state, without a change of its payment. Every button is a capsule 28 points high that does
    /// its action, and "Smazat fakturu…" is there in each state.
    @Test(
        arguments: [
            (State.draft, ["Vystavit", "Upravit", "Zobrazit PDF"]),
            (State.unpaid, ["Označit jako uhrazenou", "Upravit", "Zobrazit PDF"]),
            (State.paid, ["Upravit platbu", "Zobrazit PDF"]),
            (State.paidAfterToday, ["Upravit platbu", "Zobrazit PDF"]),
            (State.unpaidToCheck, ["Označit jako uhrazenou", "Upravit", "Zobrazit PDF"]),
            (State.paidToCheck, ["Zobrazit PDF"]),
        ] as [(State, [String])])
    func eachStateOffersItsButtonsInTheOrderOfTheDesign(state: State, offered: [String]) async throws {
        let presses = Presses()
        let detail = detail(of: invoice(in: state))

        try await withHostedView(
            card(of: detail, presses: presses), size: CGSize(width: 400, height: 1_000)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zobrazit PDF", in: window) != nil }

                let present = Self.actionNames.filter { accessibilityButton(labelled: $0, in: window) != nil }
                #expect(Set(present) == Set(offered), "\(state) has \(present), not \(offered)")
                let frames = try offered.map { name in
                    try #require(accessibilityButton(labelled: name, in: window)?.accessibilityFrame?(), "No \(name)")
                }
                for (name, frame) in zip(offered, frames) {
                    #expect(abs(frame.height - 28) < 0.5, "\(name) is \(frame.height) points high")
                    #expect(
                        accessibilityButton(labelled: name, in: window)?.isAccessibilityEnabled?() != false,
                        "\(name) is disabled")
                }
                for index in frames.indices.dropFirst() {
                    #expect(
                        reads(frames[index], after: frames[index - 1]),
                        "\(offered[index]) does not follow \(offered[index - 1]): \(frames)")
                }

                for name in offered {
                    let button = try #require(accessibilityButton(labelled: name, in: window))
                    #expect(button.accessibilityPerformPress?() == true, "\(name) cannot be pressed")
                    #expect(presses.names.last == Self.actionOf[name], "\(name) does \(presses.names)")
                }
                let delete = try #require(accessibilityButton(labelled: "Smazat fakturu…", in: window))
                #expect(delete.accessibilityPerformPress?() == true)
                #expect(presses.names.last == "delete")
            }
        }
    }

    // MARK: The header

    /// The header says the number as the title, then the status in a pill that keeps the day of the payment, and ends
    /// with the ✕ that closes the detail. The card is one group, "Detail faktury", and the pill reads as its words.
    @Test func theHeaderHoldsTheNumberThePillWithTheDayAndTheButtonThatCloses() async throws {
        let presses = Presses()
        let detail = detail(paymentEffect: levies)
        #expect(detail.statusLabel == "Uhrazená 3.\u{00A0}2.")

        try await withHostedView(
            card(of: detail, presses: presses), size: CGSize(width: 400, height: 1_000)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "Detail faktury", in: window) != nil }

                let group = try #require(accessibilityElement(labelled: "Detail faktury", in: window))
                let readings = accessibilityReadings(under: group)
                #expect(readings.contains("2026-01-01"), "read as \(readings)")
                #expect(readings.contains("Uhrazená 3.\u{00A0}2."), "read as \(readings)")
                let close = try #require(accessibilityButton(labelled: "Zavřít detail", in: window))
                #expect(close.accessibilityPerformPress?() == true)
                #expect(presses.names == ["close"])
            }
        }
    }

    // MARK: The size

    /// The frame of the card in `window`, and the frame of its button Smazat fakturu…, in the coordinates of the
    /// screen, once the card is there.
    private func cardAndDeleteButton(in window: NSWindow) async throws -> (card: CGRect, delete: CGRect) {
        try await waitUntil { cardFrame(in: window) != nil }
        let card = try #require(cardFrame(in: window))
        let delete = try #require(
            accessibilityButton(labelled: "Smazat fakturu…", in: window)?.accessibilityFrame?(), "No Smazat fakturu…")
        return (card, delete)
    }

    /// The card is 300 points wide, as the design's panel beside a table is, and as high as its content where that fits
    /// in the room it is given, as the prototype's panel is: it is no higher in a room of 1 000 points than in one of
    /// 900, and ends 20 points under its last button, Smazat fakturu…, with the room under it left empty.
    @Test func theCardIs300PointsWideAndAsHighAsItsContentWhereThatFitsInTheRoom() async throws {
        let detail = detail(paymentEffect: levies)
        var heights: [CGFloat] = []

        for room in [900.0, 1_000.0] {
            try await withHostedView(card(of: detail), size: CGSize(width: 400, height: room)) { window in
                try await withAccessibilityElements {
                    let (frame, delete) = try await cardAndDeleteButton(in: window)

                    #expect(abs(frame.width - 300) < 0.5, "\(frame)")
                    #expect(frame.height < room - 100, "\(frame) in a room of \(room)")
                    #expect(abs(delete.minY - frame.minY - 20) < 1.5, "\(delete) in \(frame)")
                    heights.append(frame.height)
                }
            }
        }
        #expect(heights.count == 2 && abs(heights[0] - heights[1]) < 0.5, "\(heights)")
    }

    /// A card in a room lower than its content keeps the height of the room, and what does not fit in it scrolls: the
    /// content is higher than the part of it that the card shows. In a room that holds the whole content the card is as
    /// high as its content, which ends 20 points under its last button, and there is nothing to scroll.
    @Test func aCardHigherThanItsRoomKeepsTheHeightOfTheRoomAndScrollsItsContent() async throws {
        let detail = detail(of: invoice(in: .paid), paymentEffect: effect(on: "2026-10-15"))

        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 420)) { window in
            try await withAccessibilityElements {
                try await waitUntil { cardFrame(in: window) != nil }

                let frame = try #require(cardFrame(in: window))
                let scrolled = try #require(scrollView(in: window))
                let content = try #require(scrolled.documentView)
                #expect(abs(frame.height - 420) < 1, "\(frame)")
                #expect(content.frame.height > scrolled.contentView.bounds.height + 100, "\(content.frame)")
            }
        }
        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 1_000)) { window in
            try await withAccessibilityElements {
                let (frame, delete) = try await cardAndDeleteButton(in: window)

                let scrolled = scrollView(in: window)
                let overflow = (scrolled?.documentView?.frame.height ?? 0) - (scrolled?.contentView.bounds.height ?? 0)
                #expect(frame.height < 900, "\(frame)")
                #expect(abs(delete.minY - frame.minY - 20) < 1.5, "\(delete) in \(frame)")
                #expect(overflow <= 0.5, "The card scrolls \(overflow) points")
            }
        }
    }

    // MARK: The tokens

    /// Shows the card of `detail` in a window of `scheme`, 300 points wide as the card is, and gives `body` a picture
    /// of it. The picture is of the window, as a scroll view, in which the card keeps its content, is not drawn by
    /// `ImageRenderer`.
    private func withPictureOfTheCard(
        of detail: InvoiceDetail, in scheme: ColorScheme, _ body: (OffscreenPicture) async throws -> Void
    ) async throws {
        try await withHostedView(card(of: detail), size: CGSize(width: 300, height: 1_000)) { window in
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            try await layOut(window)
            try await body(try OffscreenPicture(of: window))
        }
    }

    /// The payment of an invoice is in a box on the inset background, with the net income in the green of text; the
    /// button that deletes the invoice is a red capsule 28 points high with its words in the red of text. In a light
    /// and in a dark window.
    @Test func thePaymentBoxAndTheDeleteButtonStandOnTheTokensOfTheDesign() async throws {
        let detail = detail(of: invoice(in: .paid), paymentEffect: effect(on: "2026-10-15"))
        for scheme in [ColorScheme.light, .dark] {
            try await withPictureOfTheCard(of: detail, in: scheme) { picture in
                let whole = CGRect(origin: .zero, size: picture.size)
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                let green = try OffscreenPicture.bytes(of: Palette.greenText, in: scheme)
                let tint = try OffscreenPicture.bytes(of: Palette.redTint, in: scheme)
                let red = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)

                // A line across the box that no text is on: 220 points of the colour of the inset background.
                #expect(
                    !picture.rows(near: inset, from: 40, to: 260, by: 1).isEmpty,
                    "\(scheme): the box of the payment is not on the inset background")
                #expect(picture.count(near: green, in: whole, by: 2) > 10, "\(scheme): the net income is not green")
                let capsule = try #require(picture.extent(near: tint, by: 1), "\(scheme): no red capsule")
                #expect(abs(capsule.height - 28) <= 1, "\(scheme): the capsule is \(capsule.height) points high")
                #expect(picture.count(near: red, in: capsule, by: 2) > 10, "\(scheme): the words are not red")
            }
        }
    }

    /// The button that marks an invoice paid is an accent capsule 28 points high, and the note of what a payment would
    /// add is the shared note: a box on the orange tint with an icon in the orange of attention. In a light and in a
    /// dark window.
    @Test func theMainButtonAndTheEstimateStandOnTheTokensOfTheDesign() async throws {
        let estimate = LevyEstimate(
            day: civilDate("2026-10-30"), incomeHalere: 450_000, effect: effect(on: "2026-10-30"))
        let detail = detail(of: invoice(in: .unpaid), estimate: estimate)
        #expect(detail.estimate != nil)
        for scheme in [ColorScheme.light, .dark] {
            try await withPictureOfTheCard(of: detail, in: scheme) { picture in
                let whole = CGRect(origin: .zero, size: picture.size)
                let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)
                let orange = try OffscreenPicture.bytes(of: Palette.orange, in: scheme)

                let button = try #require(picture.extent(near: accent, by: 1), "\(scheme): no accent capsule")
                #expect(abs(button.height - 28) <= 1, "\(scheme): the capsule is \(button.height) points high")
                #expect(!picture.rows(near: tint, from: 40, to: 260, by: 1).isEmpty, "\(scheme): the note has no tint")
                #expect(picture.count(near: orange, in: whole, by: 2) > 5, "\(scheme): the icon is not orange")
            }
        }
    }

    /// The note that an invoice is to check is the shared note too, on the orange tint.
    @Test func theNoteOfAnInvoiceToCheckStandsOnTheOrangeTint() async throws {
        let detail = detail(of: invoice(in: .unpaidToCheck))
        #expect(detail.reviewNote != nil)
        for scheme in [ColorScheme.light, .dark] {
            try await withPictureOfTheCard(of: detail, in: scheme) { picture in
                let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)

                #expect(!picture.rows(near: tint, from: 40, to: 260, by: 1).isEmpty, "\(scheme): the note has no tint")
            }
        }
    }

    // MARK: The right column of the payment box

    /// The right column of the box of the payment is aligned to the right, as the prototype sets it: the amount in
    /// crowns, "příjem pro daň" and the net income end at one edge, the right edge of the content of the box (12 points
    /// inside the box, which is 20 points inside the card), and without the net income the first two do. The edge of
    /// each cell is that of the pixels of its colour in the box: the amount is in the colour of text, the label in the
    /// secondary grey and the net income in the green of text, and no other text of the box reaches so far to the
    /// right. In a light and in a dark window.
    @Test(arguments: [true, false])
    func theRightColumnOfThePaymentBoxEndsAtOneEdge(withTheNetIncome: Bool) async throws {
        let detail = detail(
            of: invoice(in: .paid), paymentEffect: withTheNetIncome ? effect(on: "2026-10-15") : nil)
        for scheme in [ColorScheme.light, .dark] {
            try await withPictureOfTheCard(of: detail, in: scheme) { picture in
                let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
                // The box, from the first to the last of the rows across it that no text is on.
                let rows = picture.rows(near: inset, from: 40, to: 260, by: 1)
                let top = try #require(rows.min(), "\(scheme): no box")
                let bottom = try #require(rows.max(), "\(scheme): no box")
                let box = CGRect(x: 20, y: top, width: 260, height: bottom - top)

                var cells: [(name: String, colour: Color)] = [
                    ("the amount", Palette.text), ("příjem pro daň", Palette.text2),
                ]
                if withTheNetIncome {
                    cells.append(("the net income", Palette.greenText))
                }
                var edges: [String: CGFloat] = [:]
                for cell in cells {
                    let colour = try OffscreenPicture.bytes(of: cell.colour, in: scheme)
                    let found = try #require(
                        picture.extent(near: colour, in: box, by: 2), "\(scheme): no \(cell.name) in the box")
                    edges[cell.name] = found.maxX
                }
                for (name, edge) in edges {
                    #expect(abs(edge - 268) <= 2, "\(scheme): \(name) ends at \(edge), not at 268 (\(edges))")
                }
            }
        }
    }

    // MARK: The note that the payment is dated later

    /// A payment dated after today says so in a line of orange text, in the section of the payment under its box and
    /// before the section of the levies, as the prototype draws it: not in a box of a note.
    @Test func theNoteThatThePaymentIsDatedLaterIsALineOfOrangeTextUnderTheBox() async throws {
        let detail = detail(of: invoice(in: .paidAfterToday), paymentEffect: effect(on: "2026-10-20"))
        let note = "Platba má datum po dnešku – do příjmů se započítá až ten den."
        #expect(detail.payment?.laterNote == note)

        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 1_000)) { window in
            try await withAccessibilityElements {
                try await waitUntil { showsText(note, in: window) }

                let readings = accessibilityReadings(in: window)
                let box = try #require(readings.firstIndex { $0.contains("Čistý příjem") }, "read as \(readings)")
                let line = try #require(readings.firstIndex(of: note), "read as \(readings)")
                let levies = try #require(readings.firstIndex(of: "Dopad na odvody 2026"), "read as \(readings)")
                #expect(box < line && line < levies, "read as \(readings)")
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            try await withPictureOfTheCard(of: detail, in: scheme) { picture in
                let whole = CGRect(origin: .zero, size: picture.size)
                let text = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)
                let tint = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)

                #expect(picture.count(near: text, in: whole, by: 2) > 10, "\(scheme): the line is not in orange text")
                #expect(picture.rows(near: tint, from: 40, to: 260, by: 1).isEmpty, "\(scheme): the line is in a box")
            }
        }
    }

    // MARK: The row of the net income

    /// The box of the payment is one element for VoiceOver (it combines what is in it), so the row is in the box when
    /// the one reading holds the day and the amount of the payment, the words "Čistý příjem" and the net.
    @Test func theRowOfTheNetIncomeIsInThePaymentBox() async throws {
        let detail = detail(paymentEffect: levies)
        let payment = try #require(detail.payment)
        #expect(payment.netIncome == "253\u{00A0}401\u{00A0}Kč")

        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 1_000)) { window in
            try await withAccessibilityElements {
                let netIncome = "253\u{00A0}401\u{00A0}Kč"
                try await waitUntil {
                    accessibilityReadings(in: window).contains { $0.contains("Čistý příjem") && $0.contains(netIncome) }
                }

                let box = try #require(
                    accessibilityReadings(in: window).first { $0.contains("Čistý příjem") && $0.contains(netIncome) })
                #expect(box.contains(payment.line))
                #expect(box.contains(payment.crowns))
                // The section of the levies is an element of its own, not a part of the box.
                #expect(!box.contains("Dopad na odvody"))
            }
        }
    }

    /// A payment whose effect is not known has no section of the levies, and no row of the net income either: the box
    /// holds the payment alone.
    @Test func aPaymentWithoutItsEffectHasNoRowOfTheNetIncome() async throws {
        let detail = detail(paymentEffect: nil)
        let payment = try #require(detail.payment)
        #expect(payment.netIncome == nil)

        try await withHostedView(card(of: detail), size: CGSize(width: 400, height: 1_000)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityReadings(in: window).contains { $0.contains(payment.line) } }

                let readings = accessibilityReadings(in: window)
                #expect(!readings.contains { $0.contains("Čistý příjem") })
                #expect(!readings.contains { $0.contains("Dopad na odvody") })
            }
        }
    }
}
