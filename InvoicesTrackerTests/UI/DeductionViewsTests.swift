import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The parts of the deductions that Zálohy a odpočty and the Simulátor share — the bar of a limit, the summary of the
/// interest, the notes and messages under the fields — drawn off-screen in a light and in a dark window and read from
/// their pixels: they take their colours from the palette, which a window shows differently in each. Each is drawn on
/// the colour of a card, so that a pixel is the colour the eye sees and not a translucent one on nothing. The controls
/// that macOS draws, such as the fields, are not drawn by the picture and are not looked at.
@MainActor
struct DeductionViewsTests {
    // MARK: The inputs of the tests

    /// What the summary and the notes are given: the interest of 250 000 Kč, of which 100 000 Kč are over the limit.
    private static let hints = DeductionHints(
        mortgageAllowed: "150\u{00A0}000\u{00A0}Kč", mortgageOverLimit: "100\u{00A0}000\u{00A0}Kč",
        mortgageLimit: "limit 150\u{00A0}000\u{00A0}Kč za 12\u{00A0}měsíců", retirementLimits: [],
        retirementAllowed: "6\u{00A0}480\u{00A0}Kč",
        giftsNote: "od 1\u{00A0}000\u{00A0}Kč (nebo nad 2\u{00A0}% základu), nejvýš 30\u{00A0}% základu",
        giftsAllowed: "20\u{00A0}000\u{00A0}Kč")

    /// The fields of the deductions, none of them typed in and none of them refused.
    private static let inputs = DeductionInputs(text: { _ in .constant("") }, message: { _ in nil }, submit: {})

    private func whole(_ picture: OffscreenPicture) -> CGRect {
        CGRect(origin: .zero, size: picture.size)
    }

    // MARK: The bar of a limit

    /// The picture of a bar for a claim of `permille` thousandths of its limit, in a room 400 points wide with 20
    /// points around it.
    private func barPicture(permille: Int, in scheme: ColorScheme) throws -> OffscreenPicture {
        let bars = RetirementLimitBars(
            limits: [LimitUse(title: "Společný limit", usedText: "6 480 z 48 000 Kč", usedPermille: permille)])
        return try OffscreenPicture(of: bars.frame(width: 400).padding(20).background(Palette.bgCard), in: scheme)
    }

