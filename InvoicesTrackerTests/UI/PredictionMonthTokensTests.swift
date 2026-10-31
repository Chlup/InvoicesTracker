import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// "Kdy čekám faktury" in the colours and shapes of the design: the six kinds of month take their fills, texts and
/// dashed edges from the tokens, a cell is rounded by the radius of a control (6 points), and the card of the months
/// is padded 20 points with a heading in the title 3 style. The cells are drawn off-screen in a light and in a dark
/// window, and the card is hosted in a window of its own.
@Suite
@MainActor
struct PredictionMonthTokensTests {
    // MARK: The colours of the six kinds

    /// The fill, the three texts and the edge that the design gives a kind of month.
    private struct Expected {
        var fill: Color
        var label: Color
        var value: Color
        var sub: Color
        var edge: (color: Color, width: CGFloat)?
    }

    /// What the design draws for each kind: paid in the green tint and green text, issued and waiting in the accent
    /// tint and accent text, over in the inset background with the faintest text, expected in the accent tint with a
    /// dashed accent edge, expected for next year in the orange tint with a dashed orange edge, and not expected on the
    /// card with a thin dashed edge in the stronger separator, its label in tertiary text and its sub-text in the
    /// faintest.
    private func expected(_ kind: PredictionCellKind) -> Expected {
        switch kind {
        case .paid:
            Expected(
                fill: Palette.greenTint, label: Palette.greenText, value: Palette.greenText, sub: Palette.greenText)
        case .waiting:
            Expected(
                fill: Palette.accentTint, label: Palette.accentText, value: Palette.accentText,
                sub: Palette.accentText)
        case .past:
            Expected(fill: Palette.bgInset, label: Palette.text4, value: Palette.text4, sub: Palette.text4)
        case .expected:
            Expected(
                fill: Palette.accentTint, label: Palette.accentText, value: Palette.accentText,
                sub: Palette.accentText, edge: (Palette.accent, 1.5))
        case .expectedNextYear:
            Expected(
                fill: Palette.orangeTint, label: Palette.orangeText, value: Palette.orangeText,
                sub: Palette.orangeText, edge: (Palette.orange, 1.5))
        case .notExpected:
            Expected(
                fill: Palette.bgCard, label: Palette.text3, value: Palette.text4, sub: Palette.text4,
                edge: (Palette.sepStrong, 1))
        }
    }

