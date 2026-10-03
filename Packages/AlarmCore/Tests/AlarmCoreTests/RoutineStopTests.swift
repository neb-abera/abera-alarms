import Foundation
import Testing

@testable import AlarmCore

/// Stop on the phone acknowledges a routine ring everywhere, and an
/// acknowledgement made anywhere else stops the phone if it is ringing.
@Suite struct RoutineStopTests {
    static let wakeID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD")!
    static let onceID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000000E")!
    static let newYork = RoutineRingTests.newYork

    /// Monday 5 October 2026, 05:00 in New York.
    static let start = ServerDates.parse("2026-10-05T05:00:00-04:00")!
    static let todaysKey = "routine:0a1b2c3d-0000-4000-8000-00000000abcd:2026-10-05T05:30"
    static let yesterdaysKey = "routine:0a1b2c3d-0000-4000-8000-00000000abcd:2026-10-04T05:30"

    let wake = Routine(id: wakeID, label: "Wake", hour: 5, minute: 30, days: Array(1...7))
    let once = Routine(id: onceID, label: "Once", hour: 5, minute: 30, days: [])

    struct Rig {
        let server: FakeAlertsServer
        let alarms: MemoryAlarms
        let documents: MemoryDocuments
        let sync: AlarmSync
        let clock: Fixtures.TestClock
    }

    func ring(_ key: String, acknowledged: Bool = false, via: String? = nil) -> RoutineRing {
        let alert = ServerDates.parse(String(key.suffix(16)) + ":00-04:00")!
        return RoutineRing(
            key: key, routineId: Self.wakeID, label: "Wake", alertAt: alert,
            startsAt: alert.addingTimeInterval(180 * 60),
            acknowledged: acknowledged, acknowledgedAt: acknowledged ? alert : nil, acknowledgedVia: via)
    }