    /// The row of the bar in the pictures of `barPicture(permille:in:)`: the rows of the use of a claim of some
    /// thousandths, a little taller than the 6 points of the bar. The soft edges of the line of text over the bar pass
    /// through every shade between the card and the text, the shade of the track among them, so the track is looked
    /// for in this row only.
    private func barRow(in scheme: ColorScheme) throws -> CGRect {
        let tax = try OffscreenPicture.bytes(of: Palette.tax, in: scheme)
        let use = try #require(
            try barPicture(permille: 135, in: scheme).extent(near: tax, by: 2), "\(scheme): no use of the limit")
        return CGRect(x: 0, y: use.minY - 1, width: 440, height: use.height + 2)
    }

    /// The bar is the bar of the design: a track 6 points tall in the grey fill, and over it the use in the colour of
    /// the income tax, from the start of the track and as wide as the use is of the limit: 6 480 of 48 000 Kč is
    /// 13,5 % of 400 points.
    @Test(arguments: [ColorScheme.light, .dark])
    func theBarOfALimitIsASixPointTrackWithTheUseInTheColourOfTheTax(scheme: ColorScheme) throws {
        let picture = try barPicture(permille: 135, in: scheme)
        let tax = try OffscreenPicture.bytes(of: Palette.tax, in: scheme)
        let track = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
        let row = try barRow(in: scheme)

        let use = try #require(picture.extent(near: tax, by: 2), "\(scheme): no use of the limit in the tax colour")
        let rest = try #require(picture.extent(near: track, in: row, by: 2), "\(scheme): no track in the grey fill")

        #expect(abs(use.height - 6) <= 1, "\(scheme): the use is \(use.height) points tall")
        #expect(abs(rest.height - 6) <= 1, "\(scheme): the track is \(rest.height) points tall")
        #expect(abs(use.minX - 20) <= 1.5, "\(scheme): the use starts at \(use.minX)")
        #expect(abs(use.width - 54) <= 2, "\(scheme): the use is \(use.width) points wide, not 13,5 % of 400")
        #expect(abs(rest.minX - use.maxX) <= 1.5, "\(scheme): the track starts at \(rest.minX), not at \(use.maxX)")
        #expect(abs(rest.maxX - 420) <= 1.5, "\(scheme): the track ends at \(rest.maxX)")
    }

    /// A claim of nothing leaves the whole track bare, and one that uses the whole limit fills it.
    @Test(arguments: [ColorScheme.light, .dark])
    func aBarOfNothingIsBareAndOneOfTheWholeLimitIsFull(scheme: ColorScheme) throws {
        let tax = try OffscreenPicture.bytes(of: Palette.tax, in: scheme)
        let track = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
        let row = try barRow(in: scheme)

        let bare = try barPicture(permille: 0, in: scheme)
        let full = try barPicture(permille: 1_000, in: scheme)

        let bareTrack = try #require(bare.extent(near: track, in: row, by: 2), "\(scheme): no track")
        #expect(bare.extent(near: tax, by: 2) == nil, "\(scheme): a use where nothing is claimed")
        #expect(abs(bareTrack.width - 400) <= 1.5, "\(scheme): the track is \(bareTrack.width) points wide")
        let filled = try #require(full.extent(near: tax, by: 2), "\(scheme): no use of the whole limit")
        #expect(full.extent(near: track, in: row, by: 2) == nil, "\(scheme): a track where the whole limit is used")
        #expect(abs(filled.width - 400) <= 1.5, "\(scheme): the use is \(filled.width) points wide")
    }

    // MARK: The summary of the interest

    /// What the interest allows is a panel on the inset background, as wide as the card's content, with what is over
    /// the limit in the orange of text and the limit in the grey of captions.
    @Test(arguments: [ColorScheme.light, .dark])
    func theSummaryOfTheInterestIsAnInsetPanelWithWhatIsOverTheLimitInOrangeText(scheme: ColorScheme) throws {
        let summary = MortgageClaimSummary(hints: Self.hints).frame(width: 600).background(Palette.bgCard)
        let picture = try OffscreenPicture(of: summary, in: scheme)
        let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
        let orange = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)

        let panel = try #require(picture.extent(near: inset, by: 2), "\(scheme): no panel on the inset background")

        #expect(abs(panel.width - 600) <= 1.5, "\(scheme): the panel is \(panel.width) points wide")
        #expect(picture.count(near: orange, in: panel, by: 8) > 40, "\(scheme): what is over is not orange text")
        // The panel holds "Uplatníte" and the amount in the colour of text as well.
        try picture.expectText(
            in: panel, setIn: Palette.text3, atLeast: 800, alongside: [Palette.text], scheme: scheme,
            "\(scheme): the limit is not a caption")
    }

    // MARK: Notes and messages

    /// A message under a field is in the red of text.
    @Test(arguments: [ColorScheme.light, .dark])
    func aMessageUnderAFieldIsInTheRedOfText(scheme: ColorScheme) throws {
        let message = FieldMessage(text: "Zadejte částku v celých korunách, například 13 340.")
            .frame(width: 400).background(Palette.bgCard)
        let picture = try OffscreenPicture(of: message, in: scheme)
        let red = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)

        #expect(picture.count(near: red, in: whole(picture), by: 8) > 100, "\(scheme): the message is not red text")
    }

    /// The title over a field is in the secondary text.
    @Test(arguments: [ColorScheme.light, .dark])
    func theTitleOverAFieldIsInSecondaryText(scheme: ColorScheme) throws {
        let field = TitledAmountField(
            title: "Zaplacené úroky za rok", text: .constant(""), width: 120, message: nil, submit: {})
        let picture = try OffscreenPicture(
            of: field.frame(width: 300, alignment: .leading).background(Palette.bgCard), in: scheme)

        try picture.expectText(
            in: whole(picture), setIn: Palette.text2, atLeast: 260, scheme: scheme,
            "\(scheme): the title is not secondary")
    }

    /// The notes under the savings and under the gifts are in the grey of captions, and what the savings allow is in
    /// the colour of text, semibold, where the sentence round it is not.
    @Test(arguments: [ColorScheme.light, .dark])
    func theNotesUnderTheSavingsAndTheGiftsAreInTheGreyOfCaptions(scheme: ColorScheme) throws {
        let savingsNote = RetirementNote(year: 2026, allowed: "6\u{00A0}480\u{00A0}Kč")
        let savings = try OffscreenPicture(of: savingsNote.frame(width: 600).background(Palette.bgCard), in: scheme)
        let giftsRow = GiftsRow(inputs: Self.inputs, hints: Self.hints)
        let gifts = try OffscreenPicture(of: giftsRow.frame(width: 600).background(Palette.bgCard), in: scheme)

        try savings.expectText(
            in: whole(savings), setIn: Palette.text3, atLeast: 1_450, alongside: [Palette.text], scheme: scheme,
            "\(scheme): the savings note")
        // The sentence round the amount is set in the grey of captions, and its edge passes through the band of the
        // faintest text, which the small amount cannot outnumber three to one.
        try savings.expectText(
            in: whole(savings), setIn: Palette.text, atLeast: 170, alongside: [Palette.text3, Palette.text4],
            scheme: scheme, "\(scheme): the amount is not in text")
        // The gifts have the label of their field in the colour of text beside the note.
        try gifts.expectText(
            in: whole(gifts), setIn: Palette.text3, atLeast: 990, alongside: [Palette.text], scheme: scheme,
            "\(scheme): the note of the gifts")
    }
}
