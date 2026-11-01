import SwiftUI

/// What the window shows when the folder for the data cannot be made, so that the app has nothing to open: the one
/// message, in the middle of the window.
struct DataFolderProblemView: View {
    var body: some View {
        Text("Složku pro data se nepodařilo vytvořit.")
            .font(Typography.title2)
            .foregroundStyle(Palette.text2)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bgWindow.ignoresSafeArea())
    }
}
