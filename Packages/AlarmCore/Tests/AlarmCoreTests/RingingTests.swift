import Foundation
import Testing

@testable import AlarmCore

/// A sync while an alarm rings leaves it ringing. Only Stop, or an answer
/// from somewhere else, ends a ring. On 12 Nov 2026 the farewell alarm was
/// acknowledged from the phone 6 s after it began, and Neb never saw it: the
/// sync that ran during the ring no longer wanted an alarm whose time had
/// passed, and stopped it.
@Suite struct RingingTests {
    static let wakeID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD")!

    func ringingRig(_ alerts: [PlannedAlert], routines: [Routine] = []) -> (Fixtures.Rig, Fixtures.TestClock) {
        let clock = Fixtures.TestClock()
        return (Fixtures.rig(alerts, routines: routines, clock: clock), clock)
    }

    @Test func aSyncDuringAnEventsRingLeavesItRinging() async {
        let (rig, clock) = ringingRig([Fixtures.alert("farewell", inMinutes: 10)])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: "farewell")
        #expect(await rig.alarms.alarms[id] != nil)

        clock.advance(minutes: 10)
        await rig.alarms.startRinging(id)
        let report = await rig.sync.sync()

        #expect(report.error == nil)
        #expect(await rig.alarms.stops.isEmpty)
        #expect(await rig.alarms.ringing == [id])
        #expect(await rig.server.acknowledgements.isEmpty)
    }

    @Test func aSyncDuringAnEventsRingAfterItsStartLeavesItRinging() async {
        let (rig, clock) = ringingRig([Fixtures.alert("farewell", inMinutes: 10)])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: "farewell")
        clock.advance(minutes: 10)
        await rig.alarms.startRinging(id)
        // The event itself has begun and the alarm still rings.
        clock.advance(minutes: 12)
        _ = await rig.sync.sync()

        #expect(await rig.alarms.stops.isEmpty)
        #expect(await rig.alarms.ringing == [id])
    }

    @Test func anEventsRingAcknowledgedElsewhereStops() async {
        let (rig, clock) = ringingRig([Fixtures.alert("farewell", inMinutes: 10)])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: "farewell")
        clock.advance(minutes: 10)
        await rig.alarms.startRinging(id)
        var state = await rig.server.state
        state.alerts[0].acknowledged = true
        await rig.server.setState(state)

        _ = await rig.sync.sync()

        #expect(await rig.alarms.ringing.isEmpty)
    }

    @Test func anEventsRingSkippedElsewhereStops() async {
        let (rig, clock) = ringingRig([Fixtures.alert("farewell", inMinutes: 10)])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: "farewell")
        clock.advance(minutes: 10)
        await rig.alarms.startRinging(id)
        var state = await rig.server.state
        state.alerts[0].skipped = true
        await rig.server.setState(state)

        _ = await rig.sync.sync()

        #expect(await rig.alarms.ringing.isEmpty)
    }

    @Test func aDeletedEventsRingStops() async {
        let (rig, clock) = ringingRig([Fixtures.alert("farewell", inMinutes: 10)])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: "farewell")
        clock.advance(minutes: 10)
        await rig.alarms.startRinging(id)
        var state = await rig.server.state
        state.alerts = []
        await rig.server.setState(state)

        _ = await rig.sync.sync()

        #expect(await rig.alarms.ringing.isEmpty)
    }

    @Test func aSyncDuringARoutinesRingLeavesItRinging() async {
        let calendar = Calendar(identifier: .gregorian)
        let at = calendar.dateComponents(in: .current, from: Fixtures.now.addingTimeInterval(10 * 60))
        let wake = Routine(
            id: Self.wakeID, label: "Wake", hour: at.hour!, minute: at.minute!, days: Array(1...7))
        let (rig, clock) = ringingRig([], routines: [wake])
        _ = await rig.sync.sync()
        #expect(await rig.alarms.alarms[Self.wakeID] != nil)

        clock.advance(minutes: 10)
        await rig.alarms.startRinging(Self.wakeID)
        _ = await rig.sync.sync()

        #expect(await rig.alarms.stops.isEmpty)
        #expect(await rig.alarms.ringing == [Self.wakeID])
    }

    @Test func aSwitchedOffRoutinesRingStops() async {
        let calendar = Calendar(identifier: .gregorian)
        let at = calendar.dateComponents(in: .current, from: Fixtures.now.addingTimeInterval(10 * 60))
        let wake = Routine(
            id: Self.wakeID, label: "Wake", hour: at.hour!, minute: at.minute!, days: Array(1...7))
        let (rig, clock) = ringingRig([], routines: [wake])
        _ = await rig.sync.sync()
        clock.advance(minutes: 10)
        await rig.alarms.startRinging(Self.wakeID)
        var off = wake
        off.enabled = false
        await rig.server.setRoutines([off])

        _ = await rig.sync.sync()

        #expect(await rig.alarms.ringing.isEmpty)
    }
}