    func rig(routines: [Routine], alerts: [PlannedAlert] = [], rings: [RoutineRing] = []) -> Rig {
        var state = Fixtures.state(alerts)
        state.routines = routines
        state.routineRings = rings
        let server = FakeAlertsServer(state: state, token: Fixtures.token)
        let alarms = MemoryAlarms()
        let documents = MemoryDocuments()
        let clock = Fixtures.TestClock(Self.start)
        let sync = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: server, alarms: alarms,
            documents: documents, now: { clock.now }, calendar: Self.newYork)
        return Rig(server: server, alarms: alarms, documents: documents, sync: sync, clock: clock)
    }

    // MARK: Stop on the phone

    @Test func stoppingARoutineAcknowledgesTodaysRingFromThePhone() async throws {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        await rig.alarms.startRinging(Self.wakeID)
        // The system stops the ring, then runs the intent.
        try await rig.alarms.stop(Self.wakeID)

        let report = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        #expect(report.error == nil)
        #expect(await rig.server.acknowledgements == [Self.todaysKey])
        let ring = try #require(await rig.server.state.routineRings.first)
        #expect(ring.acknowledged)
        #expect(ring.acknowledgedVia == "phone")
        // A repeating routine rings again tomorrow.
        #expect(await rig.alarms.alarms[Self.wakeID] != nil)
        #expect(report.waitingAcknowledgements == 0)
    }

    @Test func aSnoozedRingStoppedLaterIsTheSameRing() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 30 + 27)
        _ = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        #expect(await rig.server.acknowledgements == [Self.todaysKey])
    }

    @Test func aStopWithNoSignalIsSentOnTheNextSync() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        rig.clock.advance(minutes: 31)

        let offline = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        #expect(offline.error == .offline)
        #expect(await rig.sync.pending() == [Self.todaysKey])

        await rig.server.setOffline(false)
        rig.clock.advance(minutes: 20)
        _ = await rig.sync.sync()
        #expect(await rig.server.acknowledgements == [Self.todaysKey])
        #expect(await rig.sync.pending().isEmpty)
    }

    @Test func aServerThatDoesNotKnowTheRingDropsTheAcknowledgement() async {
        // abera.tech before routine rings shipped answers 404.
        let rig = rig(routines: [wake])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        let report = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        #expect(report.error == nil)
        #expect(await rig.sync.pending().isEmpty)
        #expect(await rig.alarms.alarms[Self.wakeID] != nil)
    }

    @Test func aStopOutsideTheWindowSendsNothing() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        var state = await rig.server.state
        state.stopAfterMinutes = 10
        await rig.server.setState(state)
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 30 + 11)
        _ = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        #expect(await rig.server.acknowledgements.isEmpty)
        #expect(await rig.sync.pending().isEmpty)
    }

    @Test func aRoutineThePhoneDoesNotKnowSendsNothing() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        _ = await rig.sync.acknowledgeRoutine(id: UUID())
        #expect(await rig.server.acknowledgements.isEmpty)
    }

    @Test func aStopBeforeTheFirstSyncUsesTheAlarmThePhoneHolds() async {
        // The last state is gone but the ledger still holds the routine's schedule.
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        rig.clock.advance(minutes: 31)
        await rig.documents.remove(AlarmSync.stateName)
        _ = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        #expect(await rig.sync.pending() == [Self.todaysKey])
    }

    @Test func aRingOnceRoutineIsAcknowledgedAndStillSwitchedOff() async throws {
        var onceRing = ring(Self.todaysKey)
        onceRing.key = "routine:0a1b2c3d-0000-4000-8000-00000000000e:2026-10-05T05:30"
        onceRing.routineId = Self.onceID
        let rig = rig(routines: [once], rings: [onceRing])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        await rig.alarms.startRinging(Self.onceID)
        // Stop on a one-time alarm removes it from the system.
        try await rig.alarms.stop(Self.onceID)
        #expect(await rig.alarms.alarms[Self.onceID] == nil)

        _ = await rig.sync.acknowledgeRoutine(id: Self.onceID)
        #expect(await rig.server.acknowledgements == [onceRing.key])
        #expect(await rig.server.state.routines.first?.enabled == false)
        #expect(await rig.alarms.alarms[Self.onceID] == nil)
    }

    // MARK: Acknowledged elsewhere

    @Test(arguments: ["browser", "pushover"])
    func anAcknowledgementElsewhereStopsTheRingAndKeepsTheRoutine(via: String) async throws {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        await rig.alarms.startRinging(Self.wakeID)

        var state = await rig.server.state
        state.routineRings = [ring(Self.todaysKey, acknowledged: true, via: via)]
        await rig.server.setState(state)
        let report = await rig.sync.sync()

        #expect(report.stopped == 1)
        #expect(await rig.alarms.stops == [Self.wakeID])
        #expect(try await rig.alarms.ringingIDs().isEmpty)
        #expect(await rig.alarms.alarms[Self.wakeID] != nil)
        #expect(await rig.server.acknowledgements.isEmpty)
    }

    @Test func aSnoozedRingAcknowledgedElsewhereIsStopped() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey, acknowledged: true, via: "pushover")])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 40)
        // Snoozed: counting down to ring again.
        await rig.alarms.startRinging(Self.wakeID)
        _ = await rig.sync.sync()
        #expect(await rig.alarms.stops == [Self.wakeID])
    }

    @Test func anOlderAcknowledgedRingDoesNotStopTodays() async throws {
        let rig = rig(routines: [wake], rings: [ring(Self.yesterdaysKey, acknowledged: true, via: "browser")])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        await rig.alarms.startRinging(Self.wakeID)
        let report = await rig.sync.sync()
        #expect(report.stopped == 0)
        #expect(await rig.alarms.stops.isEmpty)
        #expect(try await rig.alarms.ringingIDs() == [Self.wakeID])
    }

    @Test func aRoutineThatIsNotRingingIsLeftAlone() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey, acknowledged: true, via: "browser")])
        rig.clock.advance(minutes: 31)
        _ = await rig.sync.sync()
        #expect(await rig.alarms.stops.isEmpty)
        #expect(await rig.alarms.alarms[Self.wakeID] != nil)
    }

    @Test func anUnacknowledgedRingKeepsRinging() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey)])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        await rig.alarms.startRinging(Self.wakeID)
        _ = await rig.sync.sync()
        #expect(await rig.alarms.stops.isEmpty)
    }

    @Test func aCalendarAlarmAcknowledgedElsewhereIsStoppedThenRemoved() async throws {
        let alert = PlannedAlert(
            key: "brief|1", title: "Brief", startsAt: Self.start.addingTimeInterval(20 * 60),
            alertAt: Self.start.addingTimeInterval(10 * 60))
        let rig = rig(routines: [], alerts: [alert])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: alert.key)
        #expect(await rig.alarms.alarms[id] != nil)

        rig.clock.advance(minutes: 10)
        await rig.alarms.startRinging(id)
        var state = await rig.server.state
        state.alerts[0].acknowledged = true
        state.alerts[0].acknowledgedVia = "pushover"
        await rig.server.setState(state)
        let report = await rig.sync.sync()

        #expect(await rig.alarms.stops == [id])
        #expect(try await rig.alarms.ringingIDs().isEmpty)
        #expect(await rig.alarms.alarms[id] == nil)
        #expect(report.cancelled == 1)
    }

    @Test func aRingingStateThePhoneCannotReadStopsNothing() async {
        let rig = rig(routines: [wake], rings: [ring(Self.todaysKey, acknowledged: true, via: "browser")])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        await rig.alarms.startRinging(Self.wakeID)
        await rig.alarms.failRingingReads()
        let report = await rig.sync.sync()
        #expect(report.error == nil)
        #expect(await rig.alarms.stops.isEmpty)
    }

    @Test func anAlarmSystemThePhoneCannotReadSchedulesNothingAndSaysWhat() async {
        let rig = rig(routines: [wake])
        await rig.alarms.failSystemReads()
        let report = await rig.sync.sync()
        #expect(report.refused == [DesiredAlarm.routinePrefix + Self.wakeID.uuidString.lowercased()])
        #expect(report.stopped == 0)
    }

    // MARK: The zone

    @Test func everyRequestNamesThePhonesZone() async {
        let rig = rig(routines: [wake])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 31)
        _ = await rig.sync.acknowledgeRoutine(id: Self.wakeID)
        let zones = await rig.server.timeZones
        #expect(!zones.isEmpty)
        #expect(Set(zones) == ["America/New_York"])
    }
}
