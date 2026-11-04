import SwiftUI

/// The text of a choice that is set heavier while it is chosen. It takes the room of its heavier form whether it is
/// chosen or not, so that the choices beside it do not move when the choice changes.
struct ChoiceText: View {
    let title: String

    /// The font the text is set in now.
    let font: Font

    var body: some View {
        Text(verbatim: title)
            .font(Typography.bodySemibold)
            .hidden()
            .overlay {
                Text(verbatim: title)
                    .font(font)
            }
            .lineLimit(1)
    }
}

/// A row of segments on a grey track, of which one is chosen: the chosen segment is a capsule in the colour of a card
/// that stands off the track, in body semibold, and the others are plain text in body. Each segment is a capsule 28
/// points tall, and the track leaves 2 points around them. A segment that cannot be chosen is set in the faintest
/// colour of text and does nothing when it is clicked, and the pointer over it shows why, where the control says.
///
/// VoiceOver reads the control as a group under `label`, and each segment as a button that is selected while it is
/// chosen; one that cannot be chosen is a disabled button, with why as its help.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let segments: [(value: Value, title: String)]

    /// The values of the segments that cannot be chosen.
    let disabled: Set<Value>

    /// Why a segment cannot be chosen, by its value, which the pointer over it shows and VoiceOver reads as its help.
    let help: [Value: String]

    /// A control named `label` that chooses among `segments` by their values, and keeps the chosen one in `selection`.
    /// The values of the segments are different. The segments of `disabled` cannot be chosen, and `help` says why for
    /// those it names.
    init(
        _ label: String, selection: Binding<Value>, segments: [(value: Value, title: String)],
        disabled: Set<Value> = [], help: [Value: String] = [:]
    ) {
        self.label = label
        _selection = selection
        self.segments = segments
        self.disabled = disabled
        self.help = help
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.value) { segment in
                SegmentButton(
                    title: segment.title, isSelected: segment.value == selection,
                    isEnabled: !disabled.contains(segment.value), help: help[segment.value]
                ) {
                    selection = segment.value
                }
            }
        }
        .padding(2)
        .background(Palette.fill, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// One segment of a segmented control: in the faintest colour of text and disabled where it cannot be chosen, with
/// `help` on it where there is some.
private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let help: String?
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            ChoiceText(title: title, font: isSelected ? Typography.bodySemibold : Typography.body)
                .foregroundStyle(isEnabled ? Palette.text : Palette.text4)
                .padding(.horizontal, 12)
                .frame(height: DesignMetrics.smallControlHeight)
                .background {
                    if isSelected {
                        Capsule().surface(Palette.bgCard, elevation: .control)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .helpIfAny(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// The view with `text` as the help that the pointer over it shows and VoiceOver reads, or as it is for nil.
    @ViewBuilder
    func helpIfAny(_ text: String?) -> some View {
        if let text {
            help(Text(verbatim: text))
        } else {
            self
        }
    }
}
