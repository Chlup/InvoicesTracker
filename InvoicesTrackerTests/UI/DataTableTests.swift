import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The shared parts of a table in a card and of the panel beside it: the heights of the header and the rows, the
/// summary row on top of the table, the background of a selected row, and the detail panel with its header, its
/// actions, its facts and its figure, and the panel that takes the height it is offered and scrolls.
@Suite(.serialized)
@MainActor
struct DataTableTests {
    /// The frames of the named parts of `view`, hosted in a room of `width` points, and the size the view takes.
    private func frames(of view: some View, width: CGFloat) -> (frames: [String: CGRect], size: CGSize) {
        let hosting = NSHostingView(rootView: view.frame(width: width, alignment: .topLeading))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return (framesOfParts(in: hosting), size)
    }

    // MARK: The table

    @Test func theTableMetricsAreThoseOfTheBoard() {
        #expect(DataTableMetrics.headerHeight == 32)
        #expect(DataTableMetrics.rowHeight == 40)
        #expect(DataTableMetrics.margin == 16)
        #expect(DataTableMetrics.gap == 8)
    }

    @Test func theHeaderIs32AndARowIs40PointsHigh() {
        // The header is a line of text in the style of the header, and a row is a line of text given the height of
        // a row. Each has a part of AppKit behind it, which has the frame of the view it stands behind.
        let table = VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Číslo")
                .tableHeaderStyle()
                .background { LayoutPart(name: "header") }
            Text(verbatim: "x")
                .frame(height: DataTableMetrics.rowHeight)
                .background { LayoutPart(name: "row") }
        }
        let placed = frames(of: table, width: 300)

