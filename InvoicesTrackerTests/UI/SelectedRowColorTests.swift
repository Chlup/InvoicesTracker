import AppKit
import Testing
@testable import InvoicesTracker

/// The colours of the open row of the table of Faktury, in the asset catalog under names of their own: in a light
/// window a pale blue (#E8F1FD) with an edge of the blue of the design (#0071E3), as the design draws them, and in a
/// dark one a deep blue that white text stays readable on, with the brighter blue of a dark window for the edge.
@MainActor
struct SelectedRowColorTests {
    private struct Components: Equatable {
        var red: Int
        var green: Int
        var blue: Int
    }

    /// The colour in the catalog under `name`, as sRGB bytes in a window of `appearance`.
    private func components(of name: String, in appearance: NSAppearance.Name) throws -> Components {
        let color = try #require(NSColor(named: NSColor.Name(name), bundle: .main), "\(name) is not in the catalog")
        var found: Components?
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            if let srgb = color.usingColorSpace(.sRGB) {
                found = Components(
                    red: Int((srgb.redComponent * 255).rounded()), green: Int((srgb.greenComponent * 255).rounded()),
                    blue: Int((srgb.blueComponent * 255).rounded()))
            }
        }
        return try #require(found)
    }

    @Test func inALightWindowTheOpenRowIsPaleBlueWithAnEdgeOfTheBlueOfTheDesign() throws {
        #expect(try components(of: "SelectedRowColor", in: .aqua) == Components(red: 0xE8, green: 0xF1, blue: 0xFD))
        #expect(try components(of: "SelectedRowEdgeColor", in: .aqua) == Components(red: 0x00, green: 0x71, blue: 0xE3))
    }

    @Test func inADarkWindowTheOpenRowIsADeepBlueWithABrighterEdge() throws {
        #expect(try components(of: "SelectedRowColor", in: .darkAqua) == Components(red: 0x1B, green: 0x2F, blue: 0x47))
        #expect(
            try components(of: "SelectedRowEdgeColor", in: .darkAqua) == Components(red: 0x0A, green: 0x84, blue: 0xFF))
    }
}
