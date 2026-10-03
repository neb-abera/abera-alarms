import Foundation

/// One ring of a routine alarm. abera.tech plans the rings in the phone's
/// zone and names each by its routine and its scheduled local date and time:
/// `routine:{id}:{yyyy-MM-ddTHH:mm}`. Stop on the phone and an
/// acknowledgement anywhere else meet on that key.
public struct RoutineRing: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var key: String
    public var routineId: UUID
    public var label: String
    public var alertAt: Date
    /// When the ring gives up: alertAt plus the owner's stop window.
    public var startsAt: Date
    public var acknowledged: Bool
    public var acknowledgedAt: Date?
    /// "phone", "browser" or "pushover".
    public var acknowledgedVia: String?

    public var id: String { key }

    public init(
        key: String, routineId: UUID, label: String, alertAt: Date, startsAt: Date, acknowledged: Bool = false,
        acknowledgedAt: Date? = nil, acknowledgedVia: String? = nil
    ) {
        self.key = key
        self.routineId = routineId
        self.label = label
        self.alertAt = alertAt
        self.startsAt = startsAt
        self.acknowledged = acknowledged
        self.acknowledgedAt = acknowledgedAt
        self.acknowledgedVia = acknowledgedVia
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        routineId = try container.decode(UUID.self, forKey: .routineId)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? RoutineDraft.defaultLabel
        alertAt = try container.decode(Date.self, forKey: .alertAt)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        acknowledged = try container.decodeIfPresent(Bool.self, forKey: .acknowledged) ?? false
        acknowledgedAt = try container.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        acknowledgedVia = try container.decodeIfPresent(String.self, forKey: .acknowledgedVia)
    }

    /// The key of the ring being stopped at `now`: the latest scheduled ring
    /// at or before `now` and no more than `window` before it, in the
    /// calendar's zone. Nil when no ring falls in the window. A snoozed ring
    /// keeps the time it was scheduled for.
    public static func key(
        routineID: UUID, schedule: RoutineSchedule, stoppedAt now: Date, window: TimeInterval, calendar: Calendar
    ) -> String? {
        guard let ring = latestRing(schedule, atOrBefore: now, window: window, calendar: calendar) else { return nil }
        return key(routineID: routineID, schedule: schedule, ring: ring, calendar: calendar)
    }

    /// The ring times come from the same `nextFire` that schedules the alarm.
    static func latestRing(_ schedule: RoutineSchedule, atOrBefore now: Date, window: TimeInterval, calendar: Calendar)
        -> Date?
    {
        var latest: Date?
        var next = schedule.nextFire(after: now.addingTimeInterval(-window - 1), calendar: calendar)
        while let ring = next, ring <= now {
            latest = ring
            next = schedule.nextFire(after: ring, calendar: calendar)
        }
        return latest
    }

    /// The ring's local date with the routine's own hour and minute. On a day
    /// the clocks skip that time the ring sounds later, and the key still
    /// names the time it was scheduled for.
    static func key(routineID: UUID, schedule: RoutineSchedule, ring: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: ring)
        let stamp = String(
            format: "%04d-%02d-%02dT%02d:%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0, schedule.hour,
            schedule.minute)
        return DesiredAlarm.routinePrefix + routineID.uuidString.lowercased() + ":" + stamp
    }
}
