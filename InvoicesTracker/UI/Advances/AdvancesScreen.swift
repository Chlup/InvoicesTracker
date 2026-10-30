import SwiftUI

/// Zálohy a odpočty: the plan of advances of the selected year with its totals, the deductions, the taxpayer credit,
/// the children and the spouse, and beside them, or under them in a narrow window, the impact of the deductions and the
/// credits on the tax. Everything is saved by itself, a moment after the last key and when the person leaves a field or
/// the screen; a child is saved in its dialog, a sheet. The title and the line under it are the shell's. The data is
/// loaded again whenever what it depends on changes.
struct AdvancesScreen: View {
    let app: AppModel
    @State private var model: AdvancesModel

    /// The dialog of a child that is open as a sheet.
    @State private var childDialog: ChildDialogModel?

    /// `saveDelay` is the moment after the last key before a change is saved; a test makes it long, to see the saves
    /// that do not wait for it.
    init(app: AppModel, saveDelay: Duration = .milliseconds(500)) {
        self.app = app
        _model = State(initialValue: AdvancesModel(app: app, saveDelay: saveDelay))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .onTextFieldEditingEnded {
            // A field of this window has been left, with Tab, with Return or by a click elsewhere: what was typed is
            // read and saved.
            Task { await model.saveNow() }
        }
        .onDisappear {
            // What was typed last is saved even when the screen is left within the moment before the save.
            Task { await model.saveNow() }
        }
        .sheet(item: $childDialog) { dialog in
            ChildDialog(model: dialog, close: { childDialog = nil })
                .idleLockCover()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.settings != nil {
            VStack(spacing: 16) {
                if let line = model.saveFailure ?? model.errorText {
                    Notice(text: line)
                }
                AdvancePlanTable(model: model)
                SidePanelLayout(sideWidth: 300, mainMinimumWidth: 520, spacing: 16) {
                    DeductionsForm(model: model, openChild: openChild)
                    ImpactPanel(model: model, showOverview: { app.screen = .overview })
                }
            }
        } else if let errorText = model.errorText {
            Text(errorText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }
}

extension AdvancesScreen {
    /// Opens the dialog of `member`, a child of the year shown, or of a new child for nil.
    private func openChild(_ member: FamilyChild?) {
        childDialog = ChildDialogModel(
            editing: model, year: model.family?.year ?? model.year, child: member, mode: .stored)
    }
}

/// A line that says something went wrong next to the form.
private struct Notice: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
