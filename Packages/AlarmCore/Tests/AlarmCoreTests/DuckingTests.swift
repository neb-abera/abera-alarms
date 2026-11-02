import Foundation
import Testing

@testable import AlarmCore

/// Music goes down while the workout voice speaks and comes back up after.
@Suite struct DuckingTests {
    @Test func musicIsUpAtFirst() {
        let ducking = Ducking()
        #expect(!ducking.ducked)
        #expect(ducking.speaking == 0)
    }

    @Test func musicComesUpWhenTheOnlyUtteranceFinishes() {
        var ducking = Ducking()
        ducking.willSpeak()
        #expect(ducking.ducked)
        let result1 = ducking.finished()
        #expect(result1)
    }

    @Test func musicStaysDownUntilTheLastOfTwoUtterancesFinishes() {
        var ducking = Ducking()
        ducking.willSpeak()
        ducking.willSpeak()
        let result2 = ducking.finished()
        #expect(!result2)
        let result3 = ducking.finished()
        #expect(result3)
    }

    @Test func aFinishWithMusicUpAsksForNothing() {
        var ducking = Ducking()
        let result4 = ducking.finished()
        #expect(!result4)
        #expect(ducking.speaking == 0)
    }

    @Test func restoredMarksMusicUp() {
        var ducking = Ducking()
        ducking.willSpeak()
        _ = ducking.finished()
        ducking.restored()
        #expect(!ducking.ducked)
        let result5 = ducking.finished()
        #expect(!result5)
    }

    // The defect: a finish iOS never reported left music down for good.
    @Test func theBackstopBringsMusicUpWhenAFinishWentMissing() {
        var ducking = Ducking()
        ducking.willSpeak()
        ducking.willSpeak()
        let result6 = ducking.finished()
        #expect(!result6)
        let result7 = ducking.settle()
        #expect(result7)
        #expect(ducking.speaking == 0)
    }

    @Test func theBackstopDoesNothingWithMusicUp() {
        var ducking = Ducking()
        let result8 = ducking.settle()
        #expect(!result8)
    }

    // The defect: one refused attempt to bring music up was the last.
    @Test func aRefusedAttemptIsTriedAgainForAboutHalfAMinute() {
        #expect(Ducking.retryDelay(after: 0) == 0.1)
        #expect(Ducking.retryDelay(after: 3) == 0.8)
        #expect(Ducking.retryDelay(after: 4) == 1)
        let total = Ducking.retryDelays.reduce(0, +)
        #expect(total > 25 && total < 30)
        #expect(Ducking.retryDelay(after: Ducking.retryDelays.count) == nil)
        #expect(Ducking.retryDelay(after: -1) == nil)
    }

    @Test func theBackstopWaitsLongerThanASpokenTime() {
        #expect(Ducking.backstop >= 5)
    }
}
