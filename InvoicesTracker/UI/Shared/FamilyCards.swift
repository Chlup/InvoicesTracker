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
/// opens its dialog, the hints about the other parent and the bonus in a panel on the inset background, and Přidat
/// dítě, in the Simulátor with the note beside it that nothing is stored, which goes under it where the card is too
/// narrow for both. The words and the figures are the builder's (`FamilyCardsBuilder`); the card only shows them.
struct ChildrenCard: View {
    let content: ChildrenCardContent

    /// Opens the dialog of a child, or of a new one for nil.
    let open: (FamilyChild?) -> Void

    var body: some View {
        Card(spacing: 0, label: content.label) {
            FamilyCardHeader(title: "Děti · daňové zvýhodnění", total: content.total, totalCounts: true)
            Text(verbatim: content.rates)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 10)
            ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                Hairline()
                ChildRowButton(row: row) {
                    open(row.member)
                }
            }
            if content.rows.isEmpty {
                Hairline()
                Text(verbatim: content.emptyText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
            }
            if let hint = content.hint {
                Text(verbatim: hint)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .insetPanel(horizontal: 12, vertical: 10)
                    .padding(.top, 4)
            }
            Hairline()
                .padding(.top, 8)
            addRow
                .padding(.top, 10)
        }
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

    /// Přidat dítě, with a plus before it: a capsule 28 points tall on the grey fill, as the buttons inside a card are.
    private var addButton: some View {
        Button {
            open(nil)
        } label: {
            Label("Přidat dítě", systemImage: "plus")
        }
        .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
    }

    /// The note beside Přidat dítě, in callout and the grey of captions, as the design of the Simulátor sets it.
    private func noteText(_ note: String) -> some View {
        Text(verbatim: note)
            .font(Typography.callout)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The row of a child: its name and its date of birth, its rates and months or why it counts in no month, and what it
/// brings, as one button that opens its dialog. The status is in the orange of text while the child counts in no month,
/// the amount in the grey of captions while the child brings nothing. VoiceOver reads the row whole.
struct ChildRowButton: View {
    let row: ChildCardRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(heading)
                        .font(Typography.body)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: row.status)
                        .font(Typography.callout)
                        .foregroundStyle(row.countsInNoMonth ? Palette.orangeText : Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: row.amount)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(row.hasAmount ? Palette.text : Palette.text3)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(Typography.subheadlineSemibold)
                    .foregroundStyle(Palette.text4)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: row.spokenText))
    }

    /// The name in semibold, and the date of birth after it in secondary text.
    private var heading: AttributedString {
        var name = AttributedString(row.name)
        name.font = Typography.bodySemibold
        var birth = AttributedString(" · " + row.birth)
        birth.foregroundColor = Palette.text2
        return name + birth
    }
}

// MARK: - Manžel / manželka

/// "Manžel / manželka · sleva na dani": whether the credit is claimed, and for a claimed spouse the months married and
/// in the household, the own income with the limit and what counts in it, ZTP/P with its months, from 2024 the children
/// under three that the credit asks for, in a note, and the months and the amount that result. Every choice is saved at
/// once (`FamilyEditing.setSpouse`): a first month chosen after the last, or a last one before the first, moves the
/// other end of its range along, so a range is always one. The income is a typed field (`income`). The words and the
/// figures are the builder's (`FamilyCardsBuilder`); the choices show the spouse as the screen has it.
struct SpouseCard: View {
    let content: SpouseCardContent
    let editing: any FamilyEditing
    let income: SpouseIncomeInput

    /// The spouse of the year as the screen has it, with what is not saved yet.
    private var spouse: SpouseYear? {
        editing.family?.spouse
    }

    var body: some View {
        Card(spacing: 0, label: content.label) {
            FamilyCardHeader(
                title: "Manžel / manželka · sleva na dani", total: content.total, totalCounts: content.totalCounts
            )
            .padding(.bottom, 6)
            Hairline()
            claim
            if let spouse, spouse.claim {
                Hairline()
                months(of: spouse)
                Hairline()
                ownIncome
                Hairline()
                ztpp(of: spouse)
                if let note = content.youngChild {
                    youngChild(note)
                }
                if let result = content.result {
                    Text(verbatim: result)
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
    }

    // MARK: The rows

    /// "Uplatnit slevu na manžela / manželku" with what the credit is under it.
    private var claim: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Uplatnit slevu na manžela / manželku", isOn: claimChoice)
                .toggleStyle(.checkbox)
                .font(Typography.bodySemibold)
            Text(verbatim: content.claimLine)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .padding(.vertical, 10)
    }

    /// The months the spouses lived together in the household: the text and the two menus of the first and the last.
    private func months(of spouse: SpouseYear) -> some View {
        HStack(spacing: 12) {
            Text("Manželé ve společné domácnosti")
                .font(Typography.body)
                .foregroundStyle(Palette.text)
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
    /// limit, in the green of text, or over it, in the red of text, and what counts in it.
    private var ownIncome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(verbatim: content.incomeTitle)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    AmountTextField(title: content.incomeTitle, text: income.text, width: 110, submit: income.submit)
                    Text("Kč")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text)
                }
                .fixedSize()
            }
            if let message = income.message {
                FieldMessage(text: message)
            }
            if let status = content.incomeStatus {
                Text(verbatim: status)
                    .font(Typography.calloutSemibold)
                    .foregroundStyle(content.incomeIsOverLimit ? Palette.redText : Palette.greenText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: SpouseCardContent.incomeNote)
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    /// The box of ZTP/P of the spouse, and its months once it is ticked.
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

    /// The note about the children under three: green while there is one, orange while there is none. It has no icon,
    /// as the box of the design has none.
    private func youngChild(_ note: YoungChildNote) -> some View {
        Note(note.isMet ? .success : .attention, icon: .none, text: note.text)
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

/// A month to choose, "od" or "do" before it in secondary text, which VoiceOver reads under `title`.
struct MonthChoice: View {
    let label: String
    let title: String
    let month: Binding<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: label)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
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

/// The title of a card of the family in title 3, a heading for VoiceOver, with its total at the other end in semibold:
/// in the colour of the text while `totalCounts`, otherwise in the grey of captions.
private struct FamilyCardHeader: View {
    let title: String
    let total: String?
    let totalCounts: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: title)
                .font(Typography.title3)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let total {
                Text(verbatim: total)
                    .font(Typography.bodySemibold)
                    .monospacedDigit()
                    .foregroundStyle(totalCounts ? Palette.text : Palette.text3)
                    .fixedSize()
            }
        }
    }
}
