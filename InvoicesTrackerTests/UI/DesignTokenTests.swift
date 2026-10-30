import AppKit
import Foundation
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The colour tokens of the V2 design. Each one is in the asset catalog under `Token<Name>` with the value the design
/// board gives it in a light and in a dark window, `Palette`, the authorities and the elevations hand each one out
/// under its own name, and the metrics are the board's.
@MainActor
struct DesignTokenTests {
    /// A colour as the sRGB bytes of its red, green and blue, and its alpha.
    private struct Rgba: CustomStringConvertible {
        var red: Int
        var green: Int
        var blue: Int
        var alpha: Double

        /// The colour of a hex value such as `0x1D1D1F`, with the alpha given (1 when it is left out).
        init(_ hex: Int, alpha: Double = 1) {
            red = (hex >> 16) & 0xFF
            green = (hex >> 8) & 0xFF
            blue = hex & 0xFF
            self.alpha = alpha
        }

        /// The colour with these bytes and this alpha.
        init(red: Int, green: Int, blue: Int, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Whether `other` has the same bytes and an alpha within 0.005 of this one's.
        func matches(_ other: Rgba) -> Bool {
            red == other.red && green == other.green && blue == other.blue && abs(alpha - other.alpha) <= 0.005
        }

        /// The colour as `#RRGGBB@alpha`, for the message of a failed expectation.
        var description: String {
            String(format: "#%02X%02X%02X@%.3f", red, green, blue, alpha)
        }
    }

    /// A token of the board: its name in the asset catalog and its value in a light and in a dark window.
    private struct Token {
        var name: String
        var light: Rgba
        var dark: Rgba

        /// The token `name` with its value in a light and in a dark window.
        init(_ name: String, light: Rgba, dark: Rgba) {
            self.name = name
            self.light = light
            self.dark = dark
        }
    }

    /// All 41 tokens of the board, in the order of its `:root` and `.it-theme-dark` blocks.
    private static let tokens: [Token] = [
        Token("TokenText", light: Rgba(0x1D1D1F), dark: Rgba(0xF5F5F7)),
        Token("TokenText2", light: Rgba(0x55555C), dark: Rgba(0xAEAEB2)),
        Token("TokenText3", light: Rgba(0x6E6E76), dark: Rgba(0x8E8E93)),
        Token("TokenText4", light: Rgba(0x8E8E93), dark: Rgba(0x6E6E73)),
        Token("TokenOnAccent", light: Rgba(0xFFFFFF), dark: Rgba(0xFFFFFF)),
        Token("TokenBgWindow", light: Rgba(0xF5F5F7), dark: Rgba(0x161618)),
        Token("TokenBgSidebar", light: Rgba(0xECECF1), dark: Rgba(0x252528)),
        Token("TokenBgCard", light: Rgba(0xFFFFFF), dark: Rgba(0x1E1E1E)),
        Token("TokenBgInset", light: Rgba(0xF5F5F7), dark: Rgba(0x161618)),
        Token("TokenFill", light: Rgba(0xEFEFF2), dark: Rgba(0x303033)),
        Token("TokenFillStrong", light: Rgba(0x000000, alpha: 0.075), dark: Rgba(0xFFFFFF, alpha: 0.10)),
        Token("TokenSep", light: Rgba(0xE5E5EA), dark: Rgba(0x38383A)),
        Token("TokenSepStrong", light: Rgba(0xD1D1D6), dark: Rgba(0x48484A)),
        Token("TokenAccent", light: Rgba(0x0071E3), dark: Rgba(0x0A84FF)),
        Token("TokenAccentText", light: Rgba(0x0058B0), dark: Rgba(0x8FC3FF)),
        Token("TokenAccentTint", light: Rgba(0xE8F1FD), dark: Rgba(0x1B2F47)),
        Token("TokenAccentSoft", light: Rgba(0xBFD6F6), dark: Rgba(0x164778)),
        Token("TokenGreen", light: Rgba(0x1E9E4A), dark: Rgba(0x30D158)),
        Token("TokenGreenText", light: Rgba(0x146C31), dark: Rgba(0x8EE0A6)),
        Token("TokenGreenTint", light: Rgba(0xE6F4EA), dark: Rgba(0x213B27)),
        Token("TokenOrange", light: Rgba(0xD9730D), dark: Rgba(0xFF9F0A)),
        Token("TokenOrangeText", light: Rgba(0xA64F00), dark: Rgba(0xFFA95E)),
        Token("TokenOrangeTint", light: Rgba(0xFFF1DE), dark: Rgba(0x42331B)),
        Token("TokenRed", light: Rgba(0xC9221A), dark: Rgba(0xFF453A)),
        Token("TokenRedText", light: Rgba(0xA50E0E), dark: Rgba(0xFFA39C)),
        Token("TokenRedTint", light: Rgba(0xFDECEA), dark: Rgba(0x422422)),
        Token("TokenTax", light: Rgba(0x5B5BD6), dark: Rgba(0x7979EC)),
        Token("TokenSocial", light: Rgba(0x2A9D8F), dark: Rgba(0x31C4B2)),
        Token("TokenHealth", light: Rgba(0xD6457A), dark: Rgba(0xE96394)),
        Token("TokenTaxTint", light: Rgba(0xDEDEF8), dark: Rgba(0x34344F)),
        Token("TokenSocialTint", light: Rgba(0xCFEAE6), dark: Rgba(0x234642)),
        Token("TokenHealthTint", light: Rgba(0xF7D5E1), dark: Rgba(0x4F2F3A)),
        Token("TokenHighlight", light: Rgba(0xFFF1B8), dark: Rgba(0x625518)),
        Token("TokenHatchStripe", light: Rgba(0x7FB2EC), dark: Rgba(0x13569A)),
        Token("TokenHatchGround", light: Rgba(0xCFE2F8), dark: Rgba(0x1A3450)),
        Token("TokenShadowCardRing", light: Rgba(0x000000, alpha: 0.08), dark: Rgba(0xFFFFFF, alpha: 0.10)),
        Token("TokenShadowCardDrop", light: Rgba(0x000000, alpha: 0.04), dark: Rgba(0x000000, alpha: 0.30)),
        Token("TokenShadowControlRing", light: Rgba(0x000000, alpha: 0.12), dark: Rgba(0xFFFFFF, alpha: 0.14)),
        Token("TokenShadowControlDrop", light: Rgba(0x000000, alpha: 0.06), dark: Rgba(0x000000, alpha: 0.35)),
        Token("TokenShadowPopRing", light: Rgba(0x000000, alpha: 0.18), dark: Rgba(0xFFFFFF, alpha: 0.18)),
        Token("TokenShadowPopDrop", light: Rgba(0x000000, alpha: 0.16), dark: Rgba(0x000000, alpha: 0.50)),
    ]

