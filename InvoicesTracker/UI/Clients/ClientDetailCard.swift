import SwiftUI

/// The detail of one client, in the panel of the page at the right of the table of Odběratelé (`DetailPanel`): its name
/// in the header and under it Nová faktura, which starts an invoice for the client, and Upravit, which opens the form
/// of the client; then what the client paid in the year, with the invoices it was issued in it; the facts that new
/// invoices for it start from; and, under a hairline, "Šablony faktur" with Nová šablona and a panel for each template
/// of the client, or the sentence that says what a template does where it has none. The words and the numbers are the
/// builder's (`ClientDetail`); the card only shows them.
///
/// The card is as wide as a detail panel (`DetailPanelMetrics.width`) and as high as its content, or as the room it is
/// given where that is less, and what does not fit in it then scrolls. Nová faktura is read by VoiceOver with the name
/// of the client, as the toolbar has a Nová faktura of its own, and the buttons of a template with its name, as every
/// template has the same two.
struct ClientDetailCard: View {
    let detail: ClientDetail

    /// The ✕ of the header.
    let close: () -> Void

    /// Nová faktura: a blank invoice for the client.
    let newInvoice: () -> Void

    /// Upravit: the form of the client.
    let edit: () -> Void

    /// Nová šablona: the form of a new template for the client.
    let newTemplate: () -> Void

    /// Vystavit podle šablony, with the id of the template: an invoice made from it.
    let useTemplate: (Int64) -> Void

    /// Upravit of a template, with its id: the form of the template.
    let editTemplate: (Int64) -> Void

    var body: some View {
        DetailPanel(title: detail.name, pill: nil, close: close, scrolls: true) {
            Button("Nová faktura", action: newInvoice)
                .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
                .accessibilityLabel(Text(verbatim: "Nová faktura pro \(detail.name)"))
            Button("Upravit", action: edit)
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        } content: {
            DetailFigure(
                label: detail.figureLabel, figure: detail.figure, context: detail.context,
                figureIsMuted: !detail.hasReceived)
            DetailFacts(detail.facts)
            templates
        }
        .frame(width: DetailPanelMetrics.width)
        .accessibilityLabel("Detail odběratele")
    }

    /// "Šablony faktur" under a hairline, with Nová šablona, a link with a plus, at the trailing end of its line; under
    /// them a panel for each template, or what a template does where the client has none. VoiceOver reads the part as a
    /// group under its heading.
    private var templates: some View {
        DetailSection {
            HStack(alignment: .firstTextBaseline, spacing: ClientDetailMetrics.headingGap) {
                Text("Šablony faktur")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: newTemplate) {
                    HStack(spacing: ClientDetailMetrics.iconGap) {
                        Image(systemName: "plus")
                            .accessibilityHidden(true)
                        Text("Nová šablona")
                    }
                }
                .buttonStyle(TextLinkButtonStyle(.accent))
                .font(Typography.calloutSemibold)
            }
            ForEach(detail.templates) { panel in
                TemplatePanelView(panel: panel, use: { useTemplate(panel.id) }, edit: { editTemplate(panel.id) })
            }
            if detail.templates.isEmpty {
                Text(verbatim: detail.emptyTemplatesText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Šablony faktur")
    }
}

/// The sizes of the parts of the detail of a client, in points, as the prototype draws them.
private nonisolated enum ClientDetailMetrics {
    /// The space between the heading "Šablony faktur" and Nová šablona, and between the name and the amount of a
    /// template.
    static let headingGap: CGFloat = 8

    /// The space between the plus of Nová šablona and its words.
    static let iconGap: CGFloat = 4

    /// The space between the lines of the panel of a template.
    static let panelLineSpacing: CGFloat = 4

    /// The space between the edges of the panel of a template and its content, at its sides and its top.
    static let panelPadding: CGFloat = 12

    /// The space between the bottom of the panel of a template and its buttons.
    static let panelBottomPadding: CGFloat = 10

    /// The space over the buttons of the panel of a template, on top of that between its lines.
    static let buttonsTopPadding: CGFloat = 6

    /// The space between the buttons of the panel of a template.
    static let buttonGap: CGFloat = 6
}

/// The panel of a template in the detail of its client, on the inset background with the radius of a panel: the name
/// and the amount on its first line, a line for each item in callout and secondary text, the options in callout and
/// tertiary text, and the buttons Vystavit podle šablony, in the accent, and Upravit, in the colour of a card raised
/// off the panel, both 28 points high.
private struct TemplatePanelView: View {
    let panel: TemplatePanel

    /// Vystavit podle šablony.
    let use: () -> Void

    /// Upravit.
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClientDetailMetrics.panelLineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: ClientDetailMetrics.headingGap) {
                Text(verbatim: panel.name)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(verbatim: panel.amount)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .fixedSize()
            }
            ForEach(panel.itemLines.indices, id: \.self) { index in
                Text(verbatim: panel.itemLines[index])
                    .font(Typography.callout)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: panel.options)
                .font(Typography.callout)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: ClientDetailMetrics.buttonGap) {
                Button("Vystavit podle šablony", action: use)
                    .buttonStyle(CapsuleButtonStyle(.primary, size: .small))
                    .accessibilityLabel(Text(verbatim: "Vystavit podle šablony \(panel.name)"))
                Button("Upravit", action: edit)
                    .buttonStyle(CapsuleButtonStyle(.onWindow, size: .small))
                    .accessibilityLabel(Text(verbatim: "Upravit šablonu \(panel.name)"))
            }
            .padding(.top, ClientDetailMetrics.buttonsTopPadding)
        }
        .padding(.horizontal, ClientDetailMetrics.panelPadding)
        .padding(.top, ClientDetailMetrics.panelPadding)
        .padding(.bottom, ClientDetailMetrics.panelBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bgInset, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
        .accessibilityElement(children: .contain)
    }
}
