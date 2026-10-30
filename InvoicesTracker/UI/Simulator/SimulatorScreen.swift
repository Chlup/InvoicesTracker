import SwiftUI

/// Simulátor: what the income tax, the social insurance and the health insurance come to for a year and an income the
/// person chooses, with the flat-rate expenses, the activity, the deductions and the family, and what the income leaves
/// after them. Under the note that nothing entered here is stored, with Začít znovu to start again, the inputs stand
/// on the left and what the year costs and the marginal levy beside them, in the smallest window too (only a sidebar
/// widened there puts them under the inputs); the card of what the year costs ends with the net income. The breakdown
/// of the three levies and of the net income runs under both, the tax on the left and the two insurances with the net
/// income under them on the right where the window has room for two columns, and all four under each other where it
/// has not. The cards of the children and of the spouse come after the deductions, and the dialog of a child is the
/// sheet of Zálohy a odpočty in the mode of the simulation, with the lock after inactivity over it. The title and the
/// line under it are the shell's. A computation that refuses the inputs, which the fields do not let happen, leaves
/// the results out rather than show a number of its own.
///
/// The model is the app's (`AppModel.simulatorModel`), so what was entered stays while other screens are shown, and
/// other data gets a new one: the screen reads it through the app whenever it is drawn, and has the model read the
/// settings of its year when it appears, when the model is replaced and whenever the screens load again. A typed text
/// is read on Return, when its field is left and when the screen is, besides after the pause the model waits for.
struct SimulatorScreen: View {
    let app: AppModel

    /// The dialog of a child of the simulation that is open as a sheet.
    @State private var childDialog: ChildDialogModel?

    /// The note at the top of the page.
    private static let bannerText =
        "Simulace pro libovolný rok a příjem. Nic z toho, co tu zadáte, se neukládá a nemění vaše faktury, zálohy ani"
        + " odpočty."

    var body: some View {
        let model = app.simulatorModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorText = model.errorText {
                    SettingsFailureLine(text: errorText)
                }
                ComputationBanner(
                    text: Self.bannerText,
                    button: (title: "Začít znovu", action: { Task { await model.reset() } }))
                // The results fit beside the inputs in the detail of the smallest window, about 820 points wide.
                SidePanelLayout(sideWidth: 300, mainMinimumWidth: 480, spacing: 16) {
                    VStack(spacing: 16) {
                        SimulatorYearAndIncomeCard(model: model)
                        SimulatorDeductionsHeading(model: model)
                        SimulatorMortgageCard(model: model)
                        SimulatorRetirementCard(model: model)
                        SimulatorGiftsCard(model: model)
                        SimulatorFamilyCards(model: model) { member in
                            childDialog = ChildDialogModel(
                                editing: model, year: model.year, child: member, mode: .simulation)
                        }
                    }
                    VStack(spacing: 16) {
                        if let page = model.page {
                            SimulatorResultCard(summary: page.summary)
                            MarginalCard(marginal: page.marginal)
                        }
                    }
                }
                if let page = model.page {
                    breakdown(page.sections)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        // The reload key also has the screen drawn again when other data is opened, whose model it then reads.
        .task(id: LoadKey(model: ObjectIdentifier(model), data: app.reloadKey)) {
            await model.load()
        }
        .onSubmit {
            model.readTypedTexts()
        }
        .onTextFieldEditingEnded {
            // A field of this window has been left, with Tab, with Return or by a click elsewhere.
            model.readTypedTexts()
        }
        .onDisappear {
            // What was typed last counts even when the screen is left within the pause.
            model.readTypedTexts()
        }
        .sheet(item: $childDialog) { dialog in
            ChildDialog(model: dialog, close: { childDialog = nil })
                .idleLockCover()
        }
    }

    /// "Rozpis výpočtu": the cards of the tax on the left, and of the social insurance and the health insurance on the
    /// right with the net income under them, told apart by `ComputationSection.standsRight`.
    private func breakdown(_ sections: [ComputationSection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rozpis výpočtu")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            TwoColumnStack {
                ForEach(sections.filter { !$0.standsRight }) { section in
                    card(of: section)
                }
            } right: {
                ForEach(sections.filter(\.standsRight)) { section in
                    card(of: section)
                }
            }
        }
    }

    /// A card of the breakdown, which VoiceOver reads under the title of its section.
    private func card(of section: ComputationSection) -> some View {
        ComputationCard(section: section)
            .accessibilityLabel(section.title)
    }

    /// What the settings of the year are read again for: another model, or the screens loading again.
    private nonisolated struct LoadKey: Equatable {
        var model: ObjectIdentifier
        var data: ReloadKey
    }
}
