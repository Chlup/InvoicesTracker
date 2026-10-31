/// The kinds of check for a new version that the updater makes.
nonisolated enum UpdateCheckKind: Sendable {
    /// A check the person asked for, which shows its result whatever it is.
    case userInitiated

    /// The daily check the updater makes by itself, which shows only a new version.
    case background

    /// A check that only finds out whether there is a new version, without offering it. The app never asks for one.
    case informationOnly
}

/// Which checks for a new version the updater may make. Debug builds refuse the daily check in the background, so
/// that a build run from Xcode does not check the published feed by itself and offer a release in its own place. A
/// check the person asks for runs in every build, so the updater can be tried out.
nonisolated enum UpdateCheckPolicy {
    /// Whether this build refuses the checks in the background: true in Debug builds only.
    static let refusesBackgroundChecks: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Whether a check of `kind` may run, in a build that refuses the checks in the background when
    /// `refusingBackgroundChecks` is true. Every other kind of check may always run.
    static func allows(_ kind: UpdateCheckKind, refusingBackgroundChecks: Bool) -> Bool {
        kind != .background || !refusingBackgroundChecks
    }
}
