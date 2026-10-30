import SwiftUI

/// An invoice as a printed page: A4, black on white whatever the appearance of the Mac, set in IBM Plex Sans. It is the
/// preview in the app as well as the page of the PDF. The lines come from `InvoiceDocument.text`; this view only lays
/// them out.
///
/// Lengths are written as in the layout, in CSS pixels of a page 794 wide, and `Metrics` brings them to points. A page
/// is laid out at full size first. If the items and the note are too many for it, the same page is laid out again a
/// little smaller, step by step, and the first size at which everything fits is the one drawn.
///
/// Only the note gives way. Everything else is set at the height it asks for, and a note that is too long even for the
/// smallest size, 70 %, is cut with an ellipsis. An invoice whose other parts are too long for the page at that size
/// runs off the bottom of it: `InvoicePDFRenderer.fitsOnOnePage` tells beforehand whether an invoice does.
struct InvoiceDocumentView: View {
    let document: InvoiceDocument

    @Environment(\.displayScale) private var displayScale

    /// The page is laid out on a grid of an eighth of a point when it is made into a PDF. At the renderer's own scale
    /// of 1 every edge would snap to a whole point: a rule of three quarters of a point would become one of a whole
    /// point or, where it falls between two points, vanish. The PDF stays in points, so this only decides how finely
    /// the layout is placed.
    static let gridDensity: CGFloat = 8

    /// The empty border of the page, in points. It is the same at every size.
    private static let margins = EdgeInsets(top: 30, leading: 27, bottom: 25.5, trailing: 27)

    /// The width between the margins, in points.
    fileprivate static let contentWidth = PageSize.a4.width - margins.leading - margins.trailing

    /// The size of the content that the page is laid out at, as a share of its full size, from the largest.
    private static let scales: [CGFloat] = [1, 0.94, 0.88, 0.82, 0.76, 0.7]

    /// How many pixels of the QR code are drawn for each of its modules. The picture is a bitmap, and this many pixels
    /// keep its edges sharp when it is printed.
    private static let qrModuleSize: CGFloat = 10

