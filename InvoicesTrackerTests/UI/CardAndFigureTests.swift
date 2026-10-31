import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The shared card and the figures that stand in it: how VoiceOver reads a card, how the card pads its content, how the
/// sentence of a key figure is split at its emphasis and how wide it is set, where the share of a key figure stands,
/// and how a figure tile is read and marked.
@Suite(.serialized)
@MainActor
struct CardAndFigureTests {
    // MARK: The card

    @Test func aCardIsReadAsAGroupUnderItsTitle() async throws {
        let card = Card(title: "Vzhled", subtitle: "Světlý nebo tmavý vzhled aplikace") {
            Text(verbatim: "Obsah karty")
        }

        try await withHostedView(card.padding(24), size: CGSize(width: 600, height: 240)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Vzhled", in: window) != nil }
                // The heading and the subtitle are read inside the group, which the card holds (`.contain`).
                let group = try #require(accessibilityElement(labelled: "Vzhled", in: window))
                let readings = accessibilityReadings(under: group)
                #expect(readings.contains("Světlý nebo tmavý vzhled aplikace"), "read as \(readings)")
                #expect(readings.contains("Obsah karty"), "read as \(readings)")
            }
        }
    }

    @Test func aCardIsReadUnderItsLabelWhenItHasOneAndNotUnderItsTitle() async throws {
        let card = Card(title: "Děti · daňové zvýhodnění", label: "Děti") {
            Text(verbatim: "Obsah karty")
        }

        try await withHostedView(card.padding(24), size: CGSize(width: 600, height: 240)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Děti", in: window) != nil }
                // The title is the heading inside the card; no group of the window is read under it.
                #expect(frameOfCard(labelled: "Děti · daňové zvýhodnění", in: window) == nil)
            }
        }
    }

    @Test func aCardWithoutATitleIsReadUnderItsLabel() async throws {
        let card = Card(label: "Rok a příjem") {
            Text(verbatim: "Obsah karty")
        }

        try await withHostedView(card.padding(24), size: CGSize(width: 600, height: 240)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Rok a příjem", in: window) != nil }
            }
        }
    }

    /// The frames of the named parts of `view`, hosted in a room of `width` points.
    private func frames(of view: some View, width: CGFloat) -> (frames: [String: CGRect], size: CGSize) {
        let hosting = NSHostingView(rootView: view.frame(width: width, alignment: .topLeading))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return (framesOfParts(in: hosting), size)
    }

    @Test func aCardPadsItsContentBy20AndGivesItTheWholeWidthInside() throws {
        let card = Card {
            LayoutPart(name: "content")
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        let placed = frames(of: card, width: 400)

        let content = CGRect(x: 20, y: 20, width: 360, height: 50)
        #expect(placed.frames["content"] == content, "laid out as \(placed.frames)")
        #expect(placed.size == CGSize(width: 400, height: 90))
    }

    /// The part under the header of a card with a title, 50 points high.
    private func contentPart() -> some View {
        LayoutPart(name: "content")
            .frame(maxWidth: .infinity)
            .frame(height: 50)
    }

    @Test func theContentOfACardIsLowerThanItsHeaderByTheSpacingOfTheCard() throws {
        func contentTop(of card: some View) throws -> CGFloat {
            try #require(frames(of: card, width: 400).frames["content"]).minY
        }

        // The header is a line of the title; the content is lower by the spacing asked for, 12 points unless told so.
        let usual = try contentTop(of: Card(title: "Vzhled") { contentPart() })
        let twelve = try contentTop(of: Card(title: "Vzhled", spacing: 12) { contentPart() })
        let twenty = try contentTop(of: Card(title: "Vzhled", spacing: 20) { contentPart() })
        #expect(usual > 20 + 12, "the content starts at \(usual)")
        #expect(twelve == usual)
        #expect(twenty - usual == 8)
    }

    @Test func theTitleOfACardIsAHeadingAndItsAccessoryIsReadInIt() async throws {
        let card = Card(title: "Pravidla výpočtu", accessory: "verze 2026.1") {
            Text(verbatim: "Obsah karty")
        }

        try await withHostedView(card.padding(24), size: CGSize(width: 600, height: 240)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Pravidla výpočtu", in: window) != nil }
                let group = try #require(accessibilityElement(labelled: "Pravidla výpočtu", in: window))
                // The title is a heading of the group, and the accessory is read in it as text.
                let heading = (group.accessibilityChildren?() ?? []).map { $0 as AnyObject }.first { element in
                    element.accessibilityRole?()?.rawValue == "AXHeading"
                }
                #expect(heading?.accessibilityLabel?() == "Pravidla výpočtu")
                let readings = accessibilityReadings(under: group)
                #expect(readings.contains("verze 2026.1"), "read as \(readings)")
            }
        }
    }

    @Test func aCardTakesTheHeightItIsOfferedOnlyWhereItIsToFillIt() async throws {
        @MainActor func heightOfCard(fillsHeight: Bool) async throws -> CGFloat {
            var height: CGFloat = 0
            let card = Card(label: "Mezní odvod", fillsHeight: fillsHeight) {
                Text(verbatim: "Obsah karty")
            }
            try await withHostedView(card.padding(24), size: CGSize(width: 600, height: 400)) { window in
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Mezní odvod", in: window) != nil }
                    height = try #require(frameOfCard(labelled: "Mezní odvod", in: window)).height
                }
            }
            return height
        }

        // A card of one line of text is as high as the line and its padding. Asked to fill the height, it has the 400
        // points of the window less the 24 around it, so that the cards of a row of equal heights are of one height.
        let hugging = try await heightOfCard(fillsHeight: false)
        let filling = try await heightOfCard(fillsHeight: true)
        #expect(hugging < 100, "a card that does not fill is \(hugging) high")
        #expect(abs(filling - 352) < 0.5, "a card that fills is \(filling) high")
    }

    @Test func aResultCardIsReadAsAGroupUnderItsLabel() async throws {
        let card = ResultCard(label: "Výsledek") {
            Text(verbatim: "Vlevo")
        } trailing: {
            Text(verbatim: "Vpravo")
        }

        try await withHostedView(card.padding(24), size: CGSize(width: 1_000, height: 240)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Výsledek", in: window) != nil }
                let group = try #require(accessibilityElement(labelled: "Výsledek", in: window))
                let readings = accessibilityReadings(under: group)
                #expect(readings.contains("Vlevo"), "read as \(readings)")
                #expect(readings.contains("Vpravo"), "read as \(readings)")
            }
        }
    }

    // MARK: The key figure

    /// The sentence of the second figure of Odhad odvodů, in the three parts it is set in: before the amount, the
    /// amount that stands out, and after it.
    private let beforeAmount = "Tolik si odložte stranou – navíc k zálohám "
    private let amount = "252\u{00A0}720\u{00A0}Kč"
    private let afterAmount = ", které platíte průběžně. Platí se po skončení roku."
    private var sentence: String {
        beforeAmount + amount + afterAmount
    }

    @Test func theSentenceOfAKeyFigureIsSplitAtItsEmphasis() {
        let data = KeyFigureData(
            eyebrow: "Odhad doplatku odvodů bez záloh", figure: "197\u{00A0}148\u{00A0}Kč", sentence: sentence,
            sentenceEmphasis: amount)

        #expect(
            data.sentenceParts == [
                KeyFigureSentencePart(text: beforeAmount, isEmphasised: false),
                KeyFigureSentencePart(text: amount, isEmphasised: true),
                KeyFigureSentencePart(text: afterAmount, isEmphasised: false),
            ])
    }

    @Test func aSentenceWithoutAnEmphasisIsOnePlainPart() {
        let plain = KeyFigureData(eyebrow: "Zbývá zaplatit", figure: "42\u{00A0}159\u{00A0}Kč", sentence: sentence)
        let empty = KeyFigureData(
            eyebrow: "Zbývá zaplatit", figure: "42\u{00A0}159\u{00A0}Kč", sentence: sentence, sentenceEmphasis: "")
        let missing = KeyFigureData(
            eyebrow: "Zbývá zaplatit", figure: "42\u{00A0}159\u{00A0}Kč", sentence: sentence,
            sentenceEmphasis: "999\u{00A0}Kč")

        for data in [plain, empty, missing] {
            #expect(data.sentenceParts == [KeyFigureSentencePart(text: sentence, isEmphasised: false)])
        }
        #expect(KeyFigureData(eyebrow: "Zbývá zaplatit", figure: "0\u{00A0}Kč").sentenceParts == [])
    }

    @Test func theEmphasisMayBeTheWholeSentenceOrItsEnds() {
        func parts(of sentence: String, emphasis: String) -> [KeyFigureSentencePart] {
            KeyFigureData(eyebrow: "E", figure: "1", sentence: sentence, sentenceEmphasis: emphasis).sentenceParts
        }

        #expect(parts(of: "Celé.", emphasis: "Celé.") == [KeyFigureSentencePart(text: "Celé.", isEmphasised: true)])
        #expect(
            parts(of: "Začátek věty.", emphasis: "Začátek")
                == [
                    KeyFigureSentencePart(text: "Začátek", isEmphasised: true),
                    KeyFigureSentencePart(text: " věty.", isEmphasised: false),
                ])
        #expect(
            parts(of: "Konec věty", emphasis: "věty")
                == [
                    KeyFigureSentencePart(text: "Konec ", isEmphasised: false),
                    KeyFigureSentencePart(text: "věty", isEmphasised: true),
                ])
    }

    /// The height of the key figure `data` in a room of `width` points.
    private func height(of data: KeyFigureData, width: CGFloat) -> CGFloat {
        let view = KeyFigureView(data).frame(width: width, alignment: .leading)
        return NSHostingView(rootView: view).fittingSize.height
    }

    @Test func theShareStandsOnTheBaselineOfTheFigureAndGoesUnderItWhenTheRoomIsNarrow() {
        let figure = "449\u{00A0}868\u{00A0}Kč"
        let withShare = KeyFigureData(
            eyebrow: "Odhad odvodů za celý rok 2026", figure: figure, share: "16,7\u{00A0}% z příjmů",
            sentence: "Odvody z odhadovaného příjmu.")
        let withoutShare = KeyFigureData(
            eyebrow: "Odhad odvodů za celý rok 2026", figure: figure, sentence: "Odvody z odhadovaného příjmu.")

        // Where there is room the share adds no height: it is on the line of the figure.
        #expect(height(of: withShare, width: 700) == height(of: withoutShare, width: 700))
        // Where there is none, it is a line of its own under the figure.
        #expect(height(of: withShare, width: 300) > height(of: withoutShare, width: 300) + 10)
    }

    /// The sentence under the figure is set at most 416 points wide, the 32 em of the 13-point type that the design
    /// gives it (about 35 em of it would have been 460), so a long sentence breaks there in a wide window; a short one
    /// is not widened to it.
    @Test func theSentenceOfAKeyFigureWrapsAt416Points() {
        let long = String(repeating: "Odvody z příjmů od 1. 1. do 17. 10. 2026 po odečtení záloh. ", count: 5)
        let wrapped = KeyFigureData(eyebrow: "Zbývá zaplatit", figure: "42\u{00A0}159\u{00A0}Kč", sentence: long)
        let short = KeyFigureData(eyebrow: "Zbývá zaplatit", figure: "42\u{00A0}159\u{00A0}Kč", sentence: "Hotovo.")

        let wrappedWidth = NSHostingView(rootView: KeyFigureView(wrapped)).fittingSize.width
        let shortWidth = NSHostingView(rootView: KeyFigureView(short)).fittingSize.width

        #expect(abs(wrappedWidth - 416) < 0.5, "A long sentence makes the key figure \(wrappedWidth) points wide")
        #expect(shortWidth < 416 - 100, "A short sentence makes the key figure \(shortWidth) points wide")
        // In a window as wide as 800 points the sentence still stops at 416: the height is that of the same sentence in
        // a room of exactly that width.
        func height(inRoomOf width: CGFloat) -> CGFloat {
            NSHostingView(rootView: KeyFigureView(wrapped).frame(width: width, alignment: .leading)).fittingSize.height
        }
        #expect(abs(height(inRoomOf: 800) - height(inRoomOf: 416)) < 0.5)
        #expect(height(inRoomOf: 300) > height(inRoomOf: 416) + 10)
    }

    /// A screen may give the sentence another width than the 416 points of the default, as the design does for the
    /// key figures of Odhad odvodů, whose sentences are 34 em and 36 em of the 13-point type (442 and 468 points): a
    /// long sentence stops there in a wide room, and a room narrower than the width gives the room it has.
    @Test func theSentenceOfAKeyFigureWrapsAtTheWidthItIsGiven() {
        let long = String(repeating: "Tolik si odložte stranou – navíc k zálohám 268 080 Kč, které platíte. ", count: 6)
        let data = KeyFigureData(eyebrow: "Odhad doplatku", figure: "198\u{00A0}702\u{00A0}Kč", sentence: long)

        for width in [CGFloat(442), 468] {
            let view = KeyFigureView(data, sentenceMaximumWidth: width)
            #expect(abs(NSHostingView(rootView: view).fittingSize.width - width) < 0.5, "\(width)")
            func height(inRoomOf room: CGFloat) -> CGFloat {
                NSHostingView(rootView: view.frame(width: room, alignment: .leading)).fittingSize.height
            }
            #expect(abs(height(inRoomOf: 900) - height(inRoomOf: width)) < 0.5, "\(width)")
            #expect(height(inRoomOf: 300) > height(inRoomOf: width) + 10, "\(width)")
        }
        // Without a width of its own, the sentence is held to 416 points.
        let held = NSHostingView(rootView: KeyFigureView(data)).fittingSize.width
        #expect(abs(held - 416) < 0.5, "\(held)")
    }

    @Test func aKeyFigureIsReadAsOnePhrase() async throws {
        let data = KeyFigureData(
            eyebrow: "Odhad odvodů za celý rok 2026", figure: "449\u{00A0}868\u{00A0}Kč",
            share: "16,7\u{00A0}% z příjmů", sentence: "Odvody z odhadovaného příjmu.")

        try await withHostedView(KeyFigureView(data).padding(24), size: CGSize(width: 800, height: 240)) { window in
            try await withAccessibilityElements {
                try await waitUntil { !accessibilityReadings(in: window).isEmpty }
                // One element: the eyebrow as it is written (the capitals are only how it is drawn), the figure, the
                // share and the sentence, in the order they are drawn in.
                #expect(
                    accessibilityReadings(in: window) == [
                        "Odhad odvodů za celý rok 2026, 449\u{00A0}868\u{00A0}Kč, 16,7\u{00A0}% z příjmů,"
                            + " Odvody z odhadovaného příjmu."
                    ])
            }
        }
    }

    // MARK: The figure tile

    @Test func aFigureTileIsReadAsOnePhraseWithoutItsDot() async throws {
        @MainActor func readings(marksNetIncome: Bool) async throws -> [String] {
            var found: [String] = []
            let tile = FigureTile(
                FigureTileData(
                    label: "Čistý příjem průměrně za měsíc", figure: "190\u{00A0}037\u{00A0}Kč",
                    share: "83,3\u{00A0}%", note: "průměr za leden–říjen", marksNetIncome: marksNetIncome))
            try await withHostedView(tile.padding(24), size: CGSize(width: 480, height: 160)) { window in
                try await withAccessibilityElements {
                    try await waitUntil { !accessibilityReadings(in: window).isEmpty }
                    found = accessibilityReadings(in: window)
                }
            }
            return found
        }

        // One element: the label, the figure, the share and the note, in the order they are drawn in.
        let plain = try await readings(marksNetIncome: false)
        #expect(
            plain == [
                "Čistý příjem průměrně za měsíc, 190\u{00A0}037\u{00A0}Kč, 83,3\u{00A0}%, průměr za leden–říjen"
            ])
        // The green dot of the net income is only for the eyes.
        #expect(try await readings(marksNetIncome: true) == plain)
    }

    /// The tile of the net income carries a mark in the green of the net income in front of its label, 20 points from
    /// the left of the picture where the tile stands in a padding of 20: a dot of 8 points where it is the card of
    /// Odhad odvodů, a line of 16 by 3 points, like the key of the net income in the legend of a chart, where it is the
    /// strip of Příjmy; no mark where the tile is not about the net income.
    @Test func aTileAboutTheNetIncomeIsMarkedWithADotOrALine() throws {
        let green = try OffscreenPicture.bytes(of: Palette.green, in: .light)
        func picture(marksNetIncome: Bool, marker: NetIncomeMarker) throws -> OffscreenPicture {
            let tile = FigureTile(
                FigureTileData(
                    label: "Čistý příjem průměrně za měsíc", figure: "190\u{00A0}037\u{00A0}Kč",
                    note: "průměr za leden–říjen", marksNetIncome: marksNetIncome, marker: marker))
            return try OffscreenPicture(of: tile.padding(20), in: .light)
        }
        /// The green pixels in the strip from `x` to `x + width` points, down the whole picture.
        func greens(_ picture: OffscreenPicture, x: CGFloat, width: CGFloat) -> Int {
            picture.count(
                near: green, in: CGRect(x: x, y: 0, width: width, height: picture.size.height), by: 24)
        }
        /// The pixel rows, in a strip 2 points wide down the middle of a dot and in the first 8 points of a line, that
        /// are green: the height of the mark, 2 rows to the point.
        func greenRows(_ picture: OffscreenPicture) -> Int {
            picture.rows(near: green, from: 23, to: 25, by: 24).count
        }

        let line = try picture(marksNetIncome: true, marker: .line)
        let dot = try picture(marksNetIncome: true, marker: .dot)
        let none = try picture(marksNetIncome: false, marker: .line)

        // The line is 16 points wide: green in its last 6 points, 30 to 36 points from the left, and not beyond.
        #expect(greens(line, x: 30, width: 6) >= 6 * 2 * 2, "The line ends before 36 points")
        #expect(greens(line, x: 36, width: 4) == 0)
        #expect(greens(line, x: 0, width: 20) == 0)
        // Of its height of 3 points (6 rows of pixels) the rows that are whole are at least 4 and at most 6.
        #expect((4...6).contains(greenRows(line)), "The line is \(greenRows(line)) rows of pixels tall")
        // The dot is 8 points wide: nothing is green from 28 points on, and its middle is 8 points tall.
        #expect(greens(dot, x: 20, width: 8) >= 150)
        #expect(greens(dot, x: 28, width: 12) == 0)
        #expect(greens(dot, x: 0, width: 20) == 0)
        #expect(greenRows(dot) >= 12, "The dot is \(greenRows(dot)) rows of pixels tall")
        // A tile that is not about the net income has no mark, whatever shape it is given.
        #expect(greens(none, x: 0, width: none.size.width) == 0)
    }

    /// The line is centred on the line of the label, as the key of a legend is: the label is a line of callout text
    /// of 15 points at the top of the tile, which stands 20 points from the top of the picture, so its middle is 27,5
    /// points down.
    @Test func theLineOfTheNetIncomeIsCentredOnTheLineOfItsLabel() throws {
        let green = try OffscreenPicture.bytes(of: Palette.green, in: .light)
        let tile = FigureTile(
            FigureTileData(
                label: "Čistý příjem od 1.\u{00A0}1. do 17.\u{00A0}10.", figure: "1\u{00A0}933\u{00A0}471\u{00A0}Kč",
                note: "88,2\u{00A0}% příjmů bez DPH po odvodech", marksNetIncome: true, marker: .line))
        let picture = try OffscreenPicture(of: tile.padding(20), in: .light)

        let rows = picture.rows(near: green, from: 23, to: 25, by: 24)

        let first = try #require(rows.first)
        let last = try #require(rows.last)
        #expect(abs((first + last + 0.5) / 2 - 27.5) <= 1, "The line is from \(first) to \(last + 0.5) points down")
    }

    @Test func aFigureTileStacksItsLabelItsFigureAndItsNoteWith2PointsBetween() throws {
        // Three lines of text, one above the other: the tile is as high as they are and the two gaps of 2 points. A
        // tile without a note is shorter by the note and the gap before it.
        func height(note: String?) -> CGFloat {
            let tile = FigureTile(FigureTileData(label: "Doplatek", figure: "5\u{00A0}371\u{00A0}Kč", note: note))
            return NSHostingView(rootView: tile).fittingSize.height
        }

        let with = height(note: "s přiznáním a přehledy")
        let without = height(note: nil)
        #expect(with - without > 2 + 10, "with a note \(with), without \(without)")
        #expect(with - without < 2 + 20, "with a note \(with), without \(without)")
    }
}
