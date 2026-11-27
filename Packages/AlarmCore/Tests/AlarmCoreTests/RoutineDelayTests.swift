import Foundation
import Testing

@testable import AlarmCore

/// One ring of an alarm, and its steps, moved later. Neb asked on
/// 2026-11-23, when the 07:00 wake up rang before his workout and he
/// wanted the beauty routine after it.
@Suite struct RoutineDelayTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    var calendar: Calendar { Self.calendar }

    let routineID = UUID(uuidString: "00000000-0000-4000-8000-0000000000E1")!
    let wash = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000E2")!, label: "Wash face", offsetMinutes: 5)
    let cream = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000E3")!, label: "Cream", offsetMinutes: 3)

    var wake: Routine {
        Routine(id: routineID, label: "wake up", hour: 7, minute: 0, days: [1, 3, 5], steps: [wash, cream])
    }

    /// A local time on Monday 23 November 2026.
    func at(_ hour: Int, _ minute: Int, day: Int = 23) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    let monday = "2026-11-23T07:00"

    func state(delays: [RoutineDelay] = [], completions: [RoutineCompletion] = []) -> AlertsState {
        AlertsState(
            configured: true, routines: [wake], stopAfterMinutes: 180, routineCompletions: completions,
            routineDelays: delays)
    }

    func delay(_ minutes: Int) -> RoutineDelay {
        RoutineDelay(routineId: routineID, cycle: monday, minutes: minutes, at: at(7, 10))
    }

    func ringKey() -> String { RoutineCycle.parentKey(routineID: routineID, stamp: monday) }
    func stepKey(_ step: RoutineStep) -> String {
        RoutineCycle.stepKey(routineID: routineID, stamp: monday, stepID: step.id)
    }

    @Test func aDelayMovesTheRingAndEveryStepAndKeepsTheStamp() throws {
        let moved = state(delays: [delay(90)])
        let routine = try #require(moved.routines.first)
        #expect(routine.delays == [monday: 90])
        let cycle = try #require(RoutineCycle.around(routine, now: at(7, 10), calendar: calendar).current)
        #expect(cycle.stamp == monday)
        #expect(cycle.at == at(8, 30))
        #expect(cycle.steps.map(\.at) == [at(8, 35), at(8, 38)])
        #expect(cycle.delay(in: routine) == 90)
    }

    /// He stopped the 07:00 ring and its first step, then moved the ring
    /// 90 minutes. The ring and both steps ring again at the new times.
    @Test func aMovedRingAndItsStepsRingAgainAfterAStop() {
        let now = at(7, 10)
        let stopped: Set<String> = [ringKey(), stepKey(wash)]
        let held = Reconciler.desired(
            from: state(delays: [delay(90)]), now: now, acknowledgedHere: stopped, calendar: calendar)
        let rings = held.filter { $0.key.hasPrefix(DesiredAlarm.routinePrefix) && $0.fireAt < at(12, 0) }
        #expect(rings.map(\.fireAt) == [at(8, 30), at(8, 35), at(8, 38)])
        #expect(rings.map(\.title) == ["wake up", "Wash face", "Cream"])
        // The repeating alarm gives way to one-time alarms, Wednesday's among them.
        #expect(!held.contains { $0.id == routineID })
        #expect(held.contains { $0.key == RoutineCycle.parentKey(routineID: routineID, stamp: "2026-11-25T07:00") })
    }

    @Test func aStepCheckedOffStaysQuietAfterTheDelay() {
        let checked = RoutineCompletion(routineId: routineID, stepId: wash.id, cycle: monday, completedAt: at(7, 6))
        let held = Reconciler.desired(
            from: state(delays: [delay(90)], completions: [checked]), now: at(7, 10), acknowledgedHere: [],
            calendar: calendar)
        #expect(!held.contains { $0.key == stepKey(wash) })
        #expect(held.contains { $0.key == stepKey(cream) && $0.fireAt == at(8, 38) })
    }

    @Test func theClockAndTheListFollowTheDelay() {
        let moved = state(delays: [delay(90)])
        let routine = moved.routines[0]
        #expect(Reconciler.nextRing(of: routine, in: moved, now: at(7, 10), calendar: calendar) == at(8, 30))
        #expect(
            RingClock.text(for: routine, in: moved, at: at(7, 10), calendar: calendar)
                == "Rings in 0 days 01:20:00, today, Mon 23 Nov at 08:30")
        // Not under way: its new time is still ahead.
        #expect(AlarmList.underWay(routine, in: moved, now: at(7, 10), calendar: calendar) == nil)
        let shown = RoutineCycle.shown(routine, in: moved, now: at(7, 10), window: 10_800, calendar: calendar)
        #expect(shown?.at == at(8, 30))
    }

    @Test func aDelayLaterTheSameRingReplacesTheFirstAndClearingIt() {
        let changes = CompletionChange.coalesce([
            .delay(delay(30)), .delay(delay(60)),
        ])
        #expect(changes == [.delay(delay(60))])
        #expect(CompletionChange.overlayDelays([], changes) == [delay(60)])
        let cleared = CompletionChange.coalesce(changes + [.clearDelay(routineId: routineID, cycle: monday)])
        #expect(CompletionChange.overlayDelays([delay(60)], cleared).isEmpty)
        #expect(CompletionChange.overlayOutcomes([], cleared).isEmpty)
        #expect(CompletionChange.overlay([], cleared).isEmpty)
    }

    @Test func theRequestIsAPutWithTheMinutes() throws {
        #expect(
            AlertsClient.delayPath(routineId: routineID, cycle: monday)
                == "routines/00000000-0000-4000-8000-0000000000e1/cycles/2026-11-23T07:00/delay")
        let body = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(DelayBody(minutes: 90))) as? [String: Any])
        #expect(body["minutes"] as? Int == 90)
        #expect(body.count == 1)
    }

    @Test func aStatusFromAnOlderServerHasNoDelaysAndARoutineSendsNone() throws {
        let old = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(old.routineDelays.isEmpty)
        let json = #"""
            {"configured":true,"routines":[{"id":"00000000-0000-4000-8000-0000000000e1","label":"wake up",
            "hour":7,"minute":0,"days":[1,3,5]}],"routineDelays":[{"routineId":"00000000-0000-4000-8000-0000000000e1",
            "cycle":"2026-11-23T07:00","minutes":45,"at":"2026-11-23T12:10:00Z"}]}
            """#
        let read = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(read.routines.first?.delays == [monday: 45])
        let sent = try #require(
            try JSONSerialization.jsonObject(with: ServerDates.encoder().encode(read.routines[0])) as? [String: Any])
        #expect(sent["delays"] == nil)
        // The phone's own copy keeps the delay across a launch.
        let copy = try ServerDates.decoder().decode(AlertsState.self, from: ServerDates.encoder().encode(read))
        #expect(copy.routines.first?.delays == [monday: 45])
    }

    @Test func theWordsForADelay() {
        #expect(RoutineDelay.words(15) == "15 min")
        #expect(RoutineDelay.words(60) == "1 h")
        #expect(RoutineDelay.words(90) == "1 h 30 min")
        #expect(RoutineDelay.words(1440) == "1 day")
        #expect(RoutineDelay.words(2 * 1440 + 185) == "2 days 3 h 5 min")
        #expect(RoutineDelay.words(10080) == "7 days")
    }

    /// Neb could not delay past 3 hours (2026-11-26). A typed delay adds to
    /// the one already made, up to 7 days after the planned time.
    @Test func aTypedDelayAddsToTheOneMadeAndStopsAtSevenDays() {
        #expect(RoutineDelay.minutes == 1...10080)
        #expect(RoutineDelay.total(adding: 120, to: 180) == 300)
        #expect(RoutineDelay.problem(adding: 4 * 60, to: 180) == nil)
        #expect(RoutineDelay.problem(adding: 10080 - 180, to: 180) == nil)
        #expect(
            RoutineDelay.problem(adding: 10080 - 179, to: 180)
                == "At most 7 days after the planned time: 6 days 21 h more.")
        #expect(RoutineDelay.problem(adding: 0, to: 0) == "Type at least 1 minute.")
        #expect(RoutineDelay.problem(adding: Int.max, to: 30) != nil)
        #expect(RoutineDelay.choices.allSatisfy { RoutineDelay.minutes.contains($0) })
    }

    /// Monday's 07:00 wake up, moved 3 days. Wednesday's ring comes first,
    /// then the moved Monday ring on Thursday with its steps, then Friday's.
    @Test func aRingMovedPastTheNextRingStillRingsWithItsStepsAndTheOthersStay() throws {
        let moved = state(delays: [delay(3 * 1440)])
        let now = at(7, 10)
        let held = Reconciler.desired(from: moved, now: now, acknowledgedHere: [ringKey()], calendar: calendar)
            .filter { $0.key.hasPrefix(DesiredAlarm.routinePrefix) && $0.fireAt < at(12, 0, day: 27) }
            .sorted { $0.fireAt < $1.fireAt }
        // Step alarms are held 48 hours ahead by their cycle's planned ring,
        // so Friday's steps wait. The moved Monday steps are held.
        #expect(
            held.map(\.fireAt) == [
                at(7, 0, day: 25), at(7, 5, day: 25), at(7, 8, day: 25),
                at(7, 0, day: 26), at(7, 5, day: 26), at(7, 8, day: 26),
                at(7, 0, day: 27),
            ])
        #expect(held[3].key == ringKey())
        #expect(held[4].key == stepKey(wash))

        // On Wednesday after its ring, the moved Monday ring is the next.
        let routine = try #require(moved.routines.first)
        let wednesday = RoutineCycle.around(routine, now: at(7, 30, day: 25), calendar: calendar)
        #expect(wednesday.current?.stamp == "2026-11-25T07:00")
        #expect(wednesday.next?.stamp == monday)
        #expect(wednesday.next?.at == at(7, 0, day: 26))
        // Once it has rung on Thursday, it is the one under way.
        let thursday = RoutineCycle.around(routine, now: at(7, 6, day: 26), calendar: calendar)
        #expect(thursday.current?.stamp == monday)
        #expect(thursday.next?.stamp == "2026-11-27T07:00")
    }

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

    @Test func delayingOfflineMovesTheAlarmsAtOnceAndReachesAbearaTechLater() async throws {
        let rig = rig(now: at(7, 10))
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        let offline = await rig.sync.setDelay(delay(90))
        #expect(offline.error == .offline)
        #expect(await rig.alarms.alarms[AlarmID.of(key: ringKey())]?.fireAt == at(8, 30))
        #expect(await rig.alarms.alarms[AlarmID.of(key: stepKey(wash))]?.fireAt == at(8, 35))

        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routineDelays.map(\.minutes) == [90])
        #expect(await rig.sync.completionChanges().isEmpty)

        let back = await rig.sync.clearDelay(routineId: routineID, cycle: monday)
        #expect(back.error == nil)
        #expect(await rig.server.state.routineDelays.isEmpty)
        #expect(await rig.alarms.alarms[AlarmID.of(key: ringKey())] == nil)
        #expect(await rig.alarms.alarms[routineID] != nil)
    }

    @Test func abearaTechRefusesADelayOutOfBounds() async throws {
        let rig = rig(now: at(7, 10))
        _ = await rig.sync.sync()
        var tooLong = delay(10081)
        tooLong.minutes = 10081
        _ = await rig.sync.setDelay(tooLong)
        #expect(await rig.server.state.routineDelays.isEmpty)
        #expect(await rig.sync.completionChanges().isEmpty)
    }
}
