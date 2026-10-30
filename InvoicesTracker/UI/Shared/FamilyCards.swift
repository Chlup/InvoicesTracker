import SwiftUI

/// How the card of the spouse reads and changes the field of the spouse's own income: its text, the message while its
/// text is refused, and what Return in it does. Zálohy a odpočty saves the income; the Simulátor only reads it.
struct SpouseIncomeInput {
    let text: Binding<String>
    let message: String?
    let submit: () -> Void
}

// MARK: - Děti

/// "Děti · daňové zvýhodnění": what the children bring for the year, the rates, a row for each child of the year that
/// opens its dialog, the hints about the other parent and the bonus, and Přidat dítě, in the Simulátor with the note
/// beside it that nothing is stored, which goes under it where the card is too narrow for both. The words and the
/// figures are the builder's (`FamilyCardsBuilder`); the card only shows them.
struct ChildrenCard: View {
    let content: ChildrenCardContent

    /// Opens the dialog of a child, or of a new one for nil.
    let open: (FamilyChild?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FamilyCardHeader(title: "Děti · daňové zvýhodnění", total: content.total, totalCounts: true)
            Text(verbatim: content.rates)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 10)
            ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                Divider()
                ChildRowButton(row: row) {
                    open(row.member)
                }
            }
            if content.rows.isEmpty {
                Divider()
                Text(verbatim: ChildrenCardContent.noChildren)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
            }
            if let hint = content.hint {
                Text(verbatim: hint)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 4)
            }
            Divider()
                .padding(.top, 8)
            addRow
                .padding(.top, 10)
        }
        .familyCard(label: "Děti")
    }

    /// Přidat dítě, with the note of the card at the other end of its line, or under it where the line is too narrow
    /// for both.
    @ViewBuilder
    private var addRow: some View {
        if let note = content.addNote {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    addButton
                    Spacer(minLength: 8)
                    noteText(note)
                }
                VStack(alignment: .leading, spacing: 8) {
                    addButton
                    noteText(note)
                }
            }
        } else {
            addButton
        }
    }

    private var addButton: some View {
        Button {
            open(nil)
        } label: {
            Label("Přidat dítě", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    private func noteText(_ note: String) -> some View {
        Text(verbatim: note)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The row of a child: its name and its date of birth, its rates and months or why it counts in no month, and what it
/// brings, as one button that opens its dialog. VoiceOver reads the row whole.
struct ChildRowButton: View {
    let row: ChildCardRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(heading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: row.status)
                        .font(.callout)
                        .foregroundStyle(row.countsInNoMonth ? Color(.attentionText) : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: row.amount)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(row.hasAmount ? Color.primary : Color.secondary)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: row.spokenText))
    }

    /// The name in bold, and the date of birth after it.
    private var heading: AttributedString {
        var name = AttributedString(row.name)
        name.font = .body.weight(.semibold)
        var birth = AttributedString(" · " + row.birth)
        birth.foregroundColor = .secondary
        return name + birth
    }
}

// MARK: - Manžel / manželka

/// "Manžel / manželka · sleva na dani": whether the credit is claimed, and for a claimed spouse the months married and
/// in the household, the own income with the limit and what counts in it, ZTP/P with its months, from 2024 the children
/// under three that the credit asks for, and the months and the amount that result. Every choice is saved at once
/// (`FamilyEditing.setSpouse`): a first month chosen after the last, or a last one before the first, moves the other
/// end of its range along, so a range is always one. The income is a typed field (`income`). The words and the figures
/// are the builder's (`FamilyCardsBuilder`); the choices show the spouse as the screen has it.
struct SpouseCard: View {
    let content: SpouseCardContent
    let editing: any FamilyEditing
    let income: SpouseIncomeInput

    /// The spouse of the year as the screen has it, with what is not saved yet.
    private var spouse: SpouseYear? {
        editing.family?.spouse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FamilyCardHeader(
                title: "Manžel / manželka · sleva na dani", total: content.total, totalCounts: content.totalCounts
            )
            .padding(.bottom, 6)
            Divider()
            claim
            if let spouse, spouse.claim {
                Divider()
                months(of: spouse)
                Divider()
                ownIncome
                Divider()
                ztpp(of: spouse)
                if let note = content.youngChild {
                    youngChild(note)
                }
                if let result = content.result {
                    Text(verbatim: result)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
        .familyCard(label: "Manžel nebo manželka")
    }

    // MARK: The rows

    /// "Uplatnit slevu na manžela / manželku" with what the credit is under it.
    private var claim: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Uplatnit slevu na manžela / manželku", isOn: claimChoice)
                .toggleStyle(.checkbox)
                .fontWeight(.semibold)
            Text(verbatim: content.claimLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .padding(.vertical, 10)
    }

    private func months(of spouse: SpouseYear) -> some View {
        HStack(spacing: 12) {
            Text("Manželé ve společné domácnosti")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            MonthChoice(
                label: "od", title: "Manželé ve společné domácnosti od",
                month: monthChoice(spouse.months.from) { $0.months = $0.months.withFrom($1) })
            MonthChoice(
                label: "do", title: "Manželé ve společné domácnosti do",
                month: monthChoice(spouse.months.to) { $0.months = $0.months.withTo($1) })
        }
        .padding(.vertical, 10)
    }

    /// The field of the income with "Kč", the message of a refused text under it, whether the income is within the
    /// limit, and what counts in it.
    private var ownIncome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(verbatim: content.incomeTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    AmountTextField(title: content.incomeTitle, text: income.text, width: 110, submit: income.submit)
                    Text("Kč")
                }
                .fixedSize()
            }
            if let message = income.message {
                FieldMessage(text: message)
            }
            if let status = content.incomeStatus {
                Text(verbatim: status)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(content.incomeIsOverLimit ? Color.red : Color(.bannerText))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: SpouseCardContent.incomeNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    private func ztpp(of spouse: SpouseYear) -> some View {
        HStack(spacing: 12) {
            // The label breaks where the months leave it too little room, as on the narrowest card.
            Toggle(isOn: ztppChoice) {
                Text("Průkaz ZTP/P – sleva dvojnásobná")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let range = spouse.ztpp {
                MonthChoice(
                    label: "od", title: "Průkaz ZTP/P od",
                    month: monthChoice(range.from) { $0.ztpp = $0.ztpp?.withFrom($1) })
                MonthChoice(
                    label: "do", title: "Průkaz ZTP/P do",
                    month: monthChoice(range.to) { $0.ztpp = $0.ztpp?.withTo($1) }
                )
            }
        }
        .padding(.vertical, 10)
    }

    /// The box about the children under three: green while there is one, amber while there is none.
    private func youngChild(_ note: YoungChildNote) -> some View {
        Text(verbatim: note.text)
            .font(.callout)
            .foregroundStyle(note.isMet ? Color(.bannerText) : Color(.simulationText))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                note.isMet ? Color.green.opacity(0.12) : Color.orange.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Choices

    /// The claim: a spouse claimed for the first time is married and in the household the whole year, without own
    /// income; one who is no longer claimed keeps what was entered.
    private var claimChoice: Binding<Bool> {
        Binding(
            get: { spouse?.claim == true },
            set: { on in
                var next = spouse ?? SpouseYear(claim: on, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil)
                next.claim = on
                save(next)
            })
    }

    /// ZTP/P: the whole year once it is ticked.
    private var ztppChoice: Binding<Bool> {
        Binding(
            get: { spouse?.ztpp != nil },
            set: { on in
                guard var next = spouse else { return }
                next.ztpp = on ? MonthRange.wholeYear : nil
                save(next)
            })
    }

    /// A month of a range of the spouse, `month` now, that `change` puts into the spouse when another is chosen.
    private func monthChoice(_ month: Int, _ change: @escaping (inout SpouseYear, Int) -> Void) -> Binding<Int> {
        Binding(
            get: { month },
            set: { chosen in
                guard var next = spouse else { return }
                change(&next, chosen)
                save(next)
            })
    }

    /// Saves `next` at once. A change that is not made is said by the screen, which keeps it waiting
    /// (`FamilyEditing.setSpouse`): the card has no place of its own to say it.
    private func save(_ next: SpouseYear) {
        Task {
            try? await editing.setSpouse(next)
        }
    }
}

// MARK: - Parts

/// A month to choose, "od" or "do" before it, which VoiceOver reads under `title`.
struct MonthChoice: View {
    let label: String
    let title: String
    let month: Binding<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker(title, selection: month) {
                ForEach(1...12, id: \.self) { month in
                    Text(verbatim: CzechFormat.monthNames[month - 1])
                        .tag(month)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

/// The title of a card of the family, a heading for VoiceOver, with its total at the other end: in the colour of the
/// text while `totalCounts`, otherwise grey.
private struct FamilyCardHeader: View {
    let title: String
    let total: String?
    let totalCounts: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let total {
                Text(verbatim: total)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(totalCounts ? Color.primary : Color.secondary)
                    .fixedSize()
            }
        }
    }
}

private extension View {
    /// A card of the family, which VoiceOver reads under `label`.
    func familyCard(label: String) -> some View {
        padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenCard()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}
