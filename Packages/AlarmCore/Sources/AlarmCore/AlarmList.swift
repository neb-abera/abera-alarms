import Foundation

/// The Alarms tab's order and which alarms show their steps. Neb asked on
/// 2026-11-21 for the alarms in the order they next ring, and for steps
/// that open and close, closed by default on an alarm that does not ring
/// that day unless he opened it.
public enum AlarmList {
    /// Switched-on alarms by their next ring not marked Done or Skipped,
    /// soonest first. Switched-off alarms after them, by time and label.
    public static func ordered(_ routines: [Routine], in state: AlertsState, now: Date, calendar: Calendar)
        -> [Routine]
    {
        let next = Dictionary(
            routines.map { ($0.id, Reconciler.nextRing(of: $0, in: state, now: now, calendar: calendar)) },
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

    /// Steps show by default when the ring they list is today and the
    /// alarm is on.
    public static func openByDefault(_ routine: Routine, cycle: RoutineCycle?, now: Date, calendar: Calendar) -> Bool {
        guard routine.enabled, let cycle else { return false }
        return calendar.isDate(cycle.at, inSameDayAs: now)
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
