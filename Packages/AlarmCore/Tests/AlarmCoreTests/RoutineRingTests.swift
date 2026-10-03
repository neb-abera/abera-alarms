import Foundation
import Testing

@testable import AlarmCore

/// One ring of a routine alarm, named as abera.tech names it, so that Stop
/// on the phone and an acknowledgement elsewhere mean the same ring.
@Suite struct RoutineRingTests {
    static let id = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD")!

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static let newYork = calendar("America/New_York")
    static let threeHours: TimeInterval = 180 * 60

    func schedule(_ hour: Int, _ minute: Int, days: [Int] = Array(1...7)) -> RoutineSchedule {
        RoutineSchedule(hour: hour, minute: minute, days: days, snoozeMinutes: 9)
    }

    func at(_ text: String) -> Date { ServerDates.parse(text)! }

    func key(
        _ schedule: RoutineSchedule, stoppedAt now: Date, window: TimeInterval = threeHours,
        calendar: Calendar = newYork
    ) -> String? {
        RoutineRing.key(routineID: Self.id, schedule: schedule, stoppedAt: now, window: window, calendar: calendar)
    }

    // MARK: The key

    @Test func theKeyIsTheRoutineAndTheLocalDateAndTimeOfTheRing() {
        // Monday 5 October 2026, 05:31 in New York.
        let weekdays = schedule(5, 30, days: [1, 2, 3, 4, 5])
        #expect(
            key(weekdays, stoppedAt: at("2026-10-05T05:31:00-04:00"))
                == "routine:0a1b2c3d-0000-4000-8000-00000000abcd:2026-10-05T05:30")
    }

    @Test func stoppingAtTheRingItselfCountsAsThatRing() {
        #expect(key(schedule(5, 30), stoppedAt: at("2026-10-05T05:30:00-04:00"))?.hasSuffix("2026-10-05T05:30") == true)
    }

    @Test func aSnoozedRingKeepsTheTimeItWasScheduledFor() {
        // Two nine-minute snoozes, then Stop.
        #expect(key(schedule(5, 30), stoppedAt: at("2026-10-05T05:48:30-04:00"))?.hasSuffix("2026-10-05T05:30") == true)
    }

    @Test func aRingSnoozedPastMidnightKeepsItsDay() {
        #expect(
            key(schedule(23, 55), stoppedAt: at("2026-10-06T00:10:00-04:00"))?.hasSuffix("2026-10-05T23:55") == true)
    }

    @Test func theLatestRingIsTheOneStopped() {
        // A window longer than a day holds two rings. The later one is stopped.
        let day: TimeInterval = 26 * 3600
        #expect(
            key(schedule(6, 0), stoppedAt: at("2026-10-06T07:00:00-04:00"), window: day)?.hasSuffix("2026-10-06T06:00")
                == true)
    }

    @Test func aStopAfterTheWindowNamesNoRing() {
        #expect(key(schedule(5, 30), stoppedAt: at("2026-10-05T05:41:00-04:00"), window: 10 * 60) == nil)
        #expect(key(schedule(5, 30), stoppedAt: at("2026-10-05T05:40:00-04:00"), window: 10 * 60) != nil)
    }

    @Test func aDayTheRoutineDoesNotRingNamesNoRing() {
        // Saturday: the last weekday ring was Friday, a day ago.
        #expect(key(schedule(5, 30, days: [1, 2, 3, 4, 5]), stoppedAt: at("2026-10-10T05:31:00-04:00")) == nil)
    }

    @Test func beforeTheRingNamesNoRing() {
        #expect(key(schedule(5, 30), stoppedAt: at("2026-10-05T05:29:00-04:00"), window: 10 * 60) == nil)
    }

    @Test func aRingOnceRoutineIsNamedTheSameWay() {
        #expect(
            key(schedule(5, 30, days: []), stoppedAt: at("2026-10-05T05:31:00-04:00"))?.hasSuffix("2026-10-05T05:30")
                == true)
    }

    // MARK: Clock changes

    @Test func aTimeTheClocksSkipKeepsTheScheduledTime() {
        // 8 March 2026: New York goes from 02:00 to 03:00. A 02:30 alarm rings at 03:00.
        let key = key(schedule(2, 30), stoppedAt: at("2026-03-08T03:01:00-04:00"))
        #expect(key?.hasSuffix("2026-03-08T02:30") == true)
    }

    @Test func aTimeTheClocksPassTwiceIsTheFirstPass() {
        // 1 November 2026: New York goes from 02:00 back to 01:00. A 01:30
        // alarm rings at the first 01:30, in daylight time.
        let first = key(schedule(1, 30), stoppedAt: at("2026-11-01T01:31:00-04:00"))
        #expect(first?.hasSuffix("2026-11-01T01:30") == true)
        // Snoozed across the change and stopped at the second 01:31: the same ring.
        let second = key(schedule(1, 30), stoppedAt: at("2026-11-01T01:31:00-05:00"))
        #expect(second == first)
    }

    @Test func theDayAfterAClockChangeRingsAtItsTime() {
        #expect(key(schedule(5, 30), stoppedAt: at("2026-11-02T05:31:00-05:00"))?.hasSuffix("2026-11-02T05:30") == true)
        #expect(key(schedule(5, 30), stoppedAt: at("2026-03-09T05:31:00-04:00"))?.hasSuffix("2026-03-09T05:30") == true)
    }

    @Test func theKeyIsInThePhonesZone() {
        // 05:31 in Amman is 22:31 the evening before in New York.
        let amman = Self.calendar("Asia/Amman")
        let stop = at("2026-10-05T05:31:00+03:00")
        #expect(key(schedule(5, 30), stoppedAt: stop, calendar: amman)?.hasSuffix("2026-10-05T05:30") == true)
        #expect(key(schedule(5, 30), stoppedAt: stop, calendar: Self.newYork) == nil)
    }

    // MARK: Decoding

    @Test func routineRingsDecodeFromTheServer() throws {
        let json = #"""
            {"configured":true,"settings":{"stopAfterMinutes":45,"phoneSound":"chime"},
             "routineRings":[{"key":"routine:0a1b2c3d-0000-4000-8000-00000000abcd:2026-10-05T05:30",
               "routineId":"0a1b2c3d-0000-4000-8000-00000000abcd","label":"Wake",
               "alertAt":"2026-10-05T09:30:00+00:00","startsAt":"2026-10-05T10:15:00+00:00",
               "acknowledged":true,"acknowledgedAt":"2026-10-05T09:31:12.1234567+00:00",
               "acknowledgedVia":"pushover"}]}
            """#
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        let ring = try #require(state.routineRings.first)
        #expect(ring.id == ring.key)
        #expect(ring.routineId == Self.id)
        #expect(ring.label == "Wake")
        #expect(ring.acknowledged)
        #expect(ring.acknowledgedVia == "pushover")
        #expect(ring.startsAt.timeIntervalSince(ring.alertAt) == 45 * 60)
        #expect(state.stopAfterMinutes == 45)
        #expect(state.phone.sound == "chime")

        // The phone's own copy keeps both.
        let again = try ServerDates.decoder().decode(AlertsState.self, from: ServerDates.encoder().encode(state))
        #expect(again == state)
    }

    @Test func aServerWithoutRingsDecodesWithNone() throws {
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(state.routineRings.isEmpty)
        #expect(state.stopAfterMinutes == AlertsState.defaultStopAfterMinutes)
    }

    @Test func aRingWithOnlyItsKeyAndTimesDecodes() throws {
        let json = #"""
            {"key":"routine:x:2026-10-05T05:30","routineId":"0a1b2c3d-0000-4000-8000-00000000abcd",
             "alertAt":"2026-10-05T09:30:00Z","startsAt":"2026-10-05T12:30:00Z"}
            """#
        let ring = try ServerDates.decoder().decode(RoutineRing.self, from: Data(json.utf8))
        #expect(!ring.acknowledged)
        #expect(ring.acknowledgedVia == nil)
        #expect(ring.label == RoutineDraft.defaultLabel)
    }

    // MARK: Where it was acknowledged

    @Test(
        arguments: [
            ("browser", "Acknowledged in a browser"), ("pushover", "Acknowledged in Pushover"),
            ("phone", "Acknowledged on a phone"), (nil, "Acknowledged on a phone"),
        ] as [(String?, String)])
    func theScreenSaysWhereItWasAcknowledged(via: String?, text: String) {
        #expect(Acknowledgement.text(via: via) == text)
    }
}
