import AppKit
import SwiftUI
import Testing

@testable import InvoicesTracker

/// The small parts of Nastavení drawn off-screen in a light and in a dark window and read from their pixels: they take
/// their colours from the palette, which a window shows differently in each. Each is drawn on the colour of a card, so
/// that a pixel is the colour the eye sees and not a translucent one on nothing. The controls that macOS draws, such as
/// the fields, are not drawn by the picture and are not looked at.
@MainActor
struct SettingsViewsTests {
    private func whole(_ picture: OffscreenPicture) -> CGRect {
        CGRect(origin: .zero, size: picture.size)
    }

    // MARK: Months without the health minimum

    /// The picture of the toggle of March, 60 points wide on a card with 20 points around it.
    private func picture(
        ofMonth month: Int = 3, isOn: Bool, isActive: Bool, in scheme: ColorScheme
    ) throws -> OffscreenPicture {
        let toggle = MonthToggle(month: month, isOn: isOn, isActive: isActive) {}
            .frame(width: 60)
            .padding(20)
            .background(Palette.bgCard)
        return try OffscreenPicture(of: toggle, in: scheme)
    }

    /// A month without the health minimum is a capsule 28 points tall in the accent, with its name in the colour of
    /// text on an accent: the selection of the design, not the dark fill of the prototype.
    @Test(arguments: [ColorScheme.light, .dark])
    func aSelectedMonthIsACapsuleOfTheAccentWithItsNameOnAccent(scheme: ColorScheme) throws {
        let picture = try picture(isOn: true, isActive: true, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
        let onAccent = try OffscreenPicture.bytes(of: Palette.onAccent, in: scheme)

        let capsule = try #require(picture.extent(near: accent, by: 2), "\(scheme): no toggle in the accent")

        #expect(abs(capsule.height - 28) <= 1.5, "\(scheme): the toggle is \(capsule.height) points tall")
        #expect(abs(capsule.width - 60) <= 1.5, "\(scheme): the toggle is \(capsule.width) points wide")
        #expect(picture.count(near: onAccent, in: capsule, by: 8) > 30, "\(scheme): the name is not on an accent")
    }

    /// A month outside the activity is marked the same way: the accent decides, not whether the month is active.
    @Test(arguments: [ColorScheme.light, .dark])
    func aSelectedMonthOutsideTheActivityIsTheAccentAsWell(scheme: ColorScheme) throws {
        let picture = try picture(isOn: true, isActive: false, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)

        #expect(picture.extent(near: accent, by: 2) != nil, "\(scheme): a marked month outside the activity")
    }

    /// A month that has the minimum is not the accent. It is a raised capsule of the colour of a card with its name in
    /// the colour of text while the activity was carried on in it, and an inset capsule 28 points tall with the
    /// faintest text where it was not.
    @Test(arguments: [ColorScheme.light, .dark])
    func theOtherMonthsAreNotTheAccent(scheme: ColorScheme) throws {
        let available = try picture(isOn: false, isActive: true, in: scheme)
        let outside = try picture(isOn: false, isActive: false, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
        let text = try OffscreenPicture.bytes(of: Palette.text, in: scheme)
        let inset = try OffscreenPicture.bytes(of: Palette.bgInset, in: scheme)

        #expect(available.extent(near: accent, by: 2) == nil, "\(scheme): a month with the minimum is the accent")
        try available.expectText(
            in: whole(available), setIn: Palette.text, atLeast: 65, scheme: scheme, "\(scheme): the name is not text")
        #expect(outside.extent(near: accent, by: 2) == nil, "\(scheme): a month outside the activity is the accent")
        let capsule = try #require(outside.extent(near: inset, by: 2), "\(scheme): no inset toggle")
        #expect(abs(capsule.height - 28) <= 1.5, "\(scheme): the inset toggle is \(capsule.height) points tall")
        try outside.expectText(
            in: capsule, setIn: Palette.text4, atLeast: 75, scheme: scheme,
            "\(scheme): the name is not the faintest text")
        #expect(outside.count(near: text, in: capsule, by: 8) == 0, "\(scheme): the name is in the colour of text")
    }

    // MARK: Failures

    /// A line that says what went wrong is in the red of text, not the system's red.
    @Test(arguments: [ColorScheme.light, .dark])
    func aLineOfAFailureIsInTheRedOfText(scheme: ColorScheme) throws {
        let line = SettingsFailureLine(text: "Změnu se nepodařilo uložit.")
            .frame(width: 300)
            .background(Palette.bgCard)
        let picture = try OffscreenPicture(of: line, in: scheme)
        let red = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)

        #expect(picture.count(near: red, in: whole(picture), by: 8) > 100, "\(scheme): the line is not red text")
    }

    /// The message under a field whose text was refused is in the red of text too, in callout.
    @Test(arguments: [ColorScheme.light, .dark])
    func theMessageUnderARefusedFieldIsInTheRedOfText(scheme: ColorScheme) throws {
        let field = SettingsTextField(
            label: "IBAN", text: .constant("CZ00"), error: "IBAN nesedí – zkontrolujte ho znak po znaku."
        )
        .frame(width: 400).background(Palette.bgCard)
        let picture = try OffscreenPicture(of: field, in: scheme)
        let red = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)

        #expect(picture.count(near: red, in: whole(picture), by: 8) > 100, "\(scheme): the message is not red text")
    }

