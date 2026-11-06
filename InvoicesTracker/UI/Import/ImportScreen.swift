import SwiftUI
import UniformTypeIdentifiers

/// Import faktur: the choice of the CSV exports and the ISDOC invoices of Fakturoid to import — dropped on the zone
/// or chosen in the panel, files or folders, several at once — then, while files are collected, the check of what
/// importing them would do ("Před importem"), and while an import runs and once it is done its progress with what it
/// did. The import runs while other screens are shown; the model is the app's (`AppModel.importModel`), so the
/// collected files, the progress and the summary are there when the screen is shown again. The title and the line
/// under it are the shell's.
///
/// The page fills the room the window gives it and asks for no minimum size of its own: it scrolls.
struct ImportScreen: View {
    let app: AppModel

    /// What the panel offers: the CSV exports, the ISDOC invoices in their own files and in XML files, and folders,
    /// which stand for the files of these kinds in them (`ImportFile.read(_:)`).
    static let acceptedTypes: [UTType] = [.commaSeparatedText, .isdoc, .xml, .folder]

    /// Whether the panel that chooses the files is open.
    @State private var showsPicker = false

    var body: some View {
        let model = app.importModel
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
                ChooseFilesCard(model: model, showPicker: { showsPicker = true }, add: { add($0, to: model) })
                // The files are the import's while it runs: the check before it is not shown meanwhile.
                if !model.files.isEmpty && !model.running {
                    ImportReviewCard(model: model)
                }
                if model.running || model.summary != nil {
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
            isPresented: $showsPicker, allowedContentTypes: Self.acceptedTypes, allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                add(urls, to: model)
            case .failure(let error):
                // A panel that was dismissed is not a failure.
                guard (error as? CocoaError)?.code != .userCancelled else { return }
                AppModel.log("Choosing the files to import", failedWith: error)
            }
        }
    }

    /// Adds `urls` to the collected files, in a task of its own.
    private func add(_ urls: [URL], to model: ImportModel) {
        Task { await model.addFiles(urls) }
    }
}

extension UTType {
    /// An ISDOC invoice in a file of its own, `.isdoc`: XML that the system does not know, which the app declares in
    /// its Info.plist (`UTImportedTypeDeclarations`) under an identifier of its own.
    nonisolated static let isdoc = UTType(importedAs: "info.chlup.InvoicesTracker.isdoc", conformingTo: .xml)
}

// MARK: - Výběr souborů

/// The card of the choice of files: the zone to drop them on, the note that asks for both exports, the note that the
/// import overwrites the invoices the app has, the hint of what the import does with the files, and, while no file is
/// collected and no result is shown, the line of the last import. A failure of an import that has no file to show
/// (another step of the vault is running, the data is locked) is said here.
private struct ChooseFilesCard: View {
    let model: ImportModel

    /// Opens the panel.
    let showPicker: () -> Void

    /// Adds the files that were dropped.
    let add: ([URL]) -> Void

    @State private var isDropTarget = false

    var body: some View {
        Card(spacing: 14, label: "Výběr souborů") {
            dropZone
            Note(
                .info, icon: .info, title: "Pro úplné faktury naimportujte oba exporty – CSV i ISDOC",
                text: "Každý soubor se naimportuje samostatně a převezme se z něj jen to, co obsahuje. Faktura z"
                    + " jediného formátu bude neúplná, dokud nenaimportujete i ten druhý.")
            Note(
                .attention, icon: .exclamation, title: "Import přepíše faktury, které už v aplikaci máte",
                text: "Data ze souborů nahradí to, co jste u nich v aplikaci změnili. Tyto změny se ztratí a vrátit je"
                    + " nepůjde.")
            Text(
                "Faktury se spárují podle čísla: nové se přidají, zálohové a stornované se přeskočí. Soubory se čtou"
                    + " jen v tomto počítači."
            )
            .font(Typography.callout)
            .foregroundStyle(Palette.text2)
            .fixedSize(horizontal: false, vertical: true)
            if model.files.isEmpty && model.summary == nil && !model.running {
                if let failure = model.failure {
                    SettingsFailureLine(text: failure)
                }
                if let line = model.lastImportLine {
                    Text(verbatim: line)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Přetáhněte sem soubory CSV nebo ISDOC, nebo klikněte a vyberte je": a button that opens the panel, which files
    /// and folders can also be dropped on. It is the zone of the design (`DropZoneLook`), and keeps the pill "Vybrat
    /// soubory…" that says what a click does. A dropped file of another kind is taken too: the check lists it with
    /// the pill "?" and says that it is neither CSV nor ISDOC, as the prototype does.
    private var dropZone: some View {
        Button(action: showPicker) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(Typography.symbolLight)
                    .imageScale(.large)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text("Přetáhněte sem soubory CSV nebo ISDOC, nebo klikněte a vyberte je")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                Text("Exporty faktur z Fakturoidu · lze vybrat víc souborů najednou")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                pill
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 34)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .modifier(DropZoneLook(isTargeted: isDropTarget))
        }
        .buttonStyle(.plain)
        .disabled(model.running)
        .dropDestination(for: URL.self) { urls, _ in
            // Only files and folders: a link dragged from a browser is no export. Nothing is taken while an import
            // runs.
            let files = urls.filter(\.isFileURL)
            guard !model.running, !files.isEmpty else { return false }
            add(files)
            return true
        } isTargeted: {
            isDropTarget = $0
        }
    }

    /// "Vybrat soubory…": the words of what a click on the zone does, drawn as a small capsule in the colour of a
    /// card, raised off the zone, as the buttons that stand on a tint are. It is no button of its own: the zone is.
    private var pill: some View {
        Text("Vybrat soubory…")
            .font(Typography.bodySemibold)
            .foregroundStyle(CapsuleButtonKind.onWindow.foreground)
            .padding(.horizontal, CapsuleButtonSize.small.horizontalPadding)
            .frame(height: CapsuleButtonSize.small.height)
            .background {
                Capsule().surface(CapsuleButtonKind.onWindow.background, elevation: .control)
            }
            .padding(.top, 4)
    }
}
