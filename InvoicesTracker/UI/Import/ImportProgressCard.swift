import SwiftUI

/// The card of the progress of an import: a block for each file with its bar and where it is, then the failure that
/// stopped the import, or the green box of the summary with Zobrazit faktury, the offer to fill in the supplier from
/// the export, and the lists of what is to check, kept and not added. The numbers are the model's (`ImportModel`); the
/// card only shows them.
struct ImportProgressCard: View {
    let model: ImportModel

    var body: some View {
        Card(spacing: 10, label: "Průběh importu") {
            header
            ForEach(model.fileRows) { row in
                FileRowView(row: row, status: model.statusText(of: row), parts: parts(of: row), running: model.running)
            }
            if let failure = model.failure {
                SettingsFailureLine(text: failure)
            }
            if let summary = model.summary {
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

    /// The counts of the file, for an import of one file, whose counts are the file's.
    private func parts(of row: ImportModel.FileRow) -> [ImportText.CountPart] {
        guard row.counts != nil, let summary = model.summary else { return [] }
        return ImportText.countParts(of: summary)
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

// MARK: - A file

/// A file of the import: its name and size, its bar, and where it is: waiting, read and going on, done, or why it
/// cannot be imported; and, for an import of one file, its counts in their colours. It is a panel on the inset
/// background.
private struct FileRowView: View {
    let row: ImportModel.FileRow
    let status: String
    let parts: [ImportText.CountPart]
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: row.name)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let size = row.size {
                    Text(verbatim: size)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                }
            }
            bar
                .accessibilityLabel("Průběh importu \(row.name)")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    statusText
                    counts
                }
                VStack(alignment: .leading, spacing: 4) {
                    statusText
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

    /// The bar: empty while the file waits, moving while the import goes on with it, full and green once it is done,
    /// and full and red when it cannot be imported. It is the accent while it waits or moves, as the prototype draws
    /// it.
    @ViewBuilder
    private var bar: some View {
        switch row.stage {
        case .waiting:
            ProgressView(value: 0.0)
                .tint(Palette.accent)
        case .read where running:
            // Moving: the rest of the import has no steps to count.
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Palette.accent)
        case .read:
            ProgressView(value: 1.0)
                .tint(Palette.accent)
        case .done:
            ProgressView(value: 1.0)
                .tint(Palette.greenText)
        case .failed:
            ProgressView(value: 1.0)
                .tint(Palette.redText)
        }
    }

    private var statusText: some View {
        Text(verbatim: status)
            .font(Typography.calloutSemibold)
            .foregroundStyle(isFailed ? Palette.redText : Palette.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isFailed: Bool {
        if case .failed = row.stage {
            return true
        }
        return false
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
        case .skipped, .review: Palette.orangeText
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
