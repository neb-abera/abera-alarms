import Testing

@testable import AlarmCore

@Suite struct TimerLengthTests {
    @Test func secondsComeFromTheAmountAndTheUnit() {
        #expect(TimerLength(90, .seconds).seconds == 90)
        #expect(TimerLength(25, .minutes).seconds == 1500)
        #expect(TimerLength(2, .hours).seconds == 7200)
        #expect(TimerLength.standard.seconds == 600)
    }

    @Test func zeroAndMoreThanAWeekCannotStart() {
        #expect(TimerLength(0, .minutes).problems == ["Enter a length of at least 1 second."])
        #expect(TimerLength(169, .hours).problems == ["A timer runs at most 7 days."])
        #expect(TimerLength(168, .hours).problems.isEmpty)
        #expect(TimerLength(Int.max, .hours).problems == ["A timer runs at most 7 days."])
    }

    @Test func theClockShowsHoursOnlyWhenThereAreAny() {
        #expect(TimerLength.clock(299) == "4:59")
        #expect(TimerLength.clock(3909) == "1:05:09")
        #expect(TimerLength.clock(-3) == "0:00")
    }

    @Test func unitNamesAgreeWithTheAmount() {
        #expect(TimerLength.Unit.minutes.name(1) == "minute")
        #expect(TimerLength.Unit.seconds.name(30) == "seconds")
    }
}
