import AppKit
import Foundation

/// When the lock after inactivity is checked (`checkIdleLock(now:)`): every 15 seconds while the data is open, and at
/// once when the Mac wakes. The time counts on the wall clock, the time in the background and asleep included, and the
/// timer follows a change of the clock. The checks run when the app's dependencies say so
/// (`AppDependencies.startsIdleChecks`); tests check it themselves.
extension AppModel {
    /// How often the lock after inactivity is checked while the data is open, and how much later a check may come: the
    /// app locks at most 20 seconds after its time is up, or at the first activity after it (`noteActivity(at:)`).
    nonisolated static let idleCheckInterval: TimeInterval = 15
    nonisolated static let idleCheckTolerance: TimeInterval = 5

    /// Starts the checks on the data that is open, in place of any that ran: the timer of the next check and, the first
    /// time, the observations of the wakes of the Mac and of the changes of its clock. Does nothing unless the app's
    /// dependencies say so.
    func startIdleChecks() {
        guard dependencies.startsIdleChecks else { return }
        if idleCheckObservations.isEmpty {
            idleCheckObservations = [
                dependencies.workspaceNotifications.addObserver(
                    forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.checkIdleLockAfterWake()
                    }
                },
                dependencies.systemNotifications.addObserver(
                    forName: .NSSystemClockDidChange, object: nil, queue: nil
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.idleCheckClockChanged()
                    }
                },
            ]
        }
        armIdleCheck()
    }

    /// Stops the timer of the checks: the data is locked, and there is nothing to check until it is open again. A wake
    /// checks nothing then either, as the data is not open (`IdleLockRule`).
    func stopIdleChecks() {
        idleCheckWake?.cancel()
        idleCheckWake = nil
    }

    /// Sets the timer of the next check, `idleCheckInterval` from now, in place of the one before.
    private func armIdleCheck() {
        idleCheckWake?.cancel()
        let date = dependencies.clock.now() + Self.idleCheckInterval
        idleCheckWake = dependencies.scheduler.schedule(at: date, tolerance: Self.idleCheckTolerance) { [weak self] in
            Task { @MainActor in
                self?.idleCheckTimerFired()
            }
        }
    }

    /// The timer of the check fired: the lock is checked, and the timer is set for the next check, unless the checks
    /// were stopped meanwhile.
    private func idleCheckTimerFired() {
        guard idleCheckWake != nil, phase == .ready else { return }
        checkIdleLock(now: dependencies.clock.now())
        armIdleCheck()
    }

    /// The Mac woke from sleep: the time it slept counts, and the lock is checked at once.
    private func checkIdleLockAfterWake() {
        checkIdleLock(now: dependencies.clock.now())
    }

    /// The clock of the Mac was set: the lock is checked at once, and the timer of the next check is set again from the
    /// new time, as the time of the wall clock it waits for moved with the clock (set back by an hour, it would fire an
    /// hour late). A clock set ahead past the time locks the app at the change, and changes that come one after another
    /// cannot keep putting the check off. The check counts a latest activity that is in the future now as the time of
    /// the check.
    private func idleCheckClockChanged() {
        guard idleCheckWake != nil else { return }
        checkIdleLock(now: dependencies.clock.now())
        armIdleCheck()
    }
}
