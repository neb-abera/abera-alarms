import Foundation

/// The clock beside an alarm that counts down to its next ring, in the
/// countdowns' words: "Rings in 0 days 06:12:33".
public enum RingClock {
    /// A switched-on routine counts down to its next ring in the phone's
    /// zone. One that is off has no clock.
    public static func text(for routine: Routine, at now: Date, calendar: Calendar = .current) -> String? {
        guard routine.enabled, let next = routine.nextFire(after: now, calendar: calendar) else { return nil }
        return "Rings in " + Remaining(from: now, to: next).clock
    }

    /// A calendar alarm counts down to its alert while it is set on this
    /// phone and has not rung. Skipped, muted or acknowledged, it has none.
    public static func text(for alert: PlannedAlert, held: Bool, at now: Date) -> String? {
        guard alert.isAlarm, held, !alert.skipped, !alert.muted, !alert.acknowledged, alert.alertAt > now
        else { return nil }
        return "Rings in " + Remaining(from: now, to: alert.alertAt).clock
    }
}
