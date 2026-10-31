import SwiftUI

/// The colour tokens of the design. Each one is a colorset in the asset catalog under `Token<Name>` with a value for a
/// light and for a dark window, so a view takes its colours from here and the appearance of the window changes them.
/// Like the asset catalog's colours, they are on the main actor.
enum Palette {
    // MARK: Text

    /// The colour of text and of the icons that stand for it: titles, figures and the content of rows.
    static var text: Color { Color(.tokenText) }

    /// The colour of secondary text, such as the eyebrow over a card.
    static var text2: Color { Color(.tokenText2) }

    /// The colour of notes and captions under a figure or a field.
    static var text3: Color { Color(.tokenText3) }

    /// The faintest colour of text, for example for the dash that stands for a missing value.
    static var text4: Color { Color(.tokenText4) }

    /// The colour of text and icons on a filled accent, which is white in a light and in a dark window.
    static var onAccent: Color { Color(.tokenOnAccent) }

    // MARK: Backgrounds and lines

    /// The background of the window.
    static var bgWindow: Color { Color(.tokenBgWindow) }

    /// The background of the sidebar.
    static var bgSidebar: Color { Color(.tokenBgSidebar) }

    /// The background of a card.
    static var bgCard: Color { Color(.tokenBgCard) }

    /// The background of an inner panel, such as a menu, a bubble or a note inside a card.
    static var bgInset: Color { Color(.tokenBgInset) }

    /// The fill of a button that has no accent, and the track of a bar.
    static var fill: Color { Color(.tokenFill) }

    /// A translucent fill that is stronger than `fill` and lets what lies under it show through.
    static var fillStrong: Color { Color(.tokenFillStrong) }

    /// The hairline between rows and around a card.
    static var sep: Color { Color(.tokenSep) }

    /// The stronger line around a field and above the total of a bill.
    static var sepStrong: Color { Color(.tokenSepStrong) }

    // MARK: Accent

    /// The blue of actions, of what is selected and of information.
    static var accent: Color { Color(.tokenAccent) }

    /// The blue of links and of other text in blue.
    static var accentText: Color { Color(.tokenAccentText) }

    /// The pale blue behind an information note and a selected row.
    static var accentTint: Color { Color(.tokenAccentTint) }

    /// The light blue of the edge of an accent tint, and of the accent where it is switched off.
    static var accentSoft: Color { Color(.tokenAccentSoft) }

    // MARK: Status

    /// The green of what is paid and of the person's own money, such as the net income.
    static var green: Color { Color(.tokenGreen) }

    /// The green of text on a card or on the pale green.
    static var greenText: Color { Color(.tokenGreenText) }

    /// The pale green behind a success note and a paid pill.
    static var greenTint: Color { Color(.tokenGreenTint) }

    /// The orange of an estimate and of what needs attention.
    static var orange: Color { Color(.tokenOrange) }

    /// The orange of text on a card or on the pale orange.
    static var orangeText: Color { Color(.tokenOrangeText) }

    /// The pale orange behind an estimate note and a warning.
    static var orangeTint: Color { Color(.tokenOrangeTint) }

    /// The red of what is overdue and of an error.
    static var red: Color { Color(.tokenRed) }

    /// The red of text on a card or on the pale red.
    static var redText: Color { Color(.tokenRedText) }

    /// The pale red behind an overdue pill and an error note.
    static var redTint: Color { Color(.tokenRedTint) }

    // MARK: Authorities

    /// The indigo of the income tax.
    static var tax: Color { Color(.tokenTax) }

    /// The teal of the social insurance.
    static var social: Color { Color(.tokenSocial) }

    /// The raspberry of the health insurance.
    static var health: Color { Color(.tokenHealth) }

    /// The pale indigo behind the income tax, in a pill or a row.
    static var taxTint: Color { Color(.tokenTaxTint) }

    /// The pale teal behind the social insurance, in a pill or a row.
    static var socialTint: Color { Color(.tokenSocialTint) }

    /// The pale raspberry behind the health insurance, in a pill or a row.
    static var healthTint: Color { Color(.tokenHealthTint) }

    // MARK: Marks

    /// The marker behind the part of a text that a search found.
    static var highlight: Color { Color(.tokenHighlight) }

    /// The stripe of the hatching that marks an estimate in a chart and in a bar.
    static var hatchStripe: Color { Color(.tokenHatchStripe) }

    /// The ground between the stripes of the hatching that marks an estimate.
    static var hatchGround: Color { Color(.tokenHatchGround) }
}

