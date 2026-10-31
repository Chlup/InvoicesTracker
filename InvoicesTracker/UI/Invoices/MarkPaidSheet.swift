import SwiftUI

extension PaymentSheetModel: Identifiable {
    /// The sheet is the sheet of one invoice.
    nonisolated var id: Int64 {
        invoice.id
    }
}

/// The sheet of the payment of an invoice, "Označit jako uhrazenou", or "Upravit platbu" for the payment it has: the
/// day the money arrived, with why it cannot be saved when it is out of range, how the income in crowns is worked out
/// (the method of the year, or the amount the bank credited), the notice about a rate that is not published yet, and
/// what the payment adds to the levies of its year. The footer has Zrušit and the button that saves at its trailing
/// end; its leading end is the place of the way into removing a stored payment. The numbers and the texts are the
/// model's (`PaymentSheetModel`); the sheet only shows them, in the colours and the type of the design.
struct MarkPaidSheet: View {
    @Bindable var model: PaymentSheetModel

    /// The time zone of the Mac, in which the day is chosen.
    let timeZone: TimeZone

    /// Zrušit.
    let cancel: () -> Void

    /// The payment was saved, or there was nothing to save: the payment is the stored one, kept as it is.
    let saved: () -> Void

    /// Why the latest save failed, over the footer, until the next save starts.
    @State private var failure: String?

    /// Whether the payment is being saved: the button that saves is off meanwhile.
    @State private var isSaving = false

    /// What the payment depends on: the sheet works it out again whenever one of them changes.
    private struct Inputs: Hashable {
        var date: CivilDate
        var useBankCZK: Bool
        var bankCZKText: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            facts
            if model.methodOption != nil {
                foreignChoices
            } else if let text = model.crownText {
                Text(verbatim: text)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.bgInset, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
            }
            if model.effect != nil {
                effectBox
            }
            if let failure {
                Text(verbatim: failure)
                    .font(Typography.body)
                    .foregroundStyle(Palette.redText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            footer
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 620)
        .task(id: Inputs(date: model.date, useBankCZK: model.useBankCZK, bankCZKText: model.bankCZKText)) {
            await model.recompute()
        }
    }

    // MARK: Parts

