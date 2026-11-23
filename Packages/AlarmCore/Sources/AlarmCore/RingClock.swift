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

    /// The same, past any ring marked Done or Skipped. An alarm that has
    /// rung with steps left says so: "Rang today at 21:30, 3 steps to go".
    public static func text(for routine: Routine, in state: AlertsState, at now: Date, calendar: Calendar = .current)
        -> String?
    {
        if let cycle = AlarmList.underWay(routine, in: state, now: now, calendar: calendar) {
            let checked = Set(state.routineCompletions.map(\.stepKey))
            let left = cycle.steps.filter { !checked.contains($0.key) }.count
            let time = calendar.dateComponents([.hour, .minute], from: cycle.at)
            return "Rang \(RingDay.word(cycle.at, now: now, calendar: calendar)) at "
                + String(format: "%02d:%02d, ", time.hour ?? 0, time.minute ?? 0)
                + (left == 1 ? "1 step to go" : "\(left) steps to go")
        }
        guard let next = Reconciler.nextRing(of: routine, in: state, now: now, calendar: calendar) else { return nil }
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
