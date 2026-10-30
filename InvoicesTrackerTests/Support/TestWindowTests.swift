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
