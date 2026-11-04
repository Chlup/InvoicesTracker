import SwiftUI

/// The measures of the share slider and of the rail, and the two conversions between a share and a place on the track.
/// The thumb is 20 points across and its centre travels from 10 points in from the leading edge to 10 points in from
/// the trailing one, so the thumb never leaves the track.
nonisolated enum ShareSliderLayout {
    /// The height of the slider.
    static let height: CGFloat = 22

    /// The height of the track.
    static let trackHeight: CGFloat = 6

    /// The diameter of the thumb.
    static let thumbDiameter: CGFloat = 20

    /// The size of the mark at the limit.
    static let stopSize = CGSize(width: 2, height: 14)

    /// How far the thumb of a slider `width` points wide stands from the first place it can take, for a share of
    /// `fraction` (0 to 1). The centre of the thumb is 10 points further, so a fill that starts at 10 ends at it.
    static func thumbX(fraction: Double, width: CGFloat) -> CGFloat {
        (width - thumbDiameter) * CGFloat(fraction)
    }

    /// The whole percent, from 0 to 100, that lies under a pointer `x` points from the leading edge of a slider `width`
    /// points wide.
    static func percent(atX x: CGFloat, width: CGFloat) -> Int {
        let travel = width - thumbDiameter
        guard travel > 0 else { return 0 }
        let fraction = Double((x - thumbDiameter / 2) / travel)
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// The whole percent a step of `delta` takes a share of `fraction` (0 to 1) to, kept between 0 and 100: the first
    /// whole percent above the share for a step up, and the first below it for a step down, so that 15,5 % steps to
    /// 16 % and to 15 %, and 15 % to 16 % and to 14 %. A share within a millionth of a percent of a whole percent is
    /// that percent, as 15 % comes as 15.000000000000002 in a Double.
    static func percent(steppingFrom fraction: Double, by delta: Int) -> Int {
        let exact = min(max(fraction, 0), 1) * 100
        let tolerance = 0.000_001
        let next: Double
        if delta > 0 {
            next = (exact + tolerance).rounded(.down) + Double(delta)
        } else if delta < 0 {
            next = (exact - tolerance).rounded(.up) + Double(delta)
        } else {
            next = exact.rounded()
        }
        return Int(min(max(next, 0), 100))
    }
}

/// How a drag took hold of a share slider when it started: by the thumb, at the distance of the pointer from the
/// centre of the thumb, or by the track beside the thumb. A drag that took the thumb reports nothing until the pointer
/// moves, so that a click on the thumb, which also focuses the slider, leaves the share as it is, also one that is no
/// whole percent; then the thumb follows the pointer at the distance it was taken at. A drag that took the track puts
/// the thumb under the pointer at once.
nonisolated struct ShareSliderGrab: Equatable {
    /// How far right of the centre of the thumb the drag took it, below zero to the left of it, or nil when the drag
    /// took the track.
    let thumbOffset: CGFloat?

    /// Where the drag started, in points from the leading edge of the slider.
    let startX: CGFloat

    /// Whether the pointer has moved since the drag started.
    private(set) var hasMoved = false

    /// The hold of a drag that starts `startX` points from the leading edge of a slider `width` points wide whose
    /// thumb stands at `fraction`: the thumb when the pointer is on it, at most 10 points from its centre, and the
    /// track otherwise.
    init(startX: CGFloat, fraction: Double, width: CGFloat) {
        let thumbX = ShareSliderLayout.thumbX(fraction: min(max(fraction, 0), 1), width: width)
        let offset = startX - (thumbX + ShareSliderLayout.thumbDiameter / 2)
        thumbOffset = abs(offset) <= ShareSliderLayout.thumbDiameter / 2 ? offset : nil
        self.startX = startX
    }

    /// The whole percent the drag sets with the pointer `x` points from the leading edge of the slider, `width` points
    /// wide: the one under the centre of the thumb as the drag holds it. Nil while a drag that took the thumb has not
    /// moved.
    mutating func percent(atX x: CGFloat, width: CGFloat) -> Int? {
        guard let thumbOffset else { return ShareSliderLayout.percent(atX: x, width: width) }
        if x != startX {
            hasMoved = true
        }
        guard hasMoved else { return nil }
        return ShareSliderLayout.percent(atX: x - thumbOffset, width: width)
    }
}

/// The track of a share: the whole width in the fill token, with an optional rail in the strong separator from the
/// start to the limit, and the fill in `color` from the start to the share. The rails start at the first place the
/// centre of a thumb can take and end at the centre of the thumb for their share.
private struct ShareTrack: View {
    let fraction: Double
    let limitFraction: Double?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.fill)
                    .frame(height: ShareSliderLayout.trackHeight)
                if let limitFraction {
                    rail(Palette.sepStrong, fraction: limitFraction, width: width)
                }
                rail(color, fraction: fraction, width: width)
            }
            .frame(width: width, height: proxy.size.height)
        }
    }

    /// A bar in `style` from the first place of a thumb's centre to its place for `fraction`.
    private func rail(_ style: Color, fraction: Double, width: CGFloat) -> some View {
        let end = ShareSliderLayout.thumbDiameter / 2 + ShareSliderLayout.thumbX(fraction: fraction, width: width)
        return Capsule()
            .fill(style)
            .frame(width: max(end - ShareSliderLayout.thumbDiameter / 2, 0), height: ShareSliderLayout.trackHeight)
            .offset(x: ShareSliderLayout.thumbDiameter / 2)
    }
}

