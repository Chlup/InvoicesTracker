import SwiftUI

/// The filter row of Faktury: the scope picker, the chips and the search, side by side where they fit and wrapping like
/// words in a paragraph where they do not. Every subview but the last is placed at the size it asks for, on to the next
/// line where the width is used up. The last one, the search, is flexible: it takes the room that is left on its line,
/// between its least and its greatest width, and stands at the end of the line, flush with the trailing edge. Where its
/// least width does not fit the line it goes on to a line of its own, again at the end.
///
/// The subviews are laid out in place rather than chosen between by a `ViewThatFits` of the possible rows, because the
/// search is a text field that must stay the same view through every wrap: a field made anew when the row wraps (the
/// window is resized, or the chips narrow as a search narrows the list) would lose the focus in the middle of a word.
///
/// The row fills the width it is offered, so that the search is flush with the right edge of the page, and asks for no
/// minimum width of its own: the page is laid out by the room the window gives it.
struct FilterRowLayout: Layout {
    /// The gap between the subviews of a line, and between the lines.
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = roomWidth(proposal, subviews: subviews)
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width).frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(frame.size))
        }
    }

    /// The width to lay out in: the one proposed, or for none the width of all the subviews in one line, the search at
    /// its greatest width.
    private func roomWidth(_ proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return max(0, width)
        }
        let last = subviews.count - 1
        let widths = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(index == last ? .infinity : .unspecified).width
        }
        return widths.reduce(0, +) + spacing * CGFloat(last)
    }

    /// The frame of every subview in a room of `width` points, from the top left of the room, and the height of the
    /// lines together.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard let last = subviews.indices.last else { return ([], 0) }
        let leastWidth = subviews[last].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
        let greatestWidth = subviews[last].sizeThatFits(.infinity).width

        // The subviews of every line, and how wide the line is with the search at its least width.
        var lines: [[Int]] = []
        var used: [CGFloat] = []
        for index in subviews.indices {
            let wanted = index == last ? leastWidth : subviews[index].sizeThatFits(.unspecified).width
            if let line = lines.indices.last, used[line] + spacing + wanted <= width {
                lines[line].append(index)
                used[line] += spacing + wanted
            } else {
                lines.append([index])
                used.append(wanted)
            }
        }

        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var top: CGFloat = 0
        for (line, indices) in lines.enumerated() {
            let sizes = indices.map { index -> CGSize in
                if index == last {
                    let room = width - (used[line] - leastWidth)
                    return subviews[index].sizeThatFits(
                        ProposedViewSize(width: min(greatestWidth, max(leastWidth, room)), height: nil))
                }
                // A subview that is wider than the whole room is offered the room, so that one that can shrink does.
                let ideal = subviews[index].sizeThatFits(.unspecified)
                return subviews[index].sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            }
            let height = sizes.map(\.height).max() ?? 0
            var left: CGFloat = 0
            for (index, size) in zip(indices, sizes) {
                let x = index == last ? max(0, width - size.width) : left
                let y = top + (height - size.height) / 2
                frames[index] = CGRect(x: x, y: y, width: size.width, height: size.height)
                left += size.width + spacing
            }
            top += height + lineSpacing
        }
        return (frames, max(0, top - lineSpacing))
    }
}