    /// The title, "Označit jako uhrazenou" or "Upravit platbu", and under it the invoice the payment is for.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: model.title)
                .font(Typography.title2)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: model.subtitle)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
        }
    }

    /// "Datum přijetí", with why the day cannot be saved under it when it cannot, and "Přijatá částka", the amount of
    /// the invoice with VAT, each between hairlines.
    private var facts: some View {
        VStack(spacing: 0) {
            Hairline()
            row("Datum přijetí") {
                DatePicker("Datum přijetí", selection: dateSelection, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .environment(\.timeZone, timeZone)
                    .environment(\.calendar, calendar)
                    .environment(\.locale, Locale(identifier: "cs_CZ"))
            }
            if let error = model.dateError {
                Text(verbatim: error)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.redText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 144)
                    .padding(.bottom, 8)
            }
            Hairline()
            row("Přijatá částka") {
                Text(verbatim: model.totalText)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
            }
            Hairline()
        }
    }

    /// A row of the facts: `label` in a column 130 points wide, and `content` beside it.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: label)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .frame(width: 130, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    /// "Příjem pro daň v Kč": the method of the year and the amount the bank credited, one of them chosen, the notice
    /// under them, and the field of the amount while the amount from the bank is chosen.
    private var foreignChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Příjem pro daň v Kč")
                .font(Typography.bodySemibold)
                .foregroundStyle(Palette.text)
            if let option = model.methodOption {
                OptionRow(option: option, isChosen: !model.useBankCZK) {
                    model.useBankCZK = false
                }
            }
            if let option = model.bankOption {
                OptionRow(option: option, isChosen: model.useBankCZK) {
                    model.useBankCZK = true
                }
            }
            if let notice = model.notice {
                Text(verbatim: notice)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.orangeText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            if model.useBankCZK {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Částka v Kč")
                            .font(Typography.body)
                            .foregroundStyle(Palette.text2)
                        TextField("Částka v Kč", text: $model.bankCZKText)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    if let error = model.bankCZKError {
                        Text(verbatim: error)
                            .font(Typography.callout)
                            .foregroundStyle(Palette.redText)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Odvody za rok 2026 vzrostou o" ("Dopad platby na odvody 2026" for a payment the invoice has) and "+1 702 Kč" in
    /// a box on the orange tint of an estimate, what share of the income that is, and under a rule the three
    /// authorities, each with its dot.
    private var effectBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: model.effectHeading)
                .font(Typography.callout)
                .foregroundStyle(Palette.orangeText)
            Text(verbatim: model.effectTotalText ?? "")
                .font(Typography.largeTitle)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
            Text(verbatim: model.effectShareText ?? "")
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            // The rule of the box is its orange text, faint, as the design draws it.
            Rectangle()
                .fill(Palette.orangeText.opacity(0.18))
                .frame(height: 1)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                ForEach(model.effectRows) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(row.authority.color)
                            .frame(width: 8, height: 8)
                            .frame(width: 10, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(verbatim: row.title)
                        Spacer(minLength: 4)
                        Text(verbatim: row.value)
                    }
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.orangeTint, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        .accessibilityElement(children: .contain)
    }

    /// The buttons at the end of the sheet. At the leading end `removal`; at the trailing end Zrušit, which Esc
    /// presses, and the button that saves, "Označit jako uhrazenou" or "Uložit platbu", which Return presses and which
    /// is off while there is no payment to save, the day cannot be saved or the payment is being saved. The buttons are
    /// the capsules of a dialog, 32 points high.
    private var footer: some View {
        HStack(spacing: 8) {
            removal
            Spacer(minLength: 0)
            Button("Zrušit", action: cancel)
                .buttonStyle(CapsuleButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(model.saveTitle, action: save)
                .buttonStyle(CapsuleButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(model.preview == nil || model.dateError != nil || isSaving)
        }
        .padding(.top, 4)
    }

    /// The leading end of the footer, the place of the way into removing a payment the invoice has. The sheet does not
    /// remove a payment, so the place is empty.
    @ViewBuilder
    private var removal: some View {
        EmptyView()
    }

    // MARK: Actions

    /// Saves the payment (`PaymentSheetModel.save()`) and closes the sheet, or says why it could not be saved, which
    /// is logged too.
    private func save() {
        failure = nil
        isSaving = true
        Task {
            do {
                try await model.save()
                saved()
            } catch {
                AppModel.log("Saving a payment", failedWith: error)
                failure = PaymentSheetModel.failureText(for: error)
            }
            isSaving = false
        }
    }

    // MARK: The day

    /// The Gregorian calendar in the time zone of the Mac, which the date picker shows the day in.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The day as an instant the date picker takes: noon of it in the time zone of the Mac, whatever the clock changes
    /// of the day.
    private var dateSelection: Binding<Date> {
        Binding(
            get: {
                let day = model.date
                let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
                return calendar.date(from: parts) ?? Date()
            },
            set: { model.date = CivilDate.today(now: $0, timeZone: timeZone) }
        )
    }
}

/// One of the ways to work out the income: a radio button, the title with a smaller line under it, and the value, in a
/// panel that is on the accent tint with an accent ring while the way is chosen, and on the card colour with a ring of
/// the fill while it is not.
private struct OptionRow: View {
    let option: PaymentOption
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isChosen ? Palette.accent : Palette.text3)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: option.title)
                        .font(Typography.bodySemibold)
                    Text(verbatim: option.detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.text2)
                }
                Spacer(minLength: 8)
                Text(verbatim: option.value)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isChosen ? Palette.accentTint : Palette.bgCard, in: panel)
            .overlay(panel.strokeBorder(isChosen ? Palette.accent : Palette.fill, lineWidth: 1))
            .contentShape(panel)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// The shape of the panel of the option, with the radius of a panel.
    private var panel: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
    }
}
