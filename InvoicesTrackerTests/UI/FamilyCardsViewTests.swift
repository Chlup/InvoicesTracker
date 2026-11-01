import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The cards of the family, "Děti · daňové zvýhodnění" and "Manžel / manželka · sleva na dani", drawn off-screen in a
/// light and in a dark window and read from their pixels: they are made of the parts of the design, which take their
/// colours from the palette. The panels are found by their colour, which the cards use for nothing else; the words by
/// the colour they are set in. One test shows the cards in a window, to read the labels they are read under.
@MainActor
struct FamilyCardsViewTests {
    // MARK: The family of the tests

    /// The row of a child born 3. 9. 2019 who is mine and lives in the household the whole year, with what its card
    /// says of it.
    private static func row(
        _ name: String, status: String, amount: String, hasAmount: Bool, countsInNoMonth: Bool = false
    ) -> ChildCardRow {
        ChildCardRow(
            member: FamilyChild(
                child: Child(id: 1, name: name, birthDate: civilDate("2019-09-03")),
                year: ChildYear(household: MonthRange.wholeYear, claimant: .me, order: 1, ztpp: nil, studies: nil),
                isStored: true),
            name: name, birth: "nar. 3.\u{00A0}9.\u{00A0}2019", status: status, countsInNoMonth: countsInNoMonth,
            amount: amount, hasAmount: hasAmount)
    }

    /// The card of the children with the rows and the hint it is given, read under `label` and saying `emptyText`
    /// while it has no row: those of Zálohy a odpočty unless told otherwise.
    private static func children(
        rows: [ChildCardRow], proofHint: String? = nil, addNote: String? = nil, label: String = "Děti",
        emptyText: String = ChildrenCardContent.noChildren
    ) -> ChildrenCardContent {
        ChildrenCardContent(
            label: label, total: rows.isEmpty ? nil : "15\u{00A0}204\u{00A0}Kč za rok",
            rates: "Za každý měsíc, na jehož začátku.", rows: rows, proofHint: proofHint, bonusHint: nil,
            addNote: addNote, emptyText: emptyText)
    }

    /// The card of the spouse, with `youngChild` in its box and `total` beside its title, read under `label`.
    private static func spouse(
        total: String, totalCounts: Bool, youngChild: YoungChildNote? = nil, label: String = "Manžel nebo manželka"
    ) -> SpouseCardContent {
        SpouseCardContent(
            label: label, total: total, totalCounts: totalCounts, claimLine: "24\u{00A0}840\u{00A0}Kč za rok.",
            incomeTitle: "Vlastní příjmy manžela / manželky za rok 2026",
            incomeStatus: "do limitu 68\u{00A0}000\u{00A0}Kč", incomeIsOverLimit: false, youngChild: youngChild,
            result: "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč")
    }

    /// The picture of the card of the children, 640 points wide.
    private func picture(of content: ChildrenCardContent, in scheme: ColorScheme) throws -> OffscreenPicture {
        try OffscreenPicture(of: ChildrenCard(content: content, open: { _ in }).frame(width: 640), in: scheme)
    }

