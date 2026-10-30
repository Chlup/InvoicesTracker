import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The picture of a payment code: black modules on white, with the quiet zone a scanner needs around them.
nonisolated enum QRImage {
    /// The white margin around the symbol that the QR standard asks for, in modules.
    private static let quietZoneModules: CGFloat = 4

    /// The white margin that CoreImage already leaves around the symbol it makes, in modules.
    private static let generatorMarginModules: CGFloat = 1

    /// No side of the picture is longer than this many pixels. A module size gone wrong would otherwise ask for a
    /// picture of gigabytes, which CoreImage hands out without a word and draws only when somebody looks at it.
    private static let longestSide: CGFloat = 4096

    /// One context for all pictures: making one is far dearer than drawing a code, and contexts can be shared.
    private static let context = CIContext()

    /// The code `payload` as a picture, or nil when the text does not fit in a QR code or `moduleSize` is not usable.
    ///
    /// The error correction is level M, and the quiet zone around the symbol is four modules wide. Every module is a
    /// square of black or white pixels with sharp edges, `moduleSize` pixels wide. A module is a whole number of
    /// pixels, so `moduleSize` is rounded, and a size that rounds to less than one pixel, or that would make the
    /// picture longer than 4096 pixels, gives nil.
    static func make(_ payload: String, moduleSize: CGFloat) -> CGImage? {
        let scale = moduleSize.rounded()
        guard scale >= 1 else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let symbol = filter.outputImage else { return nil }

        // The generator leaves one module white around the symbol, and the quiet zone is four.
        let padding = quietZoneModules - generatorMarginModules
        let modules = symbol.extent.width + 2 * padding
        guard modules * scale <= longestSide else { return nil }

        let white = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: modules, height: modules))
        let padded = symbol
            .transformed(by: CGAffineTransform(translationX: padding, y: padding))
            .composited(over: white)
        let scaled = padded.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(
            scaled, from: scaled.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }
}