    /// The colour in the catalog under `name`, as sRGB bytes in a window of `appearance`, or nil when the catalog has
    /// no colour of that name.
    private func catalogColor(_ name: String, in appearance: NSAppearance.Name) throws -> Rgba? {
        guard let color = NSColor(named: NSColor.Name(name), bundle: .main) else { return nil }
        var found: Rgba?
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            if let srgb = color.usingColorSpace(.sRGB) {
                found = Rgba(
                    red: Int((srgb.redComponent * 255).rounded()), green: Int((srgb.greenComponent * 255).rounded()),
                    blue: Int((srgb.blueComponent * 255).rounded()), alpha: Double(srgb.alphaComponent))
            }
        }
        return found
    }

    /// The tokens of the board by their names in the asset catalog.
    private static let board: [String: Token] = Dictionary(uniqueKeysWithValues: tokens.map { ($0.name, $0) })

    /// What `Palette` hands out under each of its 35 names, with the token it must take the colour from. The six
    /// shadow tokens are not here: they belong to the elevations.
    private static let palette: [(token: String, color: Color)] = [
        ("TokenText", Palette.text),
        ("TokenText2", Palette.text2),
        ("TokenText3", Palette.text3),
        ("TokenText4", Palette.text4),
        ("TokenOnAccent", Palette.onAccent),
        ("TokenBgWindow", Palette.bgWindow),
        ("TokenBgSidebar", Palette.bgSidebar),
        ("TokenBgCard", Palette.bgCard),
        ("TokenBgInset", Palette.bgInset),
        ("TokenFill", Palette.fill),
        ("TokenFillStrong", Palette.fillStrong),
        ("TokenSep", Palette.sep),
        ("TokenSepStrong", Palette.sepStrong),
        ("TokenAccent", Palette.accent),
        ("TokenAccentText", Palette.accentText),
        ("TokenAccentTint", Palette.accentTint),
        ("TokenAccentSoft", Palette.accentSoft),
        ("TokenGreen", Palette.green),
        ("TokenGreenText", Palette.greenText),
        ("TokenGreenTint", Palette.greenTint),
        ("TokenOrange", Palette.orange),
        ("TokenOrangeText", Palette.orangeText),
        ("TokenOrangeTint", Palette.orangeTint),
        ("TokenRed", Palette.red),
        ("TokenRedText", Palette.redText),
        ("TokenRedTint", Palette.redTint),
        ("TokenTax", Palette.tax),
        ("TokenSocial", Palette.social),
        ("TokenHealth", Palette.health),
        ("TokenTaxTint", Palette.taxTint),
        ("TokenSocialTint", Palette.socialTint),
        ("TokenHealthTint", Palette.healthTint),
        ("TokenHighlight", Palette.highlight),
        ("TokenHatchStripe", Palette.hatchStripe),
        ("TokenHatchGround", Palette.hatchGround),
    ]

