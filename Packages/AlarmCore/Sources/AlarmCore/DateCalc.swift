import Foundation

/// A day in the proleptic Gregorian calendar, years 1 to 9999, with no time
/// and no zone. The date calculator works on these alone, so no zone shift
/// or daylight saving change can move an answer by a day.
public struct CivilDate: Comparable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
            (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// "YYYY-MM-DD", ASCII digits only. Surrounding spaces are ignored.
    public init?(iso text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.utf8.count) == [4, 2, 2],
            parts.allSatisfy({ $0.utf8.allSatisfy { (0x30...0x39).contains($0) } }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The date an instant falls on in a zone: the phone's today.
    public init(_ instant: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        // A Gregorian calendar always gives all three. An instant outside years 1 to 9999 reads as 1970-01-01.
        self = CivilDate(year: parts.year!, month: parts.month!, day: parts.day!) ?? Self.epoch
    }

    static let epoch = CivilDate(year: 1970, month: 1, day: 1)!

    /// Days since 1970-01-01. The days-from-civil algorithm (Howard Hinnant).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        // Years start at 1, so y is never negative and plain division is floor division.
        let era = y / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The date `dayNumber` days after 1970-01-01, clamped to the calendar's range.
    public init(dayNumber: Int) {
        let days = min(max(dayNumber, Self.first.dayNumber), Self.last.dayNumber) + 719_468
        // Clamped to year 1 on, so days is never negative.
        let era = days / 146_097
        let dayOfEra = days - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.month = month
        self.day = day
    }

    static let first = CivilDate(year: 1, month: 1, day: 1)!
    static let last = CivilDate(year: 9999, month: 12, day: 31)!

    public static func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// ISO weekday: Monday 1 to Sunday 7. 1970-01-01 was a Thursday.
    public var weekday: Int {
        let fromMonday = (dayNumber + 3) % 7
        return (fromMonday < 0 ? fromMonday + 7 : fromMonday) + 1
    }

    public var weekdayName: String { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][weekday - 1] }

    /// Nil past either end of the calendar.
    public func adding(days: Int) -> CivilDate? {
        let (sum, overflow) = dayNumber.addingReportingOverflow(days)
        guard !overflow, (Self.first.dayNumber...Self.last.dayNumber).contains(sum) else { return nil }
        return CivilDate(dayNumber: sum)
    }

    /// The same day `months` months on, or the month's last day when it is
    /// shorter: January 31 plus a month is February 28. Nil past either end.
    public func adding(months: Int) -> CivilDate? {
        let (index, overflow) = (year * 12 + month - 1).addingReportingOverflow(months)
        guard !overflow else { return nil }
        let year = index >= 0 ? index / 12 : -1
        let month = index - year * 12 + 1
        guard (1...9999).contains(year) else { return nil }
        return CivilDate(year: year, month: month, day: min(day, Self.daysInMonth(year: year, month: month)))
    }

    public static func < (a: CivilDate, b: CivilDate) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

/// The span between two dates, as abera.tech's date calculator shows it.
public struct DateSpan: Equatable, Sendable {
    /// Negative when the end is before the start.
    public var totalDays: Int
    public var years: Int
    public var months: Int
    public var days: Int
    /// Whole weeks and the days left over, of the total without its sign.
    public var weeks: Int
    public var remainderDays: Int
    /// Monday to Friday days from the earlier date up to, not including, the later.
    public var weekdays: Int

    public var isBefore: Bool { totalDays < 0 }
    public var hours: Int { totalDays * 24 }
    public var minutes: Int { totalDays * 1440 }
    public var seconds: Int { totalDays * 86_400 }

    /// With start s and end e: when e is before s they swap and the total is
    /// negative. Including the end adds a day to e. Months are the most whole
    /// months m with s + m months (clamped) not past e, split into years and
    /// months, and the days are what is left.
    public static func between(_ start: CivilDate, _ end: CivilDate, includeEnd: Bool) -> DateSpan {
        let negative = end < start
        let low = negative ? end : start
        let high = negative ? start : end
        let lowDay = low.dayNumber
        let highDay = high.dayNumber + (includeEnd ? 1 : 0)
        let total = highDay - lowDay

        let last = includeEnd ? (high.adding(days: 1) ?? high) : high
        var months = (last.year - low.year) * 12 + (last.month - low.month)
        while months > 0, (low.adding(months: months)?.dayNumber ?? Int.max) > highDay { months -= 1 }
        let anchor = low.adding(months: months)?.dayNumber ?? lowDay

        return DateSpan(
            totalDays: negative ? -total : total, years: months / 12, months: months % 12, days: highDay - anchor,
            weeks: total / 7, remainderDays: total % 7, weekdays: weekdays(from: lowDay, count: total))
    }

    /// Monday to Friday days in the `count` days from `first`.
    static func weekdays(from first: Int, count: Int) -> Int {
        var result = count / 7 * 5
        let start = CivilDate(dayNumber: first).weekday
        for offset in 0..<(count % 7) where (start - 1 + offset) % 7 < 5 { result += 1 }
        return result
    }
}

/// Adding to or subtracting from a date, as abera.tech's calculator does it:
/// years, then months (each clamped to the month's last day), then
/// weeks × 7 + days.
public enum DateShift {
    /// Nil when the result is outside years 1 to 9999.
    public static func apply(to date: CivilDate, years: Int, months: Int, weeks: Int, days: Int) -> CivilDate? {
        let (yearMonths, overflowYears) = years.multipliedReportingOverflow(by: 12)
        let (weekDays, overflowWeeks) = weeks.multipliedReportingOverflow(by: 7)
        guard !overflowYears, !overflowWeeks else { return nil }
        let (allDays, overflowDays) = weekDays.addingReportingOverflow(days)
        guard !overflowDays else { return nil }
        return date.adding(months: yearMonths)?.adding(months: months)?.adding(days: allDays)
    }
}

extension DateSpan {
    /// "1 day", "2 days".
    static func count(_ value: Int, _ unit: String) -> String { "\(value) \(unit)\(value == 1 ? "" : "s")" }

    /// "45 days", or "85 days before the start" when the end is earlier.
    public var totalText: String {
        isBefore ? "\(Self.count(-totalDays, "day")) before the start" : Self.count(totalDays, "day")
    }

    /// "0 years, 1 month, 14 days".
    public var calendarText: String {
        "\(Self.count(years, "year")), \(Self.count(months, "month")), \(Self.count(days, "day"))"
    }

    /// "6 weeks, 3 days".
    public var weeksText: String { "\(Self.count(weeks, "week")), \(Self.count(remainderDays, "day"))" }
}
