import SwiftUI

/// What the window shows when the folder for the data cannot be made, so that the app has nothing to open: the one
/// message, in the middle of the window.
struct DataFolderProblemView: View {
    var body: some View {
        Text("Složku pro data se nepodařilo vytvořit.")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
