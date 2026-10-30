import Foundation

nonisolated enum AppEnvironment {
    /// True when the process was started by a test runner, which hosts the unit tests inside the app.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    /// The folder that holds all of the app's data: `InvoicesTracker/` in Application Support,
    /// which lives inside the sandbox container. It is created when missing.
    static func dataDirectory() throws -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "InvoicesTracker", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
