import SwiftUI

/// The search field of Faktury, at the end of its filter row: a capsule 32 points high and 220 to 300 wide, with a
/// magnifier, the placeholder "Hledat ve fakturách" and, while there is text, a × that clears it ("Zrušit hledání").
/// Esc clears the text too while the field has the focus. The field takes the focus whenever `focusRequests` grows,
/// which is what Hledat (⌘F) does (`AppModel.focusSearch()`), and a click anywhere in the capsule puts the focus in it.
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Hledat ve fakturách", text: $text)
                .textFieldStyle(.plain)
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
        .frame(minWidth: 220, maxWidth: 300)
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .overlay {
            if isFocused {
                Capsule().strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
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

    /// The grey circle with a white ×: clears the search, and leaves the focus in the field to type another one.
    private var clearButton: some View {
        Button {
            text = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color(nsColor: .controlBackgroundColor))
                .frame(width: 18, height: 18)
                .background(Color(nsColor: .tertiaryLabelColor), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zrušit hledání")
    }
}