    /// The picture of the card of the spouse, 640 points wide, for a spouse who is claimed or not.
    private func picture(
        of content: SpouseCardContent, claimed: Bool, in scheme: ColorScheme
    ) throws -> OffscreenPicture {
        let spouse = SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil)
        let card = SpouseCard(
            content: content, editing: FamilyEditingStub(spouse: claimed ? spouse : nil),
            income: SpouseIncomeInput(text: .constant("0"), message: nil, submit: {}))
        return try OffscreenPicture(of: card.frame(width: 640), in: scheme)
    }

    /// The inside of a card in `picture`, without the 6 points at its edge, where the ring of its elevation is drawn,
    /// which is a grey as light as the fill of a button.
    private func inside(_ picture: OffscreenPicture) -> CGRect {
        CGRect(origin: .zero, size: picture.size).insetBy(dx: 6, dy: 6)
    }

    /// The smallest rectangle inside the card in `picture` that holds every pixel of `colour`, or nil for none.
    private func extent(of colour: [Int], in picture: OffscreenPicture) -> CGRect? {
        picture.extent(near: colour, in: inside(picture), by: 2)
    }

    // MARK: The children

    /// The hint about the other parent is a panel on the inset background, as wide as the content of the card (600
    /// points of the 640), with its words in the secondary text and none in the colour of text. The panel is the band
    /// of the inset colour across the card; its edges are read from the points just inside and just outside them.
    @Test(arguments: [ColorScheme.light, .dark])
    func theHintUnderTheChildrenIsAnInsetPanelWithSecondaryText(scheme: ColorScheme) throws {
        let anna = Self.row(
            "Anna", status: "1. dítě · 12\u{00A0}měsíců", amount: "15\u{00A0}204\u{00A0}Kč", hasAmount: true)
        let hint = Self.children(
            rows: [anna],
            proofHint: "Druhý rodič, který s vámi žije, na stejné dítě ve stejném měsíci zvýhodnění uplatnit nemůže.")
        let picture = try picture(of: hint, in: scheme)
        let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
        let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
        let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)

        let band = try #require(
            picture.band(near: inset, from: 26, to: 614, by: 2), "\(scheme): no panel on the inset background")

        #expect(band.height >= 30, "\(scheme): the panel is \(band.height) points tall")
        let middle = band.midY
        for (name, x, colour) in [
            ("just inside the start", 22.0, inset), ("just before it", 18.0, card),
            ("just inside the end", 618.0, inset), ("just after it", 622.0, card),
        ] {
            let found = picture.bytes(at: CGPoint(x: x, y: middle))
            #expect(zip(found, colour).allSatisfy { abs($0 - $1) <= 2 }, "\(scheme): \(name) of the panel is \(found)")
        }
        let words = CGRect(x: 20, y: band.minY, width: 600, height: band.height)
        try picture.expectText(
            in: words, setIn: Palette.text2, atLeast: 1_000, scheme: scheme,
            "\(scheme): the hint is not secondary text")
        #expect(picture.count(near: text, in: words, by: 8) == 0, "\(scheme): the hint is in the colour of text")
    }

    /// Přidat dítě is a button of the design inside a card: a capsule 28 points tall on the grey fill, at the bottom of
    /// the card, its padding of 20 points below it.
    @Test(arguments: [ColorScheme.light, .dark])
    func addingAChildIsACapsule28PointsTallOnTheGreyFill(scheme: ColorScheme) throws {
        let picture = try picture(of: Self.children(rows: []), in: scheme)
        let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
        let bottom = CGRect(x: 6, y: picture.size.height - 52, width: picture.size.width - 12, height: 34)

        let capsule = try #require(
            picture.extent(near: fill, in: bottom, by: 2), "\(scheme): no capsule on the grey fill")

        #expect(abs(capsule.height - 28) <= 1, "\(scheme): the capsule is \(capsule.height) points tall")
        #expect(abs(capsule.maxY - (picture.size.height - 20)) <= 1, "\(scheme): the capsule ends at \(capsule.maxY)")
    }

    /// What is not a figure or a sentence of the card but its absence is in the grey of captions: the dash of a child
    /// who brings nothing, and the sentence that there is no child.
    @Test(arguments: [ColorScheme.light, .dark])
    func theDashAndTheSentenceOfNoChildAreInTheGreyOfCaptions(scheme: ColorScheme) throws {
        let away = Self.row(
            "Petr", status: "v roce 2026 s vámi nežije", amount: "—", hasAmount: false, countsInNoMonth: true)

        let withDash = try picture(of: Self.children(rows: [away]), in: scheme)
        let empty = try picture(of: Self.children(rows: []), in: scheme)

        // The dash is the amount of the row, at the end of its line before the chevron. The row stands over the
        // hairline and the button, so its middle is 93 points over the bottom of the card, and nothing else of the card
        // is at the end of that line.
        let dash = CGRect(x: 560, y: withDash.size.height - 113, width: 48, height: 40)
        try withDash.expectText(in: dash, setIn: Palette.text3, atLeast: 20, scheme: scheme, "\(scheme): the dash")
        // The sentence stands between the two hairlines of the empty card, over its button: its strokes are 78 to 90
        // points over the bottom, and no other text of the card is between 72 and 100.
        let sentence = CGRect(x: 20, y: empty.size.height - 100, width: 450, height: 28)
        try empty.expectText(
            in: sentence, setIn: Palette.text3, atLeast: 1_200, scheme: scheme, "\(scheme): the sentence")
    }

    /// The note beside Přidat dítě in the Simulátor, that nothing is stored, is in the grey of captions, as the design
    /// sets it beside the button, and not in the orange of text. It is at the end of the line of the button, the last
    /// line of the card, which has the padding of 20 points under it.
    @Test(arguments: [ColorScheme.light, .dark])
    func theNoteBesideAddingAChildIsInTheGreyOfCaptions(scheme: ColorScheme) throws {
        let simulated = Self.children(rows: [], addNote: ChildrenCardContent.simulationNote)
        let picture = try picture(of: simulated, in: scheme)
        let orange = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)
        let line = CGRect(x: 200, y: picture.size.height - 52, width: picture.size.width - 220, height: 34)

        try picture.expectText(
            in: line, setIn: Palette.text3, atLeast: 400, scheme: scheme, "\(scheme): the note is not a caption")
        #expect(picture.count(near: orange, in: line, by: 8) == 0, "\(scheme): the note is orange text")
    }

    /// The cards are read under the label of their content, and the card of the children says the empty text of its
    /// content while the year has no child: the words that each screen gives them. Here those of the Simulátor.
    @Test func theCardsAreReadUnderTheLabelOfTheirContentAndSayItsEmptyText() async throws {
        let children = Self.children(
            rows: [], label: "Děti v simulaci", emptyText: ChildrenCardContent.noChildrenInSimulation)
        let spouse = Self.spouse(total: "neuplatní se", totalCounts: false, label: "Manžel nebo manželka v simulaci")
        let cards = VStack(spacing: 16) {
            ChildrenCard(content: children, open: { _ in })
            SpouseCard(
                content: spouse, editing: FamilyEditingStub(),
                income: SpouseIncomeInput(text: .constant("0"), message: nil, submit: {}))
        }
        .padding(24)

        try await withHostedView(cards, size: CGSize(width: 700, height: 700)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Děti v simulaci", in: window) != nil }
                #expect(frameOfCard(labelled: "Manžel nebo manželka v simulaci", in: window) != nil)
                #expect(frameOfCard(labelled: "Děti", in: window) == nil)
                #expect(showsText(ChildrenCardContent.noChildrenInSimulation, in: window))
                #expect(!showsText(ChildrenCardContent.noChildren, in: window))
            }
        }
    }

    // MARK: The spouse

    /// The box about the child under three is a note of the design: green while there is such a child and orange while
    /// there is none, as wide as the content of the card, with its words in the colour of text and not tinted.
    @Test(arguments: [ColorScheme.light, .dark])
    func theBoxAboutTheChildUnderThreeIsAGreenOrAnOrangeNote(scheme: ColorScheme) throws {
        let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
        let green = try OffscreenPicture.bytes(of: Palette.greenTint, in: scheme)
        let orange = try OffscreenPicture.bytes(of: Palette.orangeTint, in: scheme)
        let met = YoungChildNote(text: "Dítě do 3 let ve společné domácnosti: Tomáš (celý rok).", isMet: true)
        let unmet = YoungChildNote(text: "Od roku 2024 se sleva uplatní jen za měsíce.", isMet: false)

        let withChild = try picture(
            of: Self.spouse(total: "24\u{00A0}840\u{00A0}Kč za rok", totalCounts: true, youngChild: met), claimed: true,
            in: scheme)
        let without = try picture(
            of: Self.spouse(total: "neuplatní se", totalCounts: false, youngChild: unmet), claimed: true, in: scheme)

        let greenNote = try #require(extent(of: green, in: withChild), "\(scheme): no green note")
        let orangeNote = try #require(extent(of: orange, in: without), "\(scheme): no orange note")
        #expect(abs(greenNote.width - 600) <= 2, "\(scheme): the green note is \(greenNote.width) points wide")
        #expect(abs(orangeNote.width - 600) <= 2, "\(scheme): the orange note is \(orangeNote.width) points wide")
        #expect(withChild.count(near: text, in: greenNote, by: 8) > 40, "\(scheme): the green note is not in text")
        #expect(extent(of: green, in: without) == nil, "\(scheme): a green note where the child is missing")
        #expect(extent(of: orange, in: withChild) == nil, "\(scheme): an orange note where the child is there")
    }

    /// The credit that does not count says "neuplatní se" beside the title in the grey of captions, and one that counts
    /// has its amount in the colour of text.
    @Test(arguments: [ColorScheme.light, .dark])
    func theTotalOfASpouseWhoDoesNotCountIsInTheGreyOfCaptions(scheme: ColorScheme) throws {
        let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
        let header = CGRect(x: 380, y: 10, width: 260, height: 40)

        let none = try picture(of: Self.spouse(total: "neuplatní se", totalCounts: false), claimed: false, in: scheme)
        let counts = try picture(
            of: Self.spouse(total: "24\u{00A0}840\u{00A0}Kč za rok", totalCounts: true), claimed: false, in: scheme)

        try none.expectText(
            in: header, setIn: Palette.text3, atLeast: 270, scheme: scheme, "\(scheme): neuplatní se is not a caption")
        #expect(none.count(near: text, in: header, by: 8) == 0, "\(scheme): neuplatní se is in the colour of text")
        try counts.expectText(
            in: header, setIn: Palette.text, atLeast: 340, scheme: scheme, "\(scheme): the amount is not in text")
    }
}
