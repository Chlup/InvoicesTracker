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
/// separator, a mark at `limitFraction` when it is below 100 %, and a round thumb. A drag or a click reports the whole
/// percent under the pointer and does not clamp it: the owner clamps to the exact limit and passes the new `fraction`
/// back, so the thumb stops at the limit. The arrow keys move the share by 1 %.
///
/// VoiceOver reads one adjustable element under `label` with the value `valueText`, and adjusts it by 1 %.
struct ShareSlider: View {
    let label: String
    let fraction: Double
    let limitFraction: Double
    let color: Color
    let valueText: String
    let onChange: (Int) -> Void
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

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
                        onChange(ShareSliderLayout.percent(atX: value.location.x, width: width))
                    }
                    .onEnded { value in
                        onChange(ShareSliderLayout.percent(atX: value.location.x, width: width))
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
                    set: { onChange(Int($0.rounded())) }),
                in: 0...100, step: 1,
                onEditingChanged: { editing in
                    if !editing { onCommit() }
                }
            )
        }
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
    }

    /// Reports the share `delta` percent from the current one, kept between 0 and 100, and then the end of the choice.
    private func step(_ delta: Int) {
        onChange(min(max(percent + delta, 0), 100))
        onCommit()
    }
}