    private static let kinds: [PredictionCellKind] = [
        .paid, .waiting, .past, .expected, .expectedNextYear, .notExpected,
    ]

    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func theKindsOfMonthTakeTheirColoursFromTheTokens(scheme: ColorScheme) throws {
        for kind in Self.kinds {
            let style = kind.style
            let wanted = expected(kind)
            for (name, found, expectedColor) in [
                ("fill", style.fill, wanted.fill), ("label", style.label, wanted.label),
                ("value", style.value, wanted.value), ("sub", style.sub, wanted.sub),
            ] {
                let bytes = try OffscreenPicture.bytes(of: found, in: scheme)
                let expectedBytes = try OffscreenPicture.bytes(of: expectedColor, in: scheme)
                #expect(bytes == expectedBytes, "The \(name) of \(kind) is \(bytes), not \(expectedBytes)")
            }
            #expect(style.edge?.width == wanted.edge?.width, "The edge of \(kind)")
            if let edge = style.edge, let wantedEdge = wanted.edge {
                #expect(
                    try OffscreenPicture.bytes(of: edge.color, in: scheme)
                        == OffscreenPicture.bytes(of: wantedEdge.color, in: scheme),
                    "The colour of the edge of \(kind)")
                #expect(!edge.dash.isEmpty, "The edge of \(kind) is dashed")
            }
        }
    }

    /// A month that is over is set regular, in the faintest text; the others set their figure semibold.
    @Test func onlyAMonthThatIsOverSetsItsFigureRegular() {
        for kind in Self.kinds {
            #expect(kind.style.valueWeight == (kind == .past ? .regular : .semibold), "\(kind)")
        }
    }

    // MARK: The shape of a cell

    /// A cell of 100 by 52 points on a ground of a colour that no cell has.
    private func picture(of kind: PredictionCellKind, in scheme: ColorScheme) throws -> OffscreenPicture {
        let cell = PredictionCell(
            month: 10, label: "říj", value: "", sub: "", kind: kind, isToggle: false, isOn: false,
            accessibilityLabel: "Říjen")
        let view = PredictionMonthCell(cell: cell, toggle: {})
            .frame(width: 100, height: 52)
            .background(Color(red: 1, green: 0, blue: 1))
        return try OffscreenPicture(of: view, in: scheme)
    }

    /// The corners are rounded by 6 points, the radius of a control: the ground that shows in the top left corner of a
    /// cell of 100 by 52, 7 points square (the words of the cell start 8 points in), is as much as shows round a
    /// rectangle of that radius, and clearly less than round one of 8 points, which the cells had before.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func aCellIsRoundedByTheRadiusOfAControl(scheme: ColorScheme) throws {
        let ground = try OffscreenPicture.bytes(of: Color(red: 1, green: 0, blue: 1), in: scheme)
        func cut(_ radius: CGFloat) throws -> OffscreenPicture {
            let rounded = RoundedRectangle(cornerRadius: radius).fill(Color.black).frame(width: 100, height: 52)
            return try OffscreenPicture(of: rounded.background(Color(red: 1, green: 0, blue: 1)), in: scheme)
        }
        let corner = CGRect(x: 0, y: 0, width: 7, height: 7)
        let wanted = try cut(DesignMetrics.controlRadius).count(near: ground, in: corner, by: 6)
        let tooRound = try cut(8).count(near: ground, in: corner, by: 6)
        #expect(tooRound > wanted + 10, "A corner of 8 points is not told from one of 6: \(tooRound), \(wanted)")

        for kind in Self.kinds {
            let found = try picture(of: kind, in: scheme).count(near: ground, in: corner, by: 6)
            #expect((found - wanted).magnitude <= 3, "The corner of \(kind) shows \(found) pixels, not \(wanted)")
        }
    }

    /// The fill is the token of the kind, to the right of the texts, where nothing else is drawn.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func aCellIsFilledWithTheTokenOfItsKind(scheme: ColorScheme) throws {
        for kind in Self.kinds {
            let picture = try picture(of: kind, in: scheme)
            let found = picture.bytes(at: CGPoint(x: 60, y: 26))
            let wanted = try OffscreenPicture.bytes(of: expected(kind).fill, in: scheme)
            let isNear = zip(found, wanted).allSatisfy { abs($0 - $1) <= 6 }
            #expect(isNear, "The fill of \(kind) is \(found), not \(wanted)")
        }
    }

    // MARK: The card

    /// The card of the months is padded 20 points on every side, as every card is: the heading starts 20 points from
    /// the left edge and ends 20 points above the foot of a card that is folded, where the heading is all there is.
    @Test func theCardOfTheMonthsIsPaddedTwentyPointsAndItsHeadingIsInTitleThree() async throws {
        let page = try PredictionSample.page(year: 2026)
        let section = PredictionMonthsSection(
            page: page, saveFailure: nil, isOpen: .constant(false), othersAreOpen: .constant(false),
            toggle: { _, _ in }, reset: { _ in })
        let view = section.frame(width: 900).padding(24)
        try await withHostedView(view, size: CGSize(width: 1_000, height: 400)) { window in
            try await withAccessibilityElements {
                try await waitUntil { frameOfCard(labelled: "Kdy čekám faktury", in: window) != nil }
                try await layOut(window)

                let card = try #require(frameOfCard(labelled: "Kdy čekám faktury", in: window))
                let header = try #require(accessibilityButton(labelled: "Kdy čekám faktury", in: window))
                let heading = try #require(header.accessibilityFrame?())
                #expect((heading.minX - card.minX - 20).magnitude <= 1, "\(heading), the card \(card)")
                #expect((card.maxX - heading.maxX - 20).magnitude <= 1, "\(heading), the card \(card)")
                #expect((card.maxY - heading.maxY - 20).magnitude <= 1, "\(heading), the card \(card)")
                #expect((heading.minY - card.minY - 20).magnitude <= 1, "\(heading), the card \(card)")
            }
        }
    }
}
