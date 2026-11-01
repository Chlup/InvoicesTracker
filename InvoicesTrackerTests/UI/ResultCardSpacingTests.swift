import AppKit
import SwiftUI
import Testing

@testable import InvoicesTracker

/// The key figures of the result cards of Přehled and Výpočet, in the window of the app, are spaced as the design of
/// each screen spaces them (`KeyFigureSpacing`): the sentence 12 points under the line of the figure on Přehled (the
/// gap of 8 and the margin of 4 of its sentence) and 10 on Výpočet (a margin of 2), not the 8 of the board. The key
/// figure of the card of Odhad odvodů has its own test (`PredictionWindowTests`), and the Simulátor's the card's
/// (`SimulatorResultCardTests`). The data is the sample year 2026 as of 17. 10. 2026.
@Suite(.serialized, .settlesBackups)
@MainActor
struct ResultCardSpacingTests {
    /// Expects the key figure of `data` in `window`, the element that VoiceOver reads from its eyebrow on, to be as
    /// tall as the key figure laid out alone at its width with `spacing` and with a sentence at most `sentenceWidth`
    /// points wide, and not as tall as with the board's spacing, which the screens would have without their own.
    private func expectKeyFigure(
        _ data: KeyFigureData, spacedAs spacing: KeyFigureSpacing, sentenceWidth: CGFloat, in window: NSWindow,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let frame = try textFrame(startingWith: data.eyebrow, in: window)
        @MainActor func height(_ spacing: KeyFigureSpacing) -> CGFloat {
            fittingHeight(
                of: KeyFigureView(data, sentenceMaximumWidth: sentenceWidth, spacing: spacing), width: frame.width)
        }

        #expect(
            abs(frame.height - height(spacing)) < 0.5,
            "\(data.eyebrow) is \(frame.height) tall, not \(height(spacing))", sourceLocation: sourceLocation)
        #expect(
            abs(height(spacing) - height(.board)) >= 1.5, "\(spacing) is the board's", sourceLocation: sourceLocation)
    }

    @Test func theKeyFigureOfPrehledIsSpacedAsTheDesignSpacesIt() async throws {
        try await EditorFixture.with { f in
            let model = OverviewModel(app: f.app)
            await model.load()
            let data = try #require(model.data).keyFigure

            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Kolik zbývá zaplatit", in: window) != nil }
                    try await layOut(window)

                    try expectKeyFigure(data, spacedAs: .overview, sentenceWidth: 416, in: window)
                }
            }
        }
    }

    @Test func theKeyFigureOfVypocetIsSpacedAsTheDesignSpacesIt() async throws {
        try await EditorFixture.with { f in
            let model = ComputationModel(app: f.app)
            await model.load()
            let data = try #require(model.page).keyFigure

            try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                try await withAccessibilityElements {
                    try await waitUntil { frameOfCard(labelled: "Výsledek", in: window) != nil }
                    try await layOut(window)

                    try expectKeyFigure(data, spacedAs: .computation, sentenceWidth: 468, in: window)
                }
            }
        }
    }
}
