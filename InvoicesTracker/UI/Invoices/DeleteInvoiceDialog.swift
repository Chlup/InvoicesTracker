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
/// that title: what deleting the invoice does, the warning that it cannot be undone, and the field where the number of
/// the invoice is typed, which has the focus when the dialog opens. The red "Smazat natrvalo" is enabled only once the
/// number (or its digits) is typed. Esc is Zrušit, as it is in every dialog of the window.
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
    @FocusState private var numberFocused: Bool

    /// What the dialog says when nothing was deleted: the number typed is not the invoice's, or the invoice is not
    /// there any more.
    nonisolated static let refusedText = "Fakturu se nepodařilo smazat – číslo nesouhlasí nebo faktura už neexistuje."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.title)
                    .font(.system(size: 17, weight: .bold))
                Text(verbatim: summary.subtitle)
                    .foregroundStyle(.secondary)
            }
            warning
            VStack(alignment: .leading, spacing: 6) {
                Text("Pro potvrzení napište číslo faktury \(Text(verbatim: summary.number).fontWeight(.semibold))")
                TextField("Číslo faktury", text: $typed)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .autocorrectionDisabled()
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.red, lineWidth: matches ? 1.5 : 0)
                    )
                    .focused($numberFocused)
                    .onSubmit(confirm)
            }
            if let failure {
                Text(verbatim: failure)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Zrušit", action: cancel)
                    .buttonStyle(.bordered)
                Button("Smazat natrvalo", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!matches || isDeleting)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .onAppear {
            numberFocused = true
        }
    }

    /// Whether the text typed is the number of the invoice, or the digits of it.
    private var matches: Bool {
        DeleteConfirmation.matches(typed: typed, number: summary.number)
    }

    /// "Smazání nejde vrátit zpět." and the consequences, in a red box.
    private var warning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Smazání nejde vrátit zpět.")
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
                ForEach(Array(summary.lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
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
