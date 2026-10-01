import Foundation
import Testing

@testable import AlarmCore

/// The date calculator. The cases are the same table abera.tech's tests use,
/// so the phone and the site give the same answer.
@Suite struct DateCalcTests {
    static func day(_ text: String) -> CivilDate { CivilDate(iso: text)! }

    struct Between: CustomTestStringConvertible, Sendable {
        var start: String
        var end: String
        var includeEnd: Bool
        var total: Int
        var years: Int
        var months: Int
        var days: Int
        var weeks: Int
        var remainder: Int
        var weekdays: Int

        var testDescription: String { "\(start) to \(end)\(includeEnd ? " including the end" : "")" }
    }

    static let between: [Between] = [
        .init(
            start: "2026-10-01", end: "2026-11-15", includeEnd: false, total: 45, years: 0, months: 1, days: 14,
            weeks: 6, remainder: 3, weekdays: 32),
        .init(
            start: "2026-10-01", end: "2026-11-15", includeEnd: true, total: 46, years: 0, months: 1, days: 15,
            weeks: 6, remainder: 4, weekdays: 32),
        .init(
            start: "2026-01-31", end: "2026-03-01", includeEnd: false, total: 29, years: 0, months: 1, days: 1,
            weeks: 4, remainder: 1, weekdays: 20),
        .init(
            start: "2024-02-29", end: "2025-02-28", includeEnd: false, total: 365, years: 1, months: 0, days: 0,
            weeks: 52, remainder: 1, weekdays: 261),
        .init(
            start: "2024-02-29", end: "2028-02-29", includeEnd: false, total: 1461, years: 4, months: 0, days: 0,
            weeks: 208, remainder: 5, weekdays: 1043),
        .init(
            start: "2026-12-25", end: "2026-10-01", includeEnd: false, total: -85, years: 0, months: 2, days: 24,
            weeks: 12, remainder: 1, weekdays: 61),
        .init(
            start: "2026-10-01", end: "2026-10-01", includeEnd: false, total: 0, years: 0, months: 0, days: 0,
            weeks: 0, remainder: 0, weekdays: 0),
        .init(
            start: "2026-10-01", end: "2026-10-01", includeEnd: true, total: 1, years: 0, months: 0, days: 1,
            weeks: 0, remainder: 1, weekdays: 1),
        .init(
            start: "2026-03-01", end: "2026-03-31", includeEnd: true, total: 31, years: 0, months: 1, days: 0,
            weeks: 4, remainder: 3, weekdays: 22),
        .init(
            start: "1991-10-07", end: "2026-10-01", includeEnd: false, total: 12778, years: 34, months: 11, days: 24,
            weeks: 1825, remainder: 3, weekdays: 9128),
    ]

    @Test(arguments: between)
    func betweenTwoDates(_ c: Between) {
        let span = DateSpan.between(Self.day(c.start), Self.day(c.end), includeEnd: c.includeEnd)
        #expect(span.totalDays == c.total)
        #expect(span.isBefore == (c.total < 0))
        #expect(span.years == c.years)
        #expect(span.months == c.months)
        #expect(span.days == c.days)
        #expect(span.weeks == c.weeks)
        #expect(span.remainderDays == c.remainder)
        #expect(span.weekdays == c.weekdays)
        #expect(span.hours == c.total * 24)
        #expect(span.minutes == c.total * 1440)
        #expect(span.seconds == c.total * 86_400)
    }

    struct Shift: CustomTestStringConvertible, Sendable {
        var date: String
        var years: Int
        var months: Int
        var weeks: Int
        var days: Int
        var result: String
        var weekday: String

        var testDescription: String { "\(date) \(years)y \(months)m \(weeks)w \(days)d" }
    }

    static let shifts: [Shift] = [
        .init(date: "2026-01-31", years: 0, months: 1, weeks: 0, days: 0, result: "2026-02-28", weekday: "Sat"),
        .init(date: "2024-02-29", years: 1, months: 0, weeks: 0, days: 0, result: "2025-02-28", weekday: "Fri"),
        .init(date: "2026-10-01", years: 0, months: 0, weeks: 6, days: 3, result: "2026-11-15", weekday: "Sun"),
        .init(date: "2026-10-01", years: 0, months: -1, weeks: 0, days: -1, result: "2026-08-31", weekday: "Mon"),
        .init(date: "2026-10-01", years: 0, months: 0, weeks: 0, days: -365, result: "2025-10-01", weekday: "Wed"),
        .init(date: "2026-03-31", years: 0, months: 6, weeks: 0, days: 0, result: "2026-09-30", weekday: "Wed"),
    ]

