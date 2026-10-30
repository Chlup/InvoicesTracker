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
/// points tall, and the track leaves 2 points around them.
///
/// VoiceOver reads the control as a group under `label`, and each segment as a button that is selected while it is
/// chosen.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let segments: [(value: Value, title: String)]

    /// A control named `label` that chooses among `segments` by their values, and keeps the chosen one in `selection`.
    /// The values of the segments are different.
    init(_ label: String, selection: Binding<Value>, segments: [(value: Value, title: String)]) {
        self.label = label
        _selection = selection
        self.segments = segments
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.value) { segment in
                SegmentButton(title: segment.title, isSelected: segment.value == selection) {
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

/// One segment of a segmented control.
private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            ChoiceText(title: title, font: isSelected ? Typography.bodySemibold : Typography.body)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 12)
                .frame(height: DesignMetrics.smallControlHeight)
                .background {
                    if isSelected {
                        Capsule().fill(Palette.bgCard).elevation(.control)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
