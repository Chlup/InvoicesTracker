import SwiftUI

/// The toolbar of the window, the same on every screen: the back arrow while the invoice editor is shown, the year
/// menu, the rate capsule with how the year converts its income in other currencies (`RateCapsule`), and Nová faktura,
/// which is in the accent of the design (`Palette.accent`) whatever accent the system has. The toolbar itself stays
/// native.
///
/// There is no control for the day the screens report as of. The current year is reported through the last day of the
/// current month automatically (`AsOfState`), and the year menu is the only choice: a year that is over is shown as a
/// whole, and the current year returns to the automatic day.
struct MainToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        if model.showsEditorBackArrow {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.leaveEditor()
                } label: {
                    Label("Zpět na faktury", systemImage: "chevron.left")
                }
                .help("Zpět na faktury")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            yearMenu
        }
        ToolbarItemGroup(placement: .primaryAction) {
            RateCapsule(model: model)
            Button {
                model.editorRequest = .chooser
            } label: {
                Label("Nová faktura", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
        }
    }

    // MARK: The year

    /// "2026 ⌄": the years newest first, with a check mark at the selected one.
    private var yearMenu: some View {
        Menu {
            Picker("Rok", selection: yearSelection) {
                ForEach(model.years, id: \.self) { year in
                    Text(verbatim: String(year))
                        .tag(year)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(verbatim: String(model.asOf.year))
                .fontWeight(.semibold)
        }
        .accessibilityLabel("Rok \(String(model.asOf.year))")
    }

    private var yearSelection: Binding<Int> {
        Binding(get: { model.asOf.year }, set: { model.selectYear($0) })
    }
}
