import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

// The helpers the window tests share to look at a picture of a window: the frames of what VoiceOver reads, given as a
// picture counts them, the pixels at a point, and the colour of text. A test that needs one writes none of its own.

// MARK: Frames as a picture counts them

/// The frame `screen`, given in the coordinates of the screen with the origin at its bottom left, as a picture of
/// `window` counts it: in points from the top left of the content of the window.
@MainActor
func pictureFrame(ofScreenFrame screen: CGRect, in window: NSWindow) throws -> CGRect {
    let frame = window.convertFromScreen(screen)
    let height = try #require(window.contentView).bounds.height
    return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
}

/// The frame of the button that VoiceOver reads under `label` in `window`, in points from the top left of its content.
@MainActor
func buttonFrame(_ label: String, in window: NSWindow) throws -> CGRect {
    let screen = try #require(
        accessibilityButton(labelled: label, in: window)?.accessibilityFrame?(), "No button \(label)")
    return try pictureFrame(ofScreenFrame: screen, in: window)
}

/// The frame of the card that VoiceOver reads under `label` in `window`, in points from the top left of its content.
@MainActor
func cardFrame(_ label: String, in window: NSWindow) throws -> CGRect {
    let screen = try #require(frameOfCard(labelled: label, in: window), "No card \(label)")
    return try pictureFrame(ofScreenFrame: screen, in: window)
}

/// The frame of the first text of `window` that VoiceOver reads as a phrase starting with `phrase`, in points from the
/// top left of its content.
@MainActor
func textFrame(startingWith phrase: String, in window: NSWindow) throws -> CGRect {
    let screen = try #require(frameOfText(startingWith: phrase, in: window), "No text \(phrase)")
    return try pictureFrame(ofScreenFrame: screen, in: window)
}

// MARK: Pixels

/// Whether the red, green and blue bytes `found` are `colour` within `margin` levels in every channel.
func isColour(_ found: [Int], _ colour: [Int], within margin: Int = 2) -> Bool {
    found.count >= colour.count && zip(colour, found).allSatisfy { abs($0 - $1) <= margin }
}

/// The bytes of the pixel of `picture` at `point`, in points from its top left, or nil where the point is outside the
/// picture.
@MainActor
func pixel(at point: CGPoint, in picture: OffscreenPicture) -> [Int]? {
    guard CGRect(origin: .zero, size: picture.size).contains(point) else { return nil }
    return picture.bytes(at: point)
}

/// Whether the pixel of `picture` at `point`, in points from its top left, is `colour` within `margin` levels in every
/// channel. A point outside the picture, such as one of a button under the fold of the page, is no colour at all.
@MainActor
func pixelIs(_ colour: [Int], at point: CGPoint, in picture: OffscreenPicture, within margin: Int = 2) -> Bool {
    guard let found = pixel(at: point, in: picture) else { return false }
    return isColour(found, colour, within: margin)
}

/// Expects the pixel of `picture` at `point` to be `colour`, within 2 levels in every channel, and says what the pixel
/// is instead when it is not: `what` is what stands at the point.
@MainActor
func expectColour(
    _ colour: [Int], at point: CGPoint, in picture: OffscreenPicture, _ what: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let found = pixel(at: point, in: picture).map { "\($0)" } ?? "outside the picture"
    #expect(pixelIs(colour, at: point, in: picture), "\(what) is \(found)", sourceLocation: sourceLocation)
}

extension OffscreenPicture {
    /// The colours that text is set in, by name, from the colour of text to the faintest grey.
    private static var coloursOfText: [(name: String, colour: Color)] {
        [("text", Palette.text), ("text2", Palette.text2), ("text3", Palette.text3), ("text4", Palette.text4)]
    }

    /// Expects the text in `region`, in points from the top left of the picture, to be set in the colour `token` of a
    /// window of `scheme` and not in one beside it: at least `least` pixels within 3 levels of `token`, and more than
    /// three times as many as there are within 3 levels of any other colour of text (`Palette.text` to
    /// `Palette.text4`). `what` says what the text is, for a failed expectation.
    ///
    /// The colours of text are only 25 to 32 levels apart, and the edge of a glyph passes through every shade from its
    /// colour to the ground, so a band of 12 levels around one of them takes in the edge of text set in the colour
    /// beside it, and "pixels near the colour" is true of both. A band of 3 levels takes in the stems of the glyphs,
    /// which are the colour itself: in a window, text of 12 and 13 points set in a colour has hundreds of them there,
    /// and the other colours of text catch at most a twelfth of that.
    func expectText(
        in region: CGRect, setIn token: Color, atLeast least: Int, scheme: ColorScheme, _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let expected = try OffscreenPicture.bytes(of: token, in: scheme)
        var counts: [(name: String, isExpected: Bool, pixels: Int)] = []
        for (name, colour) in Self.coloursOfText {
            let bytes = try OffscreenPicture.bytes(of: colour, in: scheme)
            counts.append((name, bytes == expected, count(near: bytes, in: region, by: 3)))
        }
        let own = counts.filter(\.isExpected).map(\.pixels).first ?? count(near: expected, in: region, by: 3)
        let found = counts.map { "\($0.name) \($0.pixels)" }.joined(separator: ", ")

        #expect(
            own >= least && counts.filter { !$0.isExpected }.allSatisfy { own > 3 * $0.pixels },
            "\(what): pixels within 3 levels of \(found); it needs \(least) of its colour and three times the others",
            sourceLocation: sourceLocation)
    }
}

// MARK: Appearance and size

/// The window appearance of `scheme`, so that a window of a test is light or dark whatever the Mac is.
func appearance(of scheme: ColorScheme) -> NSAppearance? {
    NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
}

/// The height of `view` laid out `width` points wide, as its hosting view needs it.
@MainActor
func fittingHeight(of view: some View, width: CGFloat) -> CGFloat {
    NSHostingView(rootView: view.frame(width: width)).fittingSize.height
}

/// Expects a note that is `height` points tall and `width` points wide, in the tone of an error with the warning icon
/// and `title` over the sentences `lines`, to be made of paragraphs (`Note(_:icon:title:paragraphs:)`): one under the
/// other, 6 points apart and 6 points under the title. The same words as one block of text (`Note(_:icon:title:text:)`)
/// stand together and 4 points under the title, so the note is taller than that by 2 points and by 6 for each sentence
/// after the first. A note made of one block, or with other gaps, is another height by more than a point. The height
/// that a window lays a note out at can differ from the measure of the view alone (`fittingHeight(of:width:)`) by
/// a half point, so a difference of a point is allowed.
@MainActor
func expectNoteOfParagraphsSixPointsApart(
    height: CGFloat, width: CGFloat, title: String, lines: [String], sourceLocation: SourceLocation = #_sourceLocation
) {
    let block = fittingHeight(
        of: Note(.error, icon: .warning, title: title, text: lines.joined(separator: "\n")), width: width)
    let paragraphs = block + 2 + 6 * CGFloat(lines.count - 1)

    #expect(
        abs(height - paragraphs) <= 1,
        "The note is \(height) points tall: \(paragraphs) as \(lines.count) paragraphs, \(block) as one block",
        sourceLocation: sourceLocation)
}
