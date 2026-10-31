import SwiftUI

/// The detail of one invoice, in the panel of the page at the right of the table (`DetailPanel`): its number and status
/// in the header and under them the buttons for what can be done with it, then the client, the amount and the items,
/// the dates, the VAT and the ČNB rate of the DUZP, the payment with what it leaves after the levies and what it adds
/// to the levies of its year (or what a payment would add and leave), and Smazat fakturu….
///
/// A draft is issued, edited and shown as a PDF; an invoice that waits for its payment is marked paid, edited and
/// shown; one that has a payment has the payment changed and is shown. A paid invoice is not edited, only its payment,
/// so its detail has no "Upravit", not even one that is off. A draft is issued in one click, without the editor:
/// "Vystavit" is off while it is being issued, and where it could not be issued a red note right under the buttons
/// says why, while the buttons stay. The card is as wide as a detail panel (`DetailPanelMetrics.width`) and as high as
/// its content, or as the room it is given where that is less, and what does not fit in it then scrolls.
struct InvoiceDetailCard: View {
    let detail: InvoiceDetail

    /// Why the draft could not be issued in one click, the reason the editor gives, or nil: a red note right under the
    /// buttons says it.
    var issueProblem: String?

    /// Whether the draft is being issued in one click: "Vystavit" is off meanwhile.
    var isIssuing = false

    /// The ✕ of the header.
    let close: () -> Void

    /// Označit jako uhrazenou, or Upravit platbu for an invoice that has a payment: both open the sheet of the payment.
    let pay: () -> Void

    /// Vystavit, for a draft: issues it in one click, as "Vystavit fakturu" in the editor would, without the editor.
    let issue: () -> Void

    /// Upravit.
    let edit: () -> Void

    /// Zobrazit PDF.
    let showPDF: () -> Void

    /// Smazat fakturu….
    let delete: () -> Void

    var body: some View {
        DetailPanel(
            title: detail.number, pill: (text: detail.statusLabel, tone: detail.status.pillTone), close: close,
            scrolls: true
        ) {
            actions
        } content: {
            if let issueProblem {
                Note(.error, icon: .info, text: issueProblem)
            }
            figure
            DetailFacts(detail.facts)
            if let payment = detail.payment {
                PaymentSection(payment: payment)
            }
            if let estimate = detail.estimate {
                Note(.attention, icon: .info, text: estimate)
            }
            if let review = detail.reviewNote {
                Note(.attention, icon: .warning, text: review)
            }
            deletion
        }
        .frame(width: DetailPanelMetrics.width)
        .accessibilityLabel("Detail faktury")
    }

    // MARK: Parts

    /// The buttons under the header, the main one in the accent: Označit jako uhrazenou for an invoice that waits for
    /// its payment, or Vystavit for a draft, off while the draft is being issued, then Upravit where the invoice can be
    /// edited, or Upravit platbu where it has a payment that can be changed, and Zobrazit PDF always. A button that
    /// does not apply is not there.
    @ViewBuilder
    private var actions: some View {
        if detail.canPay {
            button("Označit jako uhrazenou", .primary, action: pay)
        }
        if detail.canIssue {
            button("Vystavit", .primary, action: issue)
                .disabled(isIssuing)
        }
        if detail.canEdit {
            button("Upravit", .secondary, action: edit)
        }
        if detail.canEditPayment {
            button("Upravit platbu", .secondary, action: pay)
        }
        button("Zobrazit PDF", .secondary, action: showPDF)
    }

    /// A button of a kind of the design, 28 points high as the buttons inside a card are.
    private func button(
        _ title: LocalizedStringKey, _ kind: CapsuleButtonKind, action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(CapsuleButtonStyle(kind, size: .small))
    }

    /// The client, the amount with VAT in big rounded numerals, and a line for each item.
    private var figure: some View {
        DetailFigure(
            label: detail.client, figure: detail.total,
            context: detail.itemLines.isEmpty ? nil : detail.itemLines.joined(separator: "\n"))
    }

    /// The way into deleting the invoice, under a hairline at the end of the card, a red capsule that asks first.
    private var deletion: some View {
        DetailSection {
            Button(role: .destructive, action: delete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .accessibilityHidden(true)
                    Text("Smazat fakturu…")
                }
            }
            .buttonStyle(CapsuleButtonStyle(.destructive, size: .small))
        }
    }
}

// MARK: - The payment

/// "Platba": the day and the amount received, the income in crowns and how it was converted, and in the same box on
/// the inset background, under a rule, what the payment leaves of it after the levies ("Čistý příjem"); under the box
/// a line that says so when the payment is dated after today, and then the levies the payment adds to. The row of the
/// net income is there exactly when the levies are.
private struct PaymentSection: View {
    let payment: PaymentDetail

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.cardSpacing) {
            DetailSection(label: "Platba") {
                Text("Platba")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                box
                if let later = payment.laterNote {
                    Text(verbatim: later)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.orangeText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let effect = payment.effect {
                EffectSection(effect: effect)
            }
        }
    }

    /// The box on the inset background that VoiceOver reads as one phrase: the payment and the income, and under a rule
    /// across the box the net income, when the levies are known. The right column, as wide as its widest cell, is
    /// aligned to the right: the amounts and the words in it end at one edge.
    private var box: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(verbatim: payment.line)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: payment.crowns)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .fixedSize()
                    .gridColumnAlignment(.trailing)
            }
            GridRow {
                Text(verbatim: payment.note)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("příjem pro daň")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize()
            }
            if let netIncome = payment.netIncome {
                Rectangle()
                    .fill(Palette.fill)
                    .frame(height: 1)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
                GridRow {
                    Text("Čistý příjem")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.text)
                    Text(verbatim: netIncome)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.greenText)
                        .fixedSize()
                }
            }
        }
        .monospacedDigit()
        .insetPanel(horizontal: 12, vertical: 10)
        .accessibilityElement(children: .combine)
    }
}

/// "Dopad na odvody 2026": what the payment adds to each authority, and what share of the income that is.
private struct EffectSection: View {
    let effect: LevyEffectDetail

    var body: some View {
        DetailSection(spacing: 10, label: "Dopad na odvody") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: effect.heading)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text(verbatim: effect.total)
                    .font(Typography.bodyBold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.orangeText)
            }
            VStack(spacing: 6) {
                ForEach(effect.rows) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(row.authority.color)
                            .frame(width: 8, height: 8)
                            .frame(width: 10, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(verbatim: row.title)
                            .font(Typography.body)
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 4)
                        Text(verbatim: row.value)
                            .font(Typography.body)
                            .foregroundStyle(Palette.text)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(verbatim: effect.note)
                .font(Typography.callout)
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
