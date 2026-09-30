import Foundation
import Testing

@testable import AlarmCore

/// Clock-style alarms: a time, weekdays, on or off.
@Suite struct RoutineTests {
    /// Gregorian in UTC, so the tests read the same everywhere.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 2026-09-21 14:13:20 UTC.
    let monday = Fixtures.now

    func routine(_ hour: Int, _ minute: Int, days: [Int] = [], enabled: Bool = true, label: String = "Wake")
        -> Routine
    {
        Routine(id: UUID(), label: label, hour: hour, minute: minute, days: days, enabled: enabled)
    }

    func utc(_ text: String) -> Date { ServerDates.parse(text)! }

    /// A routine 30 minutes after the test clock's start, in the phone's own
    /// calendar, which is what the sync schedules with.
    func soon(days: [Int] = []) -> Routine {
        let time = Calendar.current.dateComponents([.hour, .minute], from: monday.addingTimeInterval(30 * 60))
        return routine(time.hour!, time.minute!, days: days)
    }

    // MARK: Days and times

    @Test(arguments: [
        ([Int](), "No repeat"), (Array(1...7), "Every day"), ([1, 2, 3, 4, 5], "Weekdays"), ([6, 7], "Weekends"),
        ([5, 1, 3], "Mon Wed Fri"), ([7], "Sun"),
    ])
    func daysReadAsTheClockAppSaysThem(days: [Int], text: String) {
        #expect(Routine.daysText(days) == text)
    }

    @Test func onceRingsAtTheNextTime() {
        #expect(routine(15, 0).nextFire(after: monday, calendar: Self.utc) == utc("2026-09-21T15:00:00Z"))
        #expect(routine(6, 0).nextFire(after: monday, calendar: Self.utc) == utc("2026-09-22T06:00:00Z"))
    }

