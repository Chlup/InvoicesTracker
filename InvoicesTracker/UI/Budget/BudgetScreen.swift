import SwiftUI

/// The sizes of the page of Rozpočet that its parts do not set themselves, in points.
private nonisolated enum BudgetScreenMetrics {
    /// The widest the sentence under the key figure is set: 34 em of its 13-point type.
    static let sentenceWidth: CGFloat = 442

    /// The space above the line that says the screen could not be loaded, as the other screens set it.
    static let failureTop: CGFloat = 40
}

/// Rozpočet: how the net income of the selected year is divided among Náklady, Útrata, Úspory and Investice. From the
/// top: the row that chooses what is divided (Skutečnost, Odhad za rok or Faktura, with the button of the invoice in
/// Faktura mode); the result card, with the amount to divide as the key figure and the split bar beside it, or under
/// it where the card is too narrow for two columns, whose popovers hang out over the card under it; the card
/// Rozdělení, with "Zbytek dostane", the bill of the invoice in Faktura mode and a row for each category; and the note
/// on how the split behaves. The title and the line under it are the shell's. The texts are the builder's
/// (`BudgetBuilder`); a load that fails shows its line in place of the page.
///
/// The model is the app's (`AppModel.budgetModel`), so that one model holds the changes of the split until they are
/// saved, and other data gets a new one: the screen reads it through the app whenever it is drawn, and has it load
/// when it appears, when the model is replaced and whenever the screens load again (`AppModel.reloadKey`, which has
/// today in it). A field that is left, with Tab, with Return or by a click elsewhere, ends the editing of its category
/// (`BudgetModel.endEditing(_:)`), a slider that is let go ends its slide (`BudgetModel.endSliding(_:)`), and leaving
/// the screen ends the editing of every field and saves what waits.
struct BudgetScreen: View {
    let app: AppModel

    /// The category whose field was typed into last and has not ended its editing since.
    @State private var editedCategory: BudgetCategory?

    var body: some View {
        let model = app.budgetModel
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
                content(of: model)
            }
            .pagePadding()
        }
        // The reload key also has the screen drawn again when other data is opened, whose model it then reads.
        .task(id: LoadKey(model: ObjectIdentifier(model), data: app.reloadKey)) {
            await model.load()
        }
        .onTextFieldEditingEnded {
            // A field of this window has been left, with Tab, with Return or by a click elsewhere. Only the field that
            // was typed into holds a text of its own, so its category is the one whose editing ends. The field hands
            // its text to the model once more as it ends its editing, which may come after this, so the editing ends
            // on the next turn, after that.
            guard let category = editedCategory else { return }
            Task {
                editedCategory = nil
                model.endEditing(category)
            }
        }
        .onDisappear {
            for category in BudgetCategory.allCases {
                model.endEditing(category)
            }
            Task { await model.saveNow() }
        }
    }

    /// The page of the data `model` shows, or the line that says it could not be loaded.
    @ViewBuilder
    private func content(of model: BudgetModel) -> some View {
        if let data = model.data {
            BudgetSourceRow(
                data: data,
                chooseSource: { source in
                    Task { await model.chooseSource(source) }
                },
                chooseInvoice: { id in
                    Task { await model.chooseInvoice(id: id) }
                })
            // The popovers of the bar hang out of the card over the card under it, so the card is drawn above it,
            // and nothing clips it.
            BudgetResultCard(data: data)
                .zIndex(1)
            BudgetSplitCard(data: data, model: model, editedCategory: $editedCategory)
            Note(.info, text: data.note)
        } else if let errorText = model.errorText {
            Text(verbatim: errorText)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .frame(maxWidth: .infinity)
                .padding(.top, BudgetScreenMetrics.failureTop)
        }
    }

    /// What the screen loads again for: another model, or the screens loading again.
    private nonisolated struct LoadKey: Equatable {
        var model: ObjectIdentifier
        var data: ReloadKey
    }
}

/// The result card of Rozpočet: the amount the split divides as the key figure at the left, with the orange "odhad"
/// pill beside its eyebrow where the figure is an estimate as a whole, and the split bar at the right, or under the
/// key figure where the card is too narrow for two columns. The card is the shared result card (`ResultCard`), and the
/// key figure is spaced as the design spaces it (`KeyFigureSpacing.budget`).
///
/// The popovers of the bar hang below its legend and may reach out of the card over what follows it, so the page
/// draws the card above the card under it and does not clip it. VoiceOver reads the card as a group under "K rozdělení"
/// and the bar with its legend as a group under "Rozdělení podle kategorií".
private struct BudgetResultCard: View {
    let data: BudgetData

    var body: some View {
        ResultCard(label: "K rozdělení") {
            KeyFigureView(
                data.keyFigure, sentenceMaximumWidth: BudgetScreenMetrics.sentenceWidth, spacing: .budget,
                eyebrowPill: data.showsEstimatePill ? Pill("odhad", tone: .estimate) : nil)
        } trailing: {
            SplitBarView(data.bar)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Rozdělení podle kategorií")
        }
    }
}
