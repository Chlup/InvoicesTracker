import SwiftUI

/// The search field of Faktury, at the end of its filter row: a capsule 32 points high and 170 to 280 wide, in the
/// colour of a card and raised off the page as a control, with a magnifier in the grey of notes, the placeholder
/// "Hledat ve fakturách" and, while there is text, a × that clears it ("Zrušit hledání"). Esc clears the text too while
/// the field has the focus. The field takes the focus whenever `focusRequests` grows, which is what Hledat (⌘F) does
/// (`AppModel.focusSearch()`), and a click anywhere in the capsule puts the focus in it. While it has the focus, a
/// ring of the soft accent lies around the capsule.
///
/// What is typed is the search of the app (`AppModel.searchText`): it stays until it is cleared, also across screens
/// and years. VoiceOver reads the field and the ×; the capsule around them is a group with no label of its own.
struct InvoiceSearchField: View {
    @Binding var text: String

    /// How many times the field has been asked for the focus (`AppModel.searchFocusRequests`).
    let focusRequests: Int

    @FocusState private var isFocused: Bool

    /// The identifier of the group that holds the field and the ×, which the tests find the capsule by.
    static let accessibilityID = "invoiceSearch"

    /// The least and the greatest width of the capsule, between which it takes the room its line leaves it.
    static let widths: ClosedRange<CGFloat> = 170...280

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(Typography.body.weight(.medium))
                .foregroundStyle(Palette.text3)
                .accessibilityHidden(true)
            TextField("Hledat ve fakturách", text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                // The ring around the capsule below is the field's: the system's would be a rectangle around it.
                .focusEffectDisabled()
                .autocorrectionDisabled()
                .accessibilityLabel("Hledat ve fakturách")
                .focused($isFocused)
                .onKeyPress(.escape) {
                    // With nothing to clear, Esc is left for whatever else answers it.
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
            if !text.isEmpty {
                clearButton
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minWidth: Self.widths.lowerBound, maxWidth: Self.widths.upperBound)
        .frame(height: DesignMetrics.regularControlHeight)
        .background {
            Capsule().surface(Palette.bgCard, elevation: .control)
        }
        .overlay {
            if isFocused {
                Capsule().strokeBorder(Palette.accentSoft, lineWidth: 3)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityID)
        .onChange(of: focusRequests) {
            isFocused = true
        }
    }

    /// The circle in the faintest grey with a × in the colour of the capsule: clears the search, and leaves the focus
    /// in the field to type another one.
    private var clearButton: some View {
        Button {
            text = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark")
                .font(Typography.subheadline.weight(.heavy))
                .imageScale(.small)
                .foregroundStyle(Palette.bgCard)
                .frame(width: 18, height: 18)
                .background(Palette.text4, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zrušit hledání")
    }
}
