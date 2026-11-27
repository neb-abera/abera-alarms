import Foundation

/// A Clock-style alarm: a wall-clock time, how it repeats, and an on/off
/// switch. It repeats on weekdays, on weekdays every N weeks, or every N
/// minutes, hours, days, weeks, months, or years from a start date. Stored
/// on abera.tech, rung by the phone. It never passes through Pushover or
/// Google Calendar.
public struct Routine: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var hour: Int
    public var minute: Int
    /// ISO weekdays, Monday 1 to Sunday 7. Empty with `repeatMode` weekdays
    /// rings once, at the next hour:minute, and the phone then switches it
    /// off. Always empty for an interval.
    public var days: [Int]
    /// On weekdays, or every `every` units from `startsOn`. "repeat" in JSON.
    public var repeatMode: RoutineRepeat
    /// The N: weeks between ring weeks on weekdays, units for an interval.
    public var every: Int
    /// Weeks for weekdays. Any of the six for an interval.
    public var unit: RoutineUnit
    /// The local date the series counts from, "yyyy-MM-dd". Nil for
    /// weekdays every week.
    public var startsOn: String?
    public var enabled: Bool
    public var snoozeMinutes: Int
    /// Sub-alarms chained after the ring, in order. An older server sends none.
    public var steps: [RoutineStep]
    /// When abera.tech last saved it. A ring-once routine rings at the
    /// first hour:minute after it. Nil from an older server.
    public var updatedAt: Date?
    /// This routine's rings moved later, minutes by ring stamp. Read from
    /// the state's delays, never sent with the routine.
    public var delays: [String: Int] = [:]

    enum CodingKeys: String, CodingKey {
        case id, label, hour, minute, days, enabled, snoozeMinutes, steps, updatedAt, every, unit, startsOn
        case repeatMode = "repeat"
    }

    public init(
        id: UUID, label: String, hour: Int, minute: Int, days: [Int], enabled: Bool = true, snoozeMinutes: Int = 9,
        steps: [RoutineStep] = [], updatedAt: Date? = nil, repeatMode: RoutineRepeat = .weekdays, every: Int = 1,
        unit: RoutineUnit = .weeks, startsOn: String? = nil
    ) {
        self.id = id
        self.label = label
        self.hour = hour
        self.minute = minute
        self.days = days
        self.enabled = enabled
        self.snoozeMinutes = snoozeMinutes
        self.steps = steps
        self.updatedAt = updatedAt
        self.repeatMode = repeatMode
        self.every = every
        self.unit = unit
        self.startsOn = startsOn
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
        steps = try container.decodeIfPresent([RoutineStep].self, forKey: .steps) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        // An older server sends none of the four. A value this build does
        // not know reads as the default, so a newer server never breaks the list.
        repeatMode = (try? container.decodeIfPresent(RoutineRepeat.self, forKey: .repeatMode)) ?? .weekdays
        every = (try? container.decodeIfPresent(Int.self, forKey: .every)) ?? 1
        unit = (try? container.decodeIfPresent(RoutineUnit.self, forKey: .unit)) ?? .weeks
        startsOn = try? container.decodeIfPresent(String.self, forKey: .startsOn)
    }

    /// False for a ring-once routine: on weekdays with no days.
    public var repeats: Bool { !schedule.ringsOnce }

    /// A routine on weekdays every week carries no start date and no other
    /// unit, so the alarm the phone holds for it compares equal from one
    /// sync to the next.
    public var schedule: RoutineSchedule {
        let plain = repeatMode == .weekdays && (every <= 1 || days.isEmpty)
        return RoutineSchedule(
            hour: hour, minute: minute, days: days.sorted(), snoozeMinutes: snoozeMinutes, repeatMode: repeatMode,
            every: plain ? 1 : every, unit: plain ? .weeks : unit, startsOn: plain ? nil : startsOn)
    }

    /// The draft that recreates this routine, for an edit or a switch.
    public var draft: RoutineDraft {
        RoutineDraft(
            label: label, hour: hour, minute: minute, days: days, enabled: enabled, snoozeMinutes: snoozeMinutes,
            steps: steps, repeatMode: repeatMode, every: every, unit: unit, startsOn: startsOn)
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
        default: return dayNames(days)
        }
    }

    /// "Mon Wed Fri": the short names in week order.
    static func dayNames(_ days: [Int]) -> String {
        let names = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
        return Set(days).sorted().compactMap { names[$0] }.joined(separator: " ")
    }

    /// How it repeats, in the words abera.tech uses: `daysText` on weekdays
    /// every week, "Every 2 weeks on Mon Wed Fri", "Every 97 minutes",
    /// "Every hour".
    public var repeatText: String {
        Self.repeatText(repeatMode: repeatMode, every: every, unit: unit, days: days)
    }

    public static func repeatText(repeatMode: RoutineRepeat, every: Int, unit: RoutineUnit, days: [Int]) -> String {
        switch repeatMode {
        case .interval:
            return unit.describe(every: every)
        case .weekdays:
            guard every > 1, !days.isEmpty else { return daysText(days) }
            return "Every \(every) weeks on " + dayNames(days)
        }
    }
}

