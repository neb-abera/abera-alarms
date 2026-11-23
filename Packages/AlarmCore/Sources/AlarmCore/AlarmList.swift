import Foundation

/// The Alarms tab's order and which alarms show their steps. Neb asked on
/// 2026-11-21 for the alarms in the order they next ring, and for steps
/// that open and close, closed by default on an alarm that does not ring
/// that day unless he opened it.
public enum AlarmList {
    /// Switched-on alarms by their next ring not marked Done or Skipped,
    /// soonest first. An alarm that has rung with steps still to clear
    /// keeps the ring it rang, so it stays at the top. Switched-off alarms
    /// after them, by time and label.
    public static func ordered(_ routines: [Routine], in state: AlertsState, now: Date, calendar: Calendar)
        -> [Routine]
    {
        let next = Dictionary(
            routines.map { routine in
                (
                    routine.id,
                    underWay(routine, in: state, now: now, calendar: calendar)?.at
                        ?? Reconciler.nextRing(of: routine, in: state, now: now, calendar: calendar)
                )
            },
            uniquingKeysWith: { first, _ in first })
        return routines.sorted { a, b in
            switch (next[a.id] ?? nil, next[b.id] ?? nil) {
            case (let x?, let y?): (x, a.label, a.id.uuidString) < (y, b.label, b.id.uuidString)
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): (a.hour, a.minute, a.label, a.id.uuidString) < (b.hour, b.minute, b.label, b.id.uuidString)
            }
        }
    }

    /// The ring that has rung and still has steps to clear: not skipped,
    /// and not every step checked off. Its steps ring for up to the stop
    /// window after the last one. Nil once nothing is left, and for an
    /// alarm that is off. On 2026-11-22 Neb stopped the 21:30 night
    /// routine and the list moved it to Tuesday's ring while its steps
    /// were still to ring. He said the alarm should not move to its next
    /// ring until every step is cleared.
    public static func underWay(_ routine: Routine, in state: AlertsState, now: Date, calendar: Calendar)
        -> RoutineCycle?
    {
        guard routine.enabled, !routine.steps.isEmpty else { return nil }
        let window = TimeInterval(state.stopAfterMinutes * 60)
        guard let cycle = RoutineCycle.shown(routine, in: state, now: now, window: window, calendar: calendar),
            cycle.at <= now, !cycle.isSettled(in: state, now: now)
        else { return nil }
        return cycle
    }

    /// Steps show by default when the ring they list is today or has rung,
    /// and the alarm is on.
    public static func openByDefault(_ routine: Routine, cycle: RoutineCycle?, now: Date, calendar: Calendar) -> Bool {
        guard routine.enabled, let cycle else { return false }
        return cycle.at <= now || calendar.isDate(cycle.at, inSameDayAs: now)
    }

    /// Open or closed: his own choice for this ring when he made one, else
    /// the default. A choice holds for the ring it was made on. The next
    /// ring starts from the default again.
    public static func isOpen(
        _ routine: Routine, cycle: RoutineCycle?, now: Date, calendar: Calendar, choices: [String: Bool]
    ) -> Bool {
        if let cycle, let chosen = choices[cycle.key] { return chosen }
        return openByDefault(routine, cycle: cycle, now: now, calendar: calendar)
    }

    /// The choices still about a ring the list can show. Older ones go.
    public static func pruned(_ choices: [String: Bool], keeping keys: Set<String>) -> [String: Bool] {
        choices.filter { keys.contains($0.key) }
    }
}
