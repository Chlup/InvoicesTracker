import SwiftUI
import UniformTypeIdentifiers

/// Import faktur: the choice of the CSV exports of Fakturoid to import — dropped on the zone or chosen in the panel,
/// one file or several — and under it the card of the progress with the files, the summary and what the import leaves
/// to the person. The import runs while other screens are shown; the model is the app's (`AppModel.importModel`), so
/// the progress and the summary are there when the screen is shown again. The title and the line under it are the
/// shell's.
///
/// The page fills the room the window gives it and asks for no minimum size of its own: it scrolls.
struct ImportScreen: View {
    let app: AppModel

    /// Whether the panel that chooses the files is open.
    @State private var showsPicker = false

    var body: some View {
        let model = app.importModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ChooseFilesCard(model: model, showPicker: { showsPicker = true }, start: { start($0, in: model) })
                if !model.fileRows.isEmpty {
                    ImportProgressCard(model: model)
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pagePadding()
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .fileImporter(
            isPresented: $showsPicker, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                start(urls, in: model)
            case .failure(let error):
                // A panel that was dismissed is not a failure.
                guard (error as? CocoaError)?.code != .userCancelled else { return }
                AppModel.log("Choosing the files to import", failedWith: error)
            }
        }
    }

    /// Imports `urls`, in a task of its own: the import goes on when the screen is left.
    private func start(_ urls: [URL], in model: ImportModel) {
        Task { await model.importFiles(urls) }
    }
}

// MARK: - Výběr souborů

/// The card of the choice of files: the zone to drop them on, what the import does with them, and, while no file is
/// shown, the line of the last import. A failure of an import that has no file to show (another step of the vault is
/// running, the data is locked) is said here.
private struct ChooseFilesCard: View {
    let model: ImportModel

    /// Opens the panel.
    let showPicker: () -> Void

    /// Imports the files that were dropped.
    let start: ([URL]) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            dropZone
            Text(
                "Faktury se spárují podle čísla: nové se přidají, změněné se aktualizují, zálohové a stornované se"
                    + " přeskočí. Soubory se čtou jen v tomto počítači."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if model.fileRows.isEmpty {
                if let failure = model.failure {
                    SettingsFailureLine(text: failure)
                }
                if let line = model.lastImportLine {
                    Text(verbatim: line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Výběr souborů")
    }

    /// "Přetáhněte CSV sem nebo klikněte a vyberte soubory": a button that opens the panel, which files can also be
    /// dropped on.
    private var dropZone: some View {
        Button(action: showPicker) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Přetáhněte CSV sem nebo klikněte a vyberte soubory")
                    .fontWeight(.semibold)
                Text("Export faktur z Fakturoidu · lze vybrat víc souborů najednou")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Vybrat soubory…")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 26)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(isDropTarget ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.8 : 0.35), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(model.running)
        .dropDestination(for: URL.self) { urls, _ in
            // Only files: a link dragged from a browser is no export. Nothing is taken while an import runs.
            let files = urls.filter(\.isFileURL)
            guard !model.running, !files.isEmpty else { return false }
            start(files)
            return true
        } isTargeted: {
            isDropTarget = $0
        }
    }
}
