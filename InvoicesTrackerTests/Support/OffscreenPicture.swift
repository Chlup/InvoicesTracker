import AppKit
import SwiftUI
import Testing

/// A picture of a view drawn off-screen in a window of a light or a dark appearance, at 2 pixels to the point, from
/// which a test reads the bytes of sRGB pixels. `ImageRenderer` draws it, and it draws the drop shadow under a surface
/// too: the picture of the content of a hosted window (`displayIgnoringOpacity`, which `Snapshot` takes) leaves out the
/// shadows that the compositor draws under a layer, and shows only what a view draws over itself. A view that AppKit
/// draws, such as the link of a button, is not drawn but stands as a yellow placeholder, and what a scroll view holds
/// is not drawn at all: the picture of such a view is taken of its window (`init(of:)`).
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

    /// The picture of what `window` shows now, in the appearance it has: its content view drawn from the top left into
    /// a bitmap of the picture's own, in sRGB. `ImageRenderer` leaves out what AppKit draws and what a scroll view
    /// holds, so a card that scrolls its content is drawn by its window instead. The drop shadows that the compositor
    /// draws under a layer are not in it, and where nothing is painted the pixel is clear.
    init(of window: NSWindow) throws {
        let view = try #require(window.contentView)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let scale = CGFloat(Self.scale)
        let context = try #require(
            CGContext(
                data: nil, width: Int((view.bounds.width * scale).rounded()),
                height: Int((view.bounds.height * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        let memory = try #require(context.data)
        bytes = Array(UnsafeRawBufferPointer(start: memory, count: context.bytesPerRow * context.height))
        pixelsPerRow = context.bytesPerRow / 4
        size = CGSize(width: context.width / Self.scale, height: context.height / Self.scale)
    }

    /// Whether `other` shows exactly the same pixels as this picture, and is as large.
    func isSame(as other: OffscreenPicture) -> Bool {
        size == other.size && bytes == other.bytes
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

    /// How many pixels of `region`, in points from the top left, are within `margin` levels of `colour` in every
    /// channel.
    func count(near colour: [Int], in region: CGRect, by margin: Int) -> Int {
        count(in: region) { pixel in
            zip(colour, pixel).allSatisfy { abs($0 - $1) <= margin }
        }
    }

    /// The smallest rectangle, in points from the top left, that holds every pixel within `margin` levels of `colour`
    /// in every channel, or nil where there is none: the extent of a mark in that colour. The pixels at the soft edge
    /// of a shape are not within a margin of the colour, so the extent is up to a point smaller than the shape.
    func extent(near colour: [Int], by margin: Int) -> CGRect? {
        let scale = CGFloat(Self.scale)
        let rowCount = bytes.count / (pixelsPerRow * 4)
        let columnCount = Int(size.width * scale)
        var rows: ClosedRange<Int>?
        var columns: ClosedRange<Int>?
        for row in 0..<rowCount {
            for column in 0..<columnCount
            where zip(colour, pixel(row: row, column: column)).allSatisfy({ abs($0 - $1) <= margin }) {
                rows = rows.map { min($0.lowerBound, row)...max($0.upperBound, row) } ?? row...row
                columns = columns.map { min($0.lowerBound, column)...max($0.upperBound, column) } ?? column...column
            }
        }
        guard let rows, let columns else { return nil }
        return CGRect(
            x: CGFloat(columns.lowerBound) / scale, y: CGFloat(rows.lowerBound) / scale,
            width: CGFloat(columns.count) / scale, height: CGFloat(rows.count) / scale)
    }

    /// The pixel rows of the picture, as the points from its top that they start at, in which every pixel from `start`
    /// to `end` points from the left edge is within `margin` levels of `colour` in every channel: the rows of a line
    /// that runs across that width. A line a point thick is two pixel rows (or three, where it lies between pixels).
    func rows(near colour: [Int], from start: CGFloat, to end: CGFloat, by margin: Int) -> [CGFloat] {
        let scale = CGFloat(Self.scale)
        let rowCount = bytes.count / (pixelsPerRow * 4)
        let columns = Int(start * scale)..<Int(end * scale)
        return (0..<rowCount).filter { row in
            columns.allSatisfy { column in
                zip(colour, pixel(row: row, column: column)).allSatisfy { abs($0 - $1) <= margin }
            }
        }.map { CGFloat($0) / scale }
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