    var body: some View {
        let text = document.text
        let qrImage = Self.qrImage(of: text)
        ViewThatFits(in: .vertical) {
            ForEach(Self.scales, id: \.self) { scale in
                Self.page(text: text, qrImage: qrImage, scale: scale, deviceScale: displayScale)
            }
        }
        .frame(width: PageSize.a4.width, height: PageSize.a4.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// The largest of the sizes the page is set at (1 is full size) at which all of `document` fits it, the note
    /// included, or nil when it fits at none of them. It measures the pages that `body` chooses between, laid out the
    /// way a PDF is, so it says which of them the PDF is made of: the one at this size, or for nil the smallest, which
    /// does not hold the whole document.
    static func fittingScale(for document: InvoiceDocument) -> CGFloat? {
        let text = document.text
        let qrImage = qrImage(of: text)
        return scales.first { scale in
            idealHeight(of: page(text: text, qrImage: qrImage, scale: scale, deviceScale: gridDensity))
                <= PageSize.a4.height
        }
    }

    private static func qrImage(of text: InvoiceDocumentText) -> CGImage? {
        text.qr.flatMap { QRImage.make($0.payload, moduleSize: qrModuleSize) }
    }

    /// The page set at `scale`, inside its margins.
    private static func page(
        text: InvoiceDocumentText, qrImage: CGImage?, scale: CGFloat, deviceScale: CGFloat
    ) -> some View {
        InvoicePage(text: text, qrImage: qrImage, metrics: Metrics(scale: scale, deviceScale: deviceScale))
            .padding(margins)
    }

    /// The height `page` asks for when it is as wide as the paper, as a PDF would lay it out.
    private static func idealHeight(of page: some View) -> CGFloat {
        let renderer = ImageRenderer(content: page.frame(width: PageSize.a4.width))
        renderer.scale = gridDensity
        var height = CGFloat.infinity
        renderer.render { size, _ in
            height = size.height
        }
        return height
    }
}

// MARK: - Measures

/// The lengths of the layout. Its pixels are those of a CSS page 794 wide, which is an A4 page at 96 dots per inch, so
/// a pixel is three quarters of a point, and `scale` makes the whole content smaller than that.
private struct Metrics {
    let scale: CGFloat

    /// How many device pixels there are to the point where the page is drawn: 2 on a Retina display, 8 for a PDF.
    let deviceScale: CGFloat

    private static let pointsPerPixel: CGFloat = 0.75

    func px(_ pixels: CGFloat) -> CGFloat {
        pixels * Self.pointsPerPixel * scale
    }

    /// The thickness of a rule that is `pixels` thick in the layout, but at least one device pixel, so that a thin rule
    /// of a small page does not vanish on a display that has no pixels to spare.
    func rule(_ pixels: CGFloat) -> CGFloat {
        max(px(pixels), 1 / deviceScale)
    }

    /// The two columns of the parties: 355 pixels and a gap of 55 out of the 722 of the layout. They are shares of the
    /// width between the margins rather than lengths that follow `scale`, so that the heading and the customer stay
    /// where they are however small the content is set.
    var leftColumn: CGFloat {
        InvoiceDocumentView.contentWidth * 355 / 722
    }

    var columnGap: CGFloat {
        InvoiceDocumentView.contentWidth * 55 / 722
    }
}

/// The colours of the page, which are its own and do not follow the appearance of the Mac.
private enum Ink {
    static let text = Color(.sRGB, white: 0x1F / 255, opacity: 1)
    static let muted = Color(.sRGB, white: 0x5C / 255, opacity: 1)
    static let total = Color(.sRGB, white: 0x4A / 255, opacity: 1)
    static let footer = Color(.sRGB, white: 0x3A / 255, opacity: 1)
    static let rule = Color(.sRGB, white: 0xBD / 255, opacity: 1)
}

/// How a piece of text is set: the face, the size in pixels, the colour, the line height as a multiple of the size and
/// the letter spacing as a multiple of the size.
private struct TextStyle {
    var face = InvoiceFonts.regular
    var size: CGFloat = 13
    var color = Ink.text
    var lineHeight: CGFloat = 1.5
    var spacing: CGFloat = 0

    static let body = TextStyle()
    static let muted = TextStyle(color: Ink.muted)
    static let label = TextStyle(size: 12, color: Ink.muted)
    static let small = TextStyle(size: 11, color: Ink.muted)
    static let partyName = TextStyle(face: InvoiceFonts.bold, size: 14)
    static let title = TextStyle(face: InvoiceFonts.bold, size: 25, lineHeight: naturalLineHeight)
    static let subtitle = TextStyle(size: 12, color: Ink.muted, spacing: 0.02)
    static let total = TextStyle(face: InvoiceFonts.bold, size: 22, color: Ink.total)
    static let qrLabel = TextStyle(face: InvoiceFonts.bold, size: 11, spacing: 0.02)
    static let footer = TextStyle(size: 11, color: Ink.footer, lineHeight: 1.55)

    /// The height of a line of IBM Plex Sans as a multiple of its size: its ascent and descent, which are 1,025 and
    /// 0,275 em, and no leading.
    static let naturalLineHeight: CGFloat = 1.3
}

private extension View {
    /// The view, a text, set in `style`. A line is as high as the line height of the style asks for: the space it adds
    /// to the natural line height of the face goes between the lines of a text of several, and half of it above and
    /// half below, so that a text of any number of lines is as high as lines of that height would be.
    func printed(_ style: TextStyle, _ metrics: Metrics) -> some View {
        let size = metrics.px(style.size)
        let extra = max(0, size * (style.lineHeight - TextStyle.naturalLineHeight))
        return font(.custom(style.face, fixedSize: size))
            .foregroundStyle(style.color)
            .tracking(size * style.spacing)
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}

// MARK: - The page

/// The page at one size: the heading, the two parties with the payment and the dates, the items, the summary with the
/// QR code, and at the bottom the note and the legal line.
private struct InvoicePage: View {
    let text: InvoiceDocumentText
    let qrImage: CGImage?
    let metrics: Metrics

    private var labels: InvoiceLabels {
        text.labels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .fixedSize(horizontal: false, vertical: true)
            parties
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, metrics.px(36))
            items
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, metrics.px(40))
            summaryRow
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, metrics.px(34))
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Heading

    /// The dark rule with "Faktura" and the number under it, and "DAŇOVÝ DOKLAD", over the column of the customer.
    private var heading: some View {
        TwoColumns(metrics: metrics) {
            Color.clear
                .frame(height: 0)
        } right: {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Ink.muted)
                    .frame(height: metrics.rule(4))
                    .accessibilityHidden(true)
                title
                    .padding(.top, metrics.px(14))
                Text(labels.subtitle)
                    .printed(.subtitle, metrics)
                    .padding(.top, metrics.px(8))
            }
        }
    }

    /// "Faktura 20260902", the number in grey. It is one text, so it reads and copies as one line.
    private var title: some View {
        var number = AttributedString(text.number)
        number.foregroundColor = Ink.muted
        return Text(AttributedString(labels.document + " ") + number)
            .printed(.title, metrics)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    // MARK: Parties

    private var parties: some View {
        VStack(alignment: .leading, spacing: metrics.px(18)) {
            TwoColumns(metrics: metrics) {
                PartyBlock(label: labels.supplier, party: text.supplier, metrics: metrics)
            } right: {
                PartyBlock(label: labels.customer, party: text.customer, metrics: metrics)
            }
            if !text.supplier.identifiers.isEmpty || !text.customer.identifiers.isEmpty {
                TwoColumns(metrics: metrics) {
                    FieldRows(fields: text.supplier.identifiers, metrics: metrics)
                } right: {
                    FieldRows(fields: text.customer.identifiers, metrics: metrics)
                }
            }
            TwoColumns(metrics: metrics) {
                FieldRows(fields: text.paymentRows, metrics: metrics)
            } right: {
                FieldRows(fields: text.dateRows, metrics: metrics)
            }
        }
    }

    // MARK: Items

    /// The items as a table: the columns take the width of their widest line, the description takes the rest. The heads
    /// of the first three columns are empty, as in the layout, and are given to assistive technology.
    private var items: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.clear
                    .frame(width: metrics.px(38), height: 0)
                    .accessibilityLabel(labels.quantityHeader)
                Color.clear
                    .frame(width: metrics.px(44), height: 0)
                    .accessibilityLabel(labels.unitHeader)
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
                    .accessibilityLabel(labels.descriptionHeader)
                columnHead(labels.vat, minimumWidth: 80)
                columnHead(labels.unitPrice, minimumWidth: 123)
                columnHead(labels.totalWithoutVAT, minimumWidth: 142)
            }
            rule
            ForEach(Array(text.items.enumerated()), id: \.offset) { _, item in
                GridRow {
                    cell(item.quantity, gap: .trailing)
                    cell(item.unit, gap: .trailing)
                    cell(item.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cell(item.vatRate, gap: .leading)
                    cell(item.unitPrice, gap: .leading)
                    cell(item.amount, gap: .leading)
                }
                rule
            }
        }
    }

    /// A head of a numeric column, right-aligned. The column is at least `minimumWidth` pixels wide, and its widest
    /// line keeps a gap from the column before it.
    private func columnHead(_ title: String, minimumWidth: CGFloat) -> some View {
        Text(title)
            .printed(.small, metrics)
            .padding(.leading, metrics.px(8))
            .frame(minWidth: metrics.px(minimumWidth), alignment: .trailing)
            .padding(.bottom, metrics.px(6))
            .gridColumnAlignment(.trailing)
    }

    /// A cell of an item. The layout gives the columns a width and no space between them, so a line wider than its
    /// column would touch its neighbour; `gap` keeps a few pixels of space on the side that faces the neighbour, inside
    /// the width the layout gives.
    private func cell(_ value: String, gap: Edge.Set = []) -> some View {
        Text(value)
            .printed(.body, metrics)
            .padding(gap, metrics.px(8))
            .padding(.vertical, metrics.px(8))
    }

    private var rule: some View {
        Rectangle()
            .fill(Ink.rule)
            .frame(height: metrics.rule(1))
            .gridCellColumns(6)
            .gridCellUnsizedAxes(.horizontal)
            .accessibilityHidden(true)
    }

    // MARK: Summary

    /// The QR code on the left, if there is one, and the VAT summary on the right.
    private var summaryRow: some View {
        HStack(alignment: .top, spacing: metrics.px(24)) {
            if let qrImage, let qr = text.qr {
                qrCode(qrImage, label: qr.label)
            }
            Spacer(minLength: 0)
            summary
                .frame(width: metrics.px(text.summary.baseInCrowns == nil ? 362 : 470))
        }
    }

    private func qrCode(_ image: CGImage, label: String) -> some View {
        VStack(alignment: .leading, spacing: metrics.px(4)) {
            Image(image, scale: 1, label: Text(label))
                .interpolation(.none)
                .resizable()
                .frame(width: metrics.px(112), height: metrics.px(112))
            Text(label)
                .printed(.qrLabel, metrics)
                .padding(.leading, metrics.px(8))
                .accessibilityHidden(true)
        }
    }

    /// The rate, the base and the VAT over a thick rule, and the total under it. A foreign currency has its equivalent
    /// in crowns under the base and under the VAT.
    private var summary: some View {
        let summary = text.summary
        return VStack(alignment: .leading, spacing: 0) {
            summaryColumns(
                Text(labels.vatRate).printed(.small, metrics),
                Text(labels.vatBase).printed(.small, metrics),
                Text(labels.vat).printed(.small, metrics)
            )
            .padding(.bottom, metrics.px(6))
            summaryColumns(
                Text(summary.vatRate).printed(.body, metrics),
                amount(summary.base, inCrowns: summary.baseInCrowns),
                amount(summary.vat, inCrowns: summary.vatInCrowns)
            )
            .padding(.bottom, metrics.px(8))
            Rectangle()
                .fill(Ink.muted)
                .frame(height: metrics.rule(3))
                .accessibilityHidden(true)
            Text(summary.total)
                .printed(.total, metrics)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, metrics.px(8))
        }
    }

    /// Three columns: the rate takes what the other two leave, the base is 150 pixels wide and the VAT 130.
    private func summaryColumns<First: View, Second: View, Third: View>(
        _ first: First, _ second: Second, _ third: Third
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            first
                .frame(maxWidth: .infinity, alignment: .leading)
            second
                .frame(width: metrics.px(150), alignment: .trailing)
            third
                .frame(width: metrics.px(130), alignment: .trailing)
        }
    }

    private func amount(_ value: String, inCrowns crowns: String?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .printed(.body, metrics)
            if let crowns {
                Text(crowns)
                    .printed(.small, metrics)
            }
        }
    }

    // MARK: Footer

    /// The note with its line breaks, and under it the legal line of a Czech invoice.
    private var footer: some View {
        VStack(alignment: .leading, spacing: metrics.px(12)) {
            if let note = text.note {
                Text(note)
                    .printed(.footer, metrics)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let legalFooter = text.legalFooter {
                Text(legalFooter)
                    .printed(.footer, metrics)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Blocks

/// Two columns side by side as the layout has them: a left one 355 pixels wide, a gap of 55, and a right one that takes
/// the rest.
private struct TwoColumns<Left: View, Right: View>: View {
    let metrics: Metrics
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        HStack(alignment: .top, spacing: metrics.columnGap) {
            left
                .frame(width: metrics.leftColumn, alignment: .topLeading)
            right
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// The supplier or the customer: a short rule, the head of the block, the name and the lines of the address.
private struct PartyBlock: View {
    let label: String
    let party: InvoiceDocumentText.Party
    let metrics: Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Ink.text)
                .frame(width: metrics.px(16), height: metrics.rule(1.5))
                .accessibilityHidden(true)
            Text(label)
                .printed(.label, metrics)
                .padding(.top, metrics.px(10))
            Text(party.name)
                .printed(.partyName, metrics)
                .padding(.top, metrics.px(16))
            ForEach(Array(party.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .printed(.muted, metrics)
            }
        }
    }
}

/// Labels with their values: the label on the left, the value on the right, wrapping if it is long.
private struct FieldRows: View {
    let fields: [InvoiceField]
    let metrics: Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.px(1)) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .firstTextBaseline, spacing: metrics.px(12)) {
                    Text(field.label)
                        .printed(.muted, metrics)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text(field.value)
                        .printed(.body, metrics)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
