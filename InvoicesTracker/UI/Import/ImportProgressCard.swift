import SwiftUI

/// The card of the progress of an import: while it runs, how far it is; once it is done, a block for each file it
/// imported, the green box of the summary with Zobrazit faktury, the offer to fill in the supplier from the export, and
/// the lists of what is to check, kept and not added. The numbers are the model's (`ImportModel`); the card only shows
/// them.
struct ImportProgressCard: View {
    let model: ImportModel

    var body: some View {
        Card(spacing: 10, label: "Průběh importu") {
            header
            if let progress = model.progress {
                ProgressBlock(done: progress.done, total: progress.total)
            }
            if let summary = model.summary {
                ForEach(summary.files, id: \.self) { name in
                    FileRowView(name: name, parts: summary.files.count == 1 ? ImportText.countParts(of: summary) : [])
                }
                if let failure = model.failure {
                    SettingsFailureLine(text: failure)
                }
                SummaryBox(lines: model.summaryLines, showInvoices: model.showInvoices)
                if model.canFillSupplier {
                    supplierOffer(exported: summary.exportSupplier)
                }
                ForEach(model.summaryLists, id: \.title) { list in
                    ImportListView(list: list)
                }
            }
        }
    }

    /// "Průběh", and while the import runs that it goes on when another screen is shown.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CardTitle(text: "Průběh")
            Spacer(minLength: 8)
            if model.running {
                Text("Můžete přejít jinam, import poběží dál.")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// "Doplnit údaje dodavatele z exportu": the profile of the supplier is empty and the export has the details. It
    /// is an information note, whose button is a capsule of the colour of a card with its words in the blue of a link,
    /// as the button in a note is anywhere in the app.
    private func supplierOffer(exported: Supplier?) -> some View {
        let named = exported.map { Self.named($0) } ?? ""
        return Note(
            .info, icon: .info,
            text: "Export obsahuje údaje dodavatele\(named), váš profil dodavatele je ale prázdný. Z exportu ho"
                + " můžete doplnit a pak ho upravit v Nastavení › Moje údaje."
        ) {
            Button("Doplnit údaje dodavatele z exportu") {
                Task { await model.fillSupplierFromExport() }
            }
            .buttonStyle(CapsuleButtonStyle(.onWindowAccent, size: .small))
        }
    }

    /// " (Jana Vzorová)": the name of the supplier of the export, or nothing when it has none.
    private static func named(_ supplier: Supplier) -> String {
        let name = supplier.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "" : " (\(name))"
    }
}

// MARK: - Progress

/// How far the running import is: a bar over the invoices it stores and "Importuji 3 z 12…". Before the importer stores
/// the first invoice (it fetches the rates first) the bar moves without a count.
private struct ProgressBlock: View {
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(Palette.accent)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Palette.accent)
            }
            Text(verbatim: ImportPreviewText.progress(done: done, total: total))
                .font(Typography.calloutSemibold)
                .foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A file

/// A file the import imported: its name, a full green bar, and, for an import of one file, its counts in their colours.
/// It is a panel on the inset background.
private struct FileRowView: View {
    let name: String
    let parts: [ImportText.CountPart]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: name)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: 1.0)
                .tint(Palette.greenText)
                .accessibilityLabel("Průběh importu \(name)")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    status
                    counts
                }
                VStack(alignment: .leading, spacing: 4) {
                    status
                    HStack(spacing: 12) {
                        counts
                    }
                }
            }
            .font(Typography.callout)
        }
        .insetPanel(horizontal: 14, vertical: 12)
        .accessibilityElement(children: .contain)
    }

    private var status: some View {
        Text("Hotovo")
            .font(Typography.calloutSemibold)
            .foregroundStyle(Palette.text)
    }

    @ViewBuilder
    private var counts: some View {
        ForEach(parts, id: \.text) { part in
            Text(verbatim: part.text)
                .foregroundStyle(color(of: part.tone))
        }
    }

    /// The colour of a count: what was added in the green text, what was updated in the blue of a link, what stayed
    /// as it was in the grey text, and what was skipped, or is held for review, in the orange text.
    private func color(of tone: ImportText.CountPart.Tone) -> Color {
        switch tone {
        case .added: Palette.greenText
        case .updated: Palette.accentText
        case .unchanged: Palette.text2
        case .skipped: Palette.orangeText
        }
    }
}

// MARK: - The summary

/// The green box of the summary: what the import did, and Zobrazit faktury. It is a panel on the green tint: the
/// headline in the green text, the line of the clients under it in the grey text, and the button a small capsule of
/// the accent.
private struct SummaryBox: View {
    let lines: [String]

    /// Zobrazit faktury.
    let showInvoices: () -> Void

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                text
                Spacer(minLength: 12)
                button
            }
            VStack(alignment: .leading, spacing: 10) {
                text
                button
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.greenTint, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        .accessibilityElement(children: .contain)
        // VoiceOver says what the import did when its summary appears, or once the app is unlocked when the import
        // ended under the lock after inactivity.
        .onAppear { VoiceOverAnnouncement.post(lines.joined(separator: " "), by: app) }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line)
                    .font(index == 0 ? Typography.bodySemibold : Typography.body)
                    .foregroundStyle(index == 0 ? Palette.greenText : Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var button: some View {
        Button("Zobrazit faktury", action: showInvoices)
            .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
    }
}

/// A list of the summary: its title, what it means and the line of each item, which can be selected and copied. It is a
/// panel on the inset background.
private struct ImportListView: View {
    let list: ImportList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: list.title)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: list.note)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    Text(verbatim: item)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .insetPanel(horizontal: 14, vertical: 12)
        .accessibilityElement(children: .contain)
    }
}
