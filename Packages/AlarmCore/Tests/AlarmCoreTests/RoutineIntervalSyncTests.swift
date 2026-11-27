import Foundation
import Testing

@testable import AlarmCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What the phone holds for a routine the alarm system cannot repeat: one
/// fixed-date alarm for each coming ring, topped up at every sync.
@Suite struct RoutineIntervalSyncTests {
    static let waterID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD")!
    static let stretchID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000051")!
    static let key = "routine:0a1b2c3d-0000-4000-8000-00000000abcd:"
    static let newYork = RoutineRingTests.newYork
    /// Wednesday 25 November 2026, 20:00 in New York.
    static let start = ServerDates.parse("2026-11-25T20:00:00-05:00")!

    func at(_ text: String) -> Date { ServerDates.parse(text)! }

    /// Every 97 minutes from 21:00 on 25 November: 21:00, 22:37, 00:14, 01:51.
    var water: Routine {
        Routine(
            id: Self.waterID, label: "Water", hour: 21, minute: 0, days: [], repeatMode: .interval, every: 97,
            unit: .minutes, startsOn: "2026-11-25")
    }

    /// Monday, Wednesday, and Friday at 06:30, every 2 weeks from Wednesday 25 November.
    var fortnight: Routine {
        Routine(
            id: UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000000F")!, label: "Bins", hour: 6, minute: 30,
            days: [1, 3, 5], repeatMode: .weekdays, every: 2, unit: .weeks, startsOn: "2026-11-25")
    }

    func state(_ routines: [Routine]) -> AlertsState {
        var state = Fixtures.state([])
        state.routines = routines
        return state
    }

    func desired(_ state: AlertsState, at now: Date = start, acknowledgedHere: Set<String> = []) -> [DesiredAlarm] {
        Reconciler.desired(from: state, now: now, acknowledgedHere: acknowledgedHere, calendar: Self.newYork)
    }

    struct Rig {
        let server: FakeAlertsServer
        let alarms: MemoryAlarms
        let sync: AlarmSync
        let clock: Fixtures.TestClock
    }

