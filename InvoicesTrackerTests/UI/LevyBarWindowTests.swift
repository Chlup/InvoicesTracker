import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The levy bar in a window: VoiceOver reads the bar as one picture named by its three parts, and each item of the
/// legend as what its popover shows; the legend stands in three equal columns under the bar; and an open popover hangs
/// under the panel over what follows it, takes no room, is not read, and fades the other parts. The pointer cannot be
/// moved in a test, so the popover is opened as the pointer over a part opens it (`LevyBarView.init(_:showing:)`). The
/// bar is that of the sample year as of 17. 10. 2026 (`LevyBarTests`). In every expected string `\u{00A0}` is the
/// no-break space.
@Suite(.serialized)
@MainActor
struct LevyBarWindowTests {
    /// The bar of the balances of the sample year as of 17. 10. 2026, as Výpočet shows it.
    private let data = LevyBarBuilder.balances(
        of: TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17")),
        kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.", showsTotal: true)

    /// The width the tests give the bar.
    private let width: CGFloat = 404

    /// The size of the window the bar is hosted in: the bar 20 points from its top left, and what follows the bar.
    private let windowSize = CGSize(width: 444, height: 380)

    /// The bar `width` points wide, with the popover of `authority` open or none, 20 points from the top left of the
    /// background of a window, and under it a block in the accent colour, which stands for what follows the bar on a
    /// page and which an open popover covers.
    private func hostedBar(showing authority: Authority? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LevyBarView(data, showing: authority)
                .frame(width: width)
            Rectangle()
                .fill(Palette.accent)
                .frame(width: width, height: 200)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bgWindow)
    }

    // MARK: VoiceOver and the layout

    @Test func theBarIsOneImageNamedByAllThreeParts() async throws {
        try await withHostedView(hostedBar(), size: windowSize) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }
                let image = try #require(accessibilityElement(labelled: data.accessibilityLabel, in: window))