/// When a routine rings, as the phone's alarm system needs it.
public struct RoutineSchedule: Codable, Equatable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int
    public var days: [Int]
    public var snoozeMinutes: Int
    public var repeatMode: RoutineRepeat
    public var every: Int
    public var unit: RoutineUnit
    public var startsOn: String?

    enum CodingKeys: String, CodingKey {
        case hour, minute, days, snoozeMinutes, every, unit, startsOn
        case repeatMode = "repeat"
    }

    public init(
        hour: Int, minute: Int, days: [Int], snoozeMinutes: Int, repeatMode: RoutineRepeat = .weekdays,
        every: Int = 1, unit: RoutineUnit = .weeks, startsOn: String? = nil
    ) {
        self.hour = hour
        self.minute = minute
        self.days = days
        self.snoozeMinutes = snoozeMinutes
        self.repeatMode = repeatMode
        self.every = every
        self.unit = unit
        self.startsOn = startsOn
    }

    /// A ledger or a widget snapshot from an older build has none of the
    /// last four. It reads as weekdays every week.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        days = try container.decode([Int].self, forKey: .days)
        snoozeMinutes = try container.decode(Int.self, forKey: .snoozeMinutes)
        repeatMode = (try? container.decodeIfPresent(RoutineRepeat.self, forKey: .repeatMode)) ?? .weekdays
        every = (try? container.decodeIfPresent(Int.self, forKey: .every)) ?? 1
        unit = (try? container.decodeIfPresent(RoutineUnit.self, forKey: .unit)) ?? .weeks
        startsOn = try? container.decodeIfPresent(String.self, forKey: .startsOn)
    }

    /// Ring once: on weekdays with no days. An interval has no days and repeats.
    public var ringsOnce: Bool { repeatMode == .weekdays && days.isEmpty }

    /// True when the phone's alarm system can hold it as one alarm: ring
    /// once, or weekdays every week. Any other repeat is held ring by ring.
    public var fitsSystemRepeat: Bool { repeatMode == .weekdays && (every <= 1 || days.isEmpty) }

    /// The next ring strictly after `now`, in the calendar's zone. A time the
    /// clocks skip (02:30 when they go from 02:00 to 03:00) rings when the
    /// clock reaches the next time that exists. A time the clocks pass twice
    /// (01:30 when they go from 02:00 back to 01:00) rings at the first.
    /// Nil when nothing is left to ring, or the repeat needs a start date
    /// and has none.
    public func nextFire(after now: Date, calendar: Calendar = .current) -> Date? {
        guard fitsSystemRepeat else { return seriesFire(after: now, calendar: calendar) }
        return clockFire(after: now, on: days, calendar: calendar)
    }

    /// The next hour:minute after `now` on one of `days`, or on any day when
    /// `days` is empty.
    func clockFire(after now: Date, on days: [Int], calendar: Calendar) -> Date? {
        var best: Date?
        let weekdays: [Int?] = days.isEmpty ? [nil] : days.map { Optional($0) }
        for iso in weekdays {
            var components = DateComponents(hour: hour, minute: minute, second: 0)
            // Calendar weekdays run Sunday 1 to Saturday 7. ISO runs Monday 1 to Sunday 7.
            if let iso { components.weekday = iso % 7 + 1 }
            var after = now
            var found: Date?
            // Two tries: the second skips the repeat of an hour the clocks passed twice.
            for _ in 0..<2 {
                guard
                    let next = calendar.nextDate(
                        after: after, matching: components, matchingPolicy: .nextTime, direction: .forward)
                else { break }
                if isRepeat(next, calendar: calendar) {
                    after = next
                    continue
                }
                found = next
                break
            }
            if let found, best == nil || found < best! { best = found }
        }
        return best
    }

    /// True for the second pass of a wall-clock time, when the same time
    /// read on the clock one hour earlier.
    private func isRepeat(_ date: Date, calendar: Calendar) -> Bool {
        let earlier = date.addingTimeInterval(-3600)
        let now = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let then = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: earlier)
        return now == then
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
    public var steps: [RoutineStep]
    public var repeatMode: RoutineRepeat
    public var every: Int
    public var unit: RoutineUnit
    public var startsOn: String?

    enum CodingKeys: String, CodingKey {
        case label, hour, minute, days, enabled, snoozeMinutes, steps, every, unit, startsOn
        case repeatMode = "repeat"
    }

    public init(
        label: String = RoutineDraft.defaultLabel, hour: Int, minute: Int, days: [Int] = [], enabled: Bool = true,
        snoozeMinutes: Int = 9, steps: [RoutineStep] = [], repeatMode: RoutineRepeat = .weekdays, every: Int = 1,
        unit: RoutineUnit = .weeks, startsOn: String? = nil
    ) {
        self.label = label
        self.hour = hour
        self.minute = minute
        self.days = days
        self.enabled = enabled
        self.snoozeMinutes = snoozeMinutes
        self.steps = steps
        self.repeatMode = repeatMode
        self.every = every
        self.unit = unit
        self.startsOn = startsOn
    }

    /// A draft queued by a build before steps decodes with none. One queued
    /// by a build before intervals decodes as weekdays every week.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        days = try container.decodeIfPresent([Int].self, forKey: .days) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 9
        steps = try container.decodeIfPresent([RoutineStep].self, forKey: .steps) ?? []
        repeatMode = (try? container.decodeIfPresent(RoutineRepeat.self, forKey: .repeatMode)) ?? .weekdays
        every = (try? container.decodeIfPresent(Int.self, forKey: .every)) ?? 1
        unit = (try? container.decodeIfPresent(RoutineUnit.self, forKey: .unit)) ?? .weeks
        startsOn = try? container.decodeIfPresent(String.self, forKey: .startsOn)
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
        problems += repeatProblems
        problems += RoutineStep.problems(steps)
        return problems
    }

    /// What is wrong with the repeat, by the rules abera.tech checks.
    public var repeatProblems: [String] {
        var problems: [String] = []
        if !(1...RoutineUnit.maxEvery).contains(every) {
            problems.append("Repeat every 1 to \(RoutineUnit.maxEvery).")
        }
        let started = startsOn.flatMap { CivilDate(iso: $0) } != nil
        switch repeatMode {
        case .weekdays:
            if unit != .weeks { problems.append("An alarm on days of the week repeats in weeks.") }
            if every > 1 {
                if days.isEmpty { problems.append("Choose the days it rings on.") }
                if !started { problems.append("Choose the date it starts on.") }
            }
        case .interval:
            if !days.isEmpty { problems.append("An alarm that repeats by interval has no days of the week.") }
            if !started { problems.append("Choose the date it starts on.") }
        }
        return problems
    }

    /// The body the server expects: the label trimmed, the days unique and
    /// sorted, and no start date on weekdays every week.
    var body: RoutineDraft {
        var body = self
        body.label = sentLabel
        body.days = Array(Set(days)).sorted()
        body.steps = steps.map(\.sent)
        if repeatMode == .weekdays, every == 1 { body.startsOn = nil }
        return body
    }
}

