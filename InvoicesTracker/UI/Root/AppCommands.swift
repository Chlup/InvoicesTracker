import SwiftUI

/// The commands of the menu bar: Nová faktura (⌘N) and Importovat… open what the window offers once the data is open;
/// Hledat (⌘F) focuses the search field of Faktury while that screen is shown with no sheet over it; Exportovat
/// zálohu… and Obnovit ze zálohy… run on Nastavení › Zabezpečení a zálohy, where their result is said, and not while
/// another step of that tab runs. While the app is locked after inactivity, none of them can be chosen: the window
/// shows the lock alone.
struct AppCommands: Commands {
    /// The model of the app, or nil when there is none (the app hosts the tests, or the data folder cannot be made).
    let model: AppModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nová faktura") {
                model?.editorRequest = .chooser
            }
            .keyboardShortcut("n")
            .disabled(!offersTheApp)
        }
        CommandGroup(replacing: .importExport) {
            Button("Importovat…") {
                model?.screen = .importer
            }
            .disabled(!offersTheApp)
            Button("Exportovat zálohu…") {
                model?.request(.exportBackup)
            }
            .disabled(!offersTheBackups)
            Button("Obnovit ze zálohy…") {
                model?.request(.restoreBackup)
            }
            .disabled(!offersTheBackups)
        }
        // The Edit menu has no Find… of its own, and the search field of Faktury does not answer ⌘F by itself, so this
        // item is the only owner of ⌘F and nothing collides with it. It asks the app model rather than reading a
        // focused value of the screen, because a focused value is lost as soon as the table of Faktury takes the focus,
        // which is where ⌘F is pressed. On any other screen, while the editor is open and while a sheet is open, the
        // item is disabled.
        CommandGroup(after: .textEditing) {
            Button("Hledat") {
                model?.focusSearch()
            }
            .keyboardShortcut("f")
            .disabled(!offersSearch)
        }
    }

    /// Whether the window offers the app, for Nová faktura and Importovat…: the data are open, and neither the card
    /// after unlocking with the code nor the lock after inactivity is over it.
    var offersTheApp: Bool {
        guard let model else { return false }
        return model.phase == .ready && model.completion == nil && !model.isIdleLocked
    }

    /// Whether Exportovat zálohu… and Obnovit ze zálohy… can be chosen: the window offers the app, and no other step
    /// of Zabezpečení a zálohy runs.
    var offersTheBackups: Bool {
        offersTheApp && model?.securityStepRunning == false
    }

    /// Whether Hledat can be chosen: the window offers the app, and the search field of Faktury is there to focus.
    var offersSearch: Bool {
        offersTheApp && model?.canFocusSearch == true
    }
}
