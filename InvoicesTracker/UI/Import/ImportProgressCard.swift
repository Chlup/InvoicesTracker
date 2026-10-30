import SwiftUI

/// The card of the progress of an import: a block for each file with its bar and where it is, then the failure that
/// stopped the import, or the green box of the summary with Zobrazit faktury, the offer to fill in the supplier from
/// the export, and the lists of what is to check, kept and not added. The numbers are the model's (`ImportModel`); the
/// card only shows them.
struct ImportProgressCard: View {
    let model: ImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Průběh importu")
    }

    /// "Průběh", and while the import runs that it goes on when another screen is shown.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Průběh")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if model.running {
                Text("Můžete přejít jinam, import poběží dál.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// The counts of the file, for an import of one file, whose counts are the file's.
    private func parts(of row: ImportModel.FileRow) -> [ImportText.CountPart] {
        guard row.counts != nil, let summary = model.summary else { return [] }
        return ImportText.countParts(of: summary)
    }

    /// "Doplnit údaje dodavatele z exportu": the profile of the supplier is empty and the export has the details.
    private func supplierOffer(exported: Supplier?) -> some View {
        let named = exported.map { Self.named($0) } ?? ""
        return SettingsBox(kind: .hint) {
            Text(
                verbatim: "Export obsahuje údaje dodavatele\(named), váš profil dodavatele je ale prázdný. Z exportu ho"
                    + " můžete doplnit a pak ho upravit v Nastavení › Moje údaje."
            )
            .font(.callout)
            Button("Doplnit údaje dodavatele z exportu") {
                Task { await model.fillSupplierFromExport() }
            }
            .settingsCardButton()
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
/// cannot be imported; and, for an import of one file, its counts in their colours.
private struct FileRowView: View {
    let row: ImportModel.FileRow
    let status: String
    let parts: [ImportText.CountPart]
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: row.name)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let size = row.size {
                    Text(verbatim: size)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    /// The bar: empty while the file waits, moving while the import goes on with it, full and green once it is done,
    /// and full and red when it cannot be imported.
    @ViewBuilder
    private var bar: some View {
        switch row.stage {
        case .waiting:
            ProgressView(value: 0.0)
        case .read where running:
            // Moving: the rest of the import has no steps to count.
            ProgressView()
                .progressViewStyle(.linear)
        case .read:
            ProgressView(value: 1.0)
        case .done:
            ProgressView(value: 1.0)
                .tint(.green)
        case .failed:
            ProgressView(value: 1.0)
                .tint(.red)
        }
    }

    private var statusText: some View {
        Text(verbatim: status)
            .fontWeight(.semibold)
            .foregroundStyle(isFailed ? Color.red : Color.primary)
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

    private func color(of tone: ImportText.CountPart.Tone) -> Color {
        switch tone {
        case .added: Color(.bannerText)
        case .updated: Color.blue
        case .unchanged: Color.secondary
        case .skipped: Color(.simulationText)
        case .review: Color.orange
        }
    }
}

// MARK: - The summary

/// The green box of the summary: what the import did, and Zobrazit faktury.
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        // VoiceOver says what the import did when its summary appears, or once the app is unlocked when the import
        // ended under the lock after inactivity.
        .onAppear { VoiceOverAnnouncement.post(lines.joined(separator: " "), by: app) }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(verbatim: line)
                    .fontWeight(index == 0 ? .semibold : .regular)
                    .foregroundStyle(index == 0 ? Color(.bannerText) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var button: some View {
        Button("Zobrazit faktury", action: showInvoices)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
    }
}

/// A list of the summary: its title, what it means and the line of each item, which can be selected and copied.
private struct ImportListView: View {
    let list: ImportList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: list.title)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: list.note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    Text(verbatim: item)
                        .font(.callout)
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
