import AppKit
import Testing

/// What a window shows: its content drawn from the top left into a bitmap of the test's own, in sRGB at 2 pixels to the
/// point. Where only the window itself shows, as in the padding of a page that nothing paints, the pixel is clear.
@MainActor
struct WindowPicture {
    private let bitmap: NSBitmapImageRep

    /// The pixels to a point.
    private static let scale: CGFloat = 2

    /// The picture of what `window` shows now.
    init(of window: NSWindow) throws {
        let view = try #require(window.contentView)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int((view.bounds.width * Self.scale).rounded()),
                height: Int((view.bounds.height * Self.scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: Self.scale, y: Self.scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    /// The colour at `point`, in points from the top left of the content of the window, as its red, green, blue and
    /// alpha bytes.
    func bytes(at point: CGPoint) -> [Int] {
        guard let pixel = bitmap.colorAt(x: Int(point.x * Self.scale), y: Int(point.y * Self.scale)) else {
            return []
        }
        return [pixel.redComponent, pixel.greenComponent, pixel.blueComponent, pixel.alphaComponent].map { component in
            Int((component * 255).rounded())
        }
    }
}
