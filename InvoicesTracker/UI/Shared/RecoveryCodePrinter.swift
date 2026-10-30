import AppKit
import PDFKit
import SwiftUI

/// Why the page of the recovery code could not be made, or could not be handed to the print panel. The log keeps the
/// number of the case, which says which step failed.
nonisolated enum RecoveryCodePrinterError: Error {
    /// The memory the page is drawn into could not be made.
    case noDataConsumer

    /// The PDF context the page is drawn in could not be made.
    case noPDFContext

    /// What was drawn is no PDF of a page.
    case noPage

    /// The page is there, and the print operation for it could not be made.
    case noPrintOperation
}

/// Prints the recovery code, or saves it as a PDF: the page is made in memory and handed to the standard print panel,
/// which has "Uložit jako PDF" among its choices. The app writes nothing to disk; what the person saves from the panel
/// is theirs to keep. The panel shows the code, so the lock after inactivity cancels it (`cancelPanel()`).
@MainActor
enum RecoveryCodePrinter {
    /// The print operation whose panel is up as a sheet of `panelWindow`, until it has run.
    private static weak var panelOperation: NSPrintOperation?
    private static weak var panelWindow: NSWindow?

    /// Whether the panel is up on its own, app-modally: until `run()` returns.
    private static var runsAppModally = false

    /// What the operation shown as a sheet tells once it has run, however it ended.
    private static let panelEnd = PanelEnd()

    /// Opens the print panel with the page of the code `code`, whose label is `label`, such as
    /// "kód č. 1 z 17. 10. 2026": as a sheet of `window`, the window the person works in, or on its own, app-modally,
    /// when there is none. Prints nothing by itself. A page that cannot be made is logged (the domain and the code of
    /// the error alone) and the panel does not open.
    static func print(code: String, label: String, in window: NSWindow? = NSApp.keyWindow) {
        let operation: NSPrintOperation
        do {
            operation = try printOperation(code: code, label: label)
        } catch {
            AppModel.log("Making the page of the recovery code", failedWith: error)
            return
        }
        if let window {
            panelOperation = operation
            panelWindow = window
            operation.runModal(
                for: window, delegate: panelEnd,
                didRun: #selector(PanelEnd.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            runsAppModally = true
            defer { runsAppModally = false }
            operation.run()
        }
    }

    /// Whether the print panel is up, as a sheet of a window or on its own.
    static var isPanelUp: Bool {
        panelOperation != nil || runsAppModally
    }

    /// Cancels the print panel that is up, as its Zrušit does: nothing is printed or saved, and the panel goes. The
    /// lock after inactivity calls it (`AppModel.cancelPrintPanel`); the person prints again once the app is unlocked.
    /// Does nothing while no panel is up.
    static func cancelPanel() {
        if panelOperation != nil, let window = panelWindow, let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .cancel)
        }
        if runsAppModally, NSApp.modalWindow != nil {
            NSApp.stopModal(withCode: .cancel)
            // The modal loop of the panel looks at the stop only once it has an event to handle: this one wakes it.
            let wake = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, subtype: 0, data1: 0, data2: 0)
            if let wake {
                NSApp.postEvent(wake, atStart: true)
            }
        }
    }

    /// Forgets the panel of `operation`, which has run.
    fileprivate static func operationDidRun(_ operation: NSPrintOperation) {
        guard operation === panelOperation else { return }
        panelOperation = nil
        panelWindow = nil
    }

    /// The print operation of the page, which shows the print panel. Its job title is what "Uložit jako PDF" proposes
    /// as the name of the file. Throws `RecoveryCodePrinterError` when the page cannot be made.
    static func printOperation(code: String, label: String) throws -> NSPrintOperation {
        let document = try Self.document(code: code, label: label)
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        guard let operation = document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true)
        else {
            throw RecoveryCodePrinterError.noPrintOperation
        }
        operation.jobTitle = "Kód pro obnovení InvoicesTracker – " + label.replacing("\u{00A0}", with: " ")
        operation.showsPrintPanel = true
        return operation
    }

    /// The page as a PDF, made in memory: one A4 page of text, so that the printout is sharp. Throws
    /// `RecoveryCodePrinterError` when it cannot be made.
    static func document(code: String, label: String) throws -> PDFDocument {
        let renderer = ImageRenderer(content: RecoveryCodePage(code: code, label: label))
        renderer.proposedSize = ProposedViewSize(PageSize.a4)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw RecoveryCodePrinterError.noDataConsumer
        }
        var mediaBox = CGRect(origin: .zero, size: PageSize.a4)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RecoveryCodePrinterError.noPDFContext
        }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        guard let document = PDFDocument(data: data as Data) else {
            throw RecoveryCodePrinterError.noPage
        }
        return document
    }
}

/// What a print operation shown as a sheet tells when it has run: the printer forgets its panel then.
private final class PanelEnd: NSObject {
    @objc func printOperationDidRun(
        _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        RecoveryCodePrinter.operationDidRun(operation)
    }
}

/// The page: the title, the label of the code, the code in large monospace groups, what it is for and the warning. It
/// is black on white whatever the appearance of the app is, because it is for paper.
private struct RecoveryCodePage: View {
    let code: String
    let label: String

    private var capitalisedLabel: String {
        label.prefix(1).uppercased() + label.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kód pro obnovení dat InvoicesTracker")
                    .font(.system(size: 26, weight: .bold))
                Text(capitalisedLabel)
                    .font(.system(size: 16, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 10) {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, group in
                                Text(group)
                                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                                    .tracking(2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 1))
                            }
                        }
                    }
                }
                Text("32 znaků · velikost písmen, mezery a pomlčky nehrají roli")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.3))
            }
            Text(
                """
                Data InvoicesTracker se na Macu, na kterém vznikla, odemykají přes Secure Enclave. Tento kód je jediný \
                další klíč: otevře data na jiném Macu, po opravě Macu nebo ze zálohy.
                """
            )
            .font(.system(size: 13))
            Text(
                """
                Kód nikam neposíláme a aplikace si ho nepamatuje. Kdo ztratí Mac i tento kód, data už neotevře – ani \
                autor aplikace. Tento list schovejte mimo počítač.
                """
            )
            .font(.system(size: 13, weight: .semibold))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 2))
        }
        .padding(.horizontal, 56)
        .padding(.top, 72)
        .frame(width: PageSize.a4.width, height: PageSize.a4.height, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    /// The groups in rows of four.
    private var rows: [[String]] {
        let groups = WelcomeTexts.codeGroups(code)
        return stride(from: 0, to: groups.count, by: 4).map { Array(groups[$0..<min($0 + 4, groups.count)]) }
    }
}
