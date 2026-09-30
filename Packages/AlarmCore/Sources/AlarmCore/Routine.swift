import Foundation

/// A Clock-style alarm: a wall-clock time, the weekdays it repeats on, and
/// an on/off switch. Stored on abera.tech, rung by the phone. It never
/// passes through Pushover or Google Calendar.
public struct Routine: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var hour: Int
    public var minute: Int
    /// ISO weekdays, Monday 1 to Sunday 7. Empty rings once, at the next
    /// hour:minute, and the phone then switches it off.
    public var days: [Int]
    public var enabled: Bool
    public var snoozeMinutes: Int

    public init(
        id: UUID, label: String, hour: Int, minute: Int, days: [Int], enabled: Bool = true, snoozeMinutes: Int = 9
    ) {
        self.id = id
        self.label = label
        self.hour = hour
        self.minute = minute
        self.days = days
        self.enabled = enabled
        self.snoozeMinutes = snoozeMinutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? RoutineDraft.defaultLabel
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        days = try container.decodeIfPresent([Int].self, forKey: .days) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 9
    }

    public var repeats: Bool { !days.isEmpty }

    public var schedule: RoutineSchedule {
        RoutineSchedule(hour: hour, minute: minute, days: days.sorted(), snoozeMinutes: snoozeMinutes)
    }

    /// The draft that recreates this routine, for an edit or a switch.
    public var draft: RoutineDraft {
        RoutineDraft(
            label: label, hour: hour, minute: minute, days: days, enabled: enabled, snoozeMinutes: snoozeMinutes)
    }

    /// The next time it rings after `now`, in the phone's calendar.
    public func nextFire(after now: Date, calendar: Calendar = .current) -> Date? {
        schedule.nextFire(after: now, calendar: calendar)
    }

    /// "No repeat", "Every day", "Weekdays", "Weekends", or the short day names.
    public var daysText: String { Self.daysText(days) }

    public static func daysText(_ days: [Int]) -> String {
        let set = Set(days)
        switch set {
        case []: return "No repeat"
        case Set(1...7): return "Every day"
        case Set(1...5): return "Weekdays"
        case [6, 7]: return "Weekends"
        default:
            let names = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
            return set.sorted().compactMap { names[$0] }.joined(separator: " ")
        }
    }
}

/// When a routine rings, as the phone's alarm system needs it.
public struct RoutineSchedule: Codable, Equatable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int
    public var days: [Int]
    public var snoozeMinutes: Int

    public init(hour: Int, minute: Int, days: [Int], snoozeMinutes: Int) {
        self.hour = hour
        self.minute = minute
        self.days = days
        self.snoozeMinutes = snoozeMinutes
    }

    public func nextFire(after now: Date, calendar: Calendar = .current) -> Date? {
        var best: Date?
        let weekdays: [Int?] = days.isEmpty ? [nil] : days.map { Optional($0) }
        for iso in weekdays {
            var components = DateComponents(hour: hour, minute: minute, second: 0)
            // Calendar weekdays run Sunday 1 to Saturday 7. ISO runs Monday 1 to Sunday 7.
            if let iso { components.weekday = iso % 7 + 1 }
            guard
                let next = calendar.nextDate(
                    after: now, matching: components, matchingPolicy: .nextTime, direction: .forward)
            else { continue }
            if best == nil || next < best! { best = next }
        }
        return best
    }
}

/// What the phone sends to add or change a routine.
public struct RoutineDraft: Codable, Equatable, Sendable {
    public static let defaultLabel = "Alarm"
    public static let maxRoutines = 50

    public var label: String
    public var hour: Int
    public var minute: Int
    public var days: [Int]
    public var enabled: Bool
    public var snoozeMinutes: Int

    public init(
        label: String = RoutineDraft.defaultLabel, hour: Int, minute: Int, days: [Int] = [], enabled: Bool = true,
        snoozeMinutes: Int = 9
    ) {
        self.label = label
        self.hour = hour
        self.minute = minute
        self.days = days
        self.enabled = enabled
        self.snoozeMinutes = snoozeMinutes
    }

    /// The label as sent: trimmed, and "Alarm" when empty.
    public var sentLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel : trimmed
    }

    /// The same bounds the server checks. Empty when the draft can be sent.
    public var problems: [String] {
        var problems: [String] = []
        if sentLabel.count > 60 { problems.append("The label is longer than 60 characters.") }
        if !(0...23).contains(hour) || !(0...59).contains(minute) { problems.append("Choose a time.") }
        if days.contains(where: { !(1...7).contains($0) }) { problems.append("Choose days from Monday to Sunday.") }
        if !(1...30).contains(snoozeMinutes) { problems.append("Snooze must be 1 to 30 minutes.") }
        return problems
    }

    /// The body the server expects: the label trimmed, the days unique and sorted.
    var body: RoutineDraft {
        var body = self
        body.label = sentLabel
        body.days = Array(Set(days)).sorted()
        return body
    }
}
