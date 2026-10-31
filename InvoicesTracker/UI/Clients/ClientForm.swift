import SwiftUI

/// The sheet "Nový odběratel" / "Upravit odběratele": the name, the address, the numbers, the e-mail, and the currency,
/// VAT mode, language, due days and way of payment that new invoices for the client start from. Nothing is written
/// until Uložit odběratele; Zrušit throws the edit away. The words and the numbers are the model's
/// (`ClientFormModel`); the sheet only shows them.
struct ClientForm: View {
    @Bindable var model: ClientFormModel

    /// Zrušit.
    let cancel: () -> Void

    /// The client was saved: its id, which a new client got from the save.
    let saved: (Int64) -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: model.title, subtitle: model.subtitle)
            ScrollView {
                fields
                    // A little room around the fields, so that their borders are not cut by the scroll view.
                    .padding(2)
            }
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
            FormProblems(errors: model.showsErrors ? model.errors : [], failure: model.failure)
            footer
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 620)
        .defaultFocus($nameFocused, model.isNew)
        .task {
            await model.load()
        }
    }

    // MARK: The fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField("Název") {
                FormTextField("Název", text: $model.name)
                    .focused($nameFocused)
            }
            twoFields(
                LabeledField("Ulice a číslo") { FormTextField("Ulice a číslo", text: $model.street) },
                LabeledField("Město") { FormTextField("Město", text: $model.city) })
            twoFields(
                LabeledField("PSČ") { FormTextField("PSČ", text: $model.postcode) },
                LabeledField("Země") { countryPicker })
            twoFields(
                LabeledField("IČO") { FormTextField("IČO", text: $model.ico) },
                LabeledField("DIČ") { FormTextField("DIČ", text: $model.dic) })
            twoFields(
                LabeledField("E-mail pro faktury") { FormTextField("E-mail pro faktury", text: $model.email) },
                LabeledField("Měna") { currencyPicker })
            twoFields(
                LabeledField("Režim DPH") { vatPicker },
                LabeledField("Jazyk faktury") { languagePicker })
            twoFields(
                LabeledField("Splatnost (dní)") { FormTextField("Splatnost (dní)", text: $model.dueDaysText) },
                LabeledField("Platební metoda") {
                    FormTextField("Platební metoda", text: $model.paymentMethod, prompt: "Převodem, ACH (USD)…")
                })
        }
    }

    /// Two fields side by side, of the same width.
    private func twoFields(_ first: some View, _ second: some View) -> some View {
        HStack(alignment: .top, spacing: 16) {
            first
            second
        }
    }

    private var countryPicker: some View {
        Picker("Země", selection: $model.country) {
            ForEach(model.countryChoices) { choice in
                Text(verbatim: choice.name)
                    .tag(choice.code)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var currencyPicker: some View {
        Picker("Měna", selection: $model.currency) {
            ForEach(model.currencies, id: \.self) { currency in
                Text(verbatim: ClientFormModel.currencyLabel(currency))
                    .tag(currency)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var vatPicker: some View {
        Picker("Režim DPH", selection: $model.vatMode) {
            ForEach(VatMode.allCases, id: \.self) { mode in
                Text(verbatim: mode.formLabel)
                    .tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var languagePicker: some View {
        Picker("Jazyk faktury", selection: $model.language) {
            ForEach([InvoiceLanguage.cs, .en], id: \.self) { language in
                Text(verbatim: ClientFormModel.languageLabel(language))
                    .tag(language)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    // MARK: The buttons

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Zrušit", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("Uložit odběratele", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSaving)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private func save() {
        Task {
            // A save that does not happen says why in the sheet (`errors` and `failure` of the model, which has logged
            // what the database said), so there is nothing more to do here.
            if let id = try? await model.save() {
                saved(id)
            }
        }
    }
}