/// A routine change made on the phone that abera.tech has not taken yet.
public enum RoutineChange: Codable, Equatable, Sendable {
    /// A new routine, under an id the phone made until abera.tech gives its own.
    case create(local: UUID, draft: RoutineDraft)
    case update(id: UUID, draft: RoutineDraft)
    case delete(id: UUID)

    /// The routine it changes: the phone's own id for one not yet sent.
    public var id: UUID {
        switch self {
        case .create(let local, _): local
        case .update(let id, _), .delete(let id): id
        }
    }

    /// The same change, naming a routine by abera.tech's id once it has one.
    func renaming(_ ids: [UUID: UUID]) -> RoutineChange {
        switch self {
        case .create: self
        case .update(let id, let draft): .update(id: ids[id] ?? id, draft: draft)
        case .delete(let id): .delete(id: ids[id] ?? id)
        }
    }

    /// The fewest changes that leave abera.tech where these would. An edit
    /// to a routine not yet sent folds into its creation, a delete of one
    /// cancels it, and only the last edit of a routine is kept.
    public static func coalesce(_ changes: [RoutineChange]) -> [RoutineChange] {
        var out: [RoutineChange] = []
        for change in changes {
            let created = out.firstIndex { if case .create(change.id, _) = $0 { true } else { false } }
            switch change {
            case .create:
                out.append(change)
            case .update(let id, let draft):
                if let created {
                    out[created] = .create(local: id, draft: draft)
                } else {
                    out.removeAll { if case .update(id, _) = $0 { true } else { false } }
                    out.append(change)
                }
            case .delete(let id):
                if let created {
                    out.remove(at: created)
                } else {
                    out.removeAll { if case .update(id, _) = $0 { true } else { false } }
                    out.append(change)
                }
            }
        }
        return out
    }