    /// The colour as sRGB bytes in a window of `scheme`.
    private func resolved(_ color: Color, in scheme: ColorScheme) -> Rgba {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment)
        return Rgba(
            red: Int((resolved.red * 255).rounded()), green: Int((resolved.green * 255).rounded()),
            blue: Int((resolved.blue * 255).rounded()), alpha: Double(resolved.opacity))
    }

    /// Expects `color` to be the token `name` of the board, in a light and in a dark window.
    private func expectColor(
        _ color: Color, isToken name: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let token = try #require(
            Self.board[name], "\(name) is not a token of the board", sourceLocation: sourceLocation)
        let windows: [(label: String, scheme: ColorScheme, expected: Rgba)] = [
            ("light", .light, token.light), ("dark", .dark, token.dark),
        ]
        for window in windows {
            let found = resolved(color, in: window.scheme)
            #expect(
                found.matches(window.expected),
                "The colour for \(name) in a \(window.label) window is \(found), the board has \(window.expected)",
                sourceLocation: sourceLocation)
        }
    }

    @Test func everyTokenHasTheBoardsLightAndDarkValue() throws {
        #expect(Self.tokens.count == 41)
        for token in Self.tokens {
            let windows: [(label: String, appearance: NSAppearance.Name, expected: Rgba)] = [
                ("light", .aqua, token.light), ("dark", .darkAqua, token.dark),
            ]
            for window in windows {
                guard let found = try catalogColor(token.name, in: window.appearance) else {
                    Issue.record("\(token.name) is not in the catalog")
                    break
                }
                #expect(
                    found.matches(window.expected),
                    "\(token.name) in a \(window.label) window is \(found), the board has \(window.expected)")
            }
        }
    }

    @Test func thePaletteHandsOutEachTokenUnderItsOwnName() throws {
        #expect(Self.palette.count == 35)
        for entry in Self.palette {
            try expectColor(entry.color, isToken: entry.token)
        }
    }

    @Test func anAuthorityTakesItsColourAndItsTintFromThePalette() throws {
        let authorities: [(authority: Authority, color: String, tint: String)] = [
            (.tax, "TokenTax", "TokenTaxTint"),
            (.social, "TokenSocial", "TokenSocialTint"),
            (.health, "TokenHealth", "TokenHealthTint"),
        ]
        #expect(authorities.count == Authority.allCases.count)
        for entry in authorities {
            try expectColor(entry.authority.color, isToken: entry.color)
            try expectColor(entry.authority.tint, isToken: entry.tint)
        }
    }

    @Test func eachElevationTakesItsRingAndItsDropFromItsOwnShadowTokens() throws {
        let levels: [(level: Elevation, ring: String, drop: String)] = [
            (.card, "TokenShadowCardRing", "TokenShadowCardDrop"),
            (.control, "TokenShadowControlRing", "TokenShadowControlDrop"),
            (.pop, "TokenShadowPopRing", "TokenShadowPopDrop"),
        ]
        for entry in levels {
            try expectColor(entry.level.ringColor, isToken: entry.ring)
            try expectColor(entry.level.dropColor, isToken: entry.drop)
        }
    }

    @Test func theDropShadowsAreAsLowAndAsSoftAsTheBoardDrawsThem() {
        #expect(Elevation.card.dropOffset == 1)
        #expect(Elevation.card.dropRadius == 1)
        #expect(Elevation.control.dropOffset == 1)
        #expect(Elevation.control.dropRadius == 1)
        #expect(Elevation.pop.dropOffset == 12)
        #expect(Elevation.pop.dropRadius == 16)
    }

    @Test func theDesignMetricsAreTheBoardsRadiiSpacingAndControlHeights() {
        #expect(DesignMetrics.cardRadius == 16)
        #expect(DesignMetrics.panelRadius == 10)
        #expect(DesignMetrics.controlRadius == 6)
        #expect(DesignMetrics.cardPadding == 20)
        #expect(DesignMetrics.cardSpacing == 16)
        #expect(DesignMetrics.innerSpacing == 12)
        #expect(DesignMetrics.pageLeading == 24)
        #expect(DesignMetrics.pageTrailing == 16)
        #expect(DesignMetrics.pageTop == 16)
        #expect(DesignMetrics.pageBottom == 24)
        #expect(DesignMetrics.regularControlHeight == 32)
        #expect(DesignMetrics.smallControlHeight == 28)
    }
}
