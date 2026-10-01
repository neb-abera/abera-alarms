import Foundation
import Testing

@testable import AlarmCore

/// When an alarm next rings, and the clock that counts down to it. The next
/// ring is `RoutineSchedule.nextFire`, the function the reconciler already
/// schedules with.
@Suite struct RingClockTests {
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static let newYork = calendar("America/New_York")

    func at(_ text: String) -> Date { ServerDates.parse(text)! }

    func routine(_ hour: Int, _ minute: Int, days: [Int] = [], enabled: Bool = true) -> Routine {
        Routine(id: UUID(), label: "Wake", hour: hour, minute: minute, days: days, enabled: enabled)
    }

    func next(_ routine: Routine, after now: String, in calendar: Calendar = newYork) -> Date? {
        routine.nextFire(after: at(now), calendar: calendar)
    }

    // MARK: The next ring

    /// From Monday 2026-10-05 12:00 in New York, a 06:00 alarm on one weekday.
    @Test(arguments: [
        (1, "2026-10-12T06:00:00-04:00"), (2, "2026-10-06T06:00:00-04:00"), (3, "2026-10-07T06:00:00-04:00"),
        (4, "2026-10-08T06:00:00-04:00"), (5, "2026-10-09T06:00:00-04:00"), (6, "2026-10-10T06:00:00-04:00"),
        (7, "2026-10-11T06:00:00-04:00"),
    ])
    func eachWeekday(day: Int, expected: String) {
        #expect(next(routine(6, 0, days: [day]), after: "2026-10-05T12:00:00-04:00") == at(expected))
    }

    @Test(arguments: [
        ([1, 2, 3, 4, 5], "2026-10-09T18:00:00-04:00", "2026-10-12T06:00:00-04:00"),
        ([6, 7], "2026-10-05T12:00:00-04:00", "2026-10-10T06:00:00-04:00"),
        (Array(1...7), "2026-10-05T12:00:00-04:00", "2026-10-06T06:00:00-04:00"),
        ([3, 5], "2026-10-07T05:59:00-04:00", "2026-10-07T06:00:00-04:00"),
    ])
    func weekdaySets(days: [Int], now: String, expected: String) {
        #expect(next(routine(6, 0, days: days), after: now) == at(expected))
    }

    @Test func noRepeatRingsTodayBeforeItsTimeAndTomorrowAfter() {
        #expect(next(routine(15, 0), after: "2026-10-05T12:00:00-04:00") == at("2026-10-05T15:00:00-04:00"))
        #expect(next(routine(6, 0), after: "2026-10-05T12:00:00-04:00") == at("2026-10-06T06:00:00-04:00"))
    }

    /// At the minute itself the alarm is ringing: the next ring is the next day.
    @Test func theMinuteItselfIsTheNextRingAfterThis() {
        #expect(next(routine(6, 0), after: "2026-10-05T05:59:59-04:00") == at("2026-10-05T06:00:00-04:00"))
        #expect(next(routine(6, 0), after: "2026-10-05T06:00:00-04:00") == at("2026-10-06T06:00:00-04:00"))
        #expect(next(routine(6, 0), after: "2026-10-05T06:00:30-04:00") == at("2026-10-06T06:00:00-04:00"))
    }

    /// 2027-03-14: New York's clocks go from 02:00 to 03:00.
    @Test func springForward() {
        #expect(next(routine(6, 0), after: "2027-03-13T12:00:00-05:00") == at("2027-03-14T06:00:00-04:00"))
        // 02:30 does not exist that night. It rings when the clock reaches 03:00.
        #expect(next(routine(2, 30), after: "2027-03-13T12:00:00-05:00") == at("2027-03-14T03:00:00-04:00"))
        #expect(next(routine(2, 30), after: "2027-03-14T03:00:00-04:00") == at("2027-03-15T02:30:00-04:00"))
    }

    /// 2026-11-01: New York's clocks go from 02:00 back to 01:00.
    @Test func fallBack() {
        #expect(next(routine(6, 0), after: "2026-10-31T12:00:00-04:00") == at("2026-11-01T06:00:00-05:00"))
        // 01:30 happens twice that night. It rings at the first.
        #expect(next(routine(1, 30), after: "2026-10-31T12:00:00-04:00") == at("2026-11-01T01:30:00-04:00"))
        // Once rung, a daily alarm waits for the next day, not the repeated hour.
        #expect(next(routine(1, 30), after: "2026-11-01T01:45:00-04:00") == at("2026-11-02T01:30:00-05:00"))
        #expect(
            next(routine(1, 30, days: [7]), after: "2026-11-01T01:45:00-04:00") == at("2026-11-08T01:30:00-05:00"))
    }

    /// The same alarm rings at 06:00 wherever the phone is.
    @Test func theZoneThePhoneIsIn() {
        let wake = routine(6, 0)
        let now = "2026-10-05T12:00:00Z"
        #expect(next(wake, after: now, in: Self.calendar("Asia/Amman")) == at("2026-10-06T06:00:00+03:00"))
        #expect(next(wake, after: now, in: Self.newYork) == at("2026-10-06T06:00:00-04:00"))
        #expect(next(wake, after: now, in: Self.calendar("UTC")) == at("2026-10-06T06:00:00Z"))
    }

    // MARK: The clock

    @Test func aRoutineThatIsOnCountsDown() {
        let text = RingClock.text(
            for: routine(18, 12, days: [1]), at: at("2026-10-05T12:00:00-04:00"), calendar: Self.newYork)
        #expect(text == "Rings in 0 days 06:12:00")
    }

    @Test func aRoutineThatIsOffHasNoClock() {
        let off = routine(18, 12, days: [1], enabled: false)
        #expect(RingClock.text(for: off, at: at("2026-10-05T12:00:00-04:00"), calendar: Self.newYork) == nil)
    }

    func alert(
        alertAt: String = "2026-10-05T13:02:03Z", type: String = AlertType.alarm, skipped: Bool = false,
        muted: Bool = false, acknowledged: Bool = false
    ) -> PlannedAlert {
        PlannedAlert(
            key: "standup", title: "Standup", startsAt: at("2026-10-05T14:00:00Z"), alertAt: at(alertAt),
            skipped: skipped, muted: muted, type: type, acknowledged: acknowledged)
    }

    @Test func anAlarmSetOnThePhoneCountsDownToItsAlert() {
        #expect(RingClock.text(for: alert(), held: true, at: at("2026-10-05T12:00:00Z")) == "Rings in 0 days 01:02:03")
    }

    @Test func anAlarmThatWillNotRingHereHasNoClock() {
        let now = at("2026-10-05T12:00:00Z")
        #expect(RingClock.text(for: alert(), held: false, at: now) == nil)
        #expect(RingClock.text(for: alert(skipped: true), held: true, at: now) == nil)
        #expect(RingClock.text(for: alert(muted: true), held: true, at: now) == nil)
        #expect(RingClock.text(for: alert(acknowledged: true), held: true, at: now) == nil)
        #expect(RingClock.text(for: alert(type: AlertType.notification), held: true, at: now) == nil)
        // Rung: its time has passed.
        #expect(RingClock.text(for: alert(alertAt: "2026-10-05T11:59:59Z"), held: true, at: now) == nil)
        #expect(RingClock.text(for: alert(alertAt: "2026-10-05T12:00:00Z"), held: true, at: now) == nil)
    }
}
