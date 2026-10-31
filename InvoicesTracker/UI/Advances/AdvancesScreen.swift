import SwiftUI

/// The sizes of the page of Zálohy a odpočty that its parts do not set themselves, in points.
private nonisolated enum AdvancesScreenMetrics {
    /// The least width of the column of the deductions and of the family beside the impact panel; where the page is
    /// narrower than this and the panel together, the panel comes under the column.
    static let cardColumnMinimumWidth: CGFloat = 520

    /// The width of the impact panel: that of the detail panels of Faktury and Odběratelé, 340 points
    /// (`DetailPanelMetrics.width`). It is a box of the same kind in the prototype, `flex: 1 1 300px; padding: 20px`,
    /// which holds 300 points of content and the padding of a card on either side.
    static let impactPanelWidth: CGFloat = DetailPanelMetrics.width
}

/// Zálohy a odpočty: the plan of advances of the selected year with its totals, the deductions, the taxpayer credit,
/// the children and the spouse, and beside them, or under them in a narrow window, the impact of the deductions and the
/// credits on the tax. Everything is saved by itself, a moment after the last key and when the person leaves a field or
/// the screen; a child is saved in its dialog, a sheet. The title and the line under it are the shell's. The data is
/// loaded again whenever what it depends on changes.
///
/// The impact panel is 340 points wide beside the column of the cards (`AdvancesScreenMetrics.impactPanelWidth`) and
/// stands there as long as the column keeps 520 points; under the column it is as wide as the page.
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
                .pagePadding()
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
                .sheetChrome()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.settings != nil {
            VStack(spacing: DesignMetrics.cardSpacing) {
                if let line = model.saveFailure ?? model.errorText {
                    Note(.error, icon: .warning, text: line)
                }
                AdvancePlanTable(model: model)
                SidePanelLayout(
                    sideWidth: AdvancesScreenMetrics.impactPanelWidth,
                    mainMinimumWidth: AdvancesScreenMetrics.cardColumnMinimumWidth, spacing: DesignMetrics.cardSpacing
                ) {
                    DeductionsForm(model: model, openChild: openChild)
                    ImpactPanel(model: model, showOverview: { app.screen = .overview })
                }
            }
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
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