        #expect(placed.frames["header"]?.height == 32, "laid out as \(placed.frames)")
        #expect(placed.frames["row"]?.height == 40, "laid out as \(placed.frames)")
    }

    @Test func aSelectedRowIsPaleBlueWithAStripeOfTheAccentAtItsLeadingEdge() throws {
        for scheme in [ColorScheme.light, .dark] {
            let row = Color.clear
                .frame(width: 200, height: DataTableMetrics.rowHeight)
                .tableRowBackground(isSelected: true)
                .background(Palette.bgCard)
            let picture = try OffscreenPicture(of: row, in: scheme)
            let tint = try OffscreenPicture.bytes(of: Palette.accentTint, in: scheme)
            let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
            let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
            #expect(tint != card && accent != tint, "\(scheme): the colours are not told apart")

            // The stripe is the first 3 points of the row, in the full height of it, and the tint is the rest.
            for point in [CGPoint(x: 0.5, y: 1), CGPoint(x: 1.5, y: 20), CGPoint(x: 2.5, y: 39)] {
                #expect(picture.bytes(at: point) == accent, "\(scheme): \(point) is not the accent")
            }
            for point in [CGPoint(x: 3.5, y: 1), CGPoint(x: 100, y: 20), CGPoint(x: 199, y: 39)] {
                #expect(picture.bytes(at: point) == tint, "\(scheme): \(point) is not the tint")
            }
        }
    }

    @Test func aRowThatIsNotSelectedHasNoBackgroundOfItsOwn() throws {
        for scheme in [ColorScheme.light, .dark] {
            let row = Color.clear
                .frame(width: 200, height: DataTableMetrics.rowHeight)
                .tableRowBackground(isSelected: false)
                .background(Palette.bgCard)
            let picture = try OffscreenPicture(of: row, in: scheme)
            let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)

            for point in [CGPoint(x: 0.5, y: 20), CGPoint(x: 1.5, y: 20), CGPoint(x: 100, y: 20)] {
                #expect(picture.bytes(at: point) == card, "\(scheme): \(point) is not the card")
            }
        }
    }

    // MARK: The summary row

    /// The summary row of 12 invoices with a total and a rate that is not out yet.
    private func summaryRow() -> some View {
        TableSummaryRow(count: "12\u{00A0}faktur", category: " · všechny stavy") {
            SummaryFigure(label: "Celkem v Kč bez DPH", value: "2\u{00A0}406\u{00A0}342\u{00A0}Kč")
            SummaryFigure(
                label: "Jednotným kurzem 2026", value: "zatím nevyhlášen", help: "GFŘ ho zveřejní v lednu 2027.",
                valueIsMuted: true)
        }
    }

    @Test func aMutedValueIsSetInTertiaryTextAndAFigureInTheColourOfText() throws {
        // Only the value is drawn, as the label is empty. In a dark window the colour of text is lighter than the
        // tertiary one, so no pixel of a muted value is lighter than the tertiary text, and many of a figure are.
        let tertiary = try OffscreenPicture.bytes(of: Palette.text3, in: .dark)
        func lighterPixels(muted: Bool) throws -> Int {
            let figure = SummaryFigure(label: "", value: "Celkem", valueIsMuted: muted)
                .padding(10)
                .background(Palette.bgCard)
            let picture = try OffscreenPicture(of: figure, in: .dark)
            return picture.count(lighterThan: tertiary, in: CGRect(origin: .zero, size: picture.size), by: 12)
        }

        #expect(try lighterPixels(muted: true) == 0)
        #expect(try lighterPixels(muted: false) > 50)
    }

    @Test func aMutedValueIsSetInBodyTextAndSoStandsLowerThanAFigureInTitle3() {
        func height(muted: Bool) -> CGFloat {
            let figure = SummaryFigure(label: "Jednotným kurzem 2026", value: "zatím nevyhlášen", valueIsMuted: muted)
            return frames(of: figure, width: 400).size.height
        }

        #expect(height(muted: true) < height(muted: false))
    }

    @Test func theSummaryRowIsAGroupCalledSouhrn() async throws {
        try await withHostedView(summaryRow().frame(width: 900), size: CGSize(width: 900, height: 160)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "Souhrn", in: window) != nil }
                let group = try #require(accessibilityElement(labelled: "Souhrn", in: window))
                #expect(group.accessibilityRole?() == .group)

                // The count and the category are read as the one line they are, and each figure as one phrase.
                let readings = accessibilityReadings(under: group)
                #expect(readings.contains("12\u{00A0}faktur · všechny stavy"), "read as \(readings)")
                #expect(
                    readings.contains("Celkem v Kč bez DPH, 2\u{00A0}406\u{00A0}342\u{00A0}Kč"), "read as \(readings)")
                #expect(readings.contains("Jednotným kurzem 2026, zatím nevyhlášen"), "read as \(readings)")
            }
        }
    }

    @Test func theSummaryRowPutsItsFiguresAtTheTrailingSideAndUnderTheCountWhereTheRoomIsNarrow() throws {
        let row = TableSummaryRow(count: "12\u{00A0}faktur", category: " · všechny stavy") {
            SummaryFigure(label: "Celkem v Kč bez DPH", value: "2\u{00A0}406\u{00A0}342\u{00A0}Kč")
                .background { LayoutPart(name: "figure") }
        }
        let wide = frames(of: row, width: 700)
        let narrow = frames(of: row, width: 300)
        let besideTheCount = try #require(wide.frames["figure"])
        let underTheCount = try #require(narrow.frames["figure"])

        // Where there is room the figure ends at the margin of the row, on the line of the count. Where there is
        // none it stands under the count, from the margin, and the row is higher by the line of the figure.
        #expect(abs(besideTheCount.maxX - (700 - DataTableMetrics.margin)) < 0.5, "\(besideTheCount)")
        #expect(abs(underTheCount.minX - DataTableMetrics.margin) < 0.5, "\(underTheCount)")
        #expect(underTheCount.minY > besideTheCount.minY + 10, "\(underTheCount) against \(besideTheCount)")
        #expect(narrow.size.height > wide.size.height + 10, "\(narrow.size) against \(wide.size)")
    }

    @Test func theSummaryRowEndsInAHairline() throws {
        for scheme in [ColorScheme.light, .dark] {
            let row = summaryRow().frame(width: 900).background(Palette.bgCard)
            let picture = try OffscreenPicture(of: row, in: scheme)
            let hairline = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
            let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)

            // The last point of the row is the hairline, over the whole width, and the point over it is the card.
            for x in [2, 450, 898] as [CGFloat] {
                #expect(picture.bytes(at: CGPoint(x: x, y: picture.size.height - 0.5)) == hairline, "\(scheme) at \(x)")
                #expect(picture.bytes(at: CGPoint(x: x, y: picture.size.height - 2)) == card, "\(scheme) at \(x)")
            }
        }
    }

    // MARK: The detail panel

    /// How many times the panel of a test was closed.
    @MainActor
    final class Closings {
        var count = 0
    }

    /// A panel with an invoice number for its title, the pill of a paid invoice and three actions, of which the first
    /// two are the long ones, and a line of content.
    private func detailPanel(
        title: String = "20260902", close: @escaping () -> Void = {}, closeLabel: String = "Zavřít detail"
    ) -> some View {
        DetailPanel(title: title, pill: (text: "Uhrazená", tone: PillTone.paid), closeLabel: closeLabel, close: close) {
            Button("Označit jako uhrazenou") {}
                .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
            Button("Upravit") {}
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            Button("Zobrazit PDF") {}
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        } content: {
            Text(verbatim: "Obsah panelu")
        }
    }

    @Test func theDetailPanelClosesFromItsCloseButton() async throws {
        let closings = Closings()
        let panel = detailPanel(close: { closings.count += 1 })

        try await withHostedView(panel.frame(width: 300).padding(24), size: CGSize(width: 348, height: 320)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zavřít detail", in: window) != nil }
                let button = try #require(accessibilityButton(labelled: "Zavřít detail", in: window))
                #expect(closings.count == 0)

                #expect(button.accessibilityPerformPress?() == true)
                try await waitUntil { closings.count == 1 }
            }
        }
    }

    @Test func theCloseButtonOfADetailPanelIsReadUnderTheLabelItIsGiven() async throws {
        let panel = detailPanel(closeLabel: "Zavřít detail odběratele")

        try await withHostedView(panel.frame(width: 300).padding(24), size: CGSize(width: 348, height: 320)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zavřít detail odběratele", in: window) != nil }
                #expect(accessibilityButton(labelled: "Zavřít detail", in: window) == nil)
            }
        }
    }

    @Test func aDetailPanelIsReadAsAGroupUnderItsTitleAndACallerMayRenameIt() async throws {
        try await withHostedView(
            detailPanel().frame(width: 300).padding(24), size: CGSize(width: 348, height: 320)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "20260902", in: window) != nil }
                let group = try #require(accessibilityElement(labelled: "20260902", in: window))
                #expect(group.accessibilityRole?() == .group)
                // The title is the heading in it, and the pill and the content are read inside.
                let readings = accessibilityReadings(under: group)
                #expect(readings.contains("Uhrazená"), "read as \(readings)")
                #expect(readings.contains("Obsah panelu"), "read as \(readings)")
            }
        }

        let renamed = detailPanel().accessibilityLabel("Detail faktury")
        try await withHostedView(
            renamed.frame(width: 300).padding(24), size: CGSize(width: 348, height: 320)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "Detail faktury", in: window) != nil }
                let group = try #require(accessibilityElement(labelled: "Detail faktury", in: window))
                #expect(group.accessibilityRole?() == .group)
            }
        }
    }

    @Test func aLongTitleIsCutBeforeThePillAndTheCloseButtonAreAndTheCloseButtonIs28Points() async throws {
        let title = "Harborlight Software, Inc. a Truhlářství Doubek s.r.o. – velmi dlouhý název odběratele"
        try await withHostedView(
            detailPanel(title: title).frame(width: 300).padding(24), size: CGSize(width: 348, height: 320)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Zavřít detail", in: window) != nil }
                let panel = try #require(accessibilityElement(labelled: title, in: window)?.accessibilityFrame?())
                let close = try #require(
                    accessibilityButton(labelled: "Zavřít detail", in: window)?.accessibilityFrame?())

                // The ✕ is a circle of 28 points at the trailing end of the header, inside the 20 points of padding.
                #expect(abs(close.width - 28) < 0.5 && abs(close.height - 28) < 0.5, "\(close)")
                #expect(abs(close.maxX - (panel.maxX - DesignMetrics.cardPadding)) < 0.5, "\(close) in \(panel)")
                #expect(showsText("Uhrazená", in: window), "The pill is cut")
            }
        }
    }

    @Test func aLongTitleStaysOnOneLineSoThePanelIsAsHighAsWithAShortOne() {
        let title = "Harborlight Software, Inc. a Truhlářství Doubek s.r.o. – velmi dlouhý název odběratele"
        let long = frames(of: detailPanel(title: title), width: 300).size.height
        let short = frames(of: detailPanel(), width: 300).size.height

        #expect(long == short, "\(long) against \(short)")
    }

    @Test func theActionsOfADetailPanelStandInARowOfSmallButtonsThatWraps() async throws {
        func frames(inRoomOf width: CGFloat) async throws -> [CGRect] {
            var found: [CGRect] = []
            try await withHostedView(
                detailPanel().frame(width: width).padding(24), size: CGSize(width: width + 48, height: 320)
            ) { window in
                try await withAccessibilityElements {
                    try await waitUntil { accessibilityButton(labelled: "Zobrazit PDF", in: window) != nil }
                    found = try ["Označit jako uhrazenou", "Upravit", "Zobrazit PDF"].map { label in
                        try #require(accessibilityButton(labelled: label, in: window)?.accessibilityFrame?())
                    }
                }
            }
            return found
        }

        // In a room that holds them all they are on one line; in one that does not, the last of them is on a line of
        // its own. They are 28 points high and 8 points apart.
        let wide = try await frames(inRoomOf: 600)
        let narrow = try await frames(inRoomOf: 300)
        #expect(wide.allSatisfy { abs($0.height - 28) < 0.5 }, "\(wide)")
        #expect(Set(wide.map { $0.minY.rounded() }).count == 1, "\(wide)")
        #expect(abs(wide[1].minX - wide[0].maxX - 8) < 0.5 && abs(wide[2].minX - wide[1].maxX - 8) < 0.5, "\(wide)")
        #expect(Set(narrow.map { $0.minY.rounded() }).count == 2, "\(narrow)")
        #expect(narrow[2].minY < narrow[0].minY - 20, "\(narrow)")
    }

    @Test func aDetailPanelWithoutActionsHasNoGapForThem() throws {
        func height(of panel: some View) -> CGFloat {
            frames(of: panel, width: 300).size.height
        }
        let with = DetailPanel(title: "Truhlářství Doubek", pill: nil, close: {}) {
            Button("Upravit") {}
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        } content: {
            Text(verbatim: "Obsah")
        }
        let without = DetailPanel(title: "Truhlářství Doubek", pill: nil, close: {}) {
            Text(verbatim: "Obsah")
        }

        // The row of actions is a button of 28 points and the gap of 10 under the line of the title.
        #expect(abs(height(of: with) - height(of: without) - 38) < 0.5)
    }

    // MARK: The panel that scrolls

    /// A panel with an invoice number for its title and an action, and `lines` short lines of content, which takes the
    /// height it is offered and scrolls what does not fit where `scrolls` says so.
    private func panel(lines: Int, scrolls: Bool) -> some View {
        DetailPanel(title: "20260902", pill: (text: "Uhrazená", tone: PillTone.paid), close: {}, scrolls: scrolls) {
            Button("Upravit") {}
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<lines, id: \.self) { line in
                    Text(verbatim: "Řádek \(line)")
                }
            }
        }
    }

    /// The height of the card that VoiceOver reads under the title of `panel` in a room of `height` points, and how
    /// much higher than what the card shows the content that scrolls in it is: nothing where nothing scrolls.
    private func heightAndOverflow(of panel: some View, offered height: CGFloat) async throws -> (CGFloat, CGFloat) {
        var result: (CGFloat, CGFloat) = (0, 0)
        try await withHostedView(
            panel.frame(width: 300).padding(24), size: CGSize(width: 348, height: height + 48)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "20260902", in: window) != nil }
                let frame = try #require(accessibilityElement(labelled: "20260902", in: window)?.accessibilityFrame?())
                let scrolled = window.contentView.flatMap { scrollView(under: $0) }
                let overflow = (scrolled?.documentView?.frame.height ?? 0) - (scrolled?.contentView.bounds.height ?? 0)
                result = (frame.height, max(0, overflow))
            }
        }
        return result
    }

    /// The first scroll view of AppKit under `view`: the one a panel that scrolls scrolls its content in.
    private func scrollView(under view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        return view.subviews.lazy.compactMap { scrollView(under: $0) }.first
    }

    /// A panel that scrolls is as high as the room it is given, whether its content is shorter or taller than that,
    /// and what does not fit in it scrolls inside the card: the card keeps its edges, and the content is higher than
    /// the part of it the card shows. A panel that does not scroll is as high as its content, with nothing to scroll.
    @Test func aPanelThatScrollsTakesTheHeightItIsOfferedAndScrollsWhatDoesNotFitInIt() async throws {
        let short = try await heightAndOverflow(of: panel(lines: 3, scrolls: true), offered: 600)
        let tall = try await heightAndOverflow(of: panel(lines: 60, scrolls: true), offered: 400)
        let plain = try await heightAndOverflow(of: panel(lines: 3, scrolls: false), offered: 600)

        #expect(abs(short.0 - 600) < 1 && short.1 < 0.5, "\(short)")
        #expect(abs(tall.0 - 400) < 1 && tall.1 > 100, "\(tall)")
        #expect(plain.0 < 300 && plain.1 < 0.5, "\(plain)")
    }

    // MARK: The facts and the figure

    @Test func theFactsOfADetailStandInTwoColumnsAndTheNoteStandsUnderItsValue() async throws {
        let facts = DetailFacts([
            DetailFact(label: "DUZP", value: "30.\u{00A0}9."),
            DetailFact(label: "Splatnost", value: "15.\u{00A0}10."),
            DetailFact(label: "Kurz ČNB k DUZP", value: "21,622", note: "ze dne 30.\u{00A0}9. 2026"),
        ])

        try await withHostedView(facts.frame(width: 260).padding(24), size: CGSize(width: 308, height: 200)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfText(startingWith: "21,622", in: window) != nil }
                let labels = try ["DUZP", "Splatnost", "Kurz ČNB k DUZP"].map { label in
                    try #require(frameOfText(startingWith: label, in: window), "no \(label)")
                }
                let values = try ["30.\u{00A0}9.", "15.\u{00A0}10.", "21,622"].map { value in
                    try #require(frameOfText(startingWith: value, in: window), "no \(value)")
                }
                let note = try #require(frameOfText(startingWith: "ze dne", in: window))

                // The values start in one column, 14 points after the widest label. The screen has its origin at
                // the bottom left, so the lines go down as their y goes down.
                let widest = labels.map(\.maxX).max() ?? 0
                for value in values {
                    #expect(abs(value.minX - (widest + 14)) < 1, "\(value) after labels ending at \(widest)")
                }
                #expect(labels[0].minY > labels[1].minY && labels[1].minY > labels[2].minY, "\(labels)")
                // The note is under its value, in the same column.
                #expect(abs(note.minX - values[2].minX) < 0.5, "\(note) under \(values[2])")
                #expect(note.maxY <= values[2].minY + 0.5, "\(note) under \(values[2])")
            }
        }
    }

    @Test func theFigureOfADetailReadsItsLabelItsFigureAndItsContextInThatOrder() async throws {
        let figure = DetailFigure(
            label: "Harborlight Software, Inc.", figure: "12\u{00A0}432,00\u{00A0}USD",
            context: "168\u{00A0}h × 74,00\u{00A0}USD · Software development")

        try await withHostedView(
            figure.frame(width: 260).padding(24), size: CGSize(width: 308, height: 200)
        ) { window in
            try await withAccessibilityElements {
                try await waitUntil { !accessibilityReadings(in: window).isEmpty }
                #expect(
                    accessibilityReadings(in: window) == [
                        "Harborlight Software, Inc.", "12\u{00A0}432,00\u{00A0}USD",
                        "168\u{00A0}h × 74,00\u{00A0}USD · Software development",
                    ])
            }
        }
    }

    @Test func theFigureOfADetailStaysOneLineAndTheLabelAndTheContextAreLeftOutWhereThereAreNone() {
        func height(of figure: DetailFigure, width: CGFloat) -> CGFloat {
            frames(of: figure, width: width).size.height
        }
        let amount = DetailFigure(label: nil, figure: "12\u{00A0}432,00\u{00A0}USD", context: nil)
        let full = DetailFigure(
            label: "Odběratel", figure: "12\u{00A0}432,00\u{00A0}USD", context: "Software development")

        // A figure in a room narrower than it is scaled down, which makes its line lower, and is not broken into two.
        #expect(height(of: amount, width: 90) <= height(of: amount, width: 400))
        // The label and the context add a line each, and the 2 points between the lines.
        #expect(height(of: full, width: 400) > height(of: amount, width: 400) + 2 * (12 + 2))
    }
}
