import SwiftUI

/// The sizes of the page of the Simulátor that its parts do not set themselves, in points.
private nonisolated enum SimulatorScreenMetrics {
    /// The width of the column of the result beside the inputs.
    static let resultWidth: CGFloat = 360

    /// The least width of the column of the inputs beside the result. The detail of the smallest window is 828 points
    /// wide inside the padding of the page, and 440, the space of 16 and the 360 of the result are 816 of them.
    static let inputsMinimumWidth: CGFloat = 440

    /// The space at the sides of the heading "Rozpis výpočtu".
    static let headingInset: CGFloat = 4
}

/// Simulátor: what the income tax, the social insurance and the health insurance come to for a year and an income the
/// person chooses, with the flat-rate expenses, the activity, the deductions and the family, and what the income leaves
/// after them. Under the note that nothing entered here is stored, with Začít znovu to start again, the inputs stand
/// on the left and the result in a column of 360 points beside them, in the smallest window too (only a sidebar
/// widened there puts the result under the inputs). The result is one card: the levies of the year as the key figure,
/// the bar of the levies by authority, the net income and the marginal levy. The breakdown of the three levies and of
/// the net income runs under both, the tax on the left and the two insurances with the net income under them on the
/// right where the window has room for two columns, and all four under each other where it has not. The cards of the
/// children and of the spouse come after the deductions, and the dialog of a child is the sheet of Zálohy a odpočty in
/// the mode of the simulation, with the lock after inactivity over it. The title and the line under it are the shell's.
/// A computation that refuses the inputs, which the fields do not let happen, leaves the results out rather than show a
/// number of its own.
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
            VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
                if let errorText = model.errorText {
                    SettingsFailureLine(text: errorText)
                }
                ComputationBanner(
                    text: Self.bannerText,
                    button: (title: "Začít znovu", action: { Task { await model.reset() } }))
                // The result fits beside the inputs in the detail of the smallest window, 828 points wide.
                SidePanelLayout(
                    sideWidth: SimulatorScreenMetrics.resultWidth,
                    mainMinimumWidth: SimulatorScreenMetrics.inputsMinimumWidth, spacing: DesignMetrics.cardSpacing
                ) {
                    VStack(spacing: DesignMetrics.cardSpacing) {
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
                    VStack(spacing: DesignMetrics.cardSpacing) {
                        if let page = model.page {
                            SimulatorResultCard(summary: page.summary)
                        }
                    }
                    .accessibilityAside(named: "Výsledek simulace")
                }
                if let page = model.page {
                    breakdown(page.sections)
                }
            }
            .pagePadding()
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
                .sheetChrome()
        }
    }

    /// "Rozpis výpočtu": the cards of the tax on the left, and of the social insurance and the health insurance on the
    /// right with the net income under them, told apart by `ComputationSection.standsRight`.
    private func breakdown(_ sections: [ComputationSection]) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.innerSpacing) {
            Text("Rozpis výpočtu")
                .font(Typography.title3)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, SimulatorScreenMetrics.headingInset)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rozpis výpočtu simulace")
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
