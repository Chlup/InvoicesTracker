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
