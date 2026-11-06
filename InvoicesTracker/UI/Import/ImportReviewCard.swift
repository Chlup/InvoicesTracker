import SwiftUI

/// The card of the review before an import ("Před importem"): the collected files, each with what it holds and a button
/// that takes it out, what importing them would do per invoice, the failure when the files cannot be checked or the
/// import did not finish, and the buttons "Zrušit" and "Importovat". The files and the preview are the model's
/// (`ImportModel`); the card only shows them. It shows while files are collected.
struct ImportReviewCard: View {
    let model: ImportModel

    var body: some View {
        Card(spacing: 10, label: "Kontrola před importem") {
            header
            ForEach(model.files) { file in
                FileLine(file: file) {
                    Task { await model.removeFile(named: file.name) }
                }
            }
            ForEach(model.outcomeRows, id: \.label) { row in
                OutcomeLine(row: row)
            }
            if let failure = model.failure {
                SettingsFailureLine(text: failure)
            }
            buttons
        }
    }

    /// "Před importem" and how many files are collected.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CardTitle(text: "Před importem")
            Spacer(minLength: 8)
            Text(verbatim: ImportPreviewText.filesHeader(count: model.files.count))
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
        }
    }

    /// "Zrušit", which drops the files, and the button that imports them, which is offered only with something to
    /// import.
    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 8)
            Button("Zrušit") {
                model.cancel()
            }
            .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            .disabled(model.running)
            Button(model.importButtonTitle) {
                Task { await model.importCollected() }
            }
            .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
            .disabled(!model.canImport)
        }
    }
}

/// A collected file: its kind, its name, what it holds and its size (or why it cannot be used), and the button that
/// takes it out. It is a panel on the inset background.
private struct FileLine: View {
    let file: ImportFile

    /// Takes the file out of the import.
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ImportPreviewText.pill(of: file) + " · " + file.name)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: ImportPreviewText.fileDetail(of: file))
                    .font(Typography.callout)
                    .foregroundStyle(isFailed ? Palette.redText : Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Odebrat", action: remove)
                .buttonStyle(TextLinkButtonStyle())
                .accessibilityLabel("Odebrat \(file.name)")
        }
        .insetPanel(horizontal: 14, vertical: 10)
        .accessibilityElement(children: .contain)
    }

    private var isFailed: Bool {
        if case .failed = file.content {
            return true
        }
        return false
    }
}

/// A row of the preview: what will become of some invoices, how many, and their numbers.
private struct OutcomeLine: View {
    let row: ImportOutcomeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(row.label) \(row.count)")
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
            Text(verbatim: row.note)
                .font(Typography.callout)
                .foregroundStyle(row.tone == .overwrite ? Palette.orangeText : Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
