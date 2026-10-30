import AppKit
import SwiftUI

/// A view of AppKit with no size of its own, which a layout under test places: its frame in the hosting view says where
/// the layout put it. The tests of the layouts (`FilterRowLayout`, `TwoColumnStack`, `MonthCellGrid`) put named parts
/// in the layout, host it, and read the frames of the parts back with `framesOfParts(in:)`.
@MainActor
struct LayoutPart: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        NamedPartView(name: name)
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// The view of AppKit that a `LayoutPart` is.
final class NamedPartView: NSView {
    let name: String

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("The parts are made in code.")
    }
}

/// The frames of the parts of the layout in `root`, by name, in the coordinates of `root` with the origin at its top
/// left, where the layout went when `root` was laid out.
@MainActor
func framesOfParts(in root: NSView) -> [String: CGRect] {
    var frames: [String: CGRect] = [:]
    collectParts(in: root, root: root, into: &frames)
    return frames
}

@MainActor
private func collectParts(in view: NSView, root: NSView, into frames: inout [String: CGRect]) {
    if let part = view as? NamedPartView {
        var frame = part.convert(part.bounds, to: root)
        if !root.isFlipped {
            frame.origin.y = root.bounds.height - frame.maxY
        }
        frames[part.name] = frame
    }
    for subview in view.subviews {
        collectParts(in: subview, root: root, into: &frames)
    }
}
