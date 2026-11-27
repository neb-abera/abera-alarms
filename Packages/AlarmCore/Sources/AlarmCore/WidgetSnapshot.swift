import Foundation

/// What the Home Screen and Lock Screen widgets show, written by the app
/// into the app group after every sync and every change on the phone. The
/// widgets read it and never reach abera.tech. It holds no token: only
/// titles, times and countdowns.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// The app group the app and the widget share.
    public static let appGroup = "group.tech.abera.alarms"
    public static let fileName = "widget-snapshot.json"
    /// At most this many events and calendar alarms are kept. A widget shows one.
    static let maxListed = 20

    /// One alarm that rings once: a calendar alarm, a timer, or one ring of
    /// a routine held ring by ring.
    public struct OneTime: Codable, Equatable, Sendable {
        public var title: String
        public var at: Date
        /// True for one ring of a routine or of its step. False from an older build.
        public var routine: Bool

        public init(title: String, at: Date, routine: Bool = false) {
            self.title = title
            self.at = at
            self.routine = routine
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            at = try container.decode(Date.self, forKey: .at)
            routine = try container.decodeIfPresent(Bool.self, forKey: .routine) ?? false
        }
    }

    /// A routine set on this phone as one alarm. One that repeats rings at
    /// each of its days. One that does not rings once, at `once`. A routine
    /// every N weeks or every interval is held ring by ring, and its rings
    /// are listed with the one-time alarms.
    public struct RoutineAlarm: Codable, Equatable, Sendable {
        public var label: String
        public var schedule: RoutineSchedule
        public var once: Date?

        public init(label: String, schedule: RoutineSchedule, once: Date? = nil) {
            self.label = label
            self.schedule = schedule
            self.once = once
        }
    }

    /// A calendar event, alarm or not.
    public struct Event: Codable, Equatable, Sendable {
        public var title: String
        public var startsAt: Date
        public var location: String?

        public init(title: String, startsAt: Date, location: String? = nil) {
            self.title = title
            self.startsAt = startsAt
            self.location = location
        }
    }

    /// One ring the widget shows.
    public struct Ring: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case calendar, routine, timer
        }

        public var title: String
        public var at: Date
        public var kind: Kind

        public init(title: String, at: Date, kind: Kind) {
            self.title = title
            self.at = at
            self.kind = kind
        }
    }

    public var writtenAt: Date
    /// False before pairing: the widget asks to open the app.
    public var paired: Bool
    /// The calendar alarms this phone holds, in time order.
    public var alarms: [OneTime]
    public var routines: [RoutineAlarm]
    public var timer: OneTime?
    /// The events not yet started, alarms included, in time order.
    public var events: [Event]
    public var countdowns: [Countdown]

    public init(
        writtenAt: Date, paired: Bool = true, alarms: [OneTime] = [], routines: [RoutineAlarm] = [],
        timer: OneTime? = nil, events: [Event] = [], countdowns: [Countdown] = []
    ) {
        self.writtenAt = writtenAt
        self.paired = paired
        self.alarms = alarms
        self.routines = routines
        self.timer = timer
        self.events = events
        self.countdowns = countdowns
    }

    /// The snapshot of the phone at `now`. `held` is what the alarm system
    /// holds for the sync (AlarmSync.heldAlarms): the alarms marked Set on
    /// this phone. A routine counts from there, so one that is on but was
    /// refused by iOS is left out, as it will not ring.
    public static func make(
        state: AlertsState?, held: [DesiredAlarm], timer: OneTime?, paired: Bool, now: Date
    ) -> WidgetSnapshot {
        let alarms =
            held
            .filter { !$0.isRoutine && $0.fireAt > now }
            .sorted { ($0.fireAt, $0.key) < ($1.fireAt, $1.key) }
            .prefix(maxListed)
            .map { OneTime(title: $0.title, at: $0.fireAt, routine: $0.key.hasPrefix(DesiredAlarm.routinePrefix)) }
        let routines =
            held
            .compactMap { alarm -> RoutineAlarm? in
                guard let schedule = alarm.routine else { return nil }
                return RoutineAlarm(
                    label: alarm.title, schedule: schedule, once: schedule.ringsOnce ? alarm.fireAt : nil)
            }
            .sorted { $0.label < $1.label }
        let events = (state?.alerts ?? [])
            .filter { $0.startsAt > now && !$0.skipped }
            .sorted { ($0.startsAt, $0.key) < ($1.startsAt, $1.key) }
            .prefix(maxListed)
            .map { Event(title: $0.title, startsAt: $0.startsAt, location: $0.location) }
        return WidgetSnapshot(
            writtenAt: now, paired: paired, alarms: Array(alarms), routines: routines,
            timer: timer.flatMap { $0.at > now ? $0 : nil }, events: Array(events),
            countdowns: state?.countdowns ?? [])
    }

    /// Every ring after `now` up to `end`, earliest first, at most `limit`.
    /// A repeating routine gives one ring for each of its days.
    public func rings(after now: Date, through end: Date, limit: Int = 50, calendar: Calendar = .current) -> [Ring] {
        var rings: [Ring] = []
        rings += alarms.filter { $0.at > now && $0.at <= end }.map {
            Ring(title: $0.title, at: $0.at, kind: $0.routine ? .routine : .calendar)
        }
        if let timer, timer.at > now, timer.at <= end {
            rings.append(Ring(title: timer.title, at: timer.at, kind: .timer))
        }
        for routine in routines {
            if let once = routine.once {
                if once > now, once <= end { rings.append(Ring(title: routine.label, at: once, kind: .routine)) }
                continue
            }
            var after = now
            for _ in 0..<limit {
                guard let next = routine.schedule.nextFire(after: after, calendar: calendar), next <= end else { break }
                rings.append(Ring(title: routine.label, at: next, kind: .routine))
                after = next
            }
        }
        return Array(rings.sorted { ($0.at, $0.title) < ($1.at, $1.title) }.prefix(limit))
    }

    /// The next ring after `now`: the earliest calendar alarm, routine or
    /// timer. Nil when nothing is set. Routines are looked for a week ahead,
    /// the longest one on weekdays waits, or as far as the soonest ring.
    public func nextRing(after now: Date, calendar: Calendar = .current) -> Ring? {
        let week = now.addingTimeInterval(8 * 86_400)
        let nextRoutine = routines.compactMap { $0.once ?? $0.schedule.nextFire(after: now, calendar: calendar) }
        let soonestOneTime = (alarms.map(\.at) + (timer.map { [$0.at] } ?? []) + nextRoutine)
            .filter { $0 > now }.min()
        let end = max(week, soonestOneTime ?? week)
        return rings(after: now, through: end, limit: 1, calendar: calendar).first
    }

    /// The next event after `now` that is not the ring shown: a different
    /// title or start. Nil when none is left.
    public func nextEvent(after now: Date, besides ring: Ring?) -> Event? {
        events.first { event in
            guard event.startsAt > now else { return false }
            guard let ring, ring.kind == .calendar else { return true }
            return event.title != ring.title
        }
    }

    /// The countdown a widget shows: the one chosen, while abera.tech still
    /// has it, else the next one to come, else the latest that passed.
    public func countdown(_ id: UUID?, at now: Date) -> Countdown? {
        if let id, let chosen = countdowns.first(where: { $0.id == id }) { return chosen }
        let upcoming = countdowns.filter { $0.nextAt(now) > now }.min { $0.nextAt(now) < $1.nextAt(now) }
        return upcoming ?? countdowns.max { $0.nextAt(now) < $1.nextAt(now) }
    }

    public func encoded() throws -> Data { try ServerDates.encoder().encode(self) }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        try ServerDates.decoder().decode(WidgetSnapshot.self, from: data)
    }
}

extension Remaining {
    /// "41 days 05:12": the clock to the minute, for a widget that redraws
    /// once a minute.
    public var minuteClock: String {
        "\(days) \(days == 1 ? "day" : "days") " + String(format: "%02d:%02d", hours, minutes)
    }

    /// The minute clock, or "Passed 2 days 03:04 ago" once the target has gone.
    public var minuteText: String { passed ? "Passed \(minuteClock) ago" : minuteClock }
}
