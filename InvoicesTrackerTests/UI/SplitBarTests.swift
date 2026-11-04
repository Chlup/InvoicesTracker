import SwiftUI
import Testing
@testable import InvoicesTracker

/// The split bar: the widths of its parts and the centres of its popovers, which colour each tone and a negative
/// amount are drawn in, and the bar drawn off-screen in a light and a dark window.
@Suite
@MainActor
struct SplitBarTests {
    // MARK: Sample data

    private func segment(_ group: String, _ tone: SplitBarTone, _ weight: Int64) -> SplitBarSegment {
        SplitBarSegment(group: group, tone: tone, weight: weight)
    }

    private func group(_ id: String, tone: SplitBarTone, negative: Bool = false) -> SplitBarGroup {
        SplitBarGroup(
            id: id, dots: [tone], shortTitle: id, value: "1 Kč", valueIsNegative: negative,
            popover: SplitBarPopover(title: id, subtitle: "", tone: tone, rows: [], note: nil),
            accessibilityLabel: id)
    }

    /// DPH, three levies (the health one a bonus, so without width) and two categories, the last without width.
    private func data() -> SplitBarData {
        SplitBarData(
            header: "Rozdělení",
            segments: [
                segment("vat", .vat, 100),
                segment("levies", .authority(.tax), 200),
                segment("levies", .authority(.social), 100),
                segment("levies", .authority(.health), 0),
                segment("spending", .category(.spending), 400),
                segment("savings", .category(.savings), 0),
            ],
            groups: [
                group("vat", tone: .vat),
                group("levies", tone: .authority(.tax)),
                group("spending", tone: .category(.spending)),
                group("savings", tone: .category(.savings), negative: true),
            ],
            accessibilityLabel: "Rozdělení: DPH 1 Kč")
    }

    // MARK: The layout

    @Test func theWidthsAreThoseOfTheLevyBarForTheWeights() {
        let sample = data()
        let widths = SplitBarLayout.widths(of: sample, width: 400)
        #expect(widths == LevyBarLayout.partWidths(weights: sample.segments.map(\.weight), width: 400))
    }

    @Test func aPartOfNoWeightHasNoWidth() {
        let widths = SplitBarLayout.widths(of: data(), width: 400)
        #expect(widths[3] == 0)
        #expect(widths[5] == 0)
        #expect(widths[0] > 0)
    }

    @Test func aGroupOfThreePartsHasItsPopoverCentredOnTheirMiddle() throws {
        let sample = data()
        let widths = SplitBarLayout.widths(of: sample, width: 400)
        let gap = LevyBarLayout.partGap
        // The levies run from the start of the second part to the end of the third, the health one drawing nothing.
        let start = widths[0] + gap
        let end = start + widths[1] + gap + widths[2]
        let centre = try #require(SplitBarLayout.centre(ofGroup: "levies", in: sample, width: 400))
        #expect(abs(centre - (start + end) / 2) < 0.001)
    }

    @Test func aGroupOfOnePartIsCentredOnIt() throws {
        let sample = data()
        let widths = SplitBarLayout.widths(of: sample, width: 400)
        let centres = LevyBarLayout.partCentres(widths: widths)
        let centre = try #require(SplitBarLayout.centre(ofGroup: "vat", in: sample, width: 400))
        #expect(abs(centre - centres[0]) < 0.001)
    }

    @Test func aGroupWithNoWidthIsCentredWhereTheNextPartWouldBegin() throws {
        let sample = data()
        let widths = SplitBarLayout.widths(of: sample, width: 400)
        let centre = try #require(SplitBarLayout.centre(ofGroup: "savings", in: sample, width: 400))
        #expect(abs(centre - LevyBarLayout.partCentres(widths: widths)[5]) < 0.001)
    }

    @Test func aGroupThatIsNotInTheBarHasNoCentre() {
        #expect(SplitBarLayout.centre(ofGroup: "nothing", in: data(), width: 400) == nil)
    }

    // MARK: The colours

    @Test func eachToneIsDrawnInItsColour() {
        #expect(SplitBarTone.vat.color == Palette.text4)
        #expect(SplitBarTone.authority(.social).color == Authority.social.color)
        #expect(SplitBarTone.category(.spending).color == Palette.green)
        #expect(SplitBarTone.category(.savings).color == Palette.greenText)
        #expect(SplitBarTone.category(.investments).color == Palette.accent)
        #expect(SplitBarTone.category(.costs).color == Palette.text2)
    }

    @Test func aNegativeAmountIsDrawnInTheRedOfText() {
        #expect(group("a", tone: .vat, negative: true).valueColor == Palette.redText)
        #expect(group("a", tone: .vat).valueColor == Palette.text)
    }

    // MARK: The picture

    /// Each part that has a width is drawn in its colour, in a light and in a dark window.
    @Test(arguments: [ColorScheme.light, .dark])
    func thePartsAreDrawnInTheirColours(scheme: ColorScheme) throws {
        let sample = data()
        let picture = try OffscreenPicture(of: SplitBarView(sample).frame(width: 400), in: scheme)
        let widths = SplitBarLayout.widths(of: sample, width: 400)
        let centres = LevyBarLayout.partCentres(widths: widths)
        for index in sample.segments.indices where widths[index] > 0 {
            let expected = try OffscreenPicture.bytes(of: sample.segments[index].tone.color, in: scheme)
            var found = false
            var y: CGFloat = 0
            while y < picture.size.height, !found {
                found = picture.bytes(at: CGPoint(x: centres[index], y: y)) == expected
                y += 1
            }
            #expect(found, "\(scheme): the part \(index) is drawn in its colour")
        }
    }
}
