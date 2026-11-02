import Foundation
import Testing

@testable import AlarmCore

/// The rest timer: the countdown, minus and plus, Restart and End.
@Suite struct RestTests {
    let zero = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func at(_ seconds: TimeInterval) -> Date { zero.addingTimeInterval(seconds) }

    @Test func aNewRestIsNinetySecondsAndStopped() {
        let rest = Rest()
        #expect(rest.length == 90)
        #expect(!rest.running(at: zero))
        #expect(rest.remaining(at: zero) == 90)
        #expect(rest.clock(at: zero) == "1:30")
    }

    @Test func restartCountsDownTheFullRest() {
        var rest = Rest(length: 60)
        rest.restart(at: zero)
        #expect(rest.running(at: zero))
        #expect(rest.endsAt == at(60))
        #expect(rest.remaining(at: at(20)) == 40)
        #expect(rest.clock(at: at(20.4)) == "0:40")
    }

    @Test func restartWhileRunningStartsAgainFromTheTop() {
        var rest = Rest(length: 60)
        rest.restart(at: zero)
        rest.restart(at: at(45))
        #expect(rest.endsAt == at(105))
    }

    @Test func theCountdownStopsAtZero() {
        var rest = Rest(length: 30)
        rest.restart(at: zero)
        #expect(!rest.running(at: at(30)))
        #expect(rest.remaining(at: at(90)) == 0)
        #expect(rest.clock(at: at(90)) == "0:00")
    }

    @Test func plusAndMinusMoveTheRunningCountdownAndKeepTheLength() {
        var rest = Rest(length: 90)
        rest.restart(at: zero)
        rest.adjust(by: Rest.step, at: at(10))
        #expect(rest.endsAt == at(105))
        rest.adjust(by: -Rest.step, at: at(20))
        rest.adjust(by: -Rest.step, at: at(20))
        #expect(rest.endsAt == at(75))
        #expect(rest.length == 90)
    }

    @Test func minusPastZeroEndsTheCountdownWithoutChangingTheLength() {
        var rest = Rest(length: 90)
        rest.restart(at: zero)
        rest.adjust(by: -Rest.step, at: at(80))
        #expect(rest.endsAt == nil)
        #expect(rest.length == 90)
    }

    @Test func plusStopsAtTheLongestRest() {
        var rest = Rest(length: 90)
        rest.restart(at: zero)
        rest.adjust(by: 2 * Rest.longest, at: zero)
        #expect(rest.endsAt == at(TimeInterval(Rest.longest)))
    }

    @Test func plusAndMinusChangeTheLengthWhileNoneRuns() {
        var rest = Rest(length: 90)
        rest.adjust(by: Rest.step, at: zero)
        #expect(rest.length == 105)
        rest.adjust(by: -Rest.step, at: zero)
        rest.adjust(by: -Rest.step, at: zero)
        #expect(rest.length == 75)
        #expect(rest.endsAt == nil)
    }

    @Test func afterARingPlusAndMinusChangeTheLength() {
        var rest = Rest(length: 60)
        rest.restart(at: zero)
        rest.adjust(by: Rest.step, at: at(61))
        #expect(rest.length == 75)
        #expect(rest.endsAt == nil)
    }

    @Test func theLengthStaysBetweenTheShortestAndLongest() {
        var rest = Rest(length: 15)
        rest.adjust(by: -Rest.step, at: zero)
        #expect(rest.length == Rest.shortest)
        #expect(Rest(length: 99_999).length == Rest.longest)
        #expect(Rest(length: -5).length == Rest.shortest)
    }

    @Test func endStopsTheCountdownAndKeepsTheLength() {
        var rest = Rest(length: 120)
        rest.restart(at: zero)
        rest.end()
        #expect(!rest.running(at: zero))
        #expect(rest.length == 120)
        #expect(rest.remaining(at: at(5)) == 120)
    }

    @Test func itSurvivesBeingSavedAndRead() throws {
        var rest = Rest(length: 75)
        rest.restart(at: zero)
        let read = try JSONDecoder().decode(Rest.self, from: JSONEncoder().encode(rest))
        #expect(read == rest)
    }
}
