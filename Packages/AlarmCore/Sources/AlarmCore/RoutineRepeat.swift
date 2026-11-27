import Foundation

/// How a routine repeats: on days of the week, or every N units from a
/// start date. abera.tech sends it as "repeat".
public enum RoutineRepeat: String, Codable, CaseIterable, Sendable, Hashable {
    case weekdays, interval
}

/// The unit a routine's interval counts in. Minutes and hours are elapsed
/// time from the first ring. Days, weeks, months, and years keep the time on
/// the clock. A month or year without the start's day of the month (the
/// 31st, 29 February) is skipped, as countdowns skip it.
public enum RoutineUnit: String, Codable, CaseIterable, Sendable, Hashable {
    case minutes, hours, days, weeks, months, years

    /// The largest N, as abera.tech takes it.
    public static let maxEvery = 999

    /// "minute" for 1, "minutes" for more.
    public func name(_ every: Int) -> String {
        every == 1 ? String(rawValue.dropLast()) : rawValue
    }

    /// "Every 97 minutes", "Every hour".
    public func describe(every: Int) -> String {
        every == 1 ? "Every \(name(1))" : "Every \(every) \(name(every))"
    }

    /// The seconds in one unit of elapsed time. Nil for a unit that keeps
    /// the time on the clock.
    var elapsedSeconds: TimeInterval? {
        switch self {
        case .minutes: 60
        case .hours: 3600
        case .days, .weeks, .months, .years: nil
        }
    }
}

/// The ring times of a routine the alarm system cannot repeat itself:
/// weekdays every N weeks, and every interval.
extension RoutineSchedule {
    /// The date the series counts from. Nil when there is none to read.
    var start: CivilDate? { startsOn.flatMap { CivilDate(iso: String($0.prefix(10))) } }

    /// The N, held to 1 to 999.
    var step: Int { min(max(every, 1), RoutineUnit.maxEvery) }

    /// True when each ring is a set time after the one before, so its
    /// time of day moves: every N minutes or hours.
    var isElapsed: Bool { repeatMode == .interval && unit.elapsedSeconds != nil }

