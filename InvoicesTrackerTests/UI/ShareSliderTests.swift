import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The share slider and the read-only rail: where the thumb stands for a share and which share is under the pointer,
/// the colours of the track, drawn off-screen in a light and a dark window, the slider as VoiceOver adjusts it, how a
/// drag takes hold of the thumb or the track, and where an arrow key steps to.
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

    /// From a share that is no whole percent, as one set from koruny, VoiceOver steps to the next whole percent: up to
    /// the first above it and down to the first below it, so 15,7 % and 15,3 % both step to 16 % and to 15 %.
    @Test(arguments: [0.157, 0.153])
    func voiceOverStepsFromAShareBetweenWholePercentsToTheNextOne(fraction: Double) async throws {
        var changes: [Int] = []
        let slider = ShareSlider(
            label: "Podíl rezervy", fraction: fraction, limitFraction: 1, color: Palette.greenText, valueText: "",
            onChange: { changes.append($0) }, onCommit: {}
        )

        try await withHostedView(slider, size: CGSize(width: 320, height: 80)) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: "Podíl rezervy", in: window) != nil }
                let element = try #require(accessibilityElement(labelled: "Podíl rezervy", in: window))

                _ = element.accessibilityPerformIncrement?()
                _ = element.accessibilityPerformDecrement?()

                #expect(changes == [16, 15])
            }
        }
    }

    // MARK: The pointer

    /// A drag that starts on the thumb takes hold of it where the pointer is: it reports nothing until the pointer
    /// moves, so a click on the thumb leaves a share that is no whole percent, as one set from koruny, as it is; then
    /// the thumb follows the pointer at the distance it was taken at, also back to where it started. The slider is
    /// 220 points wide, so the centre of its thumb travels 200 points from 10 points in: at 16,033 % it is 42,07
    /// points in.
    @Test func aDragFromTheThumbHoldsItWhereThePointerTookIt() {
        let centre = 10 + 200 * 0.160_33
        var grab = ShareSliderGrab(startX: centre + 5, fraction: 0.160_33, width: 220)

        #expect(grab.percent(atX: centre + 5, width: 220) == nil)
        #expect(grab.percent(atX: centre + 5, width: 220) == nil)
        // 40 points to the right, the centre of the thumb is 82,07 points in: 36 %.
        #expect(grab.percent(atX: centre + 45, width: 220) == 36)
        // Back where it started, the thumb is where it was, at the whole percent there.
        #expect(grab.percent(atX: centre + 5, width: 220) == 16)
    }

    /// A drag that starts on the track beside the thumb puts the thumb under the pointer at once, and then follows the
    /// pointer: 160 points in is 75 %, 170 points in 80 %.
    @Test func aDragFromTheTrackPutsTheThumbUnderThePointer() {
        var grab = ShareSliderGrab(startX: 160, fraction: 0.160_33, width: 220)

        #expect(grab.percent(atX: 160, width: 220) == 75)
        #expect(grab.percent(atX: 170, width: 220) == 80)
    }

    /// The thumb is 20 points across: a press up to 10 points from its centre takes the thumb, one further takes the
    /// track.
    @Test func theThumbReachesTenPointsFromItsCentre() {
        let centre = 10 + 200 * 0.5
        for x in [centre - 10, centre, centre + 10] {
            var grab = ShareSliderGrab(startX: x, fraction: 0.5, width: 220)
            #expect(grab.percent(atX: x, width: 220) == nil, "\(x)")
        }
        for x in [centre - 10.5, centre + 10.5] {
            var grab = ShareSliderGrab(startX: x, fraction: 0.5, width: 220)
            #expect(grab.percent(atX: x, width: 220) == ShareSliderLayout.percent(atX: x, width: 220), "\(x)")
        }
    }

    // MARK: The keys

    /// An arrow key steps from the share to the next whole percent in its direction: from 15,5 % up to 16 % and down to
    /// 15 %, from a whole 15 % to 16 % and 14 %, though 15 % comes as 15.000000000000002 in a Double, and never beyond
    /// 0 % or 100 %.
    @Test func aStepGoesToTheNextWholePercentInItsDirection() {
        #expect(ShareSliderLayout.percent(steppingFrom: 0.155, by: 1) == 16)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.155, by: -1) == 15)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.157, by: 1) == 16)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.153, by: -1) == 15)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.15, by: 1) == 16)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.15, by: -1) == 14)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.07, by: -1) == 6)
        #expect(ShareSliderLayout.percent(steppingFrom: 0, by: -1) == 0)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.004, by: -1) == 0)
        #expect(ShareSliderLayout.percent(steppingFrom: 1, by: 1) == 100)
        #expect(ShareSliderLayout.percent(steppingFrom: 0.996, by: 1) == 100)
    }
}
