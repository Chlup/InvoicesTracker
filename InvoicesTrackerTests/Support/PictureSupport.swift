import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The frame `screen`, given in the coordinates of the screen with the origin at its bottom left, as a picture of
/// `window` counts it: in points from the top left of the content of the window.
@MainActor
func pictureFrame(ofScreenFrame screen: CGRect, in window: NSWindow) throws -> CGRect {
    let frame = window.convertFromScreen(screen)
    let height = try #require(window.contentView).bounds.height
    return CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
}

/// Whether the pixel of `picture` at `point`, in points from its top left, is `colour` within `margin` levels in every
/// channel.
@MainActor
func pixelIs(_ colour: [Int], at point: CGPoint, in picture: OffscreenPicture, within margin: Int = 2) -> Bool {
    let found = picture.bytes(at: point)
    return found.count >= colour.count && zip(colour, found).allSatisfy { abs($0 - $1) <= margin }
}

/// The window appearance of `scheme`, so that a window of a test is light or dark whatever the Mac is.
func appearance(of scheme: ColorScheme) -> NSAppearance? {
    NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
}

/// The height of `view` laid out `width` points wide, as its hosting view needs it.
@MainActor
func fittingHeight(of view: some View, width: CGFloat) -> CGFloat {
    NSHostingView(rootView: view.frame(width: width)).fittingSize.height
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
