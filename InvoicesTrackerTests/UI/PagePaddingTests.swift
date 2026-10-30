import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The padding of a page (`pagePadding(_:)`): the room the window leaves around the content of a screen, which is more
/// on the leading side than on the trailing one, and less above than below.
@MainActor
struct PagePaddingTests {
    /// The room the content is hosted in.
    private let room = CGSize(width: 400, height: 300)

    /// A view that fills the room it is given and has a part of AppKit behind it, whose frame says where it is.
    private var content: some View {
        Color.clear.background { LayoutPart(name: "content") }
    }

    /// Where the content of `page` is in the room, in points from its top left.
    private func contentFrame(of page: some View) -> CGRect? {
        let hosting = NSHostingView(rootView: page.frame(width: room.width, height: room.height))
        hosting.frame = CGRect(origin: .zero, size: room)
        hosting.layoutSubtreeIfNeeded()
        return framesOfParts(in: hosting)["content"]
    }

    /// Whether `frame` is `expected`, to a tenth of a point.
    private func isFrame(_ frame: CGRect?, _ expected: CGRect) -> Bool {
        guard let frame else { return false }
        return abs(frame.minX - expected.minX) < 0.1 && abs(frame.minY - expected.minY) < 0.1
            && abs(frame.width - expected.width) < 0.1 && abs(frame.height - expected.height) < 0.1
    }

    @Test func aPageIsPaddedBy24OnTheLeading16OnTheTrailing16AtTheTopAnd24AtTheBottom() {
        let frame = contentFrame(of: content.pagePadding())
        let expected = CGRect(x: 24, y: 16, width: 360, height: 260)

        #expect(isFrame(frame, expected), "laid out as \(String(describing: frame))")
    }

    @Test func aPageIsPaddedOnTheEdgesGivenAndOnNoOther() {
        let cases: [(edges: Edge.Set, expected: CGRect)] = [
            (.horizontal, CGRect(x: 24, y: 0, width: 360, height: 300)),
            (.vertical, CGRect(x: 0, y: 16, width: 400, height: 260)),
            ([.horizontal, .top], CGRect(x: 24, y: 16, width: 360, height: 284)),
            ([.horizontal, .bottom], CGRect(x: 24, y: 0, width: 360, height: 276)),
            (.leading, CGRect(x: 24, y: 0, width: 376, height: 300)),
            (.trailing, CGRect(x: 0, y: 0, width: 384, height: 300)),
            (.top, CGRect(x: 0, y: 16, width: 400, height: 284)),
            (.bottom, CGRect(x: 0, y: 0, width: 400, height: 276)),
        ]

        for (edges, expected) in cases {
            let frame = contentFrame(of: content.pagePadding(edges))
            #expect(isFrame(frame, expected), "\(edges): laid out as \(String(describing: frame))")
        }
    }
}
