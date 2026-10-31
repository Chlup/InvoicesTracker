import SwiftUI

/// The sheet "Nová šablona" / "Upravit šablonu": the name, the client, the items with what their descriptions come to
/// for the month a new invoice starts in (and, after the first of them, what a description may hold), the due days, the
/// VAT mode, the bank account that the invoices print, and the note. Nothing is written until Uložit šablonu; Zrušit
/// throws the edit away. A template that is stored can be deleted, after the question that the sheet asks in a red box
/// in place of its buttons. The words and the numbers are the model's (`TemplateFormModel`); the sheet only shows them.
struct TemplateForm: View {
    @Bindable var model: TemplateFormModel

    /// Zrušit.
    let cancel: () -> Void

    /// The template was saved, or deleted.
    let finished: () -> Void

    @FocusState private var nameFocused: Bool

    /// The most points the sheet takes, as tall as the least window that carries it. The fields take what the rest of
    /// the sheet leaves of it — the whole of a new template with one item, its note too — and scroll beyond that: they
    /// give way to the problems and to the question before a deletion, so the sheet never grows past it.
    static let maximumHeight: CGFloat = 700

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: model.title, subtitle: model.subtitle)
            ScrollView {
                fields
                    // A little room around the fields, so that their borders are not cut by the scroll view.
                    .padding(2)
            }
            FormProblems(errors: model.showsErrors ? model.errors : [], failure: model.failure)
            if model.confirmsDeletion {
                deleteQuestion
            } else {
                footer
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 620)
        .frame(maxHeight: Self.maximumHeight)
        .defaultFocus($nameFocused, model.isNew)
        .task {
            await model.load()
        }
    }

    // MARK: The fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField("Název šablony") {
                FormTextField("Název šablony", text: $model.name, prompt: "např. Měsíční vývoj")
                    .focused($nameFocused)
            }
            clientChoice
            itemRows
            terms
            if model.pickedClient != nil {
                accountRow
            }
            noteField
        }
    }

    /// "Odběratel": a filter chip for every client, the one chosen in the accent.
    private var clientChoice: some View {
        LabeledField("Odběratel") {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    ForEach(model.clients) { client in
                        FilterChip(client.name, isSelected: client.id == model.clientID) {
                            model.pickClient(client.id)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Odběratel šablony")
                if model.clients.isEmpty {
                    Text(verbatim: model.loadFailed ? "Odběratele se nepodařilo načíst." : EditorText.noClients)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                }
            }
        }
    }

    // MARK: The items

    /// The items, a hairline between two of them, and under them Přidat položku, with the line that says the most a
    /// template can have once it has that many.
    private var itemRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Hairline()
                }
                itemRow(binding(for: item), index: index)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if !model.canAddItem {
                    Text("Nejvýše \(EditorLimits.items) položek.")
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    model.addItem()
                } label: {
                    Label("Přidat položku", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
                .disabled(!model.canAddItem)
            }
        }
    }

    /// A binding to the item that follows it where it is in the list, so that a row that is being removed is never read
    /// by a place it no longer has.
    private func binding(for item: EditableItem) -> Binding<EditableItem> {
        Binding(
            get: { model.items.first { $0.id == item.id } ?? item },
            set: { updated in
                if let index = model.items.firstIndex(where: { $0.id == item.id }) {
                    model.items[index] = updated
                }
            })
    }

    /// An item: its number and the button that removes it where there is more than one, its description with the line
    /// of its preview under it (`TemplateFormModel.previewLine(ofItem:)`), its quantity, unit and price, and what is
    /// wrong with the quantity and the price.
    private func itemRow(_ item: Binding<EditableItem>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.items.count > 1 {
                HStack {
                    Text("Položka \(index + 1)")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Button {
                        model.removeItem(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Palette.text2)
                    }
                    .buttonStyle(.plain)
                    .help("Odebrat položku")
                    .accessibilityLabel("Odebrat položku \(index + 1)")
                }
            }
            LabeledField("Popis položky") {
                FormTextField("Popis položky \(index + 1)", text: item.description)
            }
            Text(verbatim: model.previewLine(ofItem: index))
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                LabeledField("Počet") {
                    FormTextField("Počet, položka \(index + 1)", text: item.quantityText, trailing: true)
                }
                LabeledField("MJ") {
                    UnitField(unit: item.unit, position: index + 1)
                }
                LabeledField("Cena za MJ (\(model.currencyCode))") {
                    FormTextField("Cena za MJ, položka \(index + 1)", text: item.unitPriceText, trailing: true)
                }
            }
            ForEach([item.wrappedValue.quantityError, item.wrappedValue.priceError].compactMap { $0 }, id: \.self) {
                message in
                Text(verbatim: message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.redText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The terms, the account and the note

    /// The due days and the VAT mode, in a row.
    private var terms: some View {
        HStack(alignment: .bottom, spacing: 16) {
            LabeledField("Splatnost (dní)") {
                FormTextField("Splatnost (dní)", text: $model.dueDaysText, trailing: true)
            }
            .frame(width: 110)
            LabeledField("Režim DPH") {
                Picker("Režim DPH", selection: $model.vatMode) {
                    ForEach(VatMode.allCases, id: \.self) { mode in
                        Text(verbatim: mode.formLabel)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    /// "Bankovní účet": the account that the invoices of the template print, which is the one in the currency of the
    /// client, and, in grey under it, where it comes from (`sourceHint`): from Nastavení › Moje údaje, or, in a
    /// currency that it has no boxes for, from the imported data. A line that says there is none, or that the app
    /// keeps none, has no account to say it of. It is shown once there is a client, whose currency says which account
    /// it is. There is no way from here to Nastavení: leaving the sheet would throw away what is typed in it.
    private var accountRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bankovní účet")
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
            Text(verbatim: model.accountLine.text)
                .font(Typography.body)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let hint = model.accountLine.sourceHint {
                Text(verbatim: hint)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Poznámka na faktuře": the text of the note, on the background of a card with the stronger line of a field
    /// around it, and its prompt while it is empty.
    private var noteField: some View {
        LabeledField("Poznámka na faktuře") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.note)
                    .font(Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .accessibilityLabel("Poznámka na faktuře")
                if model.note.isEmpty {
                    Text("Např. platební instrukce – vytiskne se dole na faktuře")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 72)
            .background(Palette.bgCard, in: RoundedRectangle(cornerRadius: DesignMetrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DesignMetrics.controlRadius).strokeBorder(Palette.sepStrong))
        }
    }

    // MARK: The buttons

    /// The buttons of the sheet, the capsules of a dialog, 32 points high: Smazat šablonu on the pale red at the
    /// leading end, for a stored template, which asks first; Zrušit, which Esc presses, and Uložit šablonu in the
    /// accent, which Return presses, at the trailing end.
    private var footer: some View {
        HStack(spacing: 8) {
            if !model.isNew {
                Button("Smazat šablonu", role: .destructive) {
                    model.askToDelete()
                }
                .buttonStyle(CapsuleButtonStyle(.destructive))
                .disabled(model.isWorking)
            }
            Spacer()
            Button("Zrušit", action: cancel)
                .buttonStyle(CapsuleButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Uložit šablonu", action: save)
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking)
        }
    }

    /// "Smazat šablonu „…“?" and what deleting the template does, with Zrušit, which Esc is too, and the red Smazat
    /// šablonu.
    private var deleteQuestion: some View {
        ConfirmationBox(
            title: model.deleteTitle, message: TemplateFormModel.deleteMessage,
            cancelTitle: "Zrušit", cancel: { model.cancelDeletion() },
            confirmTitle: "Smazat šablonu", confirm: delete)
    }

    private func save() {
        Task {
            // A save that does not happen says why in the sheet (`errors` and `failure` of the model, which has logged
            // what the database said), so there is nothing more to do here.
            if (try? await model.save()) != nil {
                finished()
            }
        }
    }

    private func delete() {
        Task {
            // A deletion that does not happen says so in the sheet (`failure` of the model), as a save does.
            if (try? await model.delete()) != nil {
                finished()
            }
        }
    }
}

/// The unit of an item: free text, with the usual units to choose from beside it.
private struct UnitField: View {
    @Binding var unit: String
    let position: Int

    var body: some View {
        HStack(spacing: 4) {
            FormTextField("Měrná jednotka, položka \(position)", text: $unit)
            Menu {
                ForEach(InvoiceEditorModel.units, id: \.self) { suggestion in
                    Button(suggestion) {
                        unit = suggestion
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(Typography.subheadline)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Jednotky: \(InvoiceEditorModel.units.joined(separator: ", "))")
            .accessibilityLabel("Nabídka měrných jednotek, položka \(position)")
        }
    }
}
