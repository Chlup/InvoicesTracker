import SwiftUI

/// Nastavení › Moje údaje: the supplier's details printed on every invoice, the bank accounts in crowns, dollars and
/// euros, and the lines "Na fakturách" of what the invoices of each currency print and miss. What is typed is saved by
/// itself a moment after the last key, and when the person leaves a field or the screen; the menus and the account in
/// euros at once (`SupplierTabModel`). Until the first load has ended it says "Načítám…" where the cards will be, and
/// a load again leaves the cards as they are.
struct SupplierTab: View {
    let app: AppModel
    @State private var model: SupplierTabModel

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: SupplierTabModel(app: app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let line = model.saveFailure ?? model.errorText {
                SettingsFailureLine(text: line)
            }
            if model.supplier != nil {
                AdaptiveColumns(minimumColumnWidth: 440, spacing: 16) {
                    detailsCard
                    accountsCard
                }
            } else if model.errorText == nil {
                // The first load has not ended. A load that failed says so above instead (`errorText`).
                SettingsLoadingView()
            }
        }
        .task(id: app.reloadKey) {
            await model.load()
        }
        .onTextFieldEditingEnded {
            Task { await model.saveNow() }
        }
        .onDisappear {
            // What was typed last is saved even when the tab is left within the moment before the save.
            Task { await model.saveNow() }
        }
    }

    // MARK: Vaše údaje

    private var detailsCard: some View {
        SettingsCard(title: "Vaše údaje", subtitle: "Tisknou se jako dodavatel na každé faktuře", spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                field(.name, "Jméno nebo název")
                field(.street, "Ulice a číslo", prompt: "např. Dlouhá 12")
                AdaptiveColumns(minimumColumnWidth: 160, spacing: 16) {
                    field(.postcode, "PSČ")
                    field(.city, "Město")
                    LabeledField("Země") { countryPicker }
                }
                AdaptiveColumns(minimumColumnWidth: 180, spacing: 16) {
                    field(.ico, "IČO")
                    field(.dic, "DIČ", prompt: "CZ…")
                    field(.email, "E-mail")
                    field(.phone, "Telefon")
                }
                VStack(alignment: .leading, spacing: 4) {
                    field(.czechFooter, "Patička českých faktur")
                    Text("Na anglické faktury se netiskne.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var countryPicker: some View {
        Picker("Země", selection: Binding(get: { model.supplier?.country ?? "" }, set: { model.setCountry($0) })) {
            ForEach(model.countryChoices) { choice in
                Text(verbatim: choice.name)
                    .tag(choice.code)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    // MARK: Bankovní účty

    private var accountsCard: some View {
        SettingsCard(
            title: "Bankovní účty", subtitle: "Faktura vytiskne účet ve své měně a z něj se dělá i QR platba",
            spacing: 14
        ) {
            accountBox("Účet v Kč") {
                AdaptiveColumns(minimumColumnWidth: 160, spacing: 14) {
                    field(.czkAccountNumber, "Číslo účtu / kód banky")
                    field(.czkIBAN, "IBAN", prompt: "CZ…")
                    field(.czkBIC, "BIC (SWIFT)")
                }
            }
            accountBox("Účet v USD") {
                AdaptiveColumns(minimumColumnWidth: 160, spacing: 14) {
                    field(.usdAccountNumber, "Account number")
                    field(.usdRoutingNumber, "Routing number")
                    LabeledField("Typ účtu") { accountTypePicker }
                }
            }
            if model.hasEURAccount {
                accountBox("Účet v eurech", removable: true) {
                    AdaptiveColumns(minimumColumnWidth: 160, spacing: 14) {
                        field(.eurIBAN, "IBAN")
                        field(.eurBIC, "BIC (SWIFT)")
                    }
                }
            } else {
                Button("+ Přidat účet v eurech") {
                    model.addEURAccount()
                }
                .settingsCardButton()
            }
            statusLines
        }
    }

    private var accountTypePicker: some View {
        Picker(
            "Typ účtu", selection: Binding(get: { model.usdAccountType }, set: { model.setUSDAccountType($0) })
        ) {
            ForEach(model.usdAccountTypeChoices, id: \.self) { type in
                Text(verbatim: type)
                    .tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    /// A box of an account: its title, Odebrat for the account in euros, and its fields.
    private func accountBox(
        _ title: String, removable: Bool = false, @ViewBuilder fields: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if removable {
                    Button("Odebrat") {
                        model.removeEURAccount()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Odebrat účet v eurech")
                }
            }
            fields()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// "Na fakturách": a line for each currency with a dot that says whether its invoices have what they need.
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Na fakturách")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            ForEach(model.statusLines, id: \.text) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(color(of: line.kind))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(verbatim: line.text)
                        .font(.callout)
                        .foregroundStyle(textColor(of: line.kind))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func color(of kind: InvoiceAccountStatus.Kind) -> Color {
        switch kind {
        case .ready: Color(.bannerText)
        case .incomplete: .orange
        case .absent: .secondary
        }
    }

    private func textColor(of kind: InvoiceAccountStatus.Kind) -> Color {
        switch kind {
        case .ready: .primary
        case .incomplete: Color(.simulationText)
        case .absent: .secondary
        }
    }

    // MARK: Fields

    private func field(_ field: SupplierField, _ label: String, prompt: String? = nil) -> some View {
        SettingsTextField(
            label: label, text: Binding(get: { model.text(field) }, set: { model.setText(field, $0) }),
            prompt: prompt, error: model.error(field))
    }
}