    func rig(_ routines: [Routine], rings: [RoutineRing] = []) async -> Rig {
        var initial = state(routines)
        initial.routineRings = rings
        let clock = Fixtures.TestClock(Self.start)
        let server = FakeAlertsServer(state: initial, token: Fixtures.token, now: { clock.now })
        await server.setCalendar(Self.newYork)
        let alarms = MemoryAlarms()
        let sync = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: server, alarms: alarms,
            documents: MemoryDocuments(), now: { clock.now }, calendar: Self.newYork)
        return Rig(server: server, alarms: alarms, sync: sync, clock: clock)
    }

    // MARK: What the phone should hold

    @Test func anIntervalRoutineIsHeldRingByRingAndNeverAsARepeatingAlarm() {
        let alarms = desired(state([water]))
        // 104 rings fall in 7 days. The phone holds the next 16.
        #expect(alarms.count == 16)
        #expect(alarms.allSatisfy { $0.routine == nil && !$0.isRoutine })
        #expect(alarms.allSatisfy { $0.id == AlarmID.of(key: $0.key) && $0.id != Self.waterID })
        #expect(
            alarms.prefix(4).map(\.key) == [
                Self.key + "2026-11-25T21:00", Self.key + "2026-11-25T22:37", Self.key + "2026-11-26T00:14",
                Self.key + "2026-11-26T01:51",
            ])
        #expect(alarms.first?.fireAt == at("2026-11-25T21:00:00-05:00"))
        #expect(alarms.last?.fireAt == at("2026-11-25T21:00:00-05:00").addingTimeInterval(15 * 97 * 60))
        #expect(Set(alarms.map(\.key)).count == 16)
        #expect(alarms.allSatisfy { $0.title == "Water" && $0.snoozeMinutes == 9 })
        // Each ring gives up one stop window after its own time.
        #expect(alarms.first?.startsAt == at("2026-11-25T21:00:00-05:00").addingTimeInterval(180 * 60))
    }

    @Test func weekdaysEveryTwoWeeksAreHeldRingByRingForTheNextSevenDays() {
        // Monday 23 November: Wednesday and Friday ring. The Monday after is an off week.
        let alarms = desired(state([fortnight]), at: at("2026-11-23T08:00:00-05:00"))
        #expect(alarms.map(\.fireAt) == [at("2026-11-25T06:30:00-05:00"), at("2026-11-27T06:30:00-05:00")])
        #expect(alarms.allSatisfy { $0.routine == nil })
        #expect(alarms.map(\.key).allSatisfy { $0.hasSuffix("T06:30") })
        // In the off week the next ring is more than 7 days away and is still held.
        let off = desired(state([fortnight]), at: at("2026-11-28T08:00:00-05:00"))
        #expect(off.map(\.fireAt) == [at("2026-12-07T06:30:00-05:00")])
    }

    @Test func aRoutineOnWeekdaysEveryWeekIsStillOneRepeatingAlarm() {
        let wake = Routine(id: Self.waterID, label: "Wake", hour: 5, minute: 30, days: [1, 2, 3, 4, 5])
        let alarms = desired(state([wake]))
        #expect(alarms.count == 1)
        #expect(alarms.first?.id == Self.waterID)
        #expect(alarms.first?.key == "routine:0a1b2c3d-0000-4000-8000-00000000abcd")
        #expect(alarms.first?.routine == RoutineSchedule(hour: 5, minute: 30, days: [1, 2, 3, 4, 5], snoozeMinutes: 9))
    }

    @Test func aRingOnceRoutineIsStillOneAlarmThatRingsOnce() {
        let once = Routine(id: Self.waterID, label: "Once", hour: 21, minute: 0, days: [])
        let alarms = desired(state([once]))
        #expect(alarms.count == 1)
        #expect(alarms.first?.routine?.ringsOnce == true)
        #expect(alarms.first?.fireAt == at("2026-11-25T21:00:00-05:00"))
    }

    @Test func aMonthlyRoutineHoldsItsNextRingHoweverFarOff() {
        let rent = Routine(
            id: Self.waterID, label: "Rent", hour: 8, minute: 0, days: [], repeatMode: .interval, every: 1,
            unit: .months, startsOn: "2026-10-01")
        let alarms = desired(state([rent]))
        #expect(alarms.map(\.key) == [Self.key + "2026-12-01T08:00"])
        #expect(alarms.first?.routine == nil)
    }

    @Test func aSwitchedOffIntervalRoutineHoldsNothing() {
        var off = water
        off.enabled = false
        #expect(desired(state([off])).isEmpty)
    }

    @Test func aLaterSyncTopsTheRingsUp() {
        let first = desired(state([water]))
        // 200 minutes on, 21:00 and 22:37 have rung. The ring under way
        // counts toward the 16, so 15 are ahead.
        let later = desired(state([water]), at: Self.start.addingTimeInterval(200 * 60))
        #expect(later.count == 15)
        #expect(later.first?.key == Self.key + "2026-11-26T00:14")
        #expect(later.last!.fireAt == first.last!.fireAt.addingTimeInterval(97 * 60))
        // The alarms held from the first sync stay as they are: same id, same alarm.
        let ledger = Dictionary(first.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let system = Set(first.dropFirst(2).map(\.id))
        let changes = Reconciler.changes(desired: later, ledger: ledger, system: system)
        #expect(changes.cancel.isEmpty)
        #expect(changes.schedule.map(\.key) == later.suffix(1).map(\.key))
    }

    // MARK: Done, Skipped, a delay, and steps key on the ring's own stamp

    @Test func aRingMarkedDoneOrSkippedIsNotHeldAndTheOthersAre() {
        var state = state([water])
        state.routineOutcomes = [
            RoutineOutcome(routineId: Self.waterID, cycle: "2026-11-25T22:37", status: .done, at: Self.start),
            RoutineOutcome(routineId: Self.waterID, cycle: "2026-11-26T01:51", status: .skipped, at: Self.start),
        ]
        let keys = desired(state).map(\.key)
        #expect(keys.count == 14)
        #expect(
            keys.prefix(3) == [
                Self.key + "2026-11-25T21:00", Self.key + "2026-11-26T00:14", Self.key + "2026-11-26T03:28",
            ])
        // The clock beside the alarm counts to the next ring not marked.
        state.routineOutcomes.append(
            RoutineOutcome(routineId: Self.waterID, cycle: "2026-11-25T21:00", status: .done, at: Self.start))
        #expect(
            Reconciler.nextRing(of: water, in: state, now: Self.start, calendar: Self.newYork)
                == at("2026-11-26T00:14:00-05:00"))
    }

    @Test func aStopOnThisPhoneNotYetSentKeepsThatRingOff() {
        let keys = desired(state([water]), acknowledgedHere: [Self.key + "2026-11-25T21:00"]).map(\.key)
        #expect(keys.first == Self.key + "2026-11-25T22:37")
    }

    @Test func aDelayMovesOneRingAndKeepsItsKey() {
        var state = state([water])
        state.routineDelays = [
            RoutineDelay(routineId: Self.waterID, cycle: "2026-11-25T22:37", minutes: 30, at: Self.start)
        ]
        let alarms = desired(state)
        let moved = alarms.first { $0.key == Self.key + "2026-11-25T22:37" }
        #expect(moved?.fireAt == at("2026-11-25T23:07:00-05:00"))
        #expect(alarms.first { $0.key == Self.key + "2026-11-26T00:14" }?.fireAt == at("2026-11-26T00:14:00-05:00"))
    }

    @Test func stepsOfAnIntervalRoutineRingAfterEachRingAndCheckOffByItsStamp() {
        var routine = water
        routine.steps = [RoutineStep(id: Self.stretchID, label: "Stretch", offsetMinutes: 5)]
        var state = state([routine])
        let step = ":step:0a1b2c3d-0000-4000-8000-000000000051"
        var steps = desired(state).filter { $0.key.contains(":step:") }
        #expect(steps.count == 16)
        #expect(steps.first?.key == Self.key + "2026-11-25T21:00" + step)
        #expect(steps.first?.fireAt == at("2026-11-25T21:05:00-05:00"))
        #expect(steps.first?.title == "Stretch")
        // Checked off for the 22:37 ring alone.
        state.routineCompletions = [
            RoutineCompletion(
                routineId: Self.waterID, stepId: Self.stretchID, cycle: "2026-11-25T22:37", completedAt: Self.start)
        ]
        steps = desired(state).filter { $0.key.contains(":step:") }
        #expect(steps.count == 15)
        #expect(!steps.contains { $0.key == Self.key + "2026-11-25T22:37" + step })
        #expect(steps.contains { $0.key == Self.key + "2026-11-26T00:14" + step })
        // A skipped ring takes its step with it.
        state.routineOutcomes = [
            RoutineOutcome(routineId: Self.waterID, cycle: "2026-11-25T21:00", status: .skipped, at: Self.start)
        ]
        steps = desired(state).filter { $0.key.contains(":step:") }
        #expect(steps.first?.key == Self.key + "2026-11-26T00:14" + step)
    }

    @Test func theListShowsAnIntervalRoutinesNextRingAndCountsDownToIt() {
        let state = state([water])
        let shown = RoutineCycle.shown(water, in: state, now: Self.start, window: 180 * 60, calendar: Self.newYork)
        #expect(shown?.stamp == "2026-11-25T21:00")
        #expect(
            RingClock.text(for: water, in: state, at: Self.start, calendar: Self.newYork)
                == "Rings in 0 days 01:00:00, today, Wed 25 Nov at 21:00")
        // After 21:00 rings, the list moves to 22:37.
        let later = at("2026-11-25T21:10:00-05:00")
        #expect(
            RoutineCycle.shown(water, in: state, now: later, window: 180 * 60, calendar: Self.newYork)?.stamp
                == "2026-11-25T22:37")
        let ordered = AlarmList.ordered(
            [Routine(id: UUID(), label: "Wake", hour: 5, minute: 30, days: Array(1...7)), water], in: state,
            now: Self.start, calendar: Self.newYork)
        #expect(ordered.map(\.label) == ["Water", "Wake"])
    }

    // MARK: Through a sync

    @Test func aSyncSetsSixteenOneTimeAlarmsAndALaterSyncAddsTheNext() async {
        let rig = await rig([water])
        var report = await rig.sync.sync()
        #expect(report.error == nil)
        #expect(report.scheduled == 16)
        var held = await rig.alarms.alarms
        #expect(held.count == 16)
        #expect(held[Self.waterID] == nil)
        #expect(held.values.allSatisfy { $0.routine == nil })

        // 21:00 rings and is stopped. The system drops a one-time alarm.
        rig.clock.advance(minutes: 61)
        let first = AlarmID.of(key: Self.key + "2026-11-25T21:00")
        await rig.alarms.startRinging(first)
        try? await rig.alarms.stop(first)
        report = await rig.sync.acknowledge(key: Self.key + "2026-11-25T21:00")
        #expect(report.scheduled == 0 && report.cancelled == 0)
        #expect(await rig.alarms.alarms.count == 15)

        // 22:37 rings and is stopped. The sync Stop starts adds the ring that came into reach.
        rig.clock.advance(minutes: 99)
        let second = AlarmID.of(key: Self.key + "2026-11-25T22:37")
        await rig.alarms.startRinging(second)
        try? await rig.alarms.stop(second)
        report = await rig.sync.acknowledge(key: Self.key + "2026-11-25T22:37")
        #expect(report.scheduled == 1)
        #expect(report.cancelled == 0)
        held = await rig.alarms.alarms
        #expect(held.count == 15)
        let latest = held.values.map(\.fireAt).max()
        #expect(latest == at("2026-11-25T21:00:00-05:00").addingTimeInterval(16 * 97 * 60))
        // A sync with nothing new changes nothing.
        report = await rig.sync.sync()
        #expect(report.scheduled == 0 && report.cancelled == 0)
    }

    @Test func aRingThatRangDoesNotDeleteAnIntervalRoutine() async {
        let rig = await rig([water])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 61)
        // 21:00 rang and was stopped with no signal: gone from the alarm system.
        await rig.alarms.ring(AlarmID.of(key: Self.key + "2026-11-25T21:00"))
        _ = await rig.sync.sync()
        _ = await rig.sync.sync()
        #expect(await rig.sync.pendingOff().isEmpty)
        #expect(await rig.server.routineDeletes.isEmpty)
        #expect(await rig.server.state.routines.map(\.label) == ["Water"])
        #expect(await rig.alarms.alarms.count == 15)
    }

    @Test func aRingOnceRoutineThatRangIsStillDeleted() async {
        let once = Routine(id: Self.waterID, label: "Once", hour: 21, minute: 0, days: [])
        let rig = await rig([once])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 61)
        await rig.alarms.ring(Self.waterID)
        _ = await rig.sync.sync()
        #expect(await rig.server.routineDeletes == [Self.waterID])
    }

    @Test func aRingSnoozedPastMidnightIsStoppedUnderItsOwnKey() async throws {
        // Every 100 minutes from 22:10: 22:10, 23:50, 01:30.
        var late = water
        late.hour = 22
        late.minute = 10
        late.every = 100
        let key = Self.key + "2026-11-25T23:50"
        let alert = at("2026-11-25T23:50:00-05:00")
        let rig = await rig(
            [late],
            rings: [
                RoutineRing(
                    key: key, routineId: Self.waterID, label: "Water", alertAt: alert,
                    startsAt: alert.addingTimeInterval(180 * 60))
            ])
        _ = await rig.sync.sync()
        let id = AlarmID.of(key: key)
        #expect(await rig.alarms.alarms[id]?.fireAt == alert)

        // 00:10 the next day: 22:10 rang and was stopped. 23:50 rang, was
        // snoozed twice, and is still going.
        await rig.alarms.ring(AlarmID.of(key: Self.key + "2026-11-25T22:10"))
        rig.clock.advance(minutes: 250)
        await rig.alarms.startRinging(id)
        var report = await rig.sync.sync()
        #expect(report.cancelled == 0 && report.stopped == 0)
        #expect(await rig.alarms.alarms[id] != nil, "a ringing alarm is not cancelled by a sync")

        // Stop: the system drops the alarm and runs the intent with the ring's key.
        try await rig.alarms.stop(id)
        report = await rig.sync.acknowledge(key: key)
        #expect(report.error == nil)
        #expect(await rig.server.acknowledgements == [key])
        #expect(await rig.alarms.alarms[id] == nil)
        // The 01:30 ring is still set.
        #expect(await rig.alarms.alarms[AlarmID.of(key: Self.key + "2026-11-26T01:30")] != nil)
    }

    @Test func aRingAcknowledgedElsewhereStopsOnThePhone() async {
        let key = Self.key + "2026-11-25T21:00"
        let alert = at("2026-11-25T21:00:00-05:00")
        let rig = await rig(
            [water],
            rings: [
                RoutineRing(
                    key: key, routineId: Self.waterID, label: "Water", alertAt: alert,
                    startsAt: alert.addingTimeInterval(180 * 60))
            ])
        _ = await rig.sync.sync()
        rig.clock.advance(minutes: 62)
        let id = AlarmID.of(key: key)
        await rig.alarms.startRinging(id)
        var state = await rig.server.state
        state.routineRings[0].acknowledged = true
        state.routineRings[0].acknowledgedVia = "browser"
        await rig.server.setState(state)
        _ = await rig.sync.sync()
        #expect(await rig.alarms.stops == [id])
        #expect(await rig.alarms.alarms[id] == nil)
    }

    // MARK: abera.tech in memory

    func put(_ body: String, to id: UUID) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "https://abera.tech/api/alerts/routines/\(id.uuidString.lowercased())")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(Fixtures.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)
        return request
    }

    @Test func aChangeFromAnOlderBuildKeepsTheRepeatItDoesNotSend() async throws {
        let rig = await rig([water])
        // The switch on a build before intervals: no repeat, every, unit, or startsOn.
        let old = #"{"label":"Water","hour":21,"minute":0,"days":[],"enabled":false,"snoozeMinutes":9}"#
        let (_, response) = try await rig.server.send(put(old, to: Self.waterID))
        #expect(response.statusCode == 200)
        let stored = try #require(await rig.server.state.routines.first)
        #expect(!stored.enabled)
        #expect(stored.repeatMode == .interval && stored.every == 97 && stored.unit == .minutes)
        #expect(stored.startsOn == "2026-11-25")

        // One field sent changes that field alone.
        let (_, hourly) = try await rig.server.send(
            put(
                #"{"label":"Water","hour":21,"minute":0,"days":[],"enabled":true,"snoozeMinutes":9,"every":2,"unit":"hours"}"#,
                to: Self.waterID))
        #expect(hourly.statusCode == 200)
        let changed = try #require(await rig.server.state.routines.first)
        #expect(changed.repeatText == "Every 2 hours" && changed.startsOn == "2026-11-25")

        // What is kept is checked with what is sent: days on an interval are refused.
        let (_, refused) = try await rig.server.send(
            put(
                #"{"label":"Water","hour":21,"minute":0,"days":[1],"enabled":true,"snoozeMinutes":9}"#,
                to: Self.waterID))
        #expect(refused.statusCode == 400)
    }

    @Test func aNewRoutineTakesTheDefaultsAndAnIntervalIsStoredWhole() async throws {
        let rig = await rig([])
        let client = AlertsClient(pairing: Fixtures.pairing, transport: rig.server, timeZone: Self.newYork.timeZone)
        var state = try await client.createRoutine(RoutineDraft(label: "Wake", hour: 5, minute: 30, days: [1]))
        var made = try #require(state.routines.first { $0.label == "Wake" })
        #expect(made.repeatMode == .weekdays && made.every == 1 && made.unit == .weeks && made.startsOn == nil)

        state = try await client.createRoutine(water.draft)
        made = try #require(state.routines.first { $0.label == "Water" })
        #expect(made.repeatText == "Every 97 minutes" && made.startsOn == "2026-11-25")

        // Back to weekdays every week: the start date is stored as none.
        var plain = RoutineDraft(label: "Water", hour: 21, minute: 0, days: [2])
        plain.startsOn = "2026-11-25"
        state = try await client.updateRoutine(id: made.id, plain)
        made = try #require(state.routines.first { $0.label == "Water" })
        #expect(made.repeatText == "Tue" && made.startsOn == nil)

        // A draft that breaks a rule is refused.
        await #expect(throws: APIError.self) {
            _ = try await client.createRoutine(
                RoutineDraft(hour: 6, minute: 0, repeatMode: .interval, every: 2, unit: .hours))
        }
    }

    @Test func aRoutineMadeOnThePhoneIsSentWithItsRepeatAndSetRingByRing() async {
        let rig = await rig([])
        let report = await rig.sync.changeRoutine(.create(local: UUID(), draft: water.draft))
        #expect(report.error == nil)
        let stored = await rig.server.state.routines
        #expect(stored.map(\.repeatText) == ["Every 97 minutes"])
        #expect(report.state?.routines.first?.startsOn == "2026-11-25")
        #expect(await rig.alarms.alarms.count == 16)
        #expect(await rig.alarms.alarms.values.allSatisfy { $0.routine == nil })
    }

    // MARK: The widget

    @Test func theWidgetListsAnIntervalRoutinesRingsAsRoutineRings() throws {
        let held = desired(state([water]))
        let shot = WidgetSnapshot.make(state: nil, held: held, timer: nil, paired: true, now: Self.start)
        #expect(shot.routines.isEmpty)
        #expect(shot.alarms.count == 16)
        #expect(
            shot.nextRing(after: Self.start, calendar: Self.newYork)
                == WidgetSnapshot.Ring(title: "Water", at: at("2026-11-25T21:00:00-05:00"), kind: .routine))
        let night = shot.rings(
            after: at("2026-11-25T21:00:00-05:00"), through: at("2026-11-26T02:00:00-05:00"), calendar: Self.newYork)
        #expect(
            night.map(\.at) == [
                at("2026-11-25T22:37:00-05:00"), at("2026-11-26T00:14:00-05:00"), at("2026-11-26T01:51:00-05:00"),
            ])
        #expect(night.allSatisfy { $0.kind == .routine })
        #expect(try WidgetSnapshot.decode(shot.encoded()) == shot)
    }

    @Test func aScheduleWithAnIntervalGivesItsRingsFromTheSameMath() {
        // A snapshot holding the schedule itself still lists the right rings.
        let shot = WidgetSnapshot(
            writtenAt: Self.start, routines: [WidgetSnapshot.RoutineAlarm(label: "Water", schedule: water.schedule)])
        let rings = shot.rings(after: Self.start, through: at("2026-11-26T00:30:00-05:00"), calendar: Self.newYork)
        #expect(
            rings.map(\.at) == [
                at("2026-11-25T21:00:00-05:00"), at("2026-11-25T22:37:00-05:00"), at("2026-11-26T00:14:00-05:00"),
            ])
        // One whose next ring is past the week is still found.
        let rent = RoutineSchedule(
            hour: 8, minute: 0, days: [], snoozeMinutes: 9, repeatMode: .interval, every: 1, unit: .months,
            startsOn: "2026-10-01")
        let monthly = WidgetSnapshot(
            writtenAt: Self.start, routines: [WidgetSnapshot.RoutineAlarm(label: "Rent", schedule: rent)])
        #expect(monthly.nextRing(after: Self.start, calendar: Self.newYork)?.at == at("2026-12-01T08:00:00-05:00"))
    }

    @Test func aSnapshotFromAnOlderBuildStillReads() throws {
        let old =
            #"{"writtenAt":"2026-11-25T20:00:00Z","paired":true,"alarms":[{"title":"Standup","at":"2026-11-26T14:00:00Z"}],"routines":[{"label":"Wake","schedule":{"hour":5,"minute":30,"days":[1,2,3,4,5],"snoozeMinutes":9}}],"events":[],"countdowns":[]}"#
        let shot = try WidgetSnapshot.decode(Data(old.utf8))
        #expect(shot.alarms == [WidgetSnapshot.OneTime(title: "Standup", at: at("2026-11-26T14:00:00Z"))])
        #expect(shot.alarms.first?.routine == false)
        #expect(
            shot.routines.first?.schedule
                == RoutineSchedule(hour: 5, minute: 30, days: [1, 2, 3, 4, 5], snoozeMinutes: 9))
        #expect(shot.nextRing(after: Self.start, calendar: Self.newYork)?.title == "Wake")
    }

    // MARK: Steps and alarms of their own

    @Test func anIntervalRoutineIsNotMovedUnderAnotherAndTakesNone() {
        let wake = Routine(id: UUID(), label: "Wake", hour: 6, minute: 0, days: [1, 2, 3, 4, 5])
        #expect(RoutineChaining.subordinate(water, under: wake) == .failure(.interval))
        #expect(RoutineChaining.subordinate(wake, under: water) == .failure(.interval))
        #expect(RoutineChaining.Refusal.interval.message == RoutineChaining.intervalReason)
        #expect(!RoutineChaining.canChain(water))
        #expect(RoutineChaining.canChain(wake) && RoutineChaining.canChain(fortnight))
        var stepped = water
        stepped.steps = [RoutineStep(id: Self.stretchID, label: "Stretch", offsetMinutes: 5)]
        #expect(RoutineChaining.separate(Self.stretchID, from: stepped) == nil)
    }

    @Test func aStepOfAnAlarmEveryTwoWeeksSeparatesOntoTheSameWeeks() throws {
        var parent = fortnight
        parent.steps = [RoutineStep(id: Self.stretchID, label: "Stretch", offsetMinutes: 5)]
        let (remaining, alarm) = try #require(RoutineChaining.separate(Self.stretchID, from: parent))
        #expect(remaining.every == 2 && remaining.steps.isEmpty)
        #expect(alarm.hour == 6 && alarm.minute == 35 && alarm.days == [1, 3, 5])
        #expect(alarm.repeatMode == .weekdays && alarm.every == 2 && alarm.unit == .weeks)
        #expect(alarm.startsOn == "2026-11-25")
        #expect(alarm.problems.isEmpty)
        // A plain weekday alarm's step still becomes a plain weekday alarm.
        var wake = Routine(id: UUID(), label: "Wake", hour: 6, minute: 0, days: [1, 2])
        wake.steps = parent.steps
        let plain = try #require(RoutineChaining.separate(Self.stretchID, from: wake)).alarm
        #expect(plain.every == 1 && plain.startsOn == nil && plain.problems.isEmpty)
    }

    @Test func aStepAfterMidnightEveryTwoWeeksKeepsTheWeeksItRangIn() throws {
        func ringsOf(_ draft: RoutineDraft, _ count: Int) -> [Date] {
            let routine = Routine(
                id: UUID(), label: "A", hour: draft.hour, minute: draft.minute, days: draft.days,
                repeatMode: draft.repeatMode, every: draft.every, unit: draft.unit, startsOn: draft.startsOn)
            var out: [Date] = []
            var after = at("2026-11-01T00:00:00-04:00")
            while out.count < count, let next = routine.nextFire(after: after, calendar: Self.newYork) {
                out.append(next)
                after = next
            }
            return out
        }
        func late(days: [Int], from start: String) -> Routine {
            Routine(
                id: UUID(), label: "Night", hour: 23, minute: 0, days: days,
                steps: [RoutineStep(id: Self.stretchID, label: "Pills", offsetMinutes: 90)], repeatMode: .weekdays,
                every: 2, unit: .weeks, startsOn: start)
        }
        // Each case: the separated alarm rings exactly 90 minutes after the parent did.
        for parent in [
            late(days: [1, 3], from: "2026-11-25"), late(days: [7], from: "2026-11-25"),
            late(days: [1, 6], from: "2026-11-29"),
        ] {
            let alarm = try #require(RoutineChaining.separate(Self.stretchID, from: parent)).alarm
            #expect(alarm.problems.isEmpty)
            #expect(
                ringsOf(alarm, 4) == ringsOf(parent.draft, 4).map { $0.addingTimeInterval(90 * 60) },
                "\(parent.days) from \(parent.startsOn ?? "")")
        }
        // Sunday with another day: Sunday's step falls in the next week. No one alarm rings there.
        #expect(RoutineChaining.separate(Self.stretchID, from: late(days: [3, 7], from: "2026-11-25")) == nil)
    }

    // MARK: With a delay of up to 7 days, and steps every N days

    @Test func aSevenDayDelayOnAnIntervalRingStaysHeldUnderItsStamp() {
        var state = state([water])
        let key = Self.key + "2026-11-25T22:37"
        let moved = at("2026-12-02T22:37:00-05:00")
        state.routineDelays = [
            RoutineDelay(routineId: Self.waterID, cycle: "2026-11-25T22:37", minutes: 10080, at: Self.start)
        ]
        // Before its planned time it is one of the 16.
        var alarms = desired(state)
        #expect(alarms.count == 16)
        #expect(alarms.first { $0.key == key }?.fireAt == moved)
        #expect(alarms.last?.key == key)
        // Three days on, 44 rings have passed it. It is still held, as a one-time alarm.
        alarms = desired(state, at: at("2026-11-28T20:00:00-05:00"))
        let held = alarms.first { $0.key == key }
        #expect(held?.fireAt == moved)
        #expect(held?.routine == nil && held?.id == AlarmID.of(key: key))
        // The ring under way counts toward the 16, so 15 are ahead: it and 14 others.
        #expect(alarms.count == 15)
        #expect(Set(alarms.map(\.key)).count == 15)
        // A minute before it rings it is the next ring in the phone's list.
        alarms = desired(state, at: moved.addingTimeInterval(-60))
        #expect(alarms.first?.key == key)
        // Once it has rung it is no longer wanted, and the series goes on.
        alarms = desired(state, at: moved.addingTimeInterval(120))
        #expect(!alarms.contains { $0.key == key })
        #expect(alarms.count == 15)
    }

    @Test func aDelayWhoseStampIsNoRingOfTheSeriesRingsNothing() {
        var state = state([water])
        // 22:38 is not a ring of 21:00 every 97 minutes: the series changed since the delay.
        state.routineDelays = [
            RoutineDelay(routineId: Self.waterID, cycle: "2026-11-25T22:38", minutes: 10080, at: Self.start)
        ]
        let alarms = desired(state, at: at("2026-11-28T20:00:00-05:00"))
        #expect(!alarms.contains { $0.key.hasSuffix("2026-11-25T22:38") })
        #expect(alarms.allSatisfy { $0.fireAt < at("2026-11-30T00:00:00-05:00") })
    }

    @Test func aDelayedRingInTheHourTheClocksRepeatKeepsItsOwnInstant() {
        // Every 2 hours from 00:30 on 1 November: the second ring is 01:30 for the second time.
        var late = water
        late.hour = 0
        late.minute = 30
        late.every = 2
        late.unit = .hours
        late.startsOn = "2026-11-01"
        var state = state([late])
        state.routineDelays = [
            RoutineDelay(routineId: Self.waterID, cycle: "2026-11-01T01:30", minutes: 2880, at: Self.start)
        ]
        let alarms = desired(state, at: at("2026-11-02T12:00:00-05:00"))
        // Two days after 01:30 Eastern Standard Time, not after 01:30 daylight time.
        #expect(
            alarms.first { $0.key == Self.key + "2026-11-01T01:30" }?.fireAt == at("2026-11-03T01:30:00-05:00"))
    }

    @Test func aSevenDayDelayOnARingEveryTwoWeeksRingsInTheOffWeek() {
        var state = state([fortnight])
        let key = "routine:0a1b2c3d-0000-4000-8000-00000000000f:2026-11-27T06:30"
        state.routineDelays = [
            RoutineDelay(routineId: fortnight.id, cycle: "2026-11-27T06:30", minutes: 10080, at: Self.start)
        ]
        // Thursday, the day before its planned time.
        var alarms = desired(state, at: at("2026-11-26T08:00:00-05:00"))
        #expect(alarms.map(\.key) == [key])
        #expect(alarms.first?.fireAt == at("2026-12-04T06:30:00-05:00"))
        // Saturday, after its planned time: it and the next ring week's Monday.
        alarms = desired(state, at: at("2026-11-28T08:00:00-05:00"))
        #expect(alarms.map(\.fireAt) == [at("2026-12-04T06:30:00-05:00"), at("2026-12-07T06:30:00-05:00")])
        #expect(alarms.first?.key == key)
        #expect(alarms.allSatisfy { $0.routine == nil })
    }

    @Test func aStepEveryTwoDaysRingsAtEveryRingOfItsDaysOnAnIntervalWithSeveralRingsADay() {
        // Every 8 hours from 06:00: 06:00, 14:00, and 22:00 each day.
        var routine = water
        routine.hour = 6
        routine.every = 8
        routine.unit = .hours
        routine.steps = [
            RoutineStep(id: Self.stretchID, label: "Serum", offsetMinutes: 5, everyDays: 2, startsOn: "2026-11-25")
        ]
        let now = at("2026-11-25T05:00:00-05:00")
        let cycles = RoutineCycle.upcoming(routine, now: now, ahead: 72 * 3600, calendar: Self.newYork)
        #expect(cycles.count == 9)
        // The 25th and the 27th ring it at all three rings. The 26th at none.
        #expect(cycles.map(\.steps.count) == [1, 1, 1, 0, 0, 0, 1, 1, 1])
        let steps = desired(state([routine]), at: now).filter { $0.key.contains(":step:") }
        let step = ":step:0a1b2c3d-0000-4000-8000-000000000051"
        #expect(
            steps.map(\.key) == [
                Self.key + "2026-11-25T06:00" + step, Self.key + "2026-11-25T14:00" + step,
                Self.key + "2026-11-25T22:00" + step,
            ])
        #expect(steps.first?.fireAt == at("2026-11-25T06:05:00-05:00"))
    }

    @Test func aStepEveryFewDaysCountsByTheDateInEachRingsOwnStamp() {
        // Every 97 minutes from 21:00: two rings on the 25th, then the 26th from 00:14.
        var routine = water
        routine.steps = [
            RoutineStep(id: Self.stretchID, label: "Serum", offsetMinutes: 5, everyDays: 2, startsOn: "2026-11-25")
        ]
        let cycles = RoutineCycle.upcoming(routine, now: Self.start, ahead: 7 * 86_400, calendar: Self.newYork)
        #expect(
            cycles.prefix(4).map(\.stamp) == [
                "2026-11-25T21:00", "2026-11-25T22:37", "2026-11-26T00:14", "2026-11-26T01:51",
            ])
        #expect(cycles.prefix(4).map(\.steps.count) == [1, 1, 0, 0])
        // A ring of the 25th delayed into the 26th keeps its step: the day is the stamp's.
        routine.delays = ["2026-11-25T22:37": 180]
        let moved = RoutineCycle.make(routine, at: at("2026-11-25T22:37:00-05:00"), calendar: Self.newYork)
        #expect(moved.at == at("2026-11-26T01:37:00-05:00") && moved.steps.count == 1)
    }

    @Test func aStepEveryThreeDaysUnderAnAlarmEveryTwoWeeksRingsOnTheRingDaysThatMatch() {
        var routine = fortnight
        routine.steps = [
            RoutineStep(id: Self.stretchID, label: "Serum", offsetMinutes: 5, everyDays: 3, startsOn: "2026-11-25")
        ]
        // Wed 25 Nov is day 0, Fri 27 day 2, Mon 7 Dec day 12, Wed 9 day 14, Fri 11 day 16.
        let days = ["2026-11-25", "2026-11-27", "2026-12-07", "2026-12-09", "2026-12-11"]
        let rings = days.map { RoutineCycle.make(routine, at: at($0 + "T06:30:00-05:00"), calendar: Self.newYork) }
        #expect(rings.map(\.steps.count) == [1, 0, 1, 0, 0])
        #expect(
            RoutineDraft(
                hour: 6, minute: 30, days: [1, 3, 5], steps: routine.steps, repeatMode: .weekdays,
                every: 2, unit: .weeks, startsOn: "2026-11-25"
            ).problems.isEmpty)
    }
}
