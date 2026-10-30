import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The frame the window puts around the screens: the window background of the design that the page stands on, in a
/// light and in a dark window, and the green banner above the page, which keeps its place and follows the padding of
/// the page. The windows are real ones in the test host, with the data of `EditorFixture`.
@Suite(.serialized, .settlesBackups)
@MainActor
struct AppFrameTests {
    // MARK: The window background

    /// Every screen stands on the window background of the design, not on the system's, which is white in a light
    /// window on macOS 26 and later. The pixel is in the padding at the top of the page, 8 points under the toolbar and
    /// in the middle of the window, where no screen draws anything of its own; it is the colour of `Palette.bgWindow`
    /// in a light window and in a dark one.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func everyScreenStandsOnTheWindowBackground(appearance: NSAppearance.Name) async throws {
        let scheme: ColorScheme = appearance == .aqua ? .light : .dark
        let background = try OffscreenPicture.bytes(of: Palette.bgWindow, in: scheme)
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                window.appearance = NSAppearance(named: appearance)
                for screen in Screen.allCases {
                    f.app.screen = screen
                    try await layOut(window)
                    try await waitUntil { window.title == title(of: screen, in: f.app) }
                    let sample = try pagePaddingPixel(in: window)
                    try await waitUntil(timeout: .seconds(3)) {
                        try WindowPicture(of: window).bytes(at: sample).isBackground(background)
                    }
                    let picture = try WindowPicture(of: window)
                    #expect(
                        picture.bytes(at: sample).isBackground(background),
                        "\(screen) \(appearance.rawValue): \(picture.bytes(at: sample)), not \(background)")
                }
            }
        }
    }

    /// The pixel in the padding at the top of the page of `window`: in the middle of the window, 8 points under the
    /// toolbar, in points from the top left of the content of the window.
    private func pagePaddingPixel(in window: NSWindow) throws -> CGPoint {
        let content = try #require(window.contentView)
        return CGPoint(x: content.bounds.midX, y: content.bounds.height - window.contentLayoutRect.maxY + 8)
    }

    /// The title that the window shows for `screen`.
    private func title(of screen: Screen, in app: AppModel) -> String {
        screen.header(
            year: app.asOf.year, asOf: app.asOf.asOf, today: app.today, incomeFX: app.shownYearFXMethod
        ).title
    }

    // MARK: The green banner

    /// The green banner of an action stays above the screen it belongs to, under the toolbar. It is padded like the
    /// page: 24 points from the sidebar, 16 from the right edge of the window and 16 under the toolbar.
    @Test func theGreenBannerKeepsItsPlaceAboveTheScreenAndIsPaddedLikeThePage() async throws {
        let text = "Změny jsou uložené."
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.screen = .computation
                try await waitUntil { window.title == title(of: .computation, in: f.app) }
                f.app.banner = AppBanner(text: text, screen: .computation)
                try await withAccessibilityElements {
                    try await waitUntil { frameOfGroup(holdingText: text, in: window) != nil }
                    try await layOut(window)
                    let banner = try #require(frameOfGroup(holdingText: text, in: window))
                    let room = window.convertToScreen(window.contentLayoutRect)
                    let sidebar = window.convertToScreen(try sidebarFrame(in: window))

                    #expect((banner.minX - sidebar.maxX - DesignMetrics.pageLeading).magnitude < 0.5, "\(banner)")
                    #expect((window.frame.maxX - banner.maxX - DesignMetrics.pageTrailing).magnitude < 0.5, "\(banner)")
                    #expect((room.maxY - banner.maxY - DesignMetrics.pageTop).magnitude < 0.5, "\(banner)")
                }
            }
        }
    }

    /// The frame of the sidebar of `window`, in the coordinates of the window.
    private func sidebarFrame(in window: NSWindow) throws -> CGRect {
        let frameView = try #require(window.contentView?.superview)
        let controllers = splitViews(in: frameView).compactMap { $0.delegate as? NSSplitViewController }
        let sidebar = try #require(
            controllers.flatMap(\.splitViewItems).first { $0.behavior == .sidebar }?.viewController.view)
        return sidebar.convert(sidebar.bounds, to: nil)
    }

    /// The split views in `view` and below it, from the top.
    private func splitViews(in view: NSView) -> [NSSplitView] {
        let own = (view as? NSSplitView).map { [$0] } ?? []
        return own + view.subviews.flatMap { splitViews(in: $0) }
    }
}

private extension Array where Element == Int {
    /// Whether these red, green, blue and alpha bytes are the opaque colour `background`, given as its red, green and
    /// blue bytes: none of them is more than 2 apart, as the same colour comes out a byte or so apart where layers of
    /// the window are drawn over one another.
    func isBackground(_ background: [Int]) -> Bool {
        count == 4 && self[3] == 255 && zip(prefix(3), background).allSatisfy { abs($0 - $1) <= 2 }
    }
}
