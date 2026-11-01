import SwiftUI

/// The start with empty data, in three steps under one indicator: the recovery code to store, the supplier's details
/// for the invoices, and the offer to import the invoices from Fakturoid.
struct OnboardingView: View {
    let model: AppModel
    let step: OnboardingStep

    var body: some View {
        switch step {
        case .recoveryCode(let code, let label, let number, let created):
            RecoveryCodeStep(model: model, code: code, label: label, number: number, created: created)
                // A new code is a new step: nothing that was chosen for the one before is kept.
                .id(code)
        case .supplier:
            SupplierStep(model: model)
        case .importOffer:
            ImportOfferStep(model: model)
        }
    }
}

// MARK: - Indicator

/// "Kód pro obnovení · Vaše údaje · Faktury": the steps of the start, with the one the person is at. The step the
/// person is at is an accent circle with its number in the colour of text on an accent; a step that is done is a green
/// circle with a check, and its name in the green text; one to come is a grey circle, and its number and name in the
/// faintest text.
private struct StepIndicator: View {
    /// The index of the step the person is at: 0, 1 or 2.
    let current: Int

    private static let titles = ["Kód pro obnovení", "Vaše údaje", "Faktury"]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Self.titles.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(index < current ? "✓" : String(index + 1))
                        .font(Typography.subheadlineBold)
                        .foregroundStyle(numberColor(index))
                        .frame(width: 18, height: 18)
                        .background(circleColor(index), in: Circle())
                        .accessibilityHidden(true)
                    Text(Self.titles[index])
                        .font(index == current ? Typography.calloutSemibold : Typography.callout)
                        .foregroundStyle(titleColor(index))
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(index == current ? "aktuální krok" : (index < current ? "hotovo" : ""))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kroky nastavení")
    }

    private func circleColor(_ index: Int) -> Color {
        if index == current {
            return Palette.accent
        }
        return index < current ? Palette.greenTint : Palette.fill
    }

    private func numberColor(_ index: Int) -> Color {
        if index == current {
            return Palette.onAccent
        }
        return index < current ? Palette.greenText : Palette.text4
    }

    private func titleColor(_ index: Int) -> Color {
        if index == current {
            return Palette.text
        }
        return index < current ? Palette.greenText : Palette.text4
    }
}

// MARK: - Step 1: the recovery code

/// "Uložte si kód pro obnovení": the code of the data that is about to be made, in groups, to print or copy; the choice
/// of unlocking with Touch ID; and the person's word that the code is stored away from this Mac. Pokračovat makes the
/// data; Zpět forgets the code and goes back to where the start came from.
private struct RecoveryCodeStep: View {
    let model: AppModel
    let code: String
    let label: String
    let number: Int
    let created: CivilDate

    /// The choice of Touch ID, on, as is recommended.
    @State private var touchID = true
    @State private var stored = false
    @State private var runner = StepRunner()

    var body: some View {
        WelcomeCard(label: "Kód pro obnovení", width: 600) {
            StepIndicator(current: 0)
            WelcomeHeading(
                title: "Uložte si kód pro obnovení",
                text: """
                    Na tomto Macu data odemyká Secure Enclave. Kód pro obnovení je jediný další klíč: otevře data na \
                    jiném Macu, po opravě tohoto Macu nebo ze zálohy.
                    """
            )
            RecoveryCodeCard(
                code: code, caption: WelcomeTexts.codeCaption(number: number, created: created),
                note: "32 znaků · velikost písmen ani pomlčky nehrají roli", label: label)
            Note(
                .attention, icon: .warning,
                text: """
                    Kód nikam neposíláme a aplikace si ho nepamatuje. Kdo ztratí tento Mac i kód, data už neotevře – \
                    ani autor aplikace. Uložte ho do správce hesel nebo ho vytiskněte a schovejte mimo počítač.
                    """)
            Toggle(isOn: $touchID) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Odemykat přes Touch ID")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                    Text(
                        """
                        Doporučeno. Aplikace se zeptá na Touch ID nebo heslo k Macu při spuštění a po \
                        10\u{00A0}minutách nečinnosti (dobu změníte v Nastavení). Bez Touch ID se otevře bez ověření; \
                        data na disku zůstanou šifrovaná.
                        """
                    )
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: $stored) {
                Text("Kód mám uložený mimo tento Mac")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
            }
            .toggleStyle(.checkbox)
            .insetPanel(horizontal: 14, vertical: 12)
            if let errorText = runner.errorText {
                WelcomeErrorLine(text: errorText)
            }
            WelcomeFooter(
                backTitle: "Zpět", back: { model.cancelFreshStart() }, isWorking: runner.isWorking,
                goTitle: "Pokračovat", goDisabled: !stored
            ) {
                Task { await runner.perform { try await model.finishRecoveryCodeStep(touchID: touchID) } }
            }
        }
    }
}

