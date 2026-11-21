import Foundation
import Testing

@testable import AlarmCore

/// One ring of an alarm marked Done or Skipped, and the list under the
/// alarm moving to the next ring once this one is settled. Neb asked on
/// 2026-11-21, after waking at 06:40 and switching the 07:00 alarm off.
@Suite struct RoutineOutcomeTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    var calendar: Calendar { Self.calendar }

    let routineID = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!
    let medication = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000D2")!, label: "Take medication", offsetMinutes: 5)

    var wake: Routine {
        Routine(
            id: routineID, label: "Wake up", hour: 7, minute: 0, days: [1, 2, 3, 4, 5, 6, 7], steps: [medication])
    }

    /// A local time in November 2026. The 21st is a Saturday.
    func at(_ hour: Int, _ minute: Int, day: Int = 21) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    let today = "2026-11-21T07:00"
    let tomorrow = "2026-11-22T07:00"

    func state(
        _ routines: [Routine]? = nil, outcomes: [RoutineOutcome] = [], completions: [RoutineCompletion] = [],
        rings: [RoutineRing] = []
    ) -> AlertsState {
        AlertsState(
            configured: true, routines: routines ?? [wake], routineRings: rings, stopAfterMinutes: 30,
            routineCompletions: completions, routineOutcomes: outcomes)
    }

    func outcome(_ status: RoutineOutcome.Status, _ cycle: String) -> RoutineOutcome {
        RoutineOutcome(routineId: routineID, cycle: cycle, status: status, at: at(6, 40))
    }

    func ringKey(_ cycle: String) -> String { RoutineCycle.parentKey(routineID: routineID, stamp: cycle) }
    func stepKey(_ cycle: String) -> String {
        RoutineCycle.stepKey(routineID: routineID, stamp: cycle, stepID: medication.id)
    }

    func held(_ state: AlertsState, now: Date) -> [DesiredAlarm] {
        Reconciler.desired(from: state, now: now, acknowledgedHere: [], calendar: calendar)
    }

    // MARK: Keys

    @Test func aRingKeyNamesTheAlarmAndItsTime() throws {
        let parts = try #require(RoutineCycle.parseParentKey(ringKey(today)))
        #expect(parts.routineID == routineID)
        #expect(parts.stamp == today)
        #expect(RoutineCycle.parseParentKey(stepKey(today)) == nil)
        #expect(RoutineCycle.parseParentKey("routine:" + routineID.uuidString.lowercased()) == nil)
        #expect(RoutineCycle.parseParentKey("standup|1") == nil)
    }

    // MARK: The alarms the phone holds

    @Test func anAlarmWithNoMarkIsOneRepeatingAlarm() {
        let alarms = held(state(), now: at(6, 40)).filter { $0.title == "Wake up" }
        #expect(alarms.count == 1)
        #expect(alarms[0].id == routineID)
        #expect(alarms[0].routine != nil)
    }

    @Test func doneAheadTakesThatRingOffAndKeepsEveryOther() {
        let alarms = held(state(outcomes: [outcome(.done, today)]), now: at(6, 40))
        let rings = alarms.filter { $0.title == "Wake up" }
        #expect(!rings.contains { $0.id == routineID }, "no repeating alarm while a ring ahead is answered")
        #expect(!rings.contains { $0.key == ringKey(today) })
        #expect(rings.first?.fireAt == at(7, 0, day: 22))
        // Sunday to Friday: the 7 days from 06:40 end before next Saturday at 07:00.
        #expect(rings.count == 6)
        #expect(rings.allSatisfy { $0.routine == nil && $0.snoozeMinutes == 9 })
        #expect(rings.first?.startsAt == at(7, 30, day: 22))
        // Done leaves the steps of that ring to ring.
        #expect(alarms.contains { $0.key == stepKey(today) })
    }

    @Test func skipTakesTheRingAndItsStepsOff() {
        let alarms = held(state(outcomes: [outcome(.skipped, today)]), now: at(6, 40))
        #expect(!alarms.contains { $0.key == ringKey(today) })
        #expect(!alarms.contains { $0.key == stepKey(today) })
        #expect(alarms.contains { $0.key == stepKey(tomorrow) })
        #expect(alarms.contains { $0.key == ringKey(tomorrow) })
    }

    @Test func onceTheAnsweredRingHasPassedTheAlarmRepeatsAgain() {
        let alarms = held(state(outcomes: [outcome(.done, today)]), now: at(7, 1))
        let rings = alarms.filter { $0.title == "Wake up" }
        #expect(rings.count == 1)
        #expect(rings[0].id == routineID)
    }

    @Test func theClockCountsToTheNextRingThatIsNotAnswered() {
        let marked = state(outcomes: [outcome(.done, today)])
        #expect(Reconciler.nextRing(of: wake, in: marked, now: at(6, 40), calendar: calendar) == at(7, 0, day: 22))
        #expect(Reconciler.nextRing(of: wake, in: state(), now: at(6, 40), calendar: calendar) == at(7, 0))
        #expect(RingClock.text(for: wake, in: marked, at: at(6, 40), calendar: calendar) == "Rings in 1 day 00:20:00")
        var off = wake
        off.enabled = false
        #expect(Reconciler.nextRing(of: off, in: marked, now: at(6, 40), calendar: calendar) == nil)
    }

    @Test func aRingHeldOneByOneRingsUntilItIsAnswered() {
        let key = ringKey(tomorrow)
        let id = AlarmID.of(key: key)
        let ringing = DesiredAlarm(
            id: id, key: key, title: "Wake up", location: nil, fireAt: at(7, 0, day: 22), startsAt: at(7, 30, day: 22))
        let open = state(outcomes: [outcome(.done, today)])
        #expect(Reconciler.stillRinging(open, ringing: [id], ledger: [id: ringing], acknowledgedHere: []) == [ringing])
        #expect(Reconciler.stillRinging(open, ringing: [id], ledger: [id: ringing], acknowledgedHere: [key]).isEmpty)
        let stopped = state(rings: [
            RoutineRing(
                key: key, routineId: routineID, label: "Wake up", alertAt: at(7, 0, day: 22),
                startsAt: at(7, 30, day: 22), acknowledged: true)
        ])
        #expect(Reconciler.stillRinging(stopped, ringing: [id], ledger: [id: ringing], acknowledgedHere: []).isEmpty)
    }

    // MARK: Which ring the list shows

    func shown(_ state: AlertsState, now: Date) -> String? {
        RoutineCycle.shown(wake, in: state, now: now, window: 1800, calendar: calendar)?.stamp
    }

    @Test func beforeTheAlarmTheListShowsItsComingRing() {
        #expect(shown(state(), now: at(6, 40)) == today)
    }

    @Test func doneWithEveryStepCheckedOffMovesTheListToTomorrow() {
        let checked = RoutineCompletion(
            routineId: routineID, stepId: medication.id, cycle: today, completedAt: at(6, 45))
        #expect(shown(state(outcomes: [outcome(.done, today)]), now: at(6, 50)) == today, "a step is still open")
        #expect(shown(state(outcomes: [outcome(.done, today)], completions: [checked]), now: at(6, 50)) == tomorrow)
    }

    @Test func skipMovesTheListToTomorrow() {
        #expect(shown(state(outcomes: [outcome(.skipped, today)]), now: at(6, 40)) == tomorrow)
    }

    @Test func stoppedWithEveryStepCheckedOffMovesTheListToTomorrow() {
        let checked = RoutineCompletion(
            routineId: routineID, stepId: medication.id, cycle: today, completedAt: at(7, 6))
        let stopped = RoutineRing(
            key: ringKey(today), routineId: routineID, label: "Wake up", alertAt: at(7, 0), startsAt: at(7, 30),
            acknowledged: true)
        #expect(shown(state(completions: [checked], rings: [stopped]), now: at(7, 7)) == tomorrow)
        #expect(shown(state(rings: [stopped]), now: at(7, 7)) == today, "a step is still open")
        // Without a stop or a mark, the ring under way stays until it rings out.
        #expect(shown(state(completions: [checked]), now: at(7, 7)) == today)
        #expect(shown(state(completions: [checked]), now: at(7, 40)) == tomorrow)
    }

    @Test func aSettledRingIsSettledAndAnOpenOneIsNot() throws {
        let cycle = try #require(RoutineCycle.around(wake, now: at(6, 40), calendar: calendar).next)
        #expect(!cycle.isSettled(in: state(), now: at(6, 40)))
        #expect(cycle.isSettled(in: state(outcomes: [outcome(.skipped, today)]), now: at(6, 40)))
        #expect(!cycle.isSettled(in: state(), acknowledgedHere: [ringKey(today)], now: at(6, 40)), "not rung yet")
    }

    // MARK: Through the sync

    struct Rig {
        let server: FakeAlertsServer
        let alarms: MemoryAlarms
        let sync: AlarmSync
    }

    func rig(now: Date) -> Rig {
        let server = FakeAlertsServer(state: state(), token: Fixtures.token, now: { now })
        let alarms = MemoryAlarms()
        let sync = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: server, alarms: alarms,
            documents: MemoryDocuments(), now: { now }, calendar: calendar)
        return Rig(server: server, alarms: alarms, sync: sync)
    }

    @Test func markingOfflineTakesTheRingOffAtOnceAndReachesAbearaTechLater() async throws {
        let rig = rig(now: at(6, 40))
        _ = await rig.sync.sync()
        #expect(await rig.alarms.alarms[routineID] != nil)
        await rig.server.setOffline(true)
        let offline = await rig.sync.setOutcome(
            OutcomeDraft(routineId: routineID, cycle: today, status: .done, note: "  ", at: at(6, 40)))
        #expect(offline.error == .offline)
        #expect(await rig.alarms.alarms[routineID] == nil)
        #expect(await rig.alarms.alarms[AlarmID.of(key: ringKey(tomorrow))] != nil)
        #expect(offline.state?.routineOutcomes.map(\.status) == [.done])
        #expect(offline.state?.routineOutcomes.first?.note == nil)

        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routineOutcomes.map(\.cycle) == [today])
        #expect(await rig.sync.completionChanges().isEmpty)
    }

    @Test func undoSetsTheRingAgain() async throws {
        let rig = rig(now: at(6, 40))
        _ = await rig.sync.setOutcome(OutcomeDraft(routineId: routineID, cycle: today, status: .skipped, at: at(6, 40)))
        #expect(await rig.alarms.alarms[AlarmID.of(key: stepKey(today))] == nil)
        let report = await rig.sync.clearOutcome(routineId: routineID, cycle: today)
        #expect(report.error == nil)
        #expect(await rig.server.state.routineOutcomes.isEmpty)
        #expect(await rig.alarms.alarms[routineID] != nil)
        #expect(await rig.alarms.alarms[AlarmID.of(key: stepKey(today))] != nil)
    }

    @Test func aMarkFollowedByItsUndoSendsOnlyTheUndo() {
        let changes = CompletionChange.coalesce([
            .outcome(OutcomeDraft(routineId: routineID, cycle: today, status: .done, at: at(6, 40))),
            .clearOutcome(routineId: routineID, cycle: today),
        ])
        #expect(changes == [.clearOutcome(routineId: routineID, cycle: today)])
        #expect(CompletionChange.overlayOutcomes([outcome(.done, today)], changes).isEmpty)
    }

    @Test func theRequestIsAPutWithTheStatus() throws {
        #expect(
            AlertsClient.outcomePath(routineId: routineID, cycle: today)
                == "routines/00000000-0000-4000-8000-0000000000d1/cycles/2026-11-21T07:00/outcome")
        let body = try #require(
            try JSONSerialization.jsonObject(
                with: ServerDates.encoder().encode(
                    OutcomeDraft(routineId: routineID, cycle: today, status: .skipped, note: " Sick ", at: at(6, 40))
                        .body)) as? [String: Any])
        #expect(body["status"] as? String == "skipped")
        #expect(body["note"] as? String == "Sick")
        #expect(body["at"] is String)
    }

    @Test func aStatusFromAnOlderServerHasNoMarks() throws {
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(state.routineOutcomes.isEmpty)
    }

    // MARK: History

    @Test func historyShowsTheMarkAndASkippedRingCountsNeitherWay() async throws {
        let rig = rig(now: at(7, 10))
        await rig.server.setCalendar(calendar)
        _ = await rig.sync.setOutcome(OutcomeDraft(routineId: routineID, cycle: today, status: .skipped, at: at(6, 40)))
        let history = try await rig.sync.history().get()
        let first = try #require(history.cycles.first)
        #expect(first.cycle == today)
        #expect(first.outcome?.status == .skipped)
        #expect(first.doneText(now: at(7, 10)) == "Skipped")
        let tally = try #require(history.tally(now: at(7, 10)).first)
        #expect(tally.of == history.cycles.count - 1)
    }
}
