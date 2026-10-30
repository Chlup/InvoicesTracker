import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The sidebar in the window of the app, made as the app makes it. Each screen of its list is shown by a click on its
/// row, and the row of the screen that is shown is the selected one: Faktury too, whose row carries the number of its
/// drafts, and Import, whose row carries the progress of an import that runs. Nastavení is a button below the list, not
/// a row of it.
@Suite(.serialized, .settlesBackups)
@MainActor
struct SidebarSelectionTests {
    /// The rows of the list from the top: the heading of the year with its five screens, then the heading "Evidence"
    /// with its two, then the heading "Nástroje" with Simulátor and Import.
    private static let rows: [Screen?] = [
        nil, .overview, .invoices, .advances, .computation, .prediction, nil, .clients, .templates, nil, .simulator,
        .importer,
    ]

    @Test func aClickOnTheRowOfAScreenShowsTheScreen() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let list = try await sidebarList(in: window)
                for (row, screen) in Self.rows.enumerated() {
                    guard let screen else { continue }
                    // Another screen first, so that the click has something to change.
                    f.app.screen = screen == .overview ? .computation : .overview
                    try await layOut(window)
                    // As a click on the row selects it.
                    list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    try await waitUntil(timeout: .seconds(2)) { f.app.screen == screen }
                    #expect(f.app.screen == screen, "the row of \(screen.title)")
                }
            }
        }
    }

    @Test func theRowOfTheScreenThatIsShownIsSelected() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let list = try await sidebarList(in: window)
                for (row, screen) in Self.rows.enumerated() {
                    guard let screen else { continue }
                    f.app.screen = screen
                    try await waitUntil(timeout: .seconds(2)) { list.selectedRow == row }
                    #expect(list.selectedRow == row, "the row of \(screen.title)")
                }
            }
        }
    }

    /// The row of Import carries the progress of an import that runs, and is chosen all the same: a badge put on a row
    /// after its tag hides the row from the list.
    @Test func theImportRowIsSelectableWhileAnImportRuns() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                let list = try await sidebarList(in: window)
                let row = try #require(Self.rows.firstIndex(of: .importer))
                f.app.importBadge = "0/27"
                // Another screen first, so that the click has something to change.
                f.app.screen = .overview
                try await layOut(window)
                // As a click on the row selects it.
                list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                try await waitUntil(timeout: .seconds(2)) { f.app.screen == .importer }
                #expect(f.app.screen == .importer)
            }
        }
    }

    /// The list of the sidebar in `window`, once it shows all its rows.
    private func sidebarList(in window: NSWindow) async throws -> NSOutlineView {
        try await waitUntil { outline(in: window)?.numberOfRows == Self.rows.count }
        return try #require(outline(in: window))
    }

    private func outline(in window: NSWindow) -> NSOutlineView? {
        guard let content = window.contentView else { return nil }
        return outlines(in: content).first
    }

    private func outlines(in view: NSView) -> [NSOutlineView] {
        if let outline = view as? NSOutlineView {
            return [outline]
        }
        return view.subviews.flatMap { outlines(in: $0) }
    }

    @Test func theLineUnderNastaveniNamesTheVersionAndTheBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "7"]
        #expect(SidebarView.versionText(info: info) == "Verze: 1.4.0 (7)")
        #expect(SidebarView.versionText(info: nil) == "Verze: ? (?)")
    }
}
