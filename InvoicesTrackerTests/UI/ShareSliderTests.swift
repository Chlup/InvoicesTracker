import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The share slider and the read-only rail: where the thumb stands for a share and which share is under the pointer,
/// the colours of the track, drawn off-screen in a light and a dark window, and the slider as VoiceOver adjusts it.
@Suite(.serialized)
@MainActor
struct ShareSliderTests {
    // MARK: The layout

    @Test func theThumbStandsAtItsShareOfTheRoomBetweenTheEdgesOfItsTravel() {
        #expect(ShareSliderLayout.thumbX(fraction: 0.5, width: 220) == 100)
        #expect(ShareSliderLayout.thumbX(fraction: 0, width: 220) == 0)
        #expect(ShareSliderLayout.thumbX(fraction: 1, width: 220) == 200)
    }

    @Test func thePercentUnderThePointerIsWholeAndStaysBetweenZeroAndAHundred() {
        #expect(ShareSliderLayout.percent(atX: 110, width: 220) == 50)
        #expect(ShareSliderLayout.percent(atX: -5, width: 220) == 0)
        #expect(ShareSliderLayout.percent(atX: 500, width: 220) == 100)
        #expect(ShareSliderLayout.percent(atX: 10 + 200 * 0.374, width: 220) == 37)
    }

    // MARK: The colours

    /// The fill is in the colour it is given, the part the thumb can reach is the strong separator, and the rest of the
    /// track is the fill token, in a light and in a dark window.
    @Test(arguments: [ColorScheme.light, .dark])
    func theTrackShowsTheFillTheReachableRailAndTheRest(scheme: ColorScheme) throws {
        let slider = ShareSlider(
            label: "Podíl", fraction: 0.15, limitFraction: 0.62, color: Palette.greenText, valueText: "15 %",
            onChange: { _ in }, onCommit: {}
        )
        .frame(width: 220)
        let picture = try OffscreenPicture(of: slider, in: scheme)
        let y = ShareSliderLayout.height / 2

        let green = try OffscreenPicture.bytes(of: Palette.greenText, in: scheme)
        let reachable = try OffscreenPicture.bytes(of: Palette.sepStrong, in: scheme)
        let rest = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)

        #expect(picture.bytes(at: CGPoint(x: 20, y: y)) == green, "\(scheme): the fill")
        #expect(picture.bytes(at: CGPoint(x: 100, y: y)) == reachable, "\(scheme): the reachable part")
        #expect(picture.bytes(at: CGPoint(x: 180, y: y)) == rest, "\(scheme): beyond the limit")
    }

    /// The rail has the fill and the track but no thumb: the pixel where the thumb of a slider would stand is the fill.
    @Test(arguments: [ColorScheme.light, .dark])
    func theRailHasTheFillAndNoThumb(scheme: ColorScheme) throws {
        let rail = ShareRail(fraction: 0.5, color: Palette.greenText).frame(width: 220)
        let picture = try OffscreenPicture(of: rail, in: scheme)
        let y = picture.size.height / 2

        let green = try OffscreenPicture.bytes(of: Palette.greenText, in: scheme)
        let rest = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
        #expect(picture.bytes(at: CGPoint(x: 60, y: y)) == green, "\(scheme): the fill")
        #expect(picture.bytes(at: CGPoint(x: 100, y: y)) == green, "\(scheme): the fill where a thumb would be")
        #expect(picture.bytes(at: CGPoint(x: 180, y: y)) == rest, "\(scheme): the rest")
    }

    // MARK: VoiceOver

    @Test func voiceOverAdjustsTheShareByOnePercentAndCommits() async throws {
        var changes: [Int] = []
        var commits = 0
        let slider = ShareSlider(
            label: "Podíl rezervy", fraction: 0.15, limitFraction: 0.62, color: Palette.greenText,
            valueText: "15 %", onChange: { changes.append($0) }, onCommit: { commits += 1 }
        )

        try await withHostedView(slider, size: CGSize(width: 320, height: 80)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "Podíl rezervy", in: window) != nil }
                let element = try #require(accessibilityElement(labelled: "Podíl rezervy", in: window))
                // Asked for as a function of its type, because the protocols of accessibility declare
                // `accessibilityValue()` with more than one type.
                let value: (() -> Any?)? = element.accessibilityValue
                #expect(element.accessibilityRole?() == .slider)
                #expect(((value?() ?? nil) as? NSNumber)?.intValue == 15)
                // The text VoiceOver speaks beside the number, which the value of a slider is.
                #expect(element.accessibilityValueDescription?() == "15 %")

                _ = element.accessibilityPerformIncrement?()
                #expect(changes == [16])
                #expect(commits == 1)

                _ = element.accessibilityPerformDecrement?()
                #expect(changes == [16, 14])
                #expect(commits == 2)
            }
        }
    }
}