/// The fonts of the design. Apart from the display size they are the text styles of macOS, so they follow the system's
/// sizes, and a view takes its font from here and never sets a point size of its own.
nonisolated enum Typography {
    /// The key figure of a screen: 44 points, bold and rounded. It is the one size in this enum that is set in
    /// points.
    static let display = Font.system(size: 44, weight: .bold, design: .rounded)

    /// The large title style (26 points), bold and rounded, for a big figure such as a percentage.
    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// The title style (22 points), bold, for the title of a page.
    static let title = Font.title.bold()

    /// The title 2 style (17 points), bold, for a figure in a tile.
    static let title2 = Font.title2.bold()

    /// The title 3 style (15 points), semibold, for the heading of a card.
    static let title3 = Font.title3.weight(.semibold)

    /// The title 3 style, bold, for a total in the summary of a table.
    static let title3Bold = Font.title3.bold()

    /// The headline style (13 points), semibold, for the name of a row.
    static let headline = Font.headline.weight(.semibold)

    /// The body style (13 points), for running text and the content of rows.
    static let body = Font.body

    /// The body style, semibold, for the text of a button and for what stands out in a row.
    static let bodySemibold = Font.body.weight(.semibold)

    /// The body style, bold, for the name at the top of a popover, such as the authority in the popover of the levy
    /// bar.
    static let bodyBold = Font.body.bold()

    /// The callout style (12 points), for the line of detail under a figure.
    static let callout = Font.callout

    /// The callout style, semibold, for a short label in a card.
    static let calloutSemibold = Font.callout.weight(.semibold)

    /// The callout style in a monospaced design, for text that is set in rows of fixed width, such as the text of a
    /// licence.
    static let calloutMonospaced = Font.system(.callout, design: .monospaced)

    /// The subheadline style (11 points), for small print such as a share of the income.
    static let subheadline = Font.subheadline

    /// The subheadline style, semibold, for an eyebrow and for the small text of a pill.
    static let subheadlineSemibold = Font.subheadline.weight(.semibold)

    /// The subheadline style, bold, for the number in the circle of a step.
    static let subheadlineBold = Font.subheadline.bold()

    /// The title 2 style (17 points) in a monospaced design, semibold, for the groups of characters of a recovery
    /// code.
    static let title2Monospaced = Font.system(.title2, design: .monospaced).weight(.semibold)

    /// The body style in a monospaced design, for the field where a recovery code is typed.
    static let bodyMonospaced = Font.system(.body, design: .monospaced)

    // MARK: Symbols

    /// A symbol that stands alone in a circle or a tile of 56 to 64 points, such as the lock: the large title style
    /// (26 points), regular. Where the design draws it larger, the view adds `.imageScale(.large)`.
    static let symbolLarge = Font.largeTitle

    /// A symbol on a drop zone: the large title style, light.
    static let symbolLight = Font.largeTitle.weight(.light)

    /// A symbol in a circle of 44 points, such as the key over the field of a recovery code: the title style
    /// (22 points), regular.
    static let symbolMedium = Font.title

    /// A symbol in the circle of a choice on a card: the title 2 style (17 points), semibold.
    static let symbolSmall = Font.title2.weight(.semibold)
}

/// The radii, spacings and heights of the design, in points, on its grid of 4. They are named `DesignMetrics` because
/// the invoice document keeps a file-private `Metrics` of its own, which a type of that name here would clash with.
nonisolated enum DesignMetrics {
    /// The corner radius of a card, a window and a dialog.
    static let cardRadius: CGFloat = 16

    /// The corner radius of an inner panel and of a note.
    static let panelRadius: CGFloat = 10

    /// The corner radius of a field, a menu and a cell.
    static let controlRadius: CGFloat = 6

    /// The space between the edge of a card and its content.
    static let cardPadding: CGFloat = 20

    /// The space between two cards.
    static let cardSpacing: CGFloat = 16

    /// The space between the parts inside a card.
    static let innerSpacing: CGFloat = 12

    /// The space between the leading edge of the window and the content of a page.
    static let pageLeading: CGFloat = 24

    /// The space between the trailing edge of the window and the content of a page.
    static let pageTrailing: CGFloat = 16

    /// The space between the top of the window and the content of a page.
    static let pageTop: CGFloat = 16

    /// The space between the bottom of the window and the content of a page.
    static let pageBottom: CGFloat = 24

    /// The height of a button for a page or the toolbar.
    static let regularControlHeight: CGFloat = 32

    /// The height of a button inside a card, of a segment and of a filter.
    static let smallControlHeight: CGFloat = 28
}

extension View {
    /// Sets the text of the view as an eyebrow, the small label over a card or a group of figures: the subheadline in
    /// semibold, in capitals with a little space between the letters, in the grey of secondary text.
    func eyebrow() -> some View {
        font(Typography.subheadlineSemibold)
            .textCase(.uppercase)
            .tracking(0.66)
            .foregroundStyle(Palette.text2)
    }
}
