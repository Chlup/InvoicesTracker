import SwiftUI

/// The detail of one invoice, in a card of the page at the right of the table: its number and status, the buttons for
/// what can be done with it, the client, the amount, the dates, the VAT and the ČNB rate of the DUZP, the payment with
/// what it leaves after the levies and what it adds to the levies of its year (or what a payment would add and leave),
/// and Smazat fakturu…. The card is `width` points wide and as tall as the room it is given, and what does not fit in
/// it scrolls.
struct InvoiceDetailCard: View {
    /// The width of the card.
    static let width: CGFloat = 320

    let detail: InvoiceDetail

    /// The × of the header.
    let close: () -> Void

    /// Označit jako uhrazenou, or Upravit platbu for an invoice that has a payment: both open the sheet of the payment.
    let pay: () -> Void

    /// Vystavit, for a draft: opens the editor on it, where "Vystavit fakturu" issues it.
    let issue: () -> Void

    /// Upravit.
    let edit: () -> Void

    /// Zobrazit PDF.
    let showPDF: () -> Void

    /// Smazat fakturu….
    let delete: () -> Void

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .screenCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detail faktury")
    }

    /// Everything the detail shows, which the scroll view holds.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summary
            facts
            if let payment = detail.payment {
                PaymentSection(payment: payment)
            }
            if let estimate = detail.estimate {
                NoteBox(symbol: "info.circle", text: estimate)
            }
            if let review = detail.reviewNote {
                NoteBox(symbol: "exclamationmark.triangle", text: review)
            }
            Divider()
            Button(role: .destructive, action: delete) {
                Label("Smazat fakturu…", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Parts

    /// The number, the status and the ×, and under them the buttons.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: detail.number)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                StatusPill(status: detail.status, label: detail.statusLabel)
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zavřít detail")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    payButton
                    issueButton
                    editButton
                    pdfButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    payButton
                    issueButton
                    HStack(spacing: 6) {
                        editButton
                        pdfButton
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var payButton: some View {
        if detail.canPay {
            Button("Označit jako uhrazenou", action: pay)
                .buttonStyle(.borderedProminent)
        } else if detail.canEditPayment {
            Button("Upravit platbu", action: pay)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var issueButton: some View {
        if detail.canIssue {
            Button("Vystavit", action: issue)
                .buttonStyle(.borderedProminent)
        }
    }

    /// Upravit, which is off for a paid invoice: only its payment can be changed then (Upravit platbu).
    private var editButton: some View {
        Button("Upravit", action: edit)
            .buttonStyle(.bordered)
            .disabled(!detail.canEdit)
            .help(Text(detail.canEdit ? "" : "Uhrazená faktura se nedá upravit, jen její platba."))
    }

    private var pdfButton: some View {
        Button("Zobrazit PDF", action: showPDF)
            .buttonStyle(.bordered)
    }

    /// The client, the amount with VAT in big rounded numerals, and a line for each item.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: detail.client)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(verbatim: detail.total)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ForEach(Array(detail.itemLines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(detail.facts, id: \.label) { fact in
                GridRow {
                    Text(fact.label)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: fact.value)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = fact.note {
                            Text(verbatim: note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - The payment

/// "Platba": the day and the amount received, the income in crowns and how it was converted, and in the same grey box
/// under a divider what the payment leaves of it after the levies ("Čistý příjem"), then under the box the levies the
/// payment adds to. The row of the net income is there exactly when the levies are.
private struct PaymentSection: View {
    let payment: PaymentDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("Platba")
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 6)
                box
                if let later = payment.laterNote {
                    Text(later)
                        .font(.callout)
                        .foregroundStyle(Color(.attentionText))
                }
            }
            if let effect = payment.effect {
                EffectSection(effect: effect)
            }
        }
    }

    /// The grey box that VoiceOver reads as one phrase: the payment and the income, and under a divider across the box
    /// the net income, when the levies are known.
    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: payment.line)
                        .fontWeight(.semibold)
                    Text(verbatim: payment.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: payment.crowns)
                        .fontWeight(.semibold)
                    Text("příjem pro daň")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            if let netIncome = payment.netIncome {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Čistý příjem")
                        .fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Text(verbatim: netIncome)
                        .fontWeight(.bold)
                        .foregroundStyle(Color(.bannerText))
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// "Dopad na odvody 2026": what the payment adds to each authority, and what share of the income that is.
private struct EffectSection: View {
    let effect: LevyEffectDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: effect.heading)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text(verbatim: effect.total)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(Color(.attentionText))
            }
            .padding(.top, 6)
            VStack(spacing: 6) {
                ForEach(effect.rows) { row in
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
            Text(verbatim: effect.note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A sentence in an orange box with a symbol: what a payment would add to the levies and what it would leave, or why an
/// invoice is to check.
private struct NoteBox: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
