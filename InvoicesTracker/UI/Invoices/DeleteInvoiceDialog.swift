import SwiftUI

/// An invoice whose deletion the window asks to confirm (`AppModel.invoiceDeletion`): what the dialog says, and what
/// deletes the invoice.
struct InvoiceDeletionRequest: Identifiable {
    let invoiceID: Int64
    let summary: InvoiceDeletionSummary

    /// Deletes the invoice if the text is its number: true when it was deleted. Throws what the database throws.
    let delete: (String) async throws -> Bool

    var id: Int64 {
        invoiceID
    }
}

/// The dialog "Smazat fakturu …?" inside the window (`windowDialog(item:title:content:)`), which VoiceOver names by
/// that title: what deleting the invoice does, in the red note of an error with the triangle of a warning, and the
/// field where the number of the invoice is typed, which has the focus when the dialog opens. The red "Smazat
/// natrvalo" is enabled only once the number (or its digits) is typed. Esc is Zrušit, as it is in every dialog of the
/// window.
struct DeleteInvoiceDialog: View {
    let summary: InvoiceDeletionSummary

    /// Deletes the invoice if the text is its number: true when it was deleted. Throws what the database throws.
    let delete: (String) async throws -> Bool

    /// Zrušit.
    let cancel: () -> Void

    /// The invoice was deleted.
    let deleted: () -> Void

    @State private var typed = ""
    @State private var failure: String?
    @State private var isDeleting = false

    /// What the dialog says when nothing was deleted: the number typed is not the invoice's, or the invoice is not
    /// there any more.
    nonisolated static let refusedText = "Fakturu se nepodařilo smazat – číslo nesouhlasí nebo faktura už neexistuje."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: summary.title, subtitle: summary.subtitle, isHeading: false)
            Note(.error, icon: .warning, title: "Smazání nejde vrátit zpět.", paragraphs: summary.lines)
            NumberConfirmationField(number: summary.number, typed: $typed, matches: matches, submit: confirm)
            if let failure {
                Text(verbatim: failure)
                    .font(Typography.body)
                    .foregroundStyle(Palette.redText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Zrušit", action: cancel)
                    .buttonStyle(CapsuleButtonStyle(.secondary))
                Button("Smazat natrvalo", action: confirm)
                    .buttonStyle(CapsuleButtonStyle(.destructiveConfirm))
                    .disabled(!matches || isDeleting)
            }
            .padding(.top, 4)
        }
    }

    /// Whether the text typed is the number of the invoice, or the digits of it.
    private var matches: Bool {
        DeleteConfirmation.matches(typed: typed, number: summary.number)
    }

    private func confirm() {
        guard matches, !isDeleting else { return }
        failure = nil
        isDeleting = true
        Task {
            do {
                if try await delete(typed) {
                    deleted()
                } else {
                    failure = Self.refusedText
                }
            } catch {
                AppModel.log("Deleting an invoice", failedWith: error)
                failure = "Fakturu se nepodařilo smazat."
            }
            isDeleting = false
        }
    }
}
