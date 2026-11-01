import SwiftUI
import Testing
@testable import InvoicesTracker

/// The hairline of the design, which every card draws between its parts: one point thick across the whole width of its
/// room, in the colour of the separators, or in the stronger colour above the result of a bill and above the total of
/// an invoice.
@MainActor
struct HairlineTests {
    private let schemes = [ColorScheme.light, .dark]

    /// A hairline is one point high, runs across the whole width of its room and is in the colour of the
    /// separators, in a light and in a dark window.
    @Test func aHairlineIsOnePointHighAndAcrossTheWholeWidthInTheColourOfTheSeparators() throws {
        for scheme in schemes {
            let picture = try OffscreenPicture(of: Hairline().frame(width: 120), in: scheme)
            let separator = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)

            #expect(picture.size == CGSize(width: 120, height: 1), "\(scheme): \(picture.size)")
            for x in [0.25, 60, 119.75] as [CGFloat] {
                #expect(picture.bytes(at: CGPoint(x: x, y: 0.5)) == separator, "\(scheme) at \(x)")
            }
        }
    }

    /// A strong hairline is as thin and as wide as the ordinary one, in the stronger colour of the separators.
    @Test func aStrongHairlineIsOnePointHighInTheStrongerColourOfTheSeparators() throws {
        for scheme in schemes {
            let picture = try OffscreenPicture(of: Hairline(isStrong: true).frame(width: 120), in: scheme)
            let strong = try OffscreenPicture.bytes(of: Palette.sepStrong, in: scheme)

            #expect(picture.size == CGSize(width: 120, height: 1), "\(scheme): \(picture.size)")
            for x in [0.25, 60, 119.75] as [CGFloat] {
                #expect(picture.bytes(at: CGPoint(x: x, y: 0.5)) == strong, "\(scheme) at \(x)")
            }
        }
    }

    /// The two colours of the hairline differ in both appearances, so that the strong one can be told from the
    /// ordinary one.
    @Test func theTwoColoursOfTheHairlineDiffer() throws {
        for scheme in schemes {
            let ordinary = try OffscreenPicture.bytes(of: Palette.sep, in: scheme)
            let strong = try OffscreenPicture.bytes(of: Palette.sepStrong, in: scheme)
            #expect(ordinary != strong, "\(scheme)")
        }
    }
}
