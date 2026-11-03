import Foundation
import Testing

@testable import AlarmCore

/// The typed length and lead on the event forms, and a new event's defaults.
@Suite struct TimeSpanTests {
    @Test func minutesComeFromTheAmountAndTheUnit() {
        #expect(TimeSpan(45, .minutes).minutes == 45)
        #expect(TimeSpan(3, .hours).minutes == 180)
        #expect(TimeSpan(2, .days).minutes == 2880)
        #expect(TimeSpan(Int.max, .days).minutes == .max)
    }

    @Test func aStoredLengthShowsInTheLargestWholeUnit() {
        #expect(TimeSpan(minutes: 0) == TimeSpan(0, .minutes))
        #expect(TimeSpan(minutes: 90) == TimeSpan(90, .minutes))
        #expect(TimeSpan(minutes: 120) == TimeSpan(2, .hours))
        #expect(TimeSpan(minutes: 1440) == TimeSpan(1, .days))
        #expect(TimeSpan(minutes: 1500) == TimeSpan(25, .hours))
    }

    @Test func aTypedAmountKeepsItsDigits() {
        #expect(TimeSpan.amount(typed: "30") == 30)
        #expect(TimeSpan.amount(typed: "30 min") == 30)
        #expect(TimeSpan.amount(typed: "") == 0)
        #expect(TimeSpan.amount(typed: String(repeating: "9", count: 30)) == 999_999_999)
    }

    @Test func unitNamesAgreeWithTheAmount() {
        #expect(TimeSpan.Unit.hours.name(1) == "hour")
        #expect(TimeSpan.Unit.hours.name(2) == "hours")
        #expect(TimeSpan.Unit.minutes.name(0) == "minutes")
    }

    @Test func aNewEventStartsAtTheNextWholeOrHalfHour() {
        let base = Date(timeIntervalSinceReferenceDate: 1800 * 1000)
        #expect(NewEvent.defaultStart(after: base) == base.addingTimeInterval(1800))
        #expect(NewEvent.defaultStart(after: base.addingTimeInterval(1)) == base.addingTimeInterval(1800))
        #expect(NewEvent.defaultStart(after: base.addingTimeInterval(1799)) == base.addingTimeInterval(1800))
        #expect(NewEvent.defaultStart(after: base.addingTimeInterval(1800)) == base.addingTimeInterval(3600))
        #expect(NewEvent.defaultLength.minutes == 30)
    }

    @Test func aDaysLengthPastTheServersBoundIsAProblem() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        var event = NewEvent(
            title: "Trip", startsAt: now.addingTimeInterval(3600), durationMinutes: TimeSpan(2, .days).minutes,
            location: nil, type: AlertType.alarm, leadMinutes: TimeSpan(1, .days).minutes)
        #expect(event.problems(now: now) == ["The length must be 5 minutes to 24 hours."])
        event.durationMinutes = TimeSpan(1, .days).minutes
        #expect(event.problems(now: now).isEmpty)
    }
}
