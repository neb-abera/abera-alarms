import Foundation
import Testing

@testable import AlarmCore

/// The workout timer: the clock, the sets and the spoken times.
@Suite struct WorkoutTests {
    let zero = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func at(_ seconds: TimeInterval) -> Date { zero.addingTimeInterval(seconds) }

    // MARK: The clock

    @Test func aNewTimerIsSetOneAtZeroAndStopped() {
        let workout = Workout()
        #expect(workout.set == 1)
        #expect(!workout.running)
        #expect(!workout.started)
        #expect(workout.elapsed(at: at(100)) == 0)
        #expect(workout.interval == 30)
    }

    @Test func theClockCountsFromTheStart() {
        var workout = Workout()
        workout.start(at: zero)
        #expect(workout.running)
        #expect(workout.elapsed(at: at(42.5)) == 42.5)
    }

    @Test func pauseHoldsTheClockAndStartCarriesOn() {
        var workout = Workout()
        workout.start(at: zero)
        workout.pause(at: at(20))
        #expect(!workout.running)
        #expect(workout.started)
        #expect(workout.elapsed(at: at(500)) == 20)
        workout.start(at: at(500))
        #expect(workout.elapsed(at: at(510)) == 30)
    }

    @Test func startTwiceAndPauseTwiceChangeNothing() {
        var workout = Workout()
        workout.pause(at: zero)
        #expect(workout == Workout())
        workout.start(at: zero)
        workout.start(at: at(10))
        #expect(workout.elapsed(at: at(10)) == 10)
        workout.pause(at: at(10))
        workout.pause(at: at(20))
        #expect(workout.elapsed(at: at(30)) == 10)
    }

    @Test func aClockBeforeItsStartReadsZero() {
        var workout = Workout()
        workout.start(at: at(10))
        #expect(workout.elapsed(at: zero) == 0)
    }

    // MARK: Sets

    @Test func nextSetRecordsTheSetAndStartsTheNextAtZero() {
        var workout = Workout()
        workout.start(at: zero)
        workout.nextSet(at: at(95))
        #expect(workout.sets == [95])
        #expect(workout.set == 2)
        #expect(workout.running)
        #expect(workout.elapsed(at: at(100)) == 5)
        #expect(workout.total(at: at(100)) == 100)
    }

    @Test func nextSetWhilePausedRecordsTheHeldTimeAndRuns() {
        var workout = Workout()
        workout.start(at: zero)
        workout.pause(at: at(40))
        workout.nextSet(at: at(300))
        #expect(workout.sets == [40])
        #expect(workout.running)
        #expect(workout.elapsed(at: at(301)) == 1)
    }

    @Test func nextSetBeforeTheClockStartsDoesNothing() {
        var workout = Workout()
        workout.nextSet(at: zero)
        #expect(workout == Workout())
    }

    @Test func stopRecordsTheSetAndLeavesTheClockStoppedAtZero() {
        var workout = Workout()
        workout.start(at: zero)
        workout.stop(at: at(75))
        #expect(workout.sets == [75])
        #expect(!workout.running)
        #expect(!workout.started)
        #expect(workout.elapsed(at: at(500)) == 0)
        #expect(workout.nextAnnouncement(after: at(500)) == nil)
        workout.start(at: at(600))
        #expect(workout.set == 2)
        #expect(workout.elapsed(at: at(610)) == 10)
    }

    @Test func stopWhilePausedRecordsTheHeldTime() {
        var workout = Workout()
        workout.start(at: zero)
        workout.pause(at: at(20))
        workout.stop(at: at(90))
        #expect(workout.sets == [20])
        #expect(!workout.started)
    }

    @Test func stopBeforeTheClockStartsDoesNothing() {
        var workout = Workout()
        workout.stop(at: zero)
        #expect(workout == Workout())
    }

    @Test func resettingTheSessionKeepsTheInterval() {
        var workout = Workout(interval: 45)
        workout.start(at: zero)
        workout.nextSet(at: at(60))
        workout.nextSet(at: at(130))
        #expect(workout.set == 3)
        workout.resetSession()
        #expect(workout == Workout(interval: 45))
    }

    @Test func aWorkoutSurvivesBeingSavedAndRead() throws {
        var workout = Workout(interval: 15)
        workout.start(at: zero)
        workout.nextSet(at: at(61))
        let data = try JSONEncoder().encode(workout)
        #expect(try JSONDecoder().decode(Workout.self, from: data) == workout)
    }

    // MARK: Spoken times

    @Test func theNextMarkIsTheNextMultipleOfTheInterval() throws {
        var workout = Workout(interval: 30)
        workout.start(at: zero)
        let first = try #require(workout.nextAnnouncement(after: zero))
        #expect(first.seconds == 30)
        #expect(first.at == at(30))
        let later = try #require(workout.nextAnnouncement(after: at(61)))
        #expect(later.seconds == 90)
        #expect(later.at == at(90))
    }

    @Test func wakingAtAMarkDoesNotSayItAgain() throws {
        var workout = Workout(interval: 30)
        workout.start(at: zero)
        let next = try #require(workout.nextAnnouncement(after: at(30).addingTimeInterval(-0.0001)))
        #expect(next.seconds == 60)
    }

    @Test func afterAPauseTheMarksFollowTheClock() throws {
        var workout = Workout(interval: 30)
        workout.start(at: zero)
        workout.pause(at: at(20))
        #expect(workout.nextAnnouncement(after: at(25)) == nil)
        workout.start(at: at(100))
        let next = try #require(workout.nextAnnouncement(after: at(100)))
        #expect(next.seconds == 30)
        #expect(next.at == at(110))
    }

    @Test func aSilentTimerSaysNothing() {
        var workout = Workout(interval: 0)
        workout.start(at: zero)
        #expect(workout.nextAnnouncement(after: at(5)) == nil)
    }

    @Test func aClockStartedInTheFutureWaitsForItsFirstMark() throws {
        var workout = Workout(interval: 10)
        workout.start(at: at(50))
        let next = try #require(workout.nextAnnouncement(after: zero))
        #expect(next.seconds == 10)
        #expect(next.at == at(60))
    }

    @Test(arguments: [
        (15, "15 seconds"), (1, "1 second"), (60, "1 minute"), (90, "1 minute 30"), (120, "2 minutes"),
        (135, "2 minutes 15"), (3600, "1 hour"), (3690, "1 hour 1 minute 30"), (7230, "2 hours 30"),
    ])
    func theTimeIsSaidShort(seconds: Int, text: String) {
        #expect(Workout.spoken(seconds) == text)
    }

    @Test(arguments: [
        (0.0, "0:00"), (9.99, "0:09"), (65, "1:05"), (725, "12:05"), (3723, "1:02:03"), (-4, "0:00"),
    ])
    func theClockReadsMinutesAndSeconds(elapsed: TimeInterval, text: String) {
        #expect(Workout.clock(elapsed) == text)
    }

    @Test(arguments: [(0, "Off"), (15, "15 s"), (60, "1 min"), (90, "1 min 30 s"), (300, "5 min")])
    func theIntervalsReadPlainly(seconds: Int, text: String) {
        #expect(Workout.intervalText(seconds) == text)
    }

    @Test func everyIntervalChoiceIsOffOrPositiveAndInOrder() {
        #expect(Workout.intervals.first == 0)
        #expect(Workout.intervals == Workout.intervals.sorted())
        #expect(Workout.intervals.contains(30))
    }
}
