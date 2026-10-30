import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The footnote of Výpočet, "Předpoklady výpočtu": not a card but a few lines of small secondary text under the page,
/// with the assumptions of the computation as bullets in two columns of at least 300 points with 32 between them (one
/// column where the room has less than the 632 points they take), and the link "Pravidla v Nastavení". The footnote
/// is hosted alone, in a room whose width the tests choose, and read by what VoiceOver reads and where it puts it.
@Suite(.serialized)
@MainActor
struct ComputationFootnoteTests {
    // MARK: Helpers

    /// The assumptions of the sample year as of 17. 10. 2026: five bullets.
    private let assumptions = computationPage(TaxEngineRegressionTests.sampleYear2026).assumptions

    /// How many times the link of a footnote has been pressed.
    private final class Presses {
        var count = 0
    }

    /// The footnote in a room of `width` points, with 24 points around it in the window it is hosted in.
    private func footnote(width: CGFloat, presses: Presses = Presses()) -> some View {
        AssumptionsFootnote(assumptions: assumptions, showSettings: { presses.count += 1 })
            .frame(width: width, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The size the footnote takes where it is offered `width`, as it is hosted alone.
    private func fittingSize(width: CGFloat) -> CGSize {
        let view = AssumptionsFootnote(assumptions: assumptions, showSettings: {}).frame(width: width)
        return NSHostingView(rootView: view).fittingSize
    }

    /// The height of a line of text set in `font`.
    private func lineHeight(of font: Font) -> CGFloat {
        NSHostingView(rootView: Text(verbatim: "Ž").font(font).fixedSize()).fittingSize.height
    }

    /// Shows the footnote `width` points wide and gives `body` the window and the frames of its five bullets, in the
    /// coordinates of the screen, whose origin is at the bottom left.
    private func withFootnote(
        width: CGFloat, presses: Presses = Presses(), _ body: (NSWindow, [CGRect]) async throws -> Void
    ) async throws {
        let size = CGSize(width: width + 48, height: 400)
        try await withHostedView(footnote(width: width, presses: presses), size: size) { window in
            try await withAccessibilityElements {
                try await waitUntil {
                    assumptions.items.allSatisfy { frameOfText(startingWith: $0, in: window) != nil }
                }
                try await layOut(window)
                let bullets = try assumptions.items.map { item in
                    try #require(frameOfText(startingWith: item, in: window), "No bullet \(item)")
                }
                try await body(window, bullets)
            }
        }
    }

    // MARK: Reading

    @Test func theFootnoteIsReadAsAGroupUnderItsHeadingWithTheBulletsAndTheLink() async throws {
        try await withFootnote(width: 900) { window, _ in
            #expect(frameOfCard(labelled: "Předpoklady výpočtu", in: window) != nil)
            let group = try #require(accessibilityElement(labelled: "Předpoklady výpočtu", in: window))
            let readings = accessibilityReadings(under: group)
            // The heading, the five bullets and the link, and not the bullets' dots, which are only for the eyes.
            #expect(readings.contains("Předpoklady výpočtu"), "read as \(readings)")
            for item in assumptions.items {
                #expect(readings.contains(item), "read as \(readings)")
            }
            #expect(readings.contains("Pravidla v Nastavení"), "read as \(readings)")
            #expect(!readings.contains { $0.contains("•") }, "read as \(readings)")
            #expect(accessibilityButton(labelled: "Pravidla v Nastavení", in: window) != nil)
        }
    }

    @Test func theLinkOpensTheRulesInNastaveni() async throws {
        let presses = Presses()
        try await withFootnote(width: 900, presses: presses) { window, _ in
            let link = try #require(accessibilityButton(labelled: "Pravidla v Nastavení", in: window))
            #expect(presses.count == 0)

            _ = link.accessibilityPerformPress?()

            #expect(presses.count == 1)
        }
    }

    // MARK: Two columns, or one

    @Test func theBulletsStandInTwoColumnsOf300PointsWith32BetweenThemFrom632PointsOfList() async throws {
        // The footnote is padded 4 points at its sides, and the list is set in by the 16 points that the dots hang in:
        // a footnote of 656 points has the 632 that two columns of 300 and the gap of 32 take.
        try await withFootnote(width: 656) { window, bullets in
            let footnote = try #require(frameOfCard(labelled: "Předpoklady výpočtu", in: window))

            // The first three bullets are one under the other in the left column, the last two in the right one.
            for index in [1, 2] {
                #expect((bullets[index].minX - bullets[0].minX).magnitude < 0.5, "\(bullets)")
                #expect(bullets[index].maxY < bullets[index - 1].minY + 0.5, "\(bullets)")
            }
            #expect((bullets[4].minX - bullets[3].minX).magnitude < 0.5, "\(bullets)")
            #expect(bullets[4].maxY < bullets[3].minY + 0.5, "\(bullets)")
            // The columns are 300 points apart plus the gap of 32, and level at the top.
            #expect((bullets[3].minX - bullets[0].minX - 332).magnitude < 0.5, "\(bullets)")
            #expect((bullets[3].maxY - bullets[0].maxY).magnitude < 0.5, "\(bullets)")
            // The group is as wide as what it holds. Its heading, at its left edge, starts after the 24 points around
            // the footnote in the window and the 4 of its own, and the bullets are set in by the 16 that their dots
            // hang in.
            let room = window.frame.minX
            #expect((footnote.minX - room - 28).magnitude < 0.5, "\(footnote) in \(window.frame)")
            #expect((bullets[0].minX - footnote.minX - 16).magnitude < 0.5, "\(bullets) in \(footnote)")
            // Nothing is wider than its column of 300 points.
            #expect(bullets.allSatisfy { $0.width <= 300.5 }, "\(bullets)")
        }
    }

    @Test func belowThatTheBulletsStandInOneColumnLikeTheLinesOfOneList() async throws {
        try await withFootnote(width: 655) { _, bullets in
            // All five are at one left edge and each is under the one before it, with the same gap of 3 points between
            // the last line of a bullet and the first of the next, the one between the third and the fourth too.
            for index in 1..<bullets.count {
                #expect((bullets[index].minX - bullets[0].minX).magnitude < 0.5, "\(bullets)")
                #expect(bullets[index].maxY < bullets[index - 1].minY + 0.5, "\(bullets)")
            }
            let gaps = (1..<bullets.count).map { bullets[$0 - 1].minY - bullets[$0].maxY }
            #expect(gaps.allSatisfy { (3 - $0).magnitude < 1 }, "the gaps are \(gaps)")
            // The text has the whole width of the list, 631 points, to the extent it needs it.
            #expect(bullets.allSatisfy { $0.width <= 631.5 }, "\(bullets)")
        }
    }

    // MARK: Metrics

    @Test func theFootnoteIsSetInCalloutTextWithTheGapsOfTheDesign() {
        // A room so wide that every bullet is a line: the inset of 4 above, the heading in callout semibold, 6 points,
        // three bullets of a line each and 3 points under each, 6 points and the link in callout. The sides are padded
        // 4 points and the foot not at all.
        let height = fittingSize(width: 1_400).height
        let line = lineHeight(of: Typography.callout)
        let expected = 4 + lineHeight(of: Typography.calloutSemibold) + 6 + 3 * (line + 3) + 6 + line

        #expect(abs(height - expected) <= 1, "the footnote is \(height) high, not \(expected)")
    }

    @Test func aBulletThatDoesNotFitALineTakesMoreLinesInsteadOfWideningTheFootnote() {
        let narrow = fittingSize(width: 400)
        let wide = fittingSize(width: 1_400)

        #expect(narrow.width == 400)
        #expect(wide.width == 1_400)
        #expect(narrow.height > wide.height)
    }
}
