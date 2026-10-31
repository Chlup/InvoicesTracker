import SwiftUI

/// The text of a licence that is bundled with the app, as Zobrazit licenci shows it: the name of the part and what it
/// is for, then the whole text on the inset background, which scrolls and can be selected and copied, and Zavřít, which
/// Esc presses too.
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
                    .font(Typography.calloutMonospaced)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Palette.bgInset, in: RoundedRectangle(cornerRadius: DesignMetrics.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: DesignMetrics.panelRadius).strokeBorder(Palette.sep))
            .frame(height: 420)
            HStack {
                Spacer()
                Button("Zavřít", action: close)
                    .buttonStyle(CapsuleButtonStyle(.primary))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 640)
    }
}
