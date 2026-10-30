import SwiftUI

/// The sheet that asks the person to confirm the uniform rates the refresh found for a finished year: what was found,
/// where it was read, what the table has more and less than the one of the year before, and Použít, Zadat ručně and
/// Později. Nothing is stored before Použít, which has to be clicked: no button of the sheet is the default one, as the
/// sheet comes up by itself over whatever the person is doing, and a stray Return must not store a table that changes
/// the income of the year. Esc is Později. The words and the choices are the model's (`UniformRateConfirmModel`); the
/// sheet only shows them.
struct UniformRateConfirmSheet: View {
    @State private var model: UniformRateConfirmModel

    init(app: AppModel, finding: GFRFinding) {
        _model = State(initialValue: UniformRateConfirmModel(app: app, finding: finding))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sources
            if !model.differenceLines.isEmpty {
                differences
            }
            Text(
                "Kurz se uloží až po vašem potvrzení a platby roku \(String(model.finding.year)) se přepočtou, pokud"
                    + " rok počítá příjmy jednotným kurzem. Když rozhodnutí odložíte, kurz zůstane čekat."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let failure = model.failure {
                Text(verbatim: failure)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 560)
        .task {
            await model.load()
        }
    }

    // MARK: Parts

    /// The sentence of what was found, and how many currencies the table has.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: model.headline)
                    .font(.system(size: 17, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: model.tableNote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Where the table was read: the issue of the Finanční zpravodaj and its PDF.
    private var sources: some View {
        HStack(spacing: 14) {
            Text("Zdroj:")
                .foregroundStyle(.secondary)
            Link("Vydání Finančního zpravodaje", destination: model.finding.issueURL)
            Link("PDF s tabulkou", destination: model.finding.pdfURL)
        }
        .font(.callout)
    }

    /// The currencies the table lacks or has more than last year's: an orange warning for those that are gone, a blue
    /// note when there are only new ones.
    private var differences: some View {
        SettingsBox(kind: model.warnsOfMissingCurrencies ? .warning : .hint) {
            ForEach(model.differenceLines, id: \.self) { line in
                Text(verbatim: line)
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            if model.isSettled {
                // Nothing is left to choose, so there is a default to press: it only closes the sheet.
                Button("Zavřít", action: model.later)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Později", action: model.later)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Button("Zadat ručně", action: model.enterManually)
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
                Button("Použít") {
                    Task { await model.use() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}
