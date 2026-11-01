import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The windows the tests show the app and its views in keep the size their test gives them, while windows of other tests
/// open, change their size and close. Where the person prefers tabs (Desktop & Dock › Prefer tabs when opening
/// documents: Always), a window that opens while another one is open would become one of its tabs, and tabs share one
/// frame. The window would then take the size of the other window and follow it when that one is resized or closed. A
/// page that moves to another arrangement so makes its fields anew, and a test typing into one of them loses its focus.
@Suite(.serialized, .settlesBackups)
@MainActor
struct TestWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// An app window 1 570 points wide is open while another one opens 1 300 points wide, is made as small as the app
    /// allows and closes. Each window has the size it was given, and the first keeps its size throughout.
    @Test func anAppWindowKeepsItsSizeWhileAnotherOneOpensChangesAndCloses() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: CGSize(width: 1_570, height: 720)) { first in
                try await layOut(first)
                let size = first.frame.size
                try await EditorFixture.with { g in
                    try await withAppWindow(of: g.app, size: CGSize(width: 1_300, height: 720)) { second in
                        try await layOut(second)
                        #expect(second.frame.width == 1_300)
                        #expect(first.frame.size == size)
                        second.setContentSize(AppWindowSize.minimum)
                        try await layOut(second)
                        #expect(first.frame.size == size)
                    }
                }
                try await layOut(first)
                #expect(first.frame.size == size)
            }
        }
    }

    /// A window of a test is open to the pointer of the person who runs the tests, as any window is, unless its test
    /// closes it (`ignoringTheRealPointer`): the tests that move the pointer by hand do, so that the real pointer
    /// passing over the window cannot close or move what they have opened. A closed window takes no event of the real
    /// mouse and says for itself where its pointer is, in the corner of its content, whatever the real pointer does.
    /// The tests that click and scroll through the event handling of the app keep the ordinary window.
    @Test func aWindowIsOpenToTheRealPointerUnlessItsTestClosesIt() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let testWindow = try #require(window as? TestWindow)
                #expect(!window.ignoresMouseEvents)
                #expect(!testWindow.isClosedToTheRealPointer)
            }
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum, ignoringTheRealPointer: true) { window in
                let testWindow = try #require(window as? TestWindow)
                #expect(window.ignoresMouseEvents)
                #expect(testWindow.isClosedToTheRealPointer)
                #expect(window.mouseLocationOutsideOfEventStream == TestWindow.restingPointer)
            }
        }
    }

    /// A test moves the pointer by hand (`movePointer(to:in:)`) only in a window that is closed to the real pointer: in
    /// any other window the test would pass or fail by where the pointer of the person who runs the tests is. The
    /// helper refuses such a window, and so keeps every test that uses it immune to the real pointer. In a closed
    /// window the pointer of the window is where the test has moved it.
    @Test func thePointerIsMovedByHandOnlyInAWindowThatIsClosedToTheRealPointer() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                withKnownIssue("A window that is open to the real pointer is refused") {
                    try movePointer(to: CGPoint(x: 40, y: 40), in: window)
                }
            }
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum, ignoringTheRealPointer: true) { window in
                try await layOut(window)
                try movePointer(to: CGPoint(x: 40, y: 50), in: window)
                #expect(window.mouseLocationOutsideOfEventStream == CGPoint(x: 40, y: 50))
            }
        }
    }

    /// SwiftUI follows the pointer in a window only while the window says the pointer is inside it, so a view reacts
    /// to the pointer that a test moves by hand only while the real pointer of the person who runs the tests is over
    /// the window too, and not when it is somewhere else on the screen. A window that is closed to the real pointer
    /// answers for itself: the levy bar of Výpočet fades its other parts while the pointer is over its part of the
    /// tax, and shows them again when the pointer leaves it, wherever the real pointer is. The window is put where the
    /// real pointer is not, so that a window that asked the real one would find the pointer outside.
    @Test func theLevyBarFollowsThePointerOfTheTestWhereverTheRealPointerIs() async throws {
        try await EditorFixture.with { f in
            let result = try await f.app.computeSelectedYear()
            let weights = Authority.allCases.map { result.balance($0).liability }
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum, ignoringTheRealPointer: true) { window in
                moveAwayFromTheRealPointer(window)
                try await withAccessibilityElements {
                    try await layOut(window)
                    try await waitUntil {
                        accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window) != nil
                    }
                    try await layOut(window)
                    let bar = window.convertFromScreen(
                        try #require(
                            accessibilityElement(labelStartingWith: "Odvody z příjmů do", in: window)?
                                .accessibilityFrame?()))

                    /// The colour of the part of the social insurance, which fades while the pointer is over the part
                    /// of the tax.
                    @MainActor func socialPart() throws -> [Int] {
                        try colourOfTheSocialPartOfTheLevyBar(weights: weights, bar: bar, in: window)
                    }
                    let resting = try socialPart()

                    try movePointer(to: CGPoint(x: bar.minX + 10, y: bar.midY), in: window)
                    try await waitUntil { ((try? socialPart()) ?? resting) != resting }

                    try movePointer(to: TestWindow.restingPointer, in: window)
                    try await waitUntil { ((try? socialPart()) ?? []) == resting }
                }
            }
        }
    }

    /// A view that is hosted alone follows the pointer that a test moves by hand: SwiftUI makes the area it follows the
    /// pointer in as the view comes to the window, before the view has its size, and takes the pointer to be outside
    /// it for good. The window of a test that is closed to the real pointer puts its content back once it is laid out
    /// (`TestWindow.makeTheAreasOfThePointerAnew()`), and the pointer of the test is inside the view then. The window
    /// is put where the real pointer is not, and the view follows the pointer of the test all the same.
    @Test func aViewHostedAloneFollowsThePointerOfTheTest() async throws {
        let state = HoverState()
        try await withHostedView(HoverArea(state: state), size: HoverArea.windowSize, ignoringTheRealPointer: true) {
            window in
            moveAwayFromTheRealPointer(window)
            try await layOut(window)

            try movePointer(to: HoverArea.centre, in: window)
            try await waitUntil { state.isHovered }

            try movePointer(to: HoverArea.corner, in: window)
            try await waitUntil { !state.isHovered }
        }
    }

    /// The same for the window of a hosted view: one 900 points wide keeps its size while another one opens 600 points
    /// wide and closes.
    @Test func aHostedViewWindowKeepsItsSizeWhileAnotherOneOpensAndCloses() async throws {
        try await withHostedView(Color.clear, size: CGSize(width: 900, height: 700)) { first in
            let size = first.frame.size
            try await withHostedView(Color.clear, size: CGSize(width: 600, height: 400)) { second in
                #expect(second.frame.width == 600)
                #expect(first.frame.size == size)
            }
            try await layOut(first)
            #expect(first.frame.size == size)
        }
    }
}