                #expect(image.accessibilityRole?() == .image)
                // The parts are no elements of their own. The children are read outside the expectation, whose macro
                // would otherwise type the `??` as optional and check nothing.
                let children = image.accessibilityChildren?() ?? []
                #expect(children.isEmpty, "The bar has \(children.count) children")
                // The bar is 16 points tall and as wide as the panel.
                let frame = try #require(image.accessibilityFrame?())
                #expect(abs(frame.height - 16) < 0.5, "\(frame)")
                #expect(abs(frame.width - width) < 0.5, "\(frame)")
            }
        }
    }

    @Test func eachLegendItemReadsItsPopoverRows() async throws {
        try await withHostedView(hostedBar(), size: windowSize) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }

                for part in data.parts {
                    #expect(
                        accessibilityElement(labelled: part.accessibilityLabel, in: window) != nil,
                        "No legend item reads \(part.accessibilityLabel)")
                }
                // No popover is open, and the names of the offices are only in a popover.
                let readings = accessibilityReadings(in: window)
                for office in Authority.allCases.map(\.office) {
                    #expect(!readings.contains { $0.contains(office) }, "\(office) is read")
                }
            }
        }
    }

    @Test func theLegendStandsInThreeEqualColumnsUnderTheBar() async throws {
        try await withHostedView(hostedBar(), size: windowSize) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }
                let bar = try #require(accessibilityElement(labelled: data.accessibilityLabel, in: window))
                let barFrame = try #require(bar.accessibilityFrame?())
                let items = try data.parts.map { part in
                    try #require(accessibilityElement(labelled: part.accessibilityLabel, in: window))
                }
                let frames = try items.map { item in try #require(item.accessibilityFrame?()) }

                // The width less two gaps of 16 points makes three columns of 124 points, at 0, 140 and 280 points
                // from the leading edge of the bar.
                for (index, frame) in frames.enumerated() {
                    #expect(abs(frame.width - 124) < 0.5, "\(frame)")
                    #expect(abs(frame.minX - barFrame.minX - CGFloat(index) * 140) < 0.5, "\(frame)")
                    // The screen has its origin at the bottom left: the legend is under the bar, 12 points lower.
                    #expect(abs(barFrame.minY - frame.maxY - 12) < 0.5, "\(frame) under \(barFrame)")
                }
            }
        }
    }

    // MARK: The section

    /// The bar with its header and its legend is one section for VoiceOver, named "Odvody podle úřadů" on every screen
    /// that shows the bar: a group that holds the picture of the bar and the three items of the legend, each of which
    /// is still read on its own, and that is as large as the whole bar, from its header to the foot of its legend.
    @Test func theBarWithItsLegendIsOneSectionNamedOdvodyPodleUradu() async throws {
        try await withHostedView(hostedBar(), size: windowSize) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }

                let section = try #require(accessibilityElement(labelled: "Odvody podle úřadů", in: window))
                #expect(section.accessibilityRole?() == .group)

                let readings = accessibilityReadings(under: section)
                #expect(readings.contains(data.accessibilityLabel), "The picture of the bar is not in the section")
                for part in data.parts {
                    #expect(readings.contains(part.accessibilityLabel), "\(part.authority) is not in the section")
                }

                // The section is the panel: the bar and the items of the legend are within its frame, and it is as
                // wide as the bar.
                let frame = try #require(section.accessibilityFrame?())
                let bar = try #require(accessibilityElement(labelled: data.accessibilityLabel, in: window))
                let barFrame = try #require(bar.accessibilityFrame?())
                #expect(abs(frame.width - width) < 0.5, "\(frame)")
                #expect(frame.insetBy(dx: -0.5, dy: -0.5).contains(barFrame), "\(barFrame) is not in \(frame)")
                for part in data.parts {
                    let item = try #require(accessibilityElement(labelled: part.accessibilityLabel, in: window))
                    let itemFrame = try #require(item.accessibilityFrame?())
                    #expect(
                        frame.insetBy(dx: -0.5, dy: -0.5).contains(itemFrame),
                        "The item of \(part.authority) is not in \(frame)")
                }
            }
        }
    }

    // MARK: An open popover

    @Test func anOpenPopoverTakesNoRoomAndIsNotRead() async throws {
        let closed = NSHostingView(rootView: LevyBarView(data).frame(width: width)).fittingSize
        let open = NSHostingView(rootView: LevyBarView(data, showing: .social).frame(width: width)).fittingSize
        #expect(open == closed)

        try await withHostedView(hostedBar(showing: .social), size: windowSize) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }

                let readings = accessibilityReadings(in: window)
                for office in Authority.allCases.map(\.office) {
                    #expect(!readings.contains { $0.contains(office) }, "\(office) is read")
                }
                // The bar and the legend read as they do with no popover open.
                #expect(readings.contains(data.accessibilityLabel))
                for part in data.parts {
                    #expect(readings.contains(part.accessibilityLabel), "\(part.authority) is not read")
                }
            }
        }
    }

    @Test func anOpenPopoverHangsUnderThePanelOverWhatFollowsAndTheOtherPartsFade() async throws {
        let closed = try await snapshot(showing: nil)
        let open = try await snapshot(showing: .social)
        let panelHeight = NSHostingView(rootView: LevyBarView(data).frame(width: width)).fittingSize.height
        let widths = LevyBarLayout.partWidths(weights: data.parts.map(\.weight), width: width)
        let centres = LevyBarLayout.partCentres(widths: widths)

        // The part whose popover is open keeps its colour, and the other two fade.
        for (index, part) in data.parts.enumerated() {
            let point = CGPoint(x: 20 + centres[index], y: open.bar.midY)
            let isUnchanged = try Snapshot.isAlike(open.picture.bytes(at: point), closed.picture.bytes(at: point))
            #expect(isUnchanged == (part.authority == .social), "The \(part.authority) part at \(point)")
        }
        // The popover is centred on its part, 8 points under the panel, over the block that follows the bar: 6 points
        // inside its corners it has the colour of a card where the block had the accent, and 40 points to either side
        // of it the block is as it was.
        let left = 20 + LevyBarLayout.popoverX(centredOn: centres[1], panelWidth: width)
        let top = 20 + panelHeight + 8
        for x in [left + 6, left + 254] {
            let point = CGPoint(x: x, y: top + 6)
            #expect(
                try !Snapshot.isAlike(open.picture.bytes(at: point), closed.picture.bytes(at: point)),
                "Nothing drawn at \(point)")
        }
        for x in [left - 40, left + 300] {
            let point = CGPoint(x: x, y: top + 6)
            #expect(
                try Snapshot.isAlike(open.picture.bytes(at: point), closed.picture.bytes(at: point)),
                "Drawn at \(point)")
        }
    }

    // MARK: In the result card

    /// The width of the result card of these tests: two columns of 416 points side by side.
    private let cardWidth: CGFloat = 900

    /// A result card `cardWidth` points wide, 20 points from the top left of the background of a window, with a
    /// stand-in for the key figure on the left and the bar with the popover of the health insurance open on the right,
    /// and, where `withBelow`, a block in the accent colour under its hairline.
    @ViewBuilder
    private func hostedResultCard(withBelow: Bool) -> some View {
        Group {
            if withBelow {
                ResultCard(label: "Výsledek") {
                    Color.clear.frame(height: 40)
                } trailing: {
                    LevyBarView(data, showing: .health)
                } below: {
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(height: 200)
                }
            } else {
                ResultCard(label: "Výsledek") {
                    Color.clear.frame(height: 40)
                } trailing: {
                    LevyBarView(data, showing: .health)
                }
            }
        }
        .frame(width: cardWidth)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bgWindow)
    }

    /// The points down the strip of the popover of the health insurance in the hosted result card, 6 points inside its
    /// leading edge and from 4 to 100 points under its top, whose colour is not that of the top of the strip: what is
    /// drawn over the popover. The strip is in the padding of the popover, where it draws nothing but its colour.
    private func pointsCrossingThePopover(withBelow: Bool) async throws -> [CGPoint] {
        var crossing: [CGPoint] = []
        try await withHostedView(hostedResultCard(withBelow: withBelow), size: CGSize(width: 960, height: 480)) {
            window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }
                let content = try #require(window.contentView)
                let card = window.convertFromScreen(try #require(frameOfCard(labelled: "Výsledek", in: window)))
                let cardTop = content.bounds.height - card.maxY
                let bar = window.convertFromScreen(
                    try #require(accessibilityElement(labelled: data.accessibilityLabel, in: window)?
                        .accessibilityFrame?()))
                // The columns are 416 points wide, and the bar is in the second, 444 points from the leading edge of
                // the card's content.
                let column = (cardWidth - 2 * DesignMetrics.cardPadding - ResultCardLayout.columnGap) / 2
                let panelHeight = NSHostingView(rootView: LevyBarView(data).frame(width: column)).fittingSize.height
                let widths = LevyBarLayout.partWidths(weights: data.parts.map(\.weight), width: column)
                let centre = LevyBarLayout.partCentres(widths: widths)[2]
                let columnX = card.minX + DesignMetrics.cardPadding + column + ResultCardLayout.columnGap
                let x = columnX + LevyBarLayout.popoverX(centredOn: centre, panelWidth: column) + 6
                let top = cardTop + DesignMetrics.cardPadding + panelHeight + LevyBarLayout.popoverGap
                // The parts and the popover are laid out in a pass of their own: the picture is taken once the part of
                // the health insurance is no longer the colour of the card around it.
                let part = CGPoint(x: columnX + centre, y: content.bounds.height - bar.midY)
                let padding = CGPoint(x: card.minX + 4, y: cardTop + 4)
                try await waitUntil {
                    let picture = try Snapshot(of: window)
                    return try !Snapshot.isAlike(picture.bytes(at: part), picture.bytes(at: padding))
                }
                let picture = try Snapshot(of: window)
                let colour = try picture.bytes(at: CGPoint(x: x, y: top + 4))
                for step in 0...192 {
                    let point = CGPoint(x: x, y: top + 4 + CGFloat(step) / 2)
                    if try !Snapshot.isAlike(picture.bytes(at: point), colour) {
                        crossing.append(point)
                    }
                }
            }
        }
        return crossing
    }

    @Test func inTheResultCardThePopoverCoversTheHairlineAndWhatIsUnderIt() async throws {
        let crossing = try await pointsCrossingThePopover(withBelow: true)

        #expect(crossing.isEmpty, "Drawn over the popover at \(crossing)")
    }

    @Test func inTheResultCardThePopoverCoversTheEdgeOfTheCard() async throws {
        let crossing = try await pointsCrossingThePopover(withBelow: false)

        #expect(crossing.isEmpty, "Drawn over the popover at \(crossing)")
    }

    // MARK: Pictures

    /// The hosted bar with the popover of `authority` open, or none, as the window draws it once the bar is drawn, and
    /// the frame of the bar in points from the top left of the content of the window.
    private func snapshot(showing authority: Authority?) async throws -> (picture: Snapshot, bar: CGRect) {
        var taken: (picture: Snapshot, bar: CGRect)?
        try await withHostedView(hostedBar(showing: authority), size: windowSize) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityElement(labelled: data.accessibilityLabel, in: window) != nil }
                let element = try #require(accessibilityElement(labelled: data.accessibilityLabel, in: window))
                let content = try #require(window.contentView)
                let inWindow = window.convertFromScreen(try #require(element.accessibilityFrame?()))
                let bar = CGRect(
                    x: inWindow.minX, y: content.bounds.height - inWindow.maxY, width: inWindow.width,
                    height: inWindow.height)
                // The parts are laid out in a pass of their own: the picture is taken once the middle of the bar is
                // no longer the background of the window around it.
                let middle = CGPoint(x: bar.midX, y: bar.midY)
                let outside = CGPoint(x: 4, y: 4)
                try await waitUntil {
                    let picture = try Snapshot(of: window)
                    return try !Snapshot.isAlike(picture.bytes(at: middle), picture.bytes(at: outside))
                }
                taken = (try Snapshot(of: window), bar)
            }
        }
        return try #require(taken)
    }
}

