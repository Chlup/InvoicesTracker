import AppKit
import SwiftUI
import Testing

/// A picture of a view drawn off-screen in a window of a light or a dark appearance, at 2 pixels to the point, from
/// which a test reads the bytes of sRGB pixels. `ImageRenderer` draws it, and it draws the drop shadow under a surface
/// too: the picture of the content of a hosted window (`displayIgnoringOpacity`, which `Snapshot` takes) leaves out the
/// shadows that the compositor draws under a layer, and shows only what a view draws over itself. A view that AppKit
/// draws, such as the link of a button, is not drawn but stands as a yellow placeholder.
@MainActor
struct OffscreenPicture {
    /// The pixels to a point.
    private static let scale = 2

    /// The size of the picture in points.
    let size: CGSize

    /// The red, green, blue and alpha bytes of the pixels, a row after the other from the top.
    private let bytes: [UInt8]

    /// The width of a row of the picture in pixels, with what the rows are padded by.
    private let pixelsPerRow: Int

    /// The picture of `view` in a window of `scheme`.
    init(of view: some View, in scheme: ColorScheme) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = CGFloat(Self.scale)
        let image = try #require(renderer.cgImage, "The view is not drawn")
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let memory = try #require(context.data)
        bytes = Array(UnsafeRawBufferPointer(start: memory, count: context.bytesPerRow * image.height))
        pixelsPerRow = context.bytesPerRow / 4
        size = CGSize(width: image.width / Self.scale, height: image.height / Self.scale)
    }

    /// The red, green and blue bytes of `color` in a window of `scheme`, drawn the way the picture draws everything,
    /// for a test to compare the pixels of a picture with.
    static func bytes(of color: Color, in scheme: ColorScheme) throws -> [Int] {
        let swatch = try OffscreenPicture(of: Rectangle().fill(color).frame(width: 4, height: 4), in: scheme)
        return swatch.bytes(at: CGPoint(x: 2, y: 2))
    }

    /// The red, green and blue bytes of the pixel at `point`, in points from the top left of the picture.
    func bytes(at point: CGPoint) -> [Int] {
        pixel(row: Int(point.y * CGFloat(Self.scale)), column: Int(point.x * CGFloat(Self.scale)))
    }

    /// How many pixels of `region`, in points from the top left, are darker than `colour` by more than `margin` levels
    /// in some channel.
    func count(darkerThan colour: [Int], in region: CGRect, by margin: Int) -> Int {
        count(in: region) { pixel in
            zip(colour, pixel).contains { $0 - $1 > margin }
        }
    }

    /// How many pixels of `region`, in points from the top left, are lighter than `colour` by more than `margin`
    /// levels in some channel.
    func count(lighterThan colour: [Int], in region: CGRect, by margin: Int) -> Int {
        count(in: region) { pixel in
            zip(colour, pixel).contains { $1 - $0 > margin }
        }
    }

    /// The red, green and blue bytes of the pixel in `row` and `column`, counted in pixels from the top left.
    private func pixel(row: Int, column: Int) -> [Int] {
        let start = (row * pixelsPerRow + column) * 4
        return [Int(bytes[start]), Int(bytes[start + 1]), Int(bytes[start + 2])]
    }

    /// How many pixels of `region`, in points from the top left, `matches`.
    private func count(in region: CGRect, where matches: ([Int]) -> Bool) -> Int {
        let scale = CGFloat(Self.scale)
        var found = 0
        for row in Int(region.minY * scale)..<Int(region.maxY * scale) {
            for column in Int(region.minX * scale)..<Int(region.maxX * scale)
            where matches(pixel(row: row, column: column)) {
                found += 1
            }
        }
        return found
    }
}