    // MARK: The appearance

    /// The picture of the choice of `appearance` on a card with 20 points around it.
    private func picture(
        ofAppearance appearance: Appearance, isChosen: Bool, in scheme: ColorScheme
    ) throws -> OffscreenPicture {
        try OffscreenPicture(
            of: AppearanceChoice(appearance: appearance, isChosen: isChosen) {}.padding(20).background(Palette.bgCard),
            in: scheme)
    }

    /// The chosen look is the one with the ring of the accent, 3 points wide, round the picture of the window: outside
    /// the picture, as the shadow of the design is, so the ring is 6 points wider and taller than the 116 by 74 of the
    /// picture and takes nothing of it. The others have a hairline ring of no colour of the accent. Selection always
    /// uses the accent of the design.
    @Test(arguments: [ColorScheme.light, .dark])
    func theChosenAppearanceHasARingOfTheAccentAndTheOthersHaveNone(scheme: ColorScheme) throws {
        let chosen = try picture(ofAppearance: .light, isChosen: true, in: scheme)
        let other = try picture(ofAppearance: .dark, isChosen: false, in: scheme)
        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)

        let ring = try #require(chosen.extent(near: accent, by: 2), "\(scheme): no ring in the accent")
        #expect(abs(ring.width - 122) <= 1.5, "\(scheme): the ring is \(ring.width) points wide")
        #expect(abs(ring.height - 80) <= 1.5, "\(scheme): the ring is \(ring.height) points tall")
        // The ring is a border of 3 points: far from the whole picture and far from nothing.
        let pixels = chosen.count(near: accent, in: whole(chosen), by: 2)
        #expect(pixels > 3_000, "\(scheme): the ring has \(pixels) pixels of the accent")
        #expect(pixels < 6_000, "\(scheme): the picture is filled with the accent: \(pixels) pixels")
        #expect(other.extent(near: accent, by: 2) == nil, "\(scheme): the other look has the accent")
    }

    /// The thumbnails draw a light and a dark window on purpose, so they keep their own colours whatever the
    /// appearance of the app is: the light one is light in a dark window and the dark one dark in a light window.
    @Test func theThumbnailsKeepTheirOwnColoursInAnyAppearance() throws {
        for scheme in [ColorScheme.light, .dark] {
            let light = try picture(ofAppearance: .light, isChosen: false, in: scheme)
            let dark = try picture(ofAppearance: .dark, isChosen: false, in: scheme)

            // The point in the middle of the picture of the big card is the window's own white or dark grey.
            let lightInside = light.bytes(at: CGPoint(x: 20 + 80, y: 20 + 50))
            let darkInside = dark.bytes(at: CGPoint(x: 20 + 80, y: 20 + 50))
            #expect(lightInside.allSatisfy { $0 > 240 }, "\(scheme): the light thumbnail is \(lightInside)")
            #expect(darkInside.allSatisfy { $0 < 90 }, "\(scheme): the dark thumbnail is \(darkInside)")
        }
    }
}