// MARK: - Step 2: the supplier

/// "Vaše údaje na fakturách": the details printed as the supplier on every invoice, and the account in crowns. Nothing
/// is required, but an IBAN with a typo is not saved: Pokračovat says so under its field. There is no Zpět: the data
/// exists from the step before, and its code was shown there for the last time.
private struct SupplierStep: View {
    let model: AppModel

    @State private var draft = SupplierDraft()
    @State private var runner = StepRunner()

    /// Whether Pokračovat was pressed with an IBAN that is not one: from then on its field says so until it is one.
    @State private var showsIBANError = false

    var body: some View {
        WelcomeCard(label: "Vaše údaje", width: 640) {
            StepIndicator(current: 1)
            WelcomeHeading(
                title: "Vaše údaje na fakturách",
                text: """
                    Vytisknou se jako dodavatel na každé faktuře. Všechno můžete později změnit v Nastavení › \
                    Moje údaje.
                    """
            )
            VStack(spacing: 12) {
                field("Jméno nebo název", $draft.name)
                field("Ulice a číslo", $draft.street, prompt: "např. Dlouhá 12")
                HStack(alignment: .top, spacing: 16) {
                    field("PSČ", $draft.postcode)
                    field("Město", $draft.city)
                }
                HStack(alignment: .top, spacing: 16) {
                    field("IČO", $draft.ico)
                    field("DIČ", $draft.dic, prompt: "CZ…")
                }
                HStack(alignment: .top, spacing: 16) {
                    field("Účet v Kč (číslo/kód banky)", $draft.czkAccount)
                    field(
                        "IBAN účtu v Kč (pro QR Platbu)", $draft.czkIban, prompt: "CZ…",
                        error: showsIBANError ? draft.ibanError : nil)
                }
            }
            Text(
                """
                E-mail, telefon, účet v USD nebo v eurech a patičku českých faktur doplníte v Nastavení › Moje údaje. \
                Z importu Fakturoidu lze prázdné údaje doplnit automaticky.
                """
            )
            .font(Typography.callout)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
            if let errorText = runner.errorText {
                WelcomeErrorLine(text: errorText)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if runner.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Přeskočit") {
                    model.skipSupplierStep()
                }
                .buttonStyle(CapsuleButtonStyle(.secondary))
                .disabled(runner.isWorking)
                Button("Pokračovat") {
                    guard draft.ibanError == nil else {
                        showsIBANError = true
                        return
                    }
                    Task {
                        await runner.perform {
                            try await model.saveSupplierStep(draft.supplier, czkAccount: draft.czkBankAccount)
                        }
                    }
                }
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(runner.isWorking)
            }
        }
    }

    /// A field with its label over it and, when what was typed is refused, `error` under it in red, as the fields of
    /// Nastavení › Moje údaje say it.
    private func field(
        _ label: String, _ text: Binding<String>, prompt: String = "", error: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
            TextField(label, text: text, prompt: Text(verbatim: prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .controlSize(.large)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignMetrics.controlRadius)
                        .strokeBorder(Palette.red, lineWidth: error == nil ? 0 : 1)
                )
            if let error {
                FieldMessage(text: error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Step 3: the import

/// "Máte faktury ve Fakturoidu?": the offer to import them now, or to begin without. Both end the start and show the
/// app.
private struct ImportOfferStep: View {
    let model: AppModel

    var body: some View {
        WelcomeCard(label: "Faktury") {
            StepIndicator(current: 2)
            WelcomeHeading(
                title: "Máte faktury ve Fakturoidu?",
                text: """
                    Import přenese faktury a platby a založí chybějící odběratele. Zálohy a odpočty pak doplníte v \
                    Zálohách a odpočtech.
                    """
            )
            VStack(spacing: 10) {
                WelcomeOptionRow(
                    systemImage: "square.and.arrow.down", tone: .accent, title: "Importovat z Fakturoidu",
                    detail: "CSV export faktur, klidně za víc let najednou.", showsChevron: false
                ) {
                    model.finishOnboarding(importNow: true)
                }
                WelcomeOptionRow(
                    systemImage: "arrow.right", tone: .neutral, title: "Začít bez importu",
                    detail: "Import najdete kdykoli dole v postranním panelu.", showsChevron: false
                ) {
                    model.finishOnboarding(importNow: false)
                }
            }
        }
    }
}