    /// The state as it will be once abera.tech has taken these changes.
    public static func overlay(_ state: AlertsState, _ changes: [RoutineChange]) -> AlertsState {
        guard !changes.isEmpty else { return state }
        var state = state
        for change in changes {
            switch change {
            case .create(let local, let draft):
                let body = draft.body
                state.routines.append(
                    Routine(
                        id: local, label: body.label, hour: body.hour, minute: body.minute, days: body.days,
                        enabled: body.enabled, snoozeMinutes: body.snoozeMinutes, steps: body.steps,
                        repeatMode: body.repeatMode, every: body.every, unit: body.unit, startsOn: body.startsOn))
            case .update(let id, let draft):
                guard let index = state.routines.firstIndex(where: { $0.id == id }) else { continue }
                let body = draft.body
                state.routines[index].label = body.label
                state.routines[index].hour = body.hour
                state.routines[index].minute = body.minute
                state.routines[index].days = body.days
                state.routines[index].enabled = body.enabled
                state.routines[index].snoozeMinutes = body.snoozeMinutes
                state.routines[index].steps = body.steps
                state.routines[index].repeatMode = body.repeatMode
                state.routines[index].every = body.every
                state.routines[index].unit = body.unit
                state.routines[index].startsOn = body.startsOn
                // Saved again when abera.tech takes it: a ring-once routine rings after that.
                state.routines[index].updatedAt = nil
            case .delete(let id):
                state.routines.removeAll { $0.id == id }
            }
        }
        state.routines.sort { ($0.hour, $0.minute, $0.label) < ($1.hour, $1.minute, $1.label) }
        return state
    }
}