/// What a view under test says about the pointer.
@MainActor
private final class HoverState {
    var isHovered = false
}

/// A rectangle in the middle of a window that tells `state` whether the pointer is over it.
private struct HoverArea: View {
    let state: HoverState

    /// The room the window gives the view: a rectangle of 300 by 200 points with 60 points around it.
    static let windowSize = CGSize(width: 420, height: 320)

    /// A point over the rectangle, in the coordinates of the window with the origin at its bottom left.
    static let centre = CGPoint(x: 210, y: 160)

    /// A point in the corner of the window, outside the rectangle.
    static let corner = CGPoint(x: 4, y: 4)

    var body: some View {
        Rectangle()
            .fill(Palette.accent)
            .frame(width: 300, height: 200)
            .onHover { state.isHovered = $0 }
            .padding(60)
    }
}

/// Puts `window` in the first corner of the screen where the real pointer is not over it, if the screen has such a
/// place. A window that is as large as the screen, or a pointer in the middle of it, leaves the window where it is.
@MainActor
private func moveAwayFromTheRealPointer(_ window: NSWindow) {
    guard let screen = NSScreen.screens.first?.visibleFrame else { return }
    let size = window.frame.size
    let pointer = NSEvent.mouseLocation
    let corners = [
        NSPoint(x: screen.minX, y: screen.minY), NSPoint(x: screen.maxX - size.width, y: screen.minY),
        NSPoint(x: screen.minX, y: screen.maxY - size.height),
        NSPoint(x: screen.maxX - size.width, y: screen.maxY - size.height),
    ]
    if let away = corners.first(where: { !NSRect(origin: $0, size: size).contains(pointer) }) {
        window.setFrameOrigin(away)
    }
}
