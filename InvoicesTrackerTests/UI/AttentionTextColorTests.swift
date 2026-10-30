import AppKit
import Testing
@testable import InvoicesTracker

/// The colour of the text that asks for attention on Přehled (what is still to pay, what a payment adds to the levies):
/// a dark brown in a light window and a lighter orange in a dark one, in the asset catalog under a name of its own,
/// not borrowed from the text of the simulation.
@MainActor
struct AttentionTextColorTests {
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

    private func brightness(_ color: Components) -> Int {
        color.red + color.green + color.blue
    }

    @Test func inALightWindowTheAttentionTextIsADarkBrown() throws {
        #expect(try components(of: "AttentionTextColor", in: .aqua) == Components(red: 0xA6, green: 0x4F, blue: 0x00))
    }

    @Test func inADarkWindowItIsALighterOrange() throws {
        let dark = try components(of: "AttentionTextColor", in: .darkAqua)
        let light = try components(of: "AttentionTextColor", in: .aqua)

        #expect(dark == Components(red: 0xFF, green: 0xA9, blue: 0x5E))
        #expect(brightness(dark) > brightness(light))
    }

    @Test func itIsNotTheColourOfTheSimulationText() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let attention = try components(of: "AttentionTextColor", in: appearance)
            let simulation = try components(of: "SimulationTextColor", in: appearance)
            #expect(attention != simulation)
        }
    }
}
