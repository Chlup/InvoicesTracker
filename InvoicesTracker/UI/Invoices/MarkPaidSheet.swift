import SwiftUI

extension PaymentSheetModel: Identifiable {
    /// The sheet is the sheet of one invoice.
    nonisolated var id: Int64 {
        invoice.id
    }
}

/// The sheet "Označit jako uhrazenou": the day the money arrived, with why it cannot be saved when it is out of range,
/// how the income in crowns is worked out (the method of the year, or the amount the bank credited), the notice about a
/// rate that is not published yet, and what the payment adds to the levies of its year. The numbers are the model's
/// (`PaymentSheetModel`); the sheet only shows them.
struct MarkPaidSheet: View {
    @Bindable var model: PaymentSheetModel

    /// The time zone of the Mac, in which the day is chosen.
    let timeZone: TimeZone

    /// Zrušit.
    let cancel: () -> Void

    /// The payment was saved.
    let saved: () -> Void

    @State private var failure: String?
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
            VStack(spacing: 0) {
                Divider()
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
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 144)
                        .padding(.bottom, 8)
                }
                Divider()
                row("Přijatá částka") {
                    Text(verbatim: model.totalText)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                Divider()
            }
            if model.methodOption != nil {
                foreignChoices
            } else if let text = model.crownText {
                Text(verbatim: text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.effect != nil {
                effectBox
            }
            if let failure {
                Text(verbatim: failure)
                    .foregroundStyle(.red)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.title)
                .font(.system(size: 17, weight: .bold))
            Text(verbatim: model.subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    /// "Příjem pro daň v Kč": the method of the year and the amount the bank credited, one of them chosen.
    private var foreignChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Příjem pro daň v Kč")
                .fontWeight(.semibold)
                .padding(.bottom, 2)
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
                    .font(.callout)
                    .foregroundStyle(Color(.simulationText))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            if model.useBankCZK {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Částka v Kč")
                            .foregroundStyle(.secondary)
                        TextField("Částka v Kč", text: $model.bankCZKText)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    if let error = model.bankCZKError {
                        Text(verbatim: error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Odvody za rok 2026 vzrostou o +1 702 Kč", what share of the income that is, and the three authorities.
    private var effectBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.effectHeading)
                .font(.callout)
                .foregroundStyle(Color(.simulationText))
            Text(verbatim: model.effectTotalText ?? "")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(verbatim: model.effectShareText ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(spacing: 4) {
                ForEach(model.effectRows) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(row.authority.color)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(verbatim: row.title)
                        Spacer(minLength: 4)
                        Text(verbatim: row.value)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Zrušit", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("Označit jako uhrazenou", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.preview == nil || model.dateError != nil || isSaving)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    // MARK: Actions

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

/// One of the ways to work out the income: a radio button, the title with a smaller line under it, and the value.
private struct OptionRow: View {
    let option: PaymentOption
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: option.title)
                        .fontWeight(.semibold)
                    Text(verbatim: option.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(verbatim: option.value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isChosen ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isChosen ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
