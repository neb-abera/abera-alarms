import Foundation
import Testing

@testable import AlarmCore

/// A routine switch moves when tapped and says where its change stands.
@Suite struct RoutineSendingTests {
    let a = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
    let b = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!

    func draft(enabled: Bool) -> RoutineDraft {
        RoutineDraft(label: "Wake", hour: 5, minute: 30, days: [1, 2, 3, 4, 5], enabled: enabled)
    }

    func state() -> AlertsState {
        var state = Fixtures.state([])
        state.routines = [Routine(id: a, label: "Wake", hour: 5, minute: 30, days: [1, 2, 3, 4, 5])]
        return state
    }

    @Test func aTappedSwitchShowsItsNewPlaceAtOnce() {
        var sending = RoutineSending()
        sending.begin(.update(id: a, draft: draft(enabled: false)))
        #expect(sending.shown(state())?.routines.first?.enabled == false)
        #expect(sending.status[a] == .sending)
    }

    @Test func aSyncThatReadTheServerBeforeTheTapDoesNotPutItBack() {
        var sending = RoutineSending()
        sending.begin(.update(id: a, draft: draft(enabled: false)))
        // The launch sync returns the server's old copy while the tap waits.
        #expect(sending.shown(state())?.routines.first?.enabled == false)
        #expect(sending.shown(nil) == nil)
    }

    @Test func abearaTechTakingItMarksItSaved() {
        var sending = RoutineSending()
        let change = RoutineChange.update(id: a, draft: draft(enabled: false))
        sending.begin(change)
        sending.finish(change, error: nil, waiting: [])
        #expect(sending.inFlight.isEmpty)
        #expect(sending.status[a] == .saved)
        sending.clearSaved(a)
        #expect(sending.status[a] == nil)
    }

    @Test func noConnectionKeepsItOnThePhoneAndSaysItWaits() {
        var sending = RoutineSending()
        let change = RoutineChange.update(id: a, draft: draft(enabled: false))
        sending.begin(change)
        sending.finish(change, error: .offline, waiting: [a])
        #expect(sending.status[a] == .waiting)
        #expect(sending.shown(state())?.routines.first?.enabled == true)  // the sync's own overlay holds it now
        sending.settle(waiting: [a])
        #expect(sending.status[a] == .waiting)
        sending.settle(waiting: [])
        #expect(sending.status[a] == .saved)
    }

    @Test func aRefusalPutsTheSwitchBackWithNoMark() {
        var sending = RoutineSending()
        let change = RoutineChange.update(id: a, draft: draft(enabled: false))
        sending.begin(change)
        sending.finish(change, error: .refused("At most 50 routine alarms."), waiting: [])
        #expect(sending.status[a] == nil)
        #expect(sending.shown(state())?.routines.first?.enabled == true)
        sending.begin(change)
        sending.finish(change, error: .unpaired, waiting: [a])
        #expect(sending.status[a] == nil)
    }

    @Test func aServerErrorNotLeftWaitingClearsTheMark() {
        var sending = RoutineSending()
        let change = RoutineChange.update(id: a, draft: draft(enabled: false))
        sending.begin(change)
        sending.finish(change, error: .status(500), waiting: [])
        #expect(sending.status[a] == nil)
    }

    @Test func aSecondTapStillSendingKeepsTheRowSending() {
        var sending = RoutineSending()
        let off = RoutineChange.update(id: a, draft: draft(enabled: false))
        let on = RoutineChange.update(id: a, draft: draft(enabled: true))
        sending.begin(off)
        sending.begin(on)
        sending.finish(off, error: nil, waiting: [])
        #expect(sending.status[a] == .sending)
        #expect(sending.shown(state())?.routines.first?.enabled == true)
        sending.clearSaved(a)
        #expect(sending.status[a] == .sending)
        sending.finish(on, error: nil, waiting: [])
        #expect(sending.status[a] == .saved)
    }

    @Test func eachRoutineKeepsItsOwnMark() {
        var sending = RoutineSending()
        sending.begin(.delete(id: b))
        sending.begin(.update(id: a, draft: draft(enabled: false)))
        sending.finish(.delete(id: b), error: nil, waiting: [a])
        #expect(sending.status[b] == .saved)
        #expect(sending.status[a] == .sending)
        #expect(RoutineChange.delete(id: b).id == b)
    }

    // MARK: Through the sync

    @Test func theSwitchMovesBeforeASlowRequestReturns() async throws {
        let rig = Fixtures.rig([])
        _ = await rig.sync.sync()
        await rig.server.setLatency(.milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        var sending = RoutineSending()
        let change = RoutineChange.create(local: a, draft: draft(enabled: true))
        sending.begin(change)
        #expect(sending.shown(AlertsState())?.routines.map(\.id) == [a])
        let report = await rig.sync.changeRoutine(change)
        #expect(clock.now - start >= .milliseconds(300))
        let waiting = Set(await rig.sync.routineChanges().map(\.id))
        sending.finish(change, error: report.error, waiting: waiting)
        #expect(sending.status[a] == .saved)
    }
}