/// What a window shows: its content drawn from the top left into a bitmap of the test's own, in sRGB at 2 pixels to
/// the point, rather than into the one AppKit makes for the window, whose colour space is that of the screen.
@MainActor
private struct Snapshot {
    private let bitmap: NSBitmapImageRep

    /// The pixels to a point.
    private static let scale: CGFloat = 2

    /// The picture of what `window` shows now.
    init(of window: NSWindow) throws {
        let view = try #require(window.contentView)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int((view.bounds.width * Self.scale).rounded()),
                height: Int((view.bounds.height * Self.scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: Self.scale, y: Self.scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    /// Whether the colours `first` and `second` (`bytes(at:)`) are alike: none of their bytes are more than 6 apart.
    /// The same colour can come out a byte or so apart where layers of the window are drawn over one another, but a
    /// line or a fill drawn over it is farther away than that.
    static func isAlike(_ first: [Int], _ second: [Int]) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { abs($0 - $1) <= 6 }
    }

    /// The colour at `point`, in points from the top left of the content of the window, as its red, green, blue and
    /// alpha bytes.
    func bytes(at point: CGPoint) throws -> [Int] {
        let pixel = try #require(
            bitmap.colorAt(x: Int(point.x * Self.scale), y: Int(point.y * Self.scale)), "No colour at \(point)")
        return [pixel.redComponent, pixel.greenComponent, pixel.blueComponent, pixel.alphaComponent].map { component in
            Int((component * 255).rounded())
        }
    }
}