/// A track with a share filled in `color` and nothing to move: it shows a share that follows from other choices, such
/// as a fixed amount or what is left.
struct ShareRail: View {
    let fraction: Double
    let color: Color

    /// A rail filled to `fraction` (0 to 1) in `color`.
    init(fraction: Double, color: Color) {
        self.fraction = fraction
        self.color = color
    }

    var body: some View {
        ShareTrack(fraction: fraction, limitFraction: nil, color: color)
            .frame(height: ShareSliderLayout.trackHeight)
            .accessibilityHidden(true)
    }
}

/// A slider for a share of 0 to 100 %: a track with the fill in `color`, the part the thumb can reach in the strong
/// separator, a mark at `limitFraction` when it is below 100 %, and a round thumb. A press on the track beside the
/// thumb puts the thumb under the pointer; a press on the thumb takes hold of it where the pointer is, so a click on
/// it changes nothing and a drag moves it with the pointer (`ShareSliderGrab`). Either reports the whole percent under
/// the centre of the thumb and does not clamp it: the owner clamps to the exact limit and passes the new `fraction`
/// back, so the thumb stops at the limit. The arrow keys step the share to the next whole percent in their direction
/// (`ShareSliderLayout.percent(steppingFrom:by:)`).
///
/// VoiceOver reads one adjustable element under `label` with the value `valueText`, and steps it as the arrow keys do.
struct ShareSlider: View {
    let label: String
    let fraction: Double
    let limitFraction: Double
    let color: Color
    let valueText: String
    let onChange: (Int) -> Void
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    /// How the drag that runs took hold of the slider, from its start to its end; nil while there is no drag.
    @State private var grab: ShareSliderGrab?

    /// A slider named `label` at `fraction` (0 to 1) that can reach `limitFraction`, filled in `color` and read as
    /// `valueText`. `onChange` gets the whole percent the person chose, and `onCommit` is called when the choice is
    /// done: at the end of a drag and after a key press.
    init(
        label: String, fraction: Double, limitFraction: Double, color: Color, valueText: String,
        onChange: @escaping (Int) -> Void, onCommit: @escaping () -> Void
    ) {
        self.label = label
        self.fraction = fraction
        self.limitFraction = limitFraction
        self.color = color
        self.valueText = valueText
        self.onChange = onChange
        self.onCommit = onCommit
    }

    /// The whole percent of the current share.
    private var percent: Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let radius = ShareSliderLayout.thumbDiameter / 2
            ZStack(alignment: .leading) {
                ShareTrack(fraction: fraction, limitFraction: limitFraction, color: color)
                if limitFraction < 1 {
                    Rectangle()
                        .fill(Palette.text3)
                        .frame(width: ShareSliderLayout.stopSize.width, height: ShareSliderLayout.stopSize.height)
                        .offset(
                            x: radius + ShareSliderLayout.thumbX(fraction: limitFraction, width: width)
                                - ShareSliderLayout.stopSize.width / 2)
                }
                Circle()
                    .surface(Palette.bgCard, elevation: .control)
                    .overlay {
                        if isFocused {
                            Circle()
                                .stroke(Palette.accentSoft, lineWidth: 3)
                                .padding(-1.5)
                        }
                    }
                    .frame(width: ShareSliderLayout.thumbDiameter, height: ShareSliderLayout.thumbDiameter)
                    .offset(x: ShareSliderLayout.thumbX(fraction: fraction, width: width))
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isFocused = true
                        drag(to: value, width: width)
                    }
                    .onEnded { value in
                        drag(to: value, width: width)
                        grab = nil
                        onCommit()
                    }
            )
        }
        .frame(height: ShareSliderLayout.height)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(percent) },
                    set: { adjust(to: Int($0.rounded())) }),
                in: 0...100, step: 1,
                onEditingChanged: { editing in
                    if !editing { onCommit() }
                }
            )
        }
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
    }

    /// Reports the whole percent of the drag that `value` describes, held as it was taken when the drag started
    /// (`ShareSliderGrab`), and nothing while a drag that took the thumb has not moved.
    private func drag(to value: DragGesture.Value, width: CGFloat) {
        var current = grab ?? ShareSliderGrab(startX: value.startLocation.x, fraction: fraction, width: width)
        let reported = current.percent(atX: value.location.x, width: width)
        grab = current
        if let reported {
            onChange(reported)
        }
    }

    /// Reports the share a step of `delta` takes the current one to, the next whole percent in its direction, and
    /// then the end of the choice.
    private func step(_ delta: Int) {
        onChange(ShareSliderLayout.percent(steppingFrom: fraction, by: delta))
        onCommit()
    }

    /// Reports the whole percent `target` that VoiceOver sets: a step of 1 % from the whole percent it reads, the
    /// increment or the decrement, steps from the share itself as an arrow key does, and nothing when it is the
    /// percent it reads.
    private func adjust(to target: Int) {
        switch target - percent {
        case 0:
            return
        case 1, -1:
            onChange(ShareSliderLayout.percent(steppingFrom: fraction, by: target - percent))
        default:
            onChange(target)
        }
    }
}