    @Test(arguments: shifts)
    func addingToADate(_ c: Shift) throws {
        let result = try #require(
            DateShift.apply(to: Self.day(c.date), years: c.years, months: c.months, weeks: c.weeks, days: c.days))
        #expect(result.iso == c.result)
        #expect(result.weekdayName == c.weekday)
    }

    /// Years and months are one step of years × 12 + months, clamped once,
    /// as on the site (and Java's LocalDate.plus(Period)).
    @Test(arguments: [
        ("2024-02-29", 1, 1, "2025-03-29"), ("2024-02-29", 1, 0, "2025-02-28"), ("2026-01-31", 0, 13, "2027-02-28"),
    ])
    func yearsAndMonthsAreOneStep(date: String, years: Int, months: Int, result: String) {
        #expect(DateShift.apply(to: Self.day(date), years: years, months: months, weeks: 0, days: 0)?.iso == result)
    }

    @Test func aShiftOutsideTheCalendarIsNoDate() {
        #expect(DateShift.apply(to: Self.day("9999-12-31"), years: 0, months: 0, weeks: 0, days: 1) == nil)
        #expect(DateShift.apply(to: Self.day("0001-01-01"), years: 0, months: -1, weeks: 0, days: 0) == nil)
        #expect(DateShift.apply(to: Self.day("2026-10-01"), years: Int.max, months: 0, weeks: 0, days: 0) == nil)
        #expect(DateShift.apply(to: Self.day("2026-10-01"), years: 0, months: Int.min, weeks: 0, days: 0) == nil)
        #expect(DateShift.apply(to: Self.day("2026-10-01"), years: 0, months: Int.max, weeks: 0, days: 0) == nil)
        #expect(DateShift.apply(to: Self.day("2026-10-01"), years: 1, months: Int.max, weeks: 0, days: 0) == nil)
        #expect(DateShift.apply(to: Self.day("2026-10-01"), years: 0, months: 0, weeks: Int.max, days: 0) == nil)
        #expect(DateShift.apply(to: Self.day("2026-10-01"), years: 0, months: 0, weeks: 1, days: Int.max) == nil)
    }

    @Test(arguments: [
        ("2026-10-01", 4, "Thu"), ("2026-10-04", 7, "Sun"), ("2026-10-05", 1, "Mon"), ("1970-01-01", 4, "Thu"),
        ("0001-01-01", 1, "Mon"), ("2000-02-29", 2, "Tue"),
    ])
    func weekdaysAreISO(text: String, weekday: Int, name: String) {
        #expect(Self.day(text).weekday == weekday)
        #expect(Self.day(text).weekdayName == name)
    }

    @Test(arguments: [
        "", "2026-1-01", "2026-13-01", "2026-02-29", "2026-04-31", "2026-00-10", "2026-10-00", "0000-01-01",
        "２０２６-10-01", "2026/10/01", "2026-10-01T00:00", "+2026-10-01", "2026-10-1a",
    ])
    func refusesWhatIsNotADate(text: String) {
        #expect(CivilDate(iso: text) == nil)
    }

    @Test func readsAndWritesISO() {
        #expect(CivilDate(iso: " 2024-02-29 ")?.iso == "2024-02-29")
        #expect(CivilDate(year: 1, month: 1, day: 1)?.iso == "0001-01-01")
        #expect(CivilDate(year: 10_000, month: 1, day: 1) == nil)
        #expect(Self.day("2026-10-01") < Self.day("2026-10-02"))
    }

    @Test func theLastDayOfTheCalendarCanBeIncluded() {
        let span = DateSpan.between(Self.day("9999-12-30"), Self.day("9999-12-31"), includeEnd: true)
        #expect(span.totalDays == 2)
        #expect(span.days == 2)
    }

    @Test func dayNumbersRoundTripAcrossTheWholeRange() {
        for text in ["0001-01-01", "1600-02-29", "1900-03-01", "1970-01-01", "2026-10-01", "9999-12-31"] {
            let date = Self.day(text)
            #expect(CivilDate(dayNumber: date.dayNumber) == date)
        }
        #expect(Self.day("1970-01-01").dayNumber == 0)
        #expect(Self.day("2026-10-01").dayNumber == 20_727)
    }

    /// The phone's today, in its own zone, as a plain date.
    @Test func todayInAZone() throws {
        let instant = try #require(ServerDates.parse("2026-10-01T22:30:00Z"))
        #expect(CivilDate(instant, in: TimeZone(identifier: "Asia/Amman")!).iso == "2026-10-02")
        #expect(CivilDate(instant, in: TimeZone(identifier: "America/New_York")!).iso == "2026-10-01")
    }

    /// A property: adding the span's total days to the start gives the end,
    /// and the y/m/d split adds back to the end, for many pairs.
    @Test func theSplitAddsBackToTheEnd() throws {
        var generator = SplitMix(seed: 42)
        for _ in 0..<2_000 {
            let a = CivilDate(dayNumber: Int(generator.next() % 80_000) - 20_000)
            let b = CivilDate(dayNumber: Int(generator.next() % 80_000) - 20_000)
            let span = DateSpan.between(a, b, includeEnd: false)
            #expect(a.adding(days: span.totalDays) == b)
            let (low, high) = a <= b ? (a, b) : (b, a)
            let back = try #require(low.adding(months: span.years * 12 + span.months)?.adding(days: span.days))
            #expect(back == high)
            #expect(span.days < 31)
            #expect(span.weekdays <= abs(span.totalDays))
        }
    }
}

/// A small seeded generator, so the property test is the same every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct DateSpanTextTests {
    @Test func readsAsTheSiteWritesIt() {
        let span = DateSpan.between(CivilDate(iso: "2026-10-01")!, CivilDate(iso: "2026-11-15")!, includeEnd: false)
        #expect(span.totalText == "45 days")
        #expect(span.calendarText == "0 years, 1 month, 14 days")
        #expect(span.weeksText == "6 weeks, 3 days")
    }

    @Test func anEarlierEndIsBeforeTheStart() {
        let span = DateSpan.between(CivilDate(iso: "2026-12-25")!, CivilDate(iso: "2026-10-01")!, includeEnd: false)
        #expect(span.totalText == "85 days before the start")
        let one = DateSpan.between(CivilDate(iso: "2026-10-02")!, CivilDate(iso: "2026-10-01")!, includeEnd: false)
        #expect(one.totalText == "1 day before the start")
        #expect(one.calendarText == "0 years, 0 months, 1 day")
        #expect(one.weeksText == "0 weeks, 1 day")
    }
}
