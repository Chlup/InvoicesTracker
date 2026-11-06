import SwiftUI

/// The card of the progress of an import ("Průběh", which VoiceOver reads as "Průběh importu"). While the import runs:
/// that it goes on when another screen is shown, a bar of 6 points in the accent over the invoices it stores, and
/// "Importuji 3 z 12…". Once it is done: the bar full in the green text, the green panel with what the import did and
/// Zobrazit faktury, under it the line of the clients and the offer to fill in the supplier from the export, and then
/// each list of what was overwritten, is to check, was not added or has a notice. The numbers are the model's
/// (`ImportModel`); the card only shows them.
struct ImportProgressCard: View {
    let model: ImportModel

    var body: some View {
        Card(spacing: 10, label: "Průběh importu") {
            header
            ProgressBar(fraction: fraction, isDone: !model.running)
            if model.running, let progress = model.progress {
                Text(verbatim: ImportPreviewText.progress(done: progress.done, total: progress.total))
                    .font(Typography.calloutSemibold)
                    .foregroundStyle(Palette.text)
            }
            if !model.running, let summary = model.summary {
                SummaryPanel(
                    headline: ImportText.headline(of: summary),
                    announcement: model.summaryLines.joined(separator: " "), showInvoices: model.showInvoices)
                Text(verbatim: ImportText.clientsLine(of: summary))
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure = model.failure {
                    SettingsFailureLine(text: failure)
                }
                if model.canFillSupplier {
                    supplierOffer(exported: summary.exportSupplier)
                }
                ForEach(model.summaryLists, id: \.title) { list in
                    ImportListView(list: list)
                }
            }
        }
    }

    /// How much of the bar is filled: the share of the invoices stored while the import runs, and all of it once it is
    /// done.
    private var fraction: Double {
        guard model.running else { return 1 }
        guard let progress = model.progress, progress.total > 0 else { return 0 }
        return min(1, Double(progress.done) / Double(progress.total))
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

// MARK: - The bar

/// The bar of the progress: 6 points tall on the grey fill, with the corners of half its height, filled from the left
/// by `fraction` in the accent while the import runs and in the green text once it is done. VoiceOver reads it as a
/// progress indicator named "Průběh importu".
private struct ProgressBar: View {
    /// How much of the bar is filled, from 0 to 1.
    let fraction: Double

    /// Whether the import is done.
    let isDone: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        shape
            .fill(Palette.fill)
            .frame(maxWidth: .infinity)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(isDone ? Palette.greenText : Palette.accent)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(shape)
            .animation(.linear(duration: 0.12), value: fraction)
            .accessibilityRepresentation {
                ProgressView(value: fraction)
            }
            .accessibilityLabel("Průběh importu")
    }
}

// MARK: - The summary

/// The green panel of the summary: what the import did in the green text, and Zobrazit faktury as the small capsule of
/// the accent on its right, or under it where the two do not fit on one line. VoiceOver says the lines of the summary
/// when it appears, or once the app is unlocked when the import ended under the lock after inactivity.
private struct SummaryPanel: View {
    /// "Hotovo – nové 11, přepsané 0, beze změny 0, přeskočené 2."
    let headline: String

    /// What VoiceOver says when the panel appears: the headline and the line of the clients.
    let announcement: String

    /// Zobrazit faktury.
    let showInvoices: () -> Void

    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                text
                Spacer(minLength: 10)
                button
            }
            VStack(alignment: .leading, spacing: 10) {
                text
                    .fixedSize(horizontal: false, vertical: true)
                button
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.greenTint, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        .accessibilityElement(children: .contain)
        .onAppear { VoiceOverAnnouncement.post(announcement, by: app) }
    }

    private var text: some View {
        Text(verbatim: headline)
            .font(Typography.bodySemibold)
            .foregroundStyle(Palette.greenText)
    }

    private var button: some View {
        Button("Zobrazit faktury", action: showInvoices)
            .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
    }
}

/// A list of the summary on the inset background: its title in semibold, what it means in the grey of captions, and
/// the line of each item in figures of one width, which can be selected and copied.
private struct ImportListView: View {
    let list: ImportList

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: list.title)
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
            Text(verbatim: list.note)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
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
