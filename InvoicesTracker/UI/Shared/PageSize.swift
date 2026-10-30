import CoreGraphics

/// The sizes of the paper the app makes pages for, in points (a point is 1/72 inch).
nonisolated enum PageSize {
    /// An A4 page: 210 × 297 mm.
    static let a4 = CGSize(width: 595.28, height: 841.89)
}
