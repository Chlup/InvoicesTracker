import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The cards, lines and banners of Přehled that the V2 design restyles, hosted one by one and looked at as VoiceOver
/// and the eye see them: the calculation of the net income between two hairlines, the calculation of the estimate and
/// how its levies are paid under a hairline, side by side or one under the other, with no pill and no sign of an
/// estimate, the New Year banner and the reminder of the uniform rate as notes with their buttons, and the surface of
/// the hover boxes of the two charts. The sample is the prediction sample's 2026 as of 17. 10. 2026. In every
/// expected string `\u{00A0}` is the no-break space.
@Suite(.serialized)
@MainActor
struct OverviewCardsTests {
    /// The calculation of the card Příjmy for the sample as of 17. 10. 2026, as the builder makes it.
    private let calculation = [
        BillRow(
            label: "Příjmy od 1.\u{00A0}1. do 17.\u{00A0}10.", value: "2\u{00A0}191\u{00A0}771\u{00A0}Kč",
            valueStyle: .semibold),
        BillRow(
            label: "Odvody", value: "258\u{00A0}300\u{00A0}Kč",
            note: "daň 32\u{00A0}076 · sociální 159\u{00A0}279 · zdravotní 66\u{00A0}945", sign: .minus,
            share: "11,8\u{00A0}%", valueStyle: .semibold, rule: .hairline),
        BillRow(
            label: "Čistý příjem", value: "1\u{00A0}933\u{00A0}471\u{00A0}Kč", sign: .equals, style: .strong,
            share: "88,2\u{00A0}%", valueStyle: .title3Bold, rule: .heavy),
        BillRow(
            label: "Průměrně za měsíc", value: "193\u{00A0}347\u{00A0}Kč", sign: .divided,
            period: "·\u{00A0}10\u{00A0}měsíců", marksNetIncome: true, valueStyle: .title2Bold, rule: .hidden),
    ]

    // MARK: Helpers

    /// The lines that the pixel rows `rows` make, as the points from the top of the picture where each starts and ends:
    /// rows that follow one another (half a point apart in a picture of two pixels to the point) are one line.
    private func lines(in rows: [CGFloat]) -> [(top: CGFloat, bottom: CGFloat)] {
        var found: [(top: CGFloat, bottom: CGFloat)] = []
        for row in rows {
            if let last = found.last, row - last.bottom <= 0.5 + 0.01 {
                found[found.count - 1].bottom = row
            } else {
                found.append((top: row, bottom: row))
            }
        }
        return found.map { (top: $0.top, bottom: $0.bottom + 0.5) }
    }

    /// The rectangle of the content of `window` in the coordinates of the screen, whose origin is at the bottom left.
    private func contentRect(of window: NSWindow) -> CGRect {
        window.contentRect(forFrameRect: window.frame)
    }

    /// The card of the estimate of the prediction sample's 2026 as of 17. 10. 2026, without the chart of its months.
    private func estimateCard() throws -> PredictionCardData {
        PredictionBuilder.card(try PredictionSample.outcome(year: 2026))
    }

    // MARK: The calculation of the net income

    /// The calculation of the card Příjmy hosted alone, 700 points wide, on the colour of a card.
    private func calculationPicture(width: CGFloat = 700, in scheme: ColorScheme) throws -> OffscreenPicture {
        try OffscreenPicture(
            of: IncomeCalculation(rows: calculation).frame(width: width).background(Palette.bgCard), in: scheme)
    }