    @Test func weekdaysSkipTheWeekend() {
        let friday = utc("2026-09-25T07:00:00Z")
        #expect(
            routine(5, 30, days: [1, 2, 3, 4, 5]).nextFire(after: friday, calendar: Self.utc)
                == utc("2026-09-28T05:30:00Z"))
    }

    @Test func sundayIsSevenInISO() {
        #expect(routine(9, 0, days: [7]).nextFire(after: monday, calendar: Self.utc) == utc("2026-09-27T09:00:00Z"))
    }

    // MARK: Drafts

    @Test func anEmptyLabelIsSentAsAlarm() {
        let draft = RoutineDraft(label: "  ", hour: 6, minute: 0, days: [3, 1, 1])
        #expect(draft.body.label == "Alarm")
        #expect(draft.body.days == [1, 3])
        #expect(draft.problems.isEmpty)
    }

    @Test func aDraftOutsideTheBoundsSaysWhy() {
        let bad = RoutineDraft(
            label: String(repeating: "x", count: 61), hour: 24, minute: 0, days: [0, 8], snoozeMinutes: 31)
        #expect(bad.problems.count == 4)
    }

    // MARK: What the phone holds

    @Test func onlySwitchedOnRoutinesRingAndTheMuteLeavesThemAlone() {
        var state = Fixtures.state([], mutedUntil: monday.addingTimeInterval(86_400))
        let on = routine(6, 0, days: [1, 2, 3, 4, 5])
        state.routines = [on, routine(7, 0, enabled: false)]
        let desired = Reconciler.desired(from: state, now: monday, acknowledgedHere: [], calendar: Self.utc)
        #expect(desired.map(\.id) == [on.id])
        #expect(desired.first?.routine?.days == [1, 2, 3, 4, 5])
    }

    @Test func aRoutineIsNotSetAgainJustBecauseADayPassed() {
        let wake = routine(6, 0, days: Array(1...7))
        var state = Fixtures.state([])
        state.routines = [wake]
        let today = Reconciler.desired(from: state, now: monday, acknowledgedHere: [], calendar: Self.utc)
        let tomorrow = Reconciler.desired(
            from: state, now: monday.addingTimeInterval(86_400), acknowledgedHere: [], calendar: Self.utc)
        #expect(today.first?.fireAt != tomorrow.first?.fireAt)
        let ledger = Dictionary(uniqueKeysWithValues: today.map { ($0.id, $0) })
        #expect(Reconciler.changes(desired: tomorrow, ledger: ledger, system: [wake.id]).isEmpty)
    }

    @Test func aNewTimeSetsItAgain() {
        var wake = routine(6, 0, days: [1])
        var state = Fixtures.state([])
        state.routines = [wake]
        let before = Reconciler.desired(from: state, now: monday, acknowledgedHere: [], calendar: Self.utc)
        wake.minute = 15
        state.routines = [wake]
        let after = Reconciler.desired(from: state, now: monday, acknowledgedHere: [], calendar: Self.utc)
        let ledger = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        #expect(
            Reconciler.changes(desired: after, ledger: ledger, system: [wake.id])
                == AlarmChanges(cancel: [wake.id], schedule: after))
    }

    // MARK: Every button

    func held(_ rig: Fixtures.Rig) async -> [UUID: DesiredAlarm] { await rig.alarms.alarms }

    @Test func addingSwitchingEditingAndDeleting() async throws {
        let clock = Fixtures.TestClock()
        let rig = Fixtures.rig([], routines: [], clock: clock)

        var report = await rig.sync.perform { client throws(APIError) in
            try await client.createRoutine(RoutineDraft(hour: 6, minute: 0, days: [1, 2, 3, 4, 5]))
        }
        let made = try #require(report.state?.routines.first)
        #expect(made.label == "Alarm")
        #expect(await held(rig)[made.id]?.routine?.days == [1, 2, 3, 4, 5])

        var switchedOff = made.draft
        switchedOff.enabled = false
        let off = switchedOff
        report = await rig.sync.perform { client throws(APIError) in try await client.updateRoutine(id: made.id, off) }
        #expect(await held(rig)[made.id] == nil)

        var moved = made.draft
        moved.hour = 7
        let later = moved
        report = await rig.sync.perform { client throws(APIError) in
            try await client.updateRoutine(id: made.id, later)
        }
        #expect(await held(rig)[made.id]?.routine?.hour == 7)

        report = await rig.sync.perform { client throws(APIError) in try await client.deleteRoutine(id: made.id) }
        #expect(report.state?.routines.isEmpty == true)
        #expect(await held(rig).isEmpty)
    }

    @Test func aOneTimeAlarmSwitchesItselfOffAfterItRings() async throws {
        let clock = Fixtures.TestClock()
        let once = soon()
        let rig = Fixtures.rig([], routines: [once], clock: clock)
        _ = await rig.sync.sync()
        #expect(await held(rig)[once.id] != nil)

        // It rings and the owner stops it. The alarm system drops it.
        clock.advance(minutes: 60)
        await rig.alarms.ring(once.id)

        let report = await rig.sync.sync()
        #expect(report.error == nil)
        #expect(report.state?.routines.first?.enabled == false)
        #expect(await rig.server.routineUpdates.map(\.enabled) == [false])
        #expect(await held(rig)[once.id] == nil)
    }

    @Test func aOneTimeAlarmThatRangOfflineIsNotSetForTomorrow() async throws {
        let clock = Fixtures.TestClock()
        let once = soon()
        let wake = routine(6, 0, days: Array(1...7))
        let rig = Fixtures.rig([], routines: [once, wake], clock: clock)
        _ = await rig.sync.sync()

        clock.advance(minutes: 60)
        await rig.alarms.ring(once.id)
        await rig.server.setOffline(true)
        // An action made offline applies the last state: the rung alarm stays off.
        _ = await rig.sync.perform { client throws(APIError) in try await client.unmute() }
        #expect(await held(rig)[once.id] == nil)

        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.routineUpdates.map(\.id) == [once.id])
        #expect(await held(rig)[once.id] == nil)
        #expect(await held(rig)[wake.id] != nil)
    }

    @Test func aRepeatingAlarmThatRangIsSetAgain() async {
        let clock = Fixtures.TestClock()
        let wake = soon(days: Array(1...7))
        let rig = Fixtures.rig([], routines: [wake], clock: clock)
        _ = await rig.sync.sync()
        clock.advance(minutes: 60)
        await rig.alarms.ring(wake.id)
        _ = await rig.sync.sync()
        #expect(await rig.server.routineUpdates.isEmpty)
        #expect(await held(rig)[wake.id] != nil)
    }

    @Test func routineRoutesCarryTheIdInThePathAndTheDraftInTheBody() async throws {
        let transport = ScriptedTransport(body: Data(#"{"configured":true,"alerts":[]}"#.utf8))
        let id = UUID(uuidString: "0B8F6A0E-1111-4222-8333-944455556666")!
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport)
            .updateRoutine(id: id, RoutineDraft(label: "PT", hour: 5, minute: 0, days: [2, 4]))
        let request = try #require(await transport.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/alerts/routines/0b8f6a0e-1111-4222-8333-944455556666")
        let body = try JSONDecoder().decode(RoutineDraft.self, from: try #require(request.httpBody))
        #expect(body == RoutineDraft(label: "PT", hour: 5, minute: 0, days: [2, 4]))
    }

    @Test func aStateWithoutRoutinesStillDecodes() throws {
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(state.routines.isEmpty)
    }
}
