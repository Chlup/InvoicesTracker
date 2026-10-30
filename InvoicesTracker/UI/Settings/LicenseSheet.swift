import SwiftUI

/// The text of a licence that is bundled with the app, as Zobrazit licenci shows it: the name of the part and what it
/// is for, then the whole text, which scrolls and can be selected and copied.
struct LicenseSheet: View {
    let licence: Licence

    /// Zavřít, which Esc presses too.
    let close: () -> Void

    /// The text, read once when the sheet is made.
    @State private var text: String?

    init(licence: Licence, close: @escaping () -> Void) {
        self.licence = licence
        self.close = close
        _text = State(initialValue: licence.text())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: licence.name, subtitle: licence.detail)
            ScrollView {
                Text(verbatim: text ?? "Text licence se nepodařilo načíst.")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .frame(height: 420)
            HStack {
                Spacer()
                Button("Zavřít", action: close)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 640)
    }
}
