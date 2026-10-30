import AppKit
import Foundation
import PDFKit
import Testing
@testable import InvoicesTracker

/// The page that holds the recovery code for the print panel: one A4 page made in memory, with the title, the code in
/// groups, its label, what it is for and the warning; and the print panel, which the lock after inactivity cancels.
/// One print panel at a time.
@Suite(.serialized)
@MainActor
struct RecoveryCodePrinterTests {
    /// Whether the print that runs the panel on its own has returned.
    @MainActor
    private final class PanelRun {
        var returned = false
    }

    private let code = "K7QF-2MWX-HC4T-RWPA-R3DN-6YJE-Q5VB-TL2S"
    private let label = "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026"

    /// The text of the page with every no-break space and every line break read as an ordinary space.
    private func text(of document: PDFDocument) throws -> String {
        try #require(document.string).replacing("\u{00A0}", with: " ").replacing("\n", with: " ")
    }

    @Test func theCodeGoesOnOneA4Page() throws {
        let document = try RecoveryCodePrinter.document(code: code, label: label)

        #expect(document.pageCount == 1)
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 595.28) < 0.01)
        #expect(abs(box.height - 841.89) < 0.01)
    }

    /// The text is in the PDF as text, not as a picture, so reading it back is also what proves the page is not blank.
    @Test func thePageHasTheTitleTheCodeInGroupsTheLabelAndTheWarning() throws {
        let document = try RecoveryCodePrinter.document(code: code, label: label)

        let text = try text(of: document)

        #expect(text.contains("Kód pro obnovení dat InvoicesTracker"))
        for group in WelcomeTexts.codeGroups(code) {
            #expect(text.contains(group))
        }
        #expect(text.contains("Kód č. 1 z 17. 10. 2026"))
        #expect(text.contains("otevře data na jiném Macu"))
        #expect(text.contains("Kdo ztratí Mac i tento kód, data už neotevře"))
    }

    @Test func thePrintOperationShowsThePrintPanelWhichHasSaveAsPDFAndNamesTheJob() throws {
        let operation = try RecoveryCodePrinter.printOperation(code: code, label: label)

        #expect(operation.showsPrintPanel)
        #expect(operation.jobTitle == "Kód pro obnovení InvoicesTracker – kód č. 1 z 17. 10. 2026")
    }

    // MARK: The panel under the lock

    /// The print panel shown as a sheet of the window the person works in goes when the lock after inactivity cancels
    /// it, as its Zrušit makes it go, and nothing is printed. The person prints again after unlocking, and the panel
    /// opens as before.
    @Test func cancellingThePanelEndsTheSheetOfThePrintPanel() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 700, height: 500), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.orderFront(nil)
        defer {
            // A panel that is left is taken down, so that the window closes alone.
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
            window.close()
        }

        RecoveryCodePrinter.print(code: code, label: label, in: window)
        try await waitUntil { window.attachedSheet != nil }
        #expect(RecoveryCodePrinter.isPanelUp)
        // A panel of the system, which the lock cancels: no sheet that the lock has to cover.
        let panel = try #require(window.attachedSheet)
        #expect(!IdleLockSheets.isUncovered(panel, among: IdleLockSheets.guarded))

        RecoveryCodePrinter.cancelPanel()

        try await waitUntil { window.attachedSheet == nil }
        try await waitUntil { !RecoveryCodePrinter.isPanelUp }

        RecoveryCodePrinter.print(code: code, label: label, in: window)
        try await waitUntil { window.attachedSheet != nil }
        RecoveryCodePrinter.cancelPanel()
        try await waitUntil { window.attachedSheet == nil }
    }

    /// A print panel run on its own, where no window is there to carry it, is app-modal: the lock stops it as its
    /// Zrušit would, and nothing is printed. It is run from a callout of the run loop, as a click runs it: a modal loop
    /// run from a block of the main queue holds the rest of the main queue back, the test with it. The app-modal
    /// session keeps every other window from becoming the key one, so the test takes its turn among the tests that
    /// type into a window, which need theirs (`whileTypingAlone`).
    @Test func cancellingThePanelStopsAPrintPanelRunOnItsOwn() async throws {
        try await whileTypingAlone {
            try await stopAPrintPanelRunOnItsOwn()
        }
    }

    /// The test above, in its turn.
    private func stopAPrintPanelRunOnItsOwn() async throws {
        let run = PanelRun()
        let code = code
        let label = label
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated {
                RecoveryCodePrinter.print(code: code, label: label, in: nil)
                run.returned = true
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        try await waitUntil { NSApp.modalWindow != nil && RecoveryCodePrinter.isPanelUp }

        RecoveryCodePrinter.cancelPanel()

        try await waitUntil { run.returned }
        if !run.returned {
            // The panel is left: it is stopped, so that the other tests go on.
            NSApp.stopModal(withCode: .cancel)
            NSApp.postEvent(try wakeEvent(), atStart: true)
            try await waitUntil { run.returned }
        }
        #expect(NSApp.modalWindow == nil)
        #expect(!RecoveryCodePrinter.isPanelUp)
    }

    /// An event of the app's own that only wakes a modal loop that waits for one.
    private func wakeEvent() throws -> NSEvent {
        try #require(
            NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: 0, data1: 0, data2: 0))
    }
}
