import Foundation

/// When the app locks after inactivity.
nonisolated enum IdleLockRule {
    /// What a check of the lock after inactivity comes to.
    nonisolated enum Outcome: Equatable, Sendable {
        /// Nothing changes: the data is not open, the app does not lock (no Touch ID, Nikdy), or the time is not up.
        case nothing

        /// The time is up while an open or save panel of the system is up: the app does not lock, and the panel counts
        /// as activity. It shows files, not the data, and the person may work in it without the app seeing it, so the
        /// time counts from the check that found it.
        case panelCountsAsActivity

        /// The app locks.
        case lock
    }

    /// What a check at `now` comes to, when the latest activity of the person in the app's windows was at
    /// `lastActivity`. The app locks when:
    /// - the data is open (`phase` is `.ready`);
    /// - the app is unlocked with Touch ID (`touchIDUnlock`), as the lock asks for the same as the launch;
    /// - a time is chosen (`time` is not never), and it has passed since `lastActivity`;
    /// - no open or save panel of the system is up (`modalPanelIsUp`, asked only then).
    static func outcome(
        phase: AppPhase, touchIDUnlock: Bool, time: IdleLockTime, lastActivity: Date, now: Date,
        modalPanelIsUp: @autoclosure () -> Bool
    ) -> Outcome {
        guard phase == .ready, touchIDUnlock, let interval = time.interval else { return .nothing }
        guard now.timeIntervalSince(lastActivity) >= interval else { return .nothing }
        return modalPanelIsUp() ? .panelCountsAsActivity : .lock
    }
}