    /// The ring's stamp, "yyyy-MM-ddTHH:mm": its own scheduled local date
    /// and time, before any delay or snooze. A ring every N minutes or hours
    /// carries the time it rings at. Any other ring carries the routine's
    /// hour and minute, so on a day the clocks skip that time the ring
    /// sounds later and the stamp still names the time it was scheduled for.
    public func stamp(of ring: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: ring)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            isElapsed ? parts.hour ?? 0 : hour, isElapsed ? parts.minute ?? 0 : minute)
    }

    /// The next ring strictly after `now` of a series the alarm system
    /// cannot repeat. Nil with no start date.
    func seriesFire(after now: Date, calendar: Calendar) -> Date? {
        guard let start else { return nil }
        switch repeatMode {
        case .weekdays:
            return weeksFire(after: now, from: start, calendar: calendar)
        case .interval:
            if let seconds = unit.elapsedSeconds {
                return elapsedFire(after: now, from: start, unit: seconds, calendar: calendar)
            }
            return datedFire(after: now, from: start, calendar: calendar)
        }
    }

    /// The latest ring at or before `now` of a series the alarm system
    /// cannot repeat, however long ago. Nil before the first ring, with no
    /// start date, and for a schedule the alarm system repeats itself.
    func lastFire(atOrBefore now: Date, calendar: Calendar) -> Date? {
        guard !fitsSystemRepeat, let start else { return nil }
        switch repeatMode {
        case .weekdays:
            return weeksFire(atOrBefore: now, from: start, calendar: calendar)
        case .interval:
            if let seconds = unit.elapsedSeconds {
                return elapsedFire(atOrBefore: now, from: start, unit: seconds, calendar: calendar)
            }
            return datedFire(atOrBefore: now, from: start, calendar: calendar)
        }
    }

    /// The ring of the series that carries `stamp`, or nil when none does:
    /// the series changed since, or never rang then. `named` is the local
    /// time the stamp reads. A ring every N minutes or hours can be the
    /// second pass of that time, after the clocks went back, so the passes
    /// up to 2 hours on are tried too.
    func ring(stamped stamp: String, near named: Date, calendar: Calendar) -> Date? {
        let candidates: [Date]
        if isElapsed {
            candidates = [0, 1800, 3600, 7200].map { named.addingTimeInterval($0) }
        } else {
            candidates = [ring(on: CivilDate(named, in: calendar.timeZone), calendar: calendar)].compactMap { $0 }
        }
        return candidates.first {
            self.stamp(of: $0, calendar: calendar) == stamp && lastFire(atOrBefore: $0, calendar: calendar) == $0
        }
    }

    /// When hour:minute comes on `day`, by the same rules as a weekday ring.
    func ring(on day: CivilDate, calendar: Calendar) -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard
            let midnight = gregorian.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        else { return nil }
        return clockFire(after: midnight.addingTimeInterval(-1), on: [], calendar: calendar)
    }

    // MARK: Every N minutes or hours

    /// How many rings a search passes over at most. The clocks going back an
    /// hour repeat at most 60 one-minute rings.
    private static let mostDropped = 1500

    /// True for a ring whose stamp an earlier ring of the series already
    /// carried: the clocks went back, the ring reads the same local time as
    /// the instant `shift` seconds before it, and that instant was a ring.
    /// It is dropped, so two rings never share a key.
    private func isDropped(_ ring: Date, anchor: Date, every seconds: TimeInterval, zone: TimeZone) -> Bool {
        let offset = zone.secondsFromGMT(for: ring)
        let shift = zone.secondsFromGMT(for: ring.addingTimeInterval(-86_400)) - offset
        guard shift > 0 else { return false }
        let earlier = ring.addingTimeInterval(TimeInterval(-shift))
        guard zone.secondsFromGMT(for: earlier) == offset + shift, earlier >= anchor else { return false }
        return TimeInterval(shift).truncatingRemainder(dividingBy: seconds) == 0
    }

    private func elapsedFire(after now: Date, from start: CivilDate, unit: TimeInterval, calendar: Calendar) -> Date? {
        guard let anchor = ring(on: start, calendar: calendar) else { return nil }
        let seconds = unit * Double(step)
        var index = now < anchor ? 0 : (now.timeIntervalSince(anchor) / seconds).rounded(.down) + 1
        for _ in 0..<Self.mostDropped {
            let ring = anchor.addingTimeInterval(index * seconds)
            if !isDropped(ring, anchor: anchor, every: seconds, zone: calendar.timeZone) { return ring }
            index += 1
        }
        return nil
    }

    private func elapsedFire(atOrBefore now: Date, from start: CivilDate, unit: TimeInterval, calendar: Calendar)
        -> Date?
    {
        guard let anchor = ring(on: start, calendar: calendar), now >= anchor else { return nil }
        let seconds = unit * Double(step)
        var index = (now.timeIntervalSince(anchor) / seconds).rounded(.down)
        for _ in 0..<Self.mostDropped where index >= 0 {
            let ring = anchor.addingTimeInterval(index * seconds)
            if !isDropped(ring, anchor: anchor, every: seconds, zone: calendar.timeZone) { return ring }
            index -= 1
        }
        return nil
    }

    // MARK: Every N days, weeks, months, or years

    /// How many rings a search tries. Every year from 29 February rings one
    /// year in four, and some in eight.
    private static let mostSkipped = 500

    private var monthsInUnit: Int { unit == .years ? 12 : 1 }
    private var daysInUnit: Int { unit == .weeks ? 7 : 1 }

    /// The date of ring `index`. Nil when its month lacks the start's day,
    /// or it falls past the calendar's end.
    private func date(ofRing index: Int, from start: CivilDate) -> CivilDate? {
        switch unit {
        case .days, .weeks:
            return start.adding(days: index * step * daysInUnit)
        case .months, .years:
            guard let moved = start.adding(months: index * step * monthsInUnit), moved.day == start.day
            else { return nil }
            return moved
        case .minutes, .hours:
            return nil
        }
    }

    /// The last ring whose date is on or before `day`, or whose month is for
    /// months and years. 0 before the start.
    private func ringIndex(near day: CivilDate, from start: CivilDate) -> Int {
        switch unit {
        case .months, .years:
            let months = (day.year - start.year) * 12 + day.month - start.month
            return max(months / (step * monthsInUnit), 0)
        case .minutes, .hours, .days, .weeks:
            return max((day.dayNumber - start.dayNumber) / (step * daysInUnit), 0)
        }
    }

    private func datedFire(after now: Date, from start: CivilDate, calendar: Calendar) -> Date? {
        let first = ringIndex(near: CivilDate(now, in: calendar.timeZone), from: start)
        for index in first..<(first + Self.mostSkipped) {
            guard let day = date(ofRing: index, from: start), let at = ring(on: day, calendar: calendar)
            else { continue }
            if at > now { return at }
        }
        return nil
    }

    private func datedFire(atOrBefore now: Date, from start: CivilDate, calendar: Calendar) -> Date? {
        let last = ringIndex(near: CivilDate(now, in: calendar.timeZone), from: start)
        for index in stride(from: last, through: max(last - Self.mostSkipped, 0), by: -1) {
            guard let day = date(ofRing: index, from: start), let at = ring(on: day, calendar: calendar)
            else { continue }
            if at <= now { return at }
        }
        return nil
    }

    // MARK: Weekdays every N weeks

    /// The days a search looks at: the rest of one ring week and all of the next.
    private static let mostDays = 32

    /// The day number of the Monday of the start's week. Weeks start on Monday.
    private func firstMonday(_ start: CivilDate) -> Int { start.dayNumber - (start.weekday - 1) }

    private func weeksFire(after now: Date, from start: CivilDate, calendar: Calendar) -> Date? {
        let first = firstMonday(start)
        var number = max(CivilDate(now, in: calendar.timeZone).dayNumber, start.dayNumber)
        for _ in 0..<Self.mostDays {
            let week = (number - first) / 7
            if week % step != 0 {
                // An off week: on to the Monday of the next ring week.
                number = first + (week + step - week % step) * 7
                continue
            }
            let day = CivilDate(dayNumber: number)
            if days.contains(day.weekday), let at = ring(on: day, calendar: calendar), at > now { return at }
            number += 1
        }
        return nil
    }

    private func weeksFire(atOrBefore now: Date, from start: CivilDate, calendar: Calendar) -> Date? {
        let first = firstMonday(start)
        var number = CivilDate(now, in: calendar.timeZone).dayNumber
        for _ in 0..<Self.mostDays where number >= start.dayNumber {
            let week = (number - first) / 7
            if week % step != 0 {
                // An off week: back to the Sunday of the ring week before it.
                number = first + (week - week % step) * 7 + 6
                continue
            }
            let day = CivilDate(dayNumber: number)
            if days.contains(day.weekday), let at = ring(on: day, calendar: calendar), at <= now { return at }
            number -= 1
        }
        return nil
    }
}

extension RoutineDraft {
    /// "Wed 25 Nov", with the year when it is not `today`'s.
    static func dayText(_ day: CivilDate, today: CivilDate) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let text = "\(day.weekdayName) \(day.day) \(months[day.month - 1])"
        return day.year == today.year ? text : "\(text) \(day.year)"
    }

    /// The line under the editor's repeat controls: what the alarm will do
    /// as it stands.
    public func repeatNote(today: CivilDate) -> String {
        if repeatMode == .weekdays, days.isEmpty {
            return every > 1
                ? "Choose the days it rings on."
                : "No repeat. It rings on the next day at this time until you stop it, then switches off."
        }
        let text = Routine.repeatText(repeatMode: repeatMode, every: every, unit: unit, days: days)
        if repeatMode == .weekdays, every <= 1 { return "Repeats: \(text). It rings until you stop it." }
        let from = startsOn.flatMap { CivilDate(iso: $0) }.map { ", from " + Self.dayText($0, today: today) } ?? ""
        return "Repeats: \(text)\(from). It rings until you stop it. The phone sets the next rings each time it syncs."
    }
}
