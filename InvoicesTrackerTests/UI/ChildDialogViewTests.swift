import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The dialog of a child drawn off-screen in a light and in a dark window and read from its pixels: what the child
/// comes to in a panel on the inset background, and the buttons of a dialog, 32 points tall. The fields and the menus,
/// which macOS draws, are not in the picture; the model of the dialog is the one the sheet is given.
@MainActor
struct ChildDialogViewTests {
    // MARK: The dialog of the tests

    /// Anna, born 3. 9. 2019, mine, in the household the whole of 2026 and stored.
    private static let anna = FamilyChild(
        child: Child(id: 1, name: "Anna", birthDate: civilDate("2019-09-03")),
        year: ChildYear(household: MonthRange.wholeYear, claimant: .me, order: 1, ztpp: nil, studies: nil),
        isStored: true)

    /// The dialog of Anna, or of a new child, with the date of birth typed in, `livesApart` as chosen, and what the
    /// sheet draws of it: 620 points wide, on the colour of a card, which the sheet that carries it gives it.
    private func picture(
        ofAnna stored: Bool, livesApart: Bool = false, in scheme: ColorScheme
    ) throws -> OffscreenPicture {
        let editing = FamilyEditingStub(children: [Self.anna])
        let model = ChildDialogModel(editing: editing, year: 2026, child: stored ? Self.anna : nil, mode: .stored)
        model.name = "Anna"
        model.birthDateText = "3. 9. 2019"
        model.livesApart = livesApart
        return try OffscreenPicture(of: ChildDialog(model: model, close: {}).background(Palette.bgCard), in: scheme)
    }

    /// The footer of the dialog: the strip at the bottom of the picture, with the bottom padding of the sheet.
    private func footer(of picture: OffscreenPicture) -> CGRect {
        CGRect(x: 0, y: picture.size.height - 70, width: picture.size.width, height: 70)
    }

    // MARK: What the child comes to

    /// What the child comes to in the year is a panel on the inset background as wide as the sheet's content (572 of
    /// its 620 points), with the words in the secondary text while the child counts and none in the colour of text, and
    /// in the orange of text while the child counts in no month. The panel is the band of the inset colour across the
    /// sheet; its edges are read from the points just inside and just outside them.
    @Test(arguments: [ColorScheme.light, .dark])
    func whatTheChildComesToIsAnInsetPanelWithTheWordsOfItsMeaning(scheme: ColorScheme) throws {
        let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)
        let card = try OffscreenPicture.bytes(of: Palette.bgCard, in: scheme)
        let orange = try OffscreenPicture.bytes(of: Palette.orangeText, in: scheme)
        let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)

        for livesApart in [false, true] {
            let picture = try picture(ofAnna: false, livesApart: livesApart, in: scheme)
            let band = try #require(
                picture.band(near: inset, from: 30, to: 590, by: 2), "\(scheme): no panel on the inset background")
            let middle = band.midY
            for (name, x, colour) in [
                ("just inside the start", 26.0, inset), ("just before it", 22.0, card),
                ("just inside the end", 594.0, inset), ("just after it", 598.0, card),
            ] {
                let found = picture.bytes(at: CGPoint(x: x, y: middle))
                #expect(
                    zip(found, colour).allSatisfy { abs($0 - $1) <= 2 }, "\(scheme): \(name) of the panel is \(found)")
            }
            let panel = CGRect(x: 24, y: band.minY, width: 572, height: band.height)
            if livesApart {
                #expect(picture.count(near: orange, in: panel, by: 8) > 100, "\(scheme): the words are not orange")
            } else {
                try picture.expectText(
                    in: panel, setIn: Palette.text2, atLeast: 930, scheme: scheme,
                    "\(scheme): the words are not secondary text")
            }
            #expect(picture.count(near: text, in: panel, by: 8) == 0, "\(scheme): the words are in the colour of text")
        }
    }

    // MARK: The buttons

    /// Uložit dítě is a capsule in the accent and Zrušit one on the grey fill, both 32 points tall, the height of the
    /// buttons of a dialog.
    @Test(arguments: [ColorScheme.light, .dark])
    func theButtonsOfTheDialogAreCapsules32PointsTall(scheme: ColorScheme) throws {
        let picture = try picture(ofAnna: false, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
        let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)

        let save = try #require(picture.extent(near: accent, in: footer(of: picture), by: 2), "\(scheme): no save")
        let cancel = try #require(picture.extent(near: fill, in: footer(of: picture), by: 2), "\(scheme): no cancel")

        #expect(abs(save.height - 32) <= 1, "\(scheme): Uložit dítě is \(save.height) points tall")
        #expect(abs(cancel.height - 32) <= 1, "\(scheme): Zrušit is \(cancel.height) points tall")
        #expect(cancel.maxX < save.minX, "\(scheme): Zrušit \(cancel) is not before Uložit dítě \(save)")
    }

    /// Odebrat dítě, which a stored child has at the leading end of the footer, is a link in the red of text, not a
    /// button: it has no background, so no pixel of the pale red a destructive button stands on.
    @Test(arguments: [ColorScheme.light, .dark])
    func removingAChildIsALinkInTheRedOfText(scheme: ColorScheme) throws {
        let picture = try picture(ofAnna: true, in: scheme)
        let red = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)
        let tint = try OffscreenPicture.bytes(of: Palette.redTint, in: scheme)

        let link = try #require(picture.extent(near: red, in: footer(of: picture), by: 8), "\(scheme): no link")

        #expect(link.minX < 100, "\(scheme): the link starts at \(link.minX), not at the leading end")
        #expect(picture.count(near: tint, in: footer(of: picture), by: 2) == 0, "\(scheme): a pale red button")
    }
}
