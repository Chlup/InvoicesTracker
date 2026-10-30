import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The columns that cards are laid out in: as many as fit at the least width of a column, one under the other where
/// they do not, and a sane least size when the layout is asked for the room it needs at least. Where the layout is to
/// give the cards of a row one height, each takes the height of the row.
@MainActor
struct AdaptiveColumnsTests {
    /// Asks its one subview for its size, for `proposal` (as a parent layout does), and tells the answer to `report`.
    private struct Asking: Layout {
        let proposal: ProposedViewSize
        let report: @MainActor (CGSize) -> Void

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let subview = subviews.first else { return .zero }
            let answer = subview.sizeThatFits(self.proposal)
            MainActor.assumeIsolated { report(answer) }
            return answer
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    /// Boxes of text that wrap, which are the taller the narrower the room is.
    private func columns(count: Int = 3) -> some View {
        AdaptiveColumns(minimumColumnWidth: 200, spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                Text(String(repeating: "word ", count: 20))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The size the columns answer when they are asked for it with `proposal`.
    private func answer(to proposal: ProposedViewSize, count: Int = 3) -> CGSize {
        var answered: CGSize?
        let view = Asking(proposal: proposal, report: { answered = $0 }) {
            columns(count: count)
        }
        _ = NSHostingView(rootView: view).fittingSize
        return answered ?? CGSize(width: -1, height: -1)
    }

    @Test func columnsThatFitSitSideBySideAndTheOthersStandOneUnderTheOther() {
        let wide = answer(to: ProposedViewSize(width: 640, height: nil))
        let narrow = answer(to: ProposedViewSize(width: 210, height: nil))

        #expect(wide.width == 640)
        // One row of three at 640 points; three rows at 210, each as high as the text is at that width.
        #expect(narrow.height > wide.height * 2)
    }

    @Test func aRequestForTheLeastRoomIsOneColumnOfTheLeastWidth() {
        let least = answer(to: .zero)
        let oneColumn = answer(to: ProposedViewSize(width: 200, height: nil))

        // Not the thousands of points that three boxes of text no wider than nothing would take.
        #expect(least.width == 200, "answered \(least)")
        #expect(least == oneColumn, "\(least) against \(oneColumn)")
        #expect(least.height < 400, "answered \(least)")
    }

    @Test func noWidthProposedAsksForAllTheColumnsSideBySide() {
        // Three columns of 200 points and the two gaps of 10 between them.
        let size = answer(to: .unspecified)
        #expect(size.width == CGFloat(620), "answered \(size)")
    }

    @Test func noColumnsTakeNoRoom() {
        #expect(answer(to: .zero, count: 0) == .zero)
    }

    // MARK: Rows of one height

    /// A box that is `height` points high unless it is offered a height, which it takes as a card that fills its room
    /// does, and tells the size it is laid out with.
    private struct Box: Layout {
        let height: CGFloat
        let report: @MainActor (CGSize) -> Void

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            CGSize(width: proposal.width ?? 100, height: proposal.height ?? height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            MainActor.assumeIsolated { report(bounds.size) }
        }
    }

    /// The sizes `columns` lays boxes of `heights` out with in `width` points, in the order of the boxes.
    private func placedSizes(
        ofBoxesHigh heights: [CGFloat], in columns: AdaptiveColumns, width: CGFloat
    ) async throws -> [CGSize] {
        var sizes = [CGSize](repeating: .zero, count: heights.count)
        let view = columns {
            ForEach(heights.indices, id: \.self) { index in
                Box(height: heights[index], report: { sizes[index] = $0 }) {
                    Color.clear
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
        try await withHostedView(view, size: CGSize(width: width, height: 400)) { _ in }
        return sizes
    }

    @Test func everyBoxOfARowTakesTheHeightOfTheTallestWhereTheRowsAreEqual() async throws {
        // Three columns fit 340 points: one row of boxes 30, 50 and 40 points high.
        let columns = AdaptiveColumns(minimumColumnWidth: 100, spacing: 10, equalRowHeights: true)
        let sizes = try await placedSizes(ofBoxesHigh: [30, 50, 40], in: columns, width: 340)

        #expect(sizes.map(\.height) == [50, 50, 50], "laid out with \(sizes)")
    }

    @Test func eachRowIsAsHighAsItsOwnTallestBoxWhereTheRowsAreEqual() async throws {
        // Two columns fit 230 points: the boxes of 30 and 50 points make the first row, the one of 40 the second.
        let columns = AdaptiveColumns(minimumColumnWidth: 100, spacing: 10, equalRowHeights: true)
        let sizes = try await placedSizes(ofBoxesHigh: [30, 50, 40], in: columns, width: 230)

        #expect(sizes.map(\.height) == [50, 50, 40], "laid out with \(sizes)")
    }

    @Test func boxesAreOfTheirOwnHeightsUnlessTheRowsAreEqual() async throws {
        let columns = AdaptiveColumns(minimumColumnWidth: 100, spacing: 10)
        let sizes = try await placedSizes(ofBoxesHigh: [30, 50, 40], in: columns, width: 340)

        #expect(sizes.map(\.height) == [30, 50, 40], "laid out with \(sizes)")
    }
}
