import SwiftUI

/// The card of the check before an import ("Před importem", which VoiceOver reads as "Kontrola před importem"): the
/// title with the count of the collected files on its right, a row for each file with its kind, its name, what it holds
/// or why it cannot be used, and the ✕ that takes it out; under them a row for each outcome of the import, what will
/// become of the invoices, with a dot in its colour, its count and the numbers in a note; the failure when the files
/// cannot be checked or the import did not finish; and the buttons "Zrušit" and the one that imports. The files and the
/// preview are the model's (`ImportModel`); the card only shows them. It shows while files are collected and no import
/// runs.
struct ImportReviewCard: View {
    let model: ImportModel

    var body: some View {
        Card(spacing: 14, label: "Kontrola před importem") {
            header
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.files) { file in
                    FileRow(file: file) {
                        Task { await model.removeFile(named: file.name) }
                    }
                }
            }
            if !model.outcomeRows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.outcomeRows, id: \.label) { row in
                        OutcomeRow(row: row)
                    }
                }
            }
            if let failure = model.failure {
                SettingsFailureLine(text: failure)
            }
            buttons
        }
    }

    /// "Před importem" and, on the right, how many files are collected: "3 soubory".
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CardTitle(text: "Před importem")
            Spacer(minLength: 8)
            Text(verbatim: ImportPreviewText.filesHeader(count: model.files.count))
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
        }
    }

    /// "Zrušit", which drops the files, and the button that imports them ("Importovat 4 faktury"), which is offered
    /// only with something to import: the small capsules of a card, at the right.
    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Zrušit") {
                model.cancel()
            }
            .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
            Button(model.importButtonTitle) {
                Task { await model.importCollected() }
            }
            .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
            .disabled(!model.canImport)
        }
    }
}

// MARK: - A file

/// A collected file, as a row on the inset background: a grey pill of its kind ("CSV", "ISDOC", or "?" for another
/// file), its name in semibold, what it holds and its size in the grey of captions, or why it cannot be used in the red
/// text, and the ✕ that takes it out, read as "Odebrat <name>". The name and what the file holds share a line where
/// they fit, and the second goes under the first where they do not.
private struct FileRow: View {
    let file: ImportFile

    /// Takes the file out of the import.
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Pill(ImportPreviewText.pill(of: file), tone: .neutral)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    name
                        .frame(maxWidth: .infinity, alignment: .leading)
                    detail
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    name
                        .fixedSize(horizontal: false, vertical: true)
                    detail
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            removeButton
        }
        // The prototype pads the row 12 points on the leading side and 6 on the trailing one, where the ✕ is.
        .padding(.leading, 6)
        .insetPanel(horizontal: 6, vertical: 6)
        .accessibilityElement(children: .contain)
    }

    /// The name of the file, which can be selected and copied.
    private var name: some View {
        Text(verbatim: file.name)
            .font(Typography.bodySemibold)
            .foregroundStyle(Palette.text)
            .textSelection(.enabled)
    }

    /// "12 faktur · 5,5 kB", "faktura 20260902 · 5,8 kB", or the error of a file that cannot be used.
    private var detail: some View {
        Text(verbatim: ImportPreviewText.fileDetail(of: file))
            .font(Typography.callout)
            .foregroundStyle(isFailed ? Palette.redText : Palette.text2)
    }

    /// The ✕ in the third grey, in a square of 28 points with no background of its own.
    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .frame(width: DesignMetrics.smallControlHeight, height: DesignMetrics.smallControlHeight)
                .contentShape([.interaction, .focusEffect], Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Odebrat \(file.name)"))
    }

    /// Whether the file cannot be used.
    private var isFailed: Bool {
        if case .failed = file.content {
            return true
        }
        return false
    }
}

// MARK: - An outcome

/// A row of the outcome under a hairline: a dot of 8 points in its colour (green for what is added, orange for what is
/// overwritten, the faintest grey otherwise), the label in semibold, the count in semibold figures of one width on the
/// right, and under them the note with the numbers, 16 points in, in the orange text for what is overwritten and the
/// third grey otherwise.
private struct OutcomeRow: View {
    let row: ImportOutcomeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(verbatim: row.label)
                            .font(Typography.bodySemibold)
                            .foregroundStyle(Palette.text)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: CzechFormat.grouped(Int64(row.count)))
                        .font(Typography.bodySemibold)
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
                Text(verbatim: row.note)
                    .font(Typography.callout)
                    .foregroundStyle(row.tone == .overwrite ? Palette.orangeText : Palette.text3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
            }
            .padding(.vertical, 8)
        }
    }

    /// The colour of the dot: green for what is added, orange for what is overwritten, the faintest grey otherwise.
    private var dotColor: Color {
        switch row.tone {
        case .new: Palette.green
        case .overwrite: Palette.orange
        case .neutral: Palette.text4
        }
    }
}
