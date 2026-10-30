import SwiftUI

@main
struct TaxesTrackerApp: App {
    /// The model of the app, made once. Nil while the app hosts the unit tests, which must not touch the data, and when
    /// the folder of the data cannot be made.
    @State private var model: AppModel? = Self.makeModel()

    /// Asks before a quit throws away the invoice that is being written.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if AppEnvironment.isRunningTests {
                // The app hosts the unit tests, so it must not open the data, start the refresh or show anything.
                EmptyView()
            } else if let model {
                RootView(model: model)
                    .onAppear {
                        appDelegate.model = model
                    }
            } else {
                DataFolderProblemView()
                    .frame(minWidth: 1100, minHeight: 720)
            }
        }
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(model: model)
            #if DEBUG
            DebugCommands()
            #endif
        }
    }

    private static func makeModel() -> AppModel? {
        guard !AppEnvironment.isRunningTests else { return nil }
        do {
            return AppModel(dependencies: try AppDependencies.production())
        } catch {
            AppModel.log("Making the folder of the data", failedWith: error)
            return nil
        }
    }
}