    /// The calculation is a hairline, 14 points, the four rows and 14 points, and a hairline: nothing else is a line
    /// across the width of the card, as the rules between the rows are as wide as the rows.
    @Test func theCalculationStandsBetweenTwoHairlinesWith14PointsAboveAndBelowItsRows() throws {
        let separator = try OffscreenPicture.bytes(of: Palette.sep, in: .light)
        let picture = try calculationPicture(width: 600, in: .light)

        let found = lines(in: picture.rows(near: separator, from: 4, to: 596, by: 3))

        #expect(found.count == 2, "The lines across the calculation are \(found)")
        guard found.count == 2 else { return }
        #expect(found[0].top < 1, "The first hairline is at \(found[0])")
        #expect(found[1].bottom > picture.size.height - 1.5, "The second is at \(found[1]) in \(picture.size)")
        let rowsHeight = NSHostingView(rootView: BillRows(rows: calculation).frame(width: 420)).fittingSize.height
        // The height that a hosting view fits is rounded up to a whole point, so the rows are up to a point lower.
        let expected = 1 + 14 + rowsHeight + 14 + 1
        #expect(
            picture.size.height <= expected && picture.size.height > expected - 1.5,
            "The calculation is \(picture.size.height) points tall, the rows \(rowsHeight)")
    }

    /// In a card wider than that the rows are 420 points wide at most, from the left edge: the rules between them, the
    /// hairline above the levies and the heavy line above the net income, end there.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theRowsOfTheCalculationAreNoWiderThan420Points(scheme: ColorScheme) throws {
        let separator = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
        let heavy = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
        let picture = try calculationPicture(in: scheme)

        for (name, colour) in [("the hairline", separator), ("the heavy line", heavy)] {
            let across420 = lines(in: picture.rows(near: colour, from: 0, to: 419.5, by: 3))
            let beyond = lines(in: picture.rows(near: colour, from: 421, to: 430, by: 3))
            // The hairline above the levies is also a part of the two hairlines that run the whole width.
            #expect(across420.count == (colour == separator ? 3 : 1), "\(scheme): \(name) is at \(across420)")
            #expect(beyond.count == (colour == separator ? 2 : 0), "\(scheme): \(name) beyond 420 is at \(beyond)")
        }
    }

    /// The green dot of the net income stands before the label of the fourth row, the average per month: under the
    /// heavy line above the net income, after the column of the signs and its gap, and it is the one green mark of
    /// the calculation, 8 points square.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func onlyTheFourthRowHasTheGreenDotOf8Points(scheme: ColorScheme) throws {
        let green = try OffscreenPicture.bytes(of: Palette.green, in: scheme)
        let heavy = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
        let picture = try calculationPicture(in: scheme)

        let extent = try #require(picture.extent(near: green, by: 6))
        let result = try #require(lines(in: picture.rows(near: heavy, from: 0, to: 419.5, by: 3)).first)

        #expect((extent.width - 8).magnitude <= 1, "The mark is \(extent.width) points wide")
        #expect((extent.height - 8).magnitude <= 1, "The mark is \(extent.height) points high")
        #expect((extent.minX - 28).magnitude <= 1, "The mark starts at \(extent.minX)")
        // Under the net income, which is a row under the heavy line: more than a row of body text lower.
        #expect(extent.minY > result.bottom + 20, "The mark is at \(extent), the heavy line at \(result)")
    }

    /// VoiceOver reads each row as one phrase, the label with its share or its months, the value and the note; the
    /// signs and the dot are not read.
    @Test func eachRowOfTheCalculationIsReadAsOnePhrase() async throws {
        let view = IncomeCalculation(rows: calculation).frame(width: 600).padding(24)
        try await withHostedView(view, size: CGSize(width: 648, height: 300)) { window in
            try await withAccessibilityElements {
                try await waitUntil { !accessibilityReadings(in: window).isEmpty }
                let readings = accessibilityReadings(in: window)

                #expect(
                    readings == [
                        "Příjmy od 1.\u{00A0}1. do 17.\u{00A0}10.: 2\u{00A0}191\u{00A0}771\u{00A0}Kč",
                        "Odvody 11,8\u{00A0}%: 258\u{00A0}300\u{00A0}Kč."
                            + " daň 32\u{00A0}076 · sociální 159\u{00A0}279 · zdravotní 66\u{00A0}945",
                        "Čistý příjem 88,2\u{00A0}%: 1\u{00A0}933\u{00A0}471\u{00A0}Kč",
                        "Průměrně za měsíc ·\u{00A0}10\u{00A0}měsíců: 193\u{00A0}347\u{00A0}Kč",
                    ])
            }
        }
    }

    // MARK: The estimate of the whole year

    /// The readings of the rows of the calculation of the sample's 2026 in the card of the estimate, by the words each
    /// starts with: the income, the levies, the net income and the average per month.
    private static let calculationStarts = [
        "Příjmy za rok: ", "Odvody 17,0\u{00A0}%: ", "Čistý příjem 83,0\u{00A0}%: ",
        "Průměrně za měsíc ·\u{00A0}12\u{00A0}měsíců: ",
    ]

    /// The readings of the rows of how the levies of the sample's 2026 are paid, by the words each starts with.
    private static let paymentStarts = [
        "Zálohy sociální a zdravotní: ", "Zálohy na daň: ", "Doplatek: ", "Odkládat průměrně za měsíc: ",
    ]

    /// The frames of the rows of `starts` in `window`, in the coordinates of the screen, found by the words VoiceOver
    /// reads each of them with.
    private func rowFrames(_ starts: [String], in window: NSWindow) throws -> [CGRect] {
        try starts.map { start in
            try #require(
                accessibilityElement(labelStartingWith: start, in: window)?.accessibilityFrame?(), "No row \(start)")
        }
    }

    /// The frame of the title of the panel of how the levies are paid in `window`, in the coordinates of the screen: a
    /// heading, which VoiceOver reads under its words.
    private func panelTitle(in window: NSWindow) throws -> CGRect {
        try #require(
            accessibilityElement(labelled: "Jak odvody zaplatíte", in: window)?.accessibilityFrame?(),
            "No title of the panel")
    }

    /// The card has no pill "odhad" and no sign "≈" anywhere in what VoiceOver reads. In a card 1 000 points wide the
    /// calculation and how the levies are paid stand side by side in two columns of one width, 32 points apart, from
    /// the edge of the card inside its padding of 20 (960 points: two columns of 464): the rows of the calculation
    /// fill the first, their values ending at its right edge, and the panel the second, its title, a heading, and its
    /// rows 14 points inside it. VoiceOver frames a row by its texts, without the space above and below them and the
    /// sign column where the sign is blank, so the texts of the first row are 8 points under the top of the blocks, and
    /// the title 10, 2 lower. The button Odhad odvodů, a button inside a card, is 28 points tall at the end of the
    /// head, 20 points from the edge.
    @Test func theEstimateCardHasNoPillAndItsTwoBlocksStandSideBySideInAWideCard() async throws {
        let card = try estimateCard()
        var opened = 0
        let view = PredictionCard(card: card, showPrediction: { opened += 1 }).frame(width: 1_000).padding(24)
        try await withHostedView(view, size: CGSize(width: 1_048, height: 500)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelStartingWith: "Příjmy za rok: ", in: window) != nil }
                let group = try #require(accessibilityElement(labelled: "Odhad za celý rok", in: window))
                let groupFrame = try #require(group.accessibilityFrame?())
                let readings = accessibilityReadings(under: group)
                #expect(!readings.contains("odhad"), "The pill is read: \(readings)")
                #expect(readings.allSatisfy { !$0.contains("≈") }, "A sign of an estimate is read: \(readings)")

                let rows = try rowFrames(Self.calculationStarts, in: window)
                let payments = try rowFrames(Self.paymentStarts, in: window)
                let title = try panelTitle(in: window)
                let left = groupFrame.minX + 20
                for row in rows {
                    #expect(row.minX > left - 0.5, "A row of the calculation is at \(row)")
                    #expect(abs(row.maxX - (left + 464)) < 1, "A row of the calculation ends at \(row.maxX)")
                }
                let panel = left + 464 + 32
                for row in payments {
                    #expect(row.minX > panel + 14 - 0.5, "A payment is at \(row)")
                    #expect(abs(row.maxX - (panel + 464 - 14)) < 1, "A payment ends at \(row.maxX)")
                }
                #expect(abs(title.minX - (panel + 14)) < 1, "The title is at \(title)")
                // The origin of the screen is at the bottom left, so the top of a frame is its largest y.
                #expect(abs(rows[0].maxY - 2 - title.maxY) < 1, "The title is at \(title), the income at \(rows[0])")
                #expect(payments[0].maxY < title.minY + 0.5, "The payments are not under the title: \(payments[0])")
                for (above, below) in zip(rows + payments, (rows + payments).dropFirst()) where above != rows.last {
                    #expect(below.maxY < above.minY + 0.5, "The rows are not one under the other: \(above), \(below)")
                }

                let button = try #require(accessibilityButton(labelled: "Odhad odvodů", in: window))
                let buttonFrame = try #require(button.accessibilityFrame?())
                #expect(abs(buttonFrame.height - 28) < 0.5, "The button is \(buttonFrame.height) points tall")
                #expect(abs(groupFrame.maxX - 20 - buttonFrame.maxX) < 1, "The button is at \(buttonFrame)")
                #expect(button.accessibilityPerformPress?() == true)
                #expect(opened == 1)
            }
        }
    }

    /// The panel's title is read as a heading, and each row of the calculation and of the panel as one phrase, with
    /// no sign and no dot.
    @Test func thePanelHasAHeadingAndEachRowIsReadAsOnePhrase() async throws {
        let view = PredictionCard(card: try estimateCard(), showPrediction: {}).frame(width: 1_000).padding(24)
        try await withHostedView(view, size: CGSize(width: 1_048, height: 500)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "Jak odvody zaplatíte", in: window) != nil }
                let readings = accessibilityReadings(in: window)

                for reading in [
                    "Příjmy za rok: 2\u{00A0}743\u{00A0}157\u{00A0}Kč. z toho přišlo 2\u{00A0}191\u{00A0}771",
                    "Odvody 17,0\u{00A0}%: 466\u{00A0}782\u{00A0}Kč."
                        + " daň 114\u{00A0}786 · sociální 247\u{00A0}832 · zdravotní 104\u{00A0}164",
                    "Čistý příjem 83,0\u{00A0}%: 2\u{00A0}276\u{00A0}375\u{00A0}Kč",
                    "Průměrně za měsíc ·\u{00A0}12\u{00A0}měsíců: 189\u{00A0}698\u{00A0}Kč",
                    "Zálohy sociální a zdravotní: 222\u{00A0}080\u{00A0}Kč. platí se každý měsíc",
                    "Zálohy na daň: 46\u{00A0}000\u{00A0}Kč",
                    "Doplatek: 198\u{00A0}702\u{00A0}Kč. s přiznáním a přehledy",
                    "Odkládat průměrně za měsíc: 20\u{00A0}392\u{00A0}Kč. (zálohy na daň + doplatek) ÷ 12",
                ] {
                    #expect(readings.contains(reading), "'\(reading)' is not read: \(readings)")
                }
                let heading = try #require(accessibilityElement(labelled: "Jak odvody zaplatíte", in: window))
                #expect(heading.accessibilityRole?()?.rawValue == "AXHeading", "The title of the panel is no heading")
            }
        }
    }

    /// Where the card is narrower than the two columns need inside its padding, 712 points (two of 340 and the gap of
    /// 32), how the levies are paid stands under the calculation, 16 points lower, both in the whole width from the
    /// edge of the card; at 712 points inside the padding they stand side by side. VoiceOver frames a row by its
    /// texts, so the title of the panel, 10 points inside it, is 34 points under the texts of the last row, which has
    /// 8 points of its own under them.
    @Test func theTwoBlocksOfTheEstimateGoOneUnderTheOtherInACardNarrowerThan712PointsInside() async throws {
        let card = try estimateCard()
        for (width, beside) in [(600 as CGFloat, false), (751, false), (752, true)] {
            let view = PredictionCard(card: card, showPrediction: {}).frame(width: width).padding(24)
            try await withHostedView(view, size: CGSize(width: width + 48, height: 900)) { window in
                try await withAccessibilityElements {
                    try await waitUntil {
                        accessibilityElement(labelStartingWith: "Příjmy za rok: ", in: window) != nil
                    }
                    let group = try #require(frameOfCard(labelled: "Odhad za celý rok", in: window))
                    let rows = try rowFrames(Self.calculationStarts, in: window)
                    let payments = try rowFrames(Self.paymentStarts, in: window)
                    let title = try panelTitle(in: window)
                    let inner = width - 40

                    let left = group.minX + 20
                    if beside {
                        #expect(title.minX > rows[0].maxX + 32 - 1, "\(width): the panel is at \(title)")
                        #expect(abs(rows[0].maxX - (left + (inner - 32) / 2)) < 1, "\(width): \(rows[0])")
                    } else {
                        for row in rows {
                            #expect(row.minX > left - 0.5, "\(width): a row is at \(row)")
                            #expect(abs(row.maxX - (left + inner)) < 1, "\(width): a row ends at \(row.maxX)")
                        }
                        #expect(abs(title.minX - left - 14) < 1, "\(width): the title is at \(title)")
                        // The panel is 16 points under the last row of the calculation, and its title 10 inside it.
                        let gap = (rows.last?.minY ?? 0) - title.maxY
                        #expect(abs(gap - (8 + 16 + 10)) < 1.5, "\(width): the title is \(gap) points under the rows")
                        for row in payments {
                            #expect(group.insetBy(dx: -0.5, dy: -0.5).contains(row), "\(width): \(row) in \(group)")
                        }
                    }
                }
            }
        }
    }

    /// The card is the head, 14 points, a hairline, 14 points and the two blocks, and its padding of 20 under them; no
    /// other line runs across it (it has no chart here): the rules of the calculation are as wide as its column.
    @Test func theTwoBlocksOfTheEstimateStandUnderAHairline() throws {
        let card = try estimateCard()
        let separator = try OffscreenPicture.bytes(of: Palette.sep, in: .light)
        let picture = try OffscreenPicture(
            of: PredictionCard(card: card, showPrediction: {}).frame(width: 1_000), in: .light)
        let found = lines(in: picture.rows(near: separator, from: 24, to: 976, by: 3))

        #expect(found.count == 1, "The lines across the card are \(found)")
        guard let line = found.first else { return }
        let blocks = NSHostingView(
            rootView: PredictionCalculationView(calculation: card.calculation).frame(width: 960)
        ).fittingSize.height
        // Under the line: 14 points, the blocks and the padding of 20. A hosted view is as high as a whole number of
        // points, so the blocks are up to a point lower.
        let under = picture.size.height - line.bottom
        #expect(
            under <= 14 + blocks + 20 + 0.5 && under > 14 + blocks + 20 - 1.5,
            "The card is \(picture.size.height) points tall, the line ends at \(line.bottom), the blocks \(blocks)")
    }

    /// The net income of the card is marked by the green dot of 8 points, and nothing else in the card is green: the
    /// green pixels of the card fit a square of 8 points, in a light and in a dark window.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theNetIncomeOfTheEstimateCardIsMarkedByADotOf8Points(scheme: ColorScheme) throws {
        let card = try estimateCard()
        let green = try OffscreenPicture.bytes(of: Palette.green, in: scheme)
        let view = PredictionCard(card: card, showPrediction: {}).frame(width: 1_000).background(Palette.bgCard)
        let picture = try OffscreenPicture(of: view, in: scheme)

        let extent = try #require(picture.extent(near: green, by: 6))

        #expect((extent.width - 8).magnitude <= 1, "The mark is \(extent.width) points wide")
        #expect((extent.height - 8).magnitude <= 1, "The mark is \(extent.height) points high")
    }

    // MARK: The two lists

    /// Two payments received: one in crowns with VAT, one in dollars.
    private let receipts = [
        LatestReceipt(
            invoiceID: 1, date: "15.\u{00A0}10.", number: "20260902", client: "Cetus Data s.r.o.",
            original: "5\u{00A0}445,00\u{00A0}Kč vč. DPH 945,00", czk: "4\u{00A0}500,00\u{00A0}Kč",
            effect: "+8\u{00A0}000\u{00A0}Kč"),
        LatestReceipt(
            invoiceID: 2, date: "2.\u{00A0}10.", number: "20260901", client: "Bravo Labs, Inc.",
            original: "14\u{00A0}350,00\u{00A0}USD · kurz 21,305", czk: "305\u{00A0}726,75\u{00A0}Kč",
            effect: "+88\u{00A0}714\u{00A0}Kč"),
    ]

    /// An advance and a VAT return to come.
    private let advance = UpcomingItem(
        date: civilDate("2026-11-01"), day: "lis", month: "2026", title: "Zálohy za listopad",
        subtitle: "sociální 12\u{00A0}150 · zdravotní 5\u{00A0}480", amount: "17\u{00A0}630\u{00A0}Kč", isVAT: false)
    private let filing = UpcomingItem(
        date: civilDate("2026-10-26"), day: "26", month: "říj", title: "DPH za září",
        subtitle: "přiznání a kontrolní hlášení · mimo odvody z příjmů", amount: "945,00\u{00A0}Kč", isVAT: true)

    /// The heading, the link and the rows of a list card standing in a window as wide as 500 points and a padding of
    /// 24: the card is padded 20 at the sides, the heading and the link are on its line, 6 points and the hairline of
    /// the first row under it, the rows follow each other and fill the width inside the padding, and the picture of the
    /// card is 20 points taller than the heading and the rows at the top and 10 at the foot.
    private func expectListCard(
        _ list: some View, heading: String, link: String, rowStarts: [String], rowHeight: CGFloat
    ) async throws {
        let picture = try OffscreenPicture(of: list.frame(width: 500), in: .light)
        let separator = try OffscreenPicture.bytes(of: Palette.sep, in: .light)
        let hairlines = lines(in: picture.rows(near: separator, from: 24, to: 476, by: 3))
        #expect(hairlines.count == rowStarts.count, "A hairline above each row, not \(hairlines)")

        let hosted = list.frame(width: 500).padding(24)
        try await withHostedView(hosted, size: CGSize(width: 548, height: 600)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(role: .link, labelled: link, in: window) != nil }
                let content = contentRect(of: window)
                let title = try #require(frameOfHeading(heading, in: window))
                let linkElement = try #require(accessibilityElement(role: .link, labelled: link, in: window))
                let linkFrame = try #require(linkElement.accessibilityFrame?())
                #expect(abs(title.minX - content.minX - 44) < 1, "The heading is at \(title)")
                #expect(abs(content.maxX - 44 - linkFrame.maxX) < 1, "The link is at \(linkFrame)")
                #expect(abs(linkFrame.midY - title.midY) < 6, "The link and the heading are not on a line")

                var rows: [CGRect] = []
                for start in rowStarts {
                    let row = try #require(accessibilityElement(labelStartingWith: start, in: window), "No \(start)")
                    rows.append(try #require(row.accessibilityFrame?()))
                }
                for row in rows {
                    #expect(abs(row.minX - content.minX - 44) < 1 && abs(content.maxX - 44 - row.maxX) < 1)
                    #expect(abs(row.height - rowHeight) < 1, "A row is \(row.height) points tall, not \(rowHeight)")
                }
                // 6 points of the card and the hairline of the row between the heading and the first row.
                #expect(abs(title.minY - rows[0].maxY - 7) < 1.5, "The first row is at \(rows[0]), heading \(title)")
                // The hairline of the next row lies between two rows.
                for (above, below) in zip(rows, rows.dropFirst()) {
                    #expect(abs(above.minY - below.maxY - 1) < 1.5, "The rows are \(above) and \(below)")
                }
                // The card is padded 20 points above the heading and 10 below the last row.
                let lastRow = try #require(rows.last)
                let expected = 20 + (title.maxY - lastRow.minY) + 10
                #expect(abs(picture.size.height - expected) < 1.5, "The card is \(picture.size.height) points tall")
            }
        }
    }

    /// The frame of the heading of a card in `window`, in the coordinates of the screen.
    private func frameOfHeading(_ title: String, in window: NSWindow) -> CGRect? {
        accessibilityElement(labelled: title, in: window)?.accessibilityFrame?()
    }

    @Test func theLatestReceiptsStandInACardPadded20And20And10WithTheLinkOfTheDesign() async throws {
        let list = LatestReceiptsList(receipts: receipts, open: { _ in }, showInvoices: {})

        try await expectListCard(
            list, heading: "Poslední přijaté platby", link: "Všechny faktury", rowStarts: ["15.", "2."], rowHeight: 53)
    }

    @Test func theUpcomingPaymentsStandInACardPadded20And20And10WithTheLinkOfTheDesign() async throws {
        let list = UpcomingList(items: [filing, advance], showAdvances: {}, showInvoices: {})

        try await expectListCard(
            list, heading: "Nejbližší platby úřadům", link: "Plán záloh", rowStarts: ["26,", "lis,"], rowHeight: 62)
    }

    /// The date badge of an upcoming payment is a panel of the inset colour, 52 by 44 points; the dot in front of its
    /// title is the grey of text for an advance and the faint grey for a VAT return.
    @Test func theBadgeIsOnTheInsetColourAndTheDotsHaveTheirGreys() throws {
        let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: .light)
        let text2 = try OffscreenPicture.bytes(of: Palette.text2, in: .light)
        let text4 = try OffscreenPicture.bytes(of: Palette.text4, in: .light)
        func picture(of item: UpcomingItem) throws -> OffscreenPicture {
            try OffscreenPicture(
                of: UpcomingList(items: [item], showAdvances: {}, showInvoices: {}).frame(width: 500), in: .light)
        }
        let advancePicture = try picture(of: advance)
        let filingPicture = try picture(of: filing)

        for shown in [advancePicture, filingPicture] {
            let badge = shown.count(
                near: inset, in: CGRect(x: 20, y: 0, width: 52, height: shown.size.height), by: 2)
            #expect(badge > 6_500, "The badge has \(badge) pixels of the inset colour, of 9 152")
        }
        // The dot is 8 points wide at 86 points from the left, in the line of the title: 20 points of the card, the
        // heading of 19, 6, the hairline of 1 and 9 points of the row put the title at 55, and the dot in its middle.
        let dot = CGRect(x: 86, y: 56, width: 8, height: 20)
        #expect(advancePicture.count(near: text2, in: dot, by: 24) >= 150)
        #expect(advancePicture.count(near: text4, in: dot, by: 24) < 50)
        #expect(filingPicture.count(near: text4, in: dot, by: 24) >= 150)
        #expect(filingPicture.count(near: text2, in: dot, by: 24) < 50)
    }

    // MARK: The line of the uniform rates

    /// The line under the chart of a year with one foreign currency: the rate of the dollar, from the instruction of
    /// the GFŘ.
    private let uniformLine = UniformLine(
        title: "Jednotný kurz za rok 2025", rates: ["1\u{00A0}USD = 21,84\u{00A0}Kč"],
        source: "pokyn GFŘ-D-75 · příjmy se přepočítávají jednotným kurzem")

    /// The line is a hairline with 12 points under it, and the title, the pills and the source in the callout size, on
    /// one row where there is room, with the pills on the inset colour as capsules.
    @Test func theUniformRateLineIsInTheCalloutSizeUnderAHairlineWithPillsOnTheInsetColour() async throws {
        let separator = try OffscreenPicture.bytes(of: Palette.sep, in: .light)
        let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: .light)
        let picture = try OffscreenPicture(
            of: UniformRateLine(line: uniformLine).frame(width: 900).background(Palette.bgCard), in: .light)

        let found = lines(in: picture.rows(near: separator, from: 4, to: 896, by: 3))

        #expect(found.count == 1 && (found.first?.top ?? 9) < 1, "The lines across it are \(found)")
        // A pill of 2 by 8 points around its words: the capsule is the inset colour behind them.
        let pillPixels = picture.count(
            near: inset, in: CGRect(x: 0, y: 0, width: 900, height: picture.size.height), by: 2)
        #expect(pillPixels > 1_000, "The pill has \(pillPixels) pixels of the inset colour")

        let hosted = UniformRateLine(line: uniformLine).frame(width: 900).padding(24)
        try await withHostedView(hosted, size: CGSize(width: 948, height: 200)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfText(startingWith: "pokyn GFŘ", in: window) != nil }
                let title = try #require(frameOfText(startingWith: uniformLine.title, in: window))
                let pill = try #require(frameOfText(startingWith: "1\u{00A0}USD", in: window))
                let source = try #require(frameOfText(startingWith: "pokyn GFŘ", in: window))
                // All three are the callout size: a line of 15 points. They stand on one row, 10 points apart.
                for frame in [title, pill, source] {
                    #expect(abs(frame.height - 15) < 0.5, "A text is \(frame.height) points tall: \(frame)")
                    #expect(abs(frame.midY - title.midY) < 2, "The texts are not on one row: \(title), \(frame)")
                }
                #expect(pill.minX > title.maxX && source.minX > pill.maxX, "\(title), \(pill), \(source)")
            }
        }
    }

    // MARK: The banners

    /// A banner is a note of the design with its buttons as small capsules at its end: the tint of its tone behind it,
    /// 52 points tall for a line of text next to a button of 28, the buttons 8 points apart and 16 points from the
    /// edge. VoiceOver reads its sentence and reaches each button on its own.
    private func expectNote(
        _ banner: some View, tint: Color, text: String, first: String, second: String, onFirst: () -> Int,
        onSecond: () -> Int
    ) async throws {
        let wanted = try OffscreenPicture.bytes(of: tint, in: .light)
        let picture = try OffscreenPicture(of: banner.frame(width: 900), in: .light)
        let inside = picture.bytes(at: CGPoint(x: 4, y: picture.size.height / 2))
        #expect(zip(wanted, inside).allSatisfy { abs($0 - $1) <= 2 }, "The note is \(inside), not \(wanted)")
        #expect(abs(picture.size.height - 52) < 0.5, "The note is \(picture.size.height) points tall")

        let hosted = banner.frame(width: 900).padding(16)
        try await withHostedView(hosted, size: CGSize(width: 932, height: 120)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: second, in: window) != nil }
                #expect(showsText(text, in: window), "The sentence is not read: \(accessibilityReadings(in: window))")
                let one = try #require(accessibilityButton(labelled: first, in: window))
                let two = try #require(accessibilityButton(labelled: second, in: window))
                let frames = [try #require(one.accessibilityFrame?()), try #require(two.accessibilityFrame?())]
                for frame in frames {
                    #expect(abs(frame.height - 28) < 0.5, "A button is \(frame.height) points tall")
                }
                #expect(abs(frames[1].minX - frames[0].maxX - 8) < 1, "The buttons are \(frames)")
                #expect(abs(contentRect(of: window).maxX - 16 - 16 - frames[1].maxX) < 1, "The buttons are \(frames)")
                #expect(one.accessibilityPerformPress?() == true)
                #expect(two.accessibilityPerformPress?() == true)
                #expect(onFirst() == 1 && onSecond() == 1)
            }
        }
    }

    @Test func theNewYearBannerIsAnInfoNoteWithTheButtonsZobrazitRokAndZavrit() async throws {
        var shown = 0
        var closed = 0
        let banner = NewYearBanner(finishedYear: 2026, showFinishedYear: { shown += 1 }, close: { closed += 1 })

        try await expectNote(
            banner, tint: Palette.accentTint, text: "Začal rok 2027 — rok 2026 je uzavřený", first: "Zobrazit rok 2026",
            second: "Zavřít", onFirst: { shown }, onSecond: { closed })
    }

    @Test func theReminderOfTheUniformRateIsAnAttentionNoteWithTheButtonsZadatRucneAndZavrit() async throws {
        var entered = 0
        var closed = 0
        let banner = UniformRateReminderBanner(year: 2026, enterManually: { entered += 1 }, close: { closed += 1 })

        try await expectNote(
            banner, tint: Palette.orangeTint, text: UniformRateReminderBanner.text(year: 2026), first: "Zadat ručně",
            second: "Zavřít", onFirst: { entered }, onSecond: { closed })
    }

    // MARK: The hover boxes of the charts

    /// The picture of `view` standing 30 points from the top left of a window background, and the frame of `view`.
    private func hoverBox(_ view: some View, in scheme: ColorScheme) throws -> (OffscreenPicture, CGRect) {
        let bare = try OffscreenPicture(of: view.fixedSize(), in: scheme)
        let picture = try OffscreenPicture(of: view.fixedSize().padding(30).background(Palette.bgWindow), in: scheme)
        return (picture, CGRect(x: 30, y: 30, width: bare.size.width, height: bare.size.height))
    }

    /// A hover box is a panel of the colour of a card with corners of 10 points, raised off the page by the popover's
    /// shadow: its inside is that colour, its corner shows the window, the window under its edge differs from the one
    /// further down, where the shadow no longer reaches, and its text is drawn on it. It is so in a light and in a dark
    /// window.
    private func expectPanel(_ view: some View) throws {
        for scheme in [ColorScheme.light, .dark] {
            let (picture, frame) = try hoverBox(view, in: scheme)
            let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
            let window = try OffscreenPicture.bytes(of: Palette.bgWindow, in: scheme)

            // 4 points in from the left edge, in the padding of the box, half way down.
            let inside = picture.bytes(at: CGPoint(x: frame.minX + 4, y: frame.midY))
            #expect(zip(card, inside).allSatisfy { abs($0 - $1) <= 2 }, "\(scheme): the box is \(inside), not \(card)")
            // The corner of a rounded panel of 10 points shows the window; 5 points in, the panel is there.
            func distance(_ one: [Int], _ other: [Int]) -> Int {
                zip(one, other).map { abs($0 - $1) }.reduce(0, +)
            }
            let corner = picture.bytes(at: CGPoint(x: frame.minX + 0.75, y: frame.minY + 0.75))
            #expect(
                distance(corner, window) < distance(corner, card),
                "\(scheme): the corner is \(corner), the window \(window), the box \(card)")
            let beyond = picture.bytes(at: CGPoint(x: frame.minX + 5, y: frame.minY + 5))
            #expect(zip(card, beyond).allSatisfy { abs($0 - $1) <= 2 }, "\(scheme): 5 points in it is \(beyond)")
            // The shadow of a popover reaches 12 points below the box and 16 more of blur: just under it the window is
            // another colour than 28 points under it.
            let under = picture.bytes(at: CGPoint(x: frame.midX, y: frame.maxY + 2))
            let faraway = picture.bytes(at: CGPoint(x: frame.midX, y: frame.maxY + 28))
            let difference = zip(faraway, under).map { abs($0 - $1) }.max() ?? 0
            #expect(difference >= 4, "\(scheme): just under the box it is \(under), far under it \(faraway)")
            // The words of the box are drawn on it, darker than the box in a light window.
            if scheme == .light {
                let interior = frame.insetBy(dx: 8, dy: 8)
                #expect(picture.count(darkerThan: card, in: interior, by: 2) > 0, "The text is not drawn")
            }
        }
    }

    @Test func theHoverBoxOfTheIncomeChartIsAPanelOfTheColourOfACard() throws {
        let column = ChartColumn(
            label: "zář", title: "Září 2026", issuedNetHalere: 31_022_675, issuedGrossHalere: 31_117_175,
            receivedNetHalere: 27_943_300, receivedGrossHalere: 27_943_300, isFuture: false, isCurrent: false,
            hasLinePoint: true, netIncomeHalere: 23_716_800, netIncomeText: "237\u{00A0}168\u{00A0}Kč",
            netIncomeNote: "součet za faktury zaplacené v měsíci")

        try expectPanel(ChartTooltip(column: column))
    }

    /// The hover box of the chart of Příjmy tells its amounts in whole Kč: two columns whose amounts differ only in
    /// haléře, which round to the same crowns, give the very same picture, while a column that differs by a crown
    /// gives another. Shown in haléře, the first two would differ in their last digits.
    @Test func theHoverBoxOfTheIncomeChartDrawsWholeCrownsAndNoHalere() throws {
        func column(issued: Int64, gross: Int64, received: Int64) -> ChartColumn {
            ChartColumn(
                label: "zář", title: "Září 2026", issuedNetHalere: issued, issuedGrossHalere: gross,
                receivedNetHalere: received, receivedGrossHalere: received, isFuture: false, isCurrent: false,
                hasLinePoint: true)
        }
        func picture(of column: ChartColumn) throws -> OffscreenPicture {
            try OffscreenPicture(of: ChartTooltip(column: column).padding(10), in: .light)
        }

        let withHalere = try picture(of: column(issued: 31_022_675, gross: 31_117_175, received: 27_943_349))
        let rounded = try picture(of: column(issued: 31_022_700, gross: 31_117_200, received: 27_943_300))
        let another = try picture(of: column(issued: 31_032_700, gross: 31_117_200, received: 27_943_300))

        #expect(withHalere.isSame(as: rounded), "The amounts are not drawn in whole Kč")
        #expect(!rounded.isSame(as: another), "A different amount draws the same picture")
    }

    @Test func theHoverBoxOfTheEstimateChartIsAPanelOfTheColourOfACard() throws {
        let outcome = try PredictionSample.outcome(year: 2026)
        let year = PredictionSample.yearInput(year: 2026)
        let effects = year.receipts.compactMap { receipt -> ReceiptEffect? in
            guard case .invoice = receipt.source else { return nil }
            return TaxEngine.effect(of: receipt, in: year)
        }
        let months = PredictionChartBuilder.months(
            year: 2026, today: PredictionSample.sampleToday, rows: SampleYear2026.chartRows, paymentEffects: effects,
            prediction: outcome.prediction, expectedPayments: outcome.expectedPayments())

        try expectPanel(PredictionChartTooltip(month: months[9]))
    }
}
