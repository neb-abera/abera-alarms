import Foundation
import Testing

@testable import AlarmCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sub-alarms chained after a routine's ring, checked off per cycle.
@Suite struct RoutineStepsTests {
    static let zone = TimeZone(identifier: "America/New_York")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    var calendar: Calendar { Self.calendar }

    let routineID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
    let medication = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!, label: "Take medication", offsetMinutes: 5)
    let beauty = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!, label: "Beauty care routine",
        offsetMinutes: 5)

    /// "Wake up" at 06:00 every day, medication at 06:05, beauty care at 06:10.
    var wake: Routine {
        Routine(
            id: routineID, label: "Wake up", hour: 6, minute: 0, days: [1, 2, 3, 4, 5, 6, 7],
            steps: [medication, beauty])
    }

    /// A local time on 2026-11-19, a Thursday.
    static func at(_ hour: Int, _ minute: Int, day: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    func at(_ hour: Int, _ minute: Int, day: Int = 19) -> Date { Self.at(hour, minute, day: day) }

    func state(_ routines: [Routine], completions: [RoutineCompletion] = [], rings: [RoutineRing] = [])
        -> AlertsState
    {
        AlertsState(
            configured: true, timeZone: Self.zone.identifier, routines: routines, routineRings: rings,
            stopAfterMinutes: 30, routineCompletions: completions)
    }

    func stepKey(_ step: RoutineStep, _ stamp: String) -> String {
        RoutineCycle.stepKey(routineID: routineID, stamp: stamp, stepID: step.id)
    }

    // MARK: Keys and times

    @Test func aStepRingIsNamedByItsRoutinesCycleAndItsOwnID() throws {
        let key = stepKey(medication, "2026-11-19T06:00")
        #expect(
            key
                == "routine:00000000-0000-4000-8000-0000000000a1:2026-11-19T06:00:step:00000000-0000-4000-8000-0000000000b1"
        )
        let parts = try #require(RoutineCycle.parseStepKey(key))
        #expect(parts.routineID == routineID)
        #expect(parts.stamp == "2026-11-19T06:00")
        #expect(parts.stepID == medication.id)
        #expect(RoutineCycle.parseStepKey("routine:00000000-0000-4000-8000-0000000000a1:2026-11-19T06:00") == nil)
        #expect(RoutineCycle.parseStepKey("standup|1") == nil)
    }

    @Test func eachStepRingsItsOffsetAfterTheOneBefore() throws {
        let cycle = try #require(RoutineCycle.around(wake, now: at(6, 1), calendar: calendar).current)
        #expect(cycle.stamp == "2026-11-19T06:00")
        #expect(cycle.at == at(6, 0))
        #expect(cycle.steps.map(\.at) == [at(6, 5), at(6, 10)])
        #expect(cycle.steps.map(\.key) == [stepKey(medication, cycle.stamp), stepKey(beauty, cycle.stamp)])
        #expect(RoutineStep.cumulativeMinutes([medication, beauty]) == [5, 10])
    }

    @Test func aCycleRunsFromOneRingToTheNext() {
        let early = RoutineCycle.around(wake, now: at(5, 50), calendar: calendar)
        #expect(early.current?.stamp == "2026-11-18T06:00")
        #expect(early.next?.stamp == "2026-11-19T06:00")
        let late = RoutineCycle.around(wake, now: at(21, 0), calendar: calendar)
        #expect(late.current?.stamp == "2026-11-19T06:00")
        #expect(late.next?.stamp == "2026-11-20T06:00")
    }

    @Test func aRingOnceRoutineHasOneCycleAfterItsSave() {
        var once = wake
        once.days = []
        once.updatedAt = at(5, 0)
        let before = RoutineCycle.around(once, now: at(5, 30), calendar: calendar)
        #expect(before.current == nil)
        #expect(before.next?.stamp == "2026-11-19T06:00")
        let after = RoutineCycle.around(once, now: at(6, 7), calendar: calendar)
        #expect(after.current?.stamp == "2026-11-19T06:00")
        #expect(after.next == nil)
    }

    @Test func aStepOverASkippedHourRingsItsMinutesAfterTheRoutine() throws {
        // 8 March 2026: New York's clocks go from 02:00 to 03:00.
        var night = wake
        night.hour = 1
        night.minute = 55
        night.steps = [RoutineStep(id: medication.id, label: "Pills", offsetMinutes: 10)]
        let ring = Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 55))!
        let cycle = try #require(RoutineCycle.around(night, now: ring, calendar: calendar).current)
        #expect(cycle.steps[0].at == ring.addingTimeInterval(600))
        #expect(Self.calendar.component(.hour, from: cycle.steps[0].at) == 3)
    }

    // MARK: Bounds

    @Test func stepsHaveTheSameBoundsAsAbearaTech() {
        #expect(RoutineStep.problems([medication, beauty]).isEmpty)
        let many = (0...RoutineStep.maxSteps).map { RoutineStep(label: "S\($0)", offsetMinutes: 1) }
        #expect(RoutineStep.problems(many).contains("At most 20 steps."))
        #expect(!RoutineStep.problems([RoutineStep(label: "Late", offsetMinutes: -1)]).isEmpty)
        #expect(
            RoutineStep.problems([
                RoutineStep(label: "A", offsetMinutes: 1000), RoutineStep(label: "B", offsetMinutes: 441),
            ]) == ["The steps must all ring within 24 hours of the alarm."])
        #expect(RoutineStep.problems([medication, medication]) == ["Two steps have the same id."])
        #expect(
            !RoutineStep.problems([RoutineStep(label: String(repeating: "x", count: 61), offsetMinutes: 1)]).isEmpty)
        var draft = wake.draft
        draft.steps = many
        #expect(draft.problems.contains("At most 20 steps."))
    }

    @Test func theDraftSendsItsStepsAndAnOlderDraftHasNone() throws {
        var draft = wake.draft
        draft.steps[0].label = "  "
        let sent = draft.body
        #expect(sent.steps.map(\.label) == ["Step", "Beauty care routine"])
        #expect(sent.steps.map(\.id) == [medication.id, beauty.id])
        let old = try JSONDecoder().decode(
            RoutineDraft.self,
            from: Data(#"{"label":"Wake","hour":6,"minute":0,"days":[1],"enabled":true,"snoozeMinutes":9}"#.utf8))
        #expect(old.steps.isEmpty)
        let routine = try JSONDecoder().decode(
            Routine.self,
            from: Data(#"{"id":"00000000-0000-4000-8000-0000000000a1","label":"Wake","hour":6,"minute":0}"#.utf8))
        #expect(routine.steps.isEmpty)
    }

    // MARK: The alarms the phone holds

    func stepAlarms(_ state: AlertsState, now: Date, here: Set<String> = []) -> [DesiredAlarm] {
        Reconciler.desired(from: state, now: now, acknowledgedHere: here, calendar: calendar)
            .filter { RoutineCycle.parseStepKey($0.key) != nil }
    }

    @Test func thePhoneHoldsEachStepThatIsStillAheadForTwoDays() {
        let alarms = stepAlarms(state([wake]), now: at(6, 7))
        #expect(
            alarms.map(\.fireAt) == [
                at(6, 10), at(6, 5, day: 20), at(6, 10, day: 20), at(6, 5, day: 21), at(6, 10, day: 21),
            ])
        #expect(alarms[0].title == "Beauty care routine")
        #expect(alarms[0].key == stepKey(beauty, "2026-11-19T06:00"))
        #expect(alarms[0].id == AlarmID.of(key: alarms[0].key))
        #expect(alarms[0].routine == nil)
        #expect(alarms[0].snoozeMinutes == 9)
        #expect(alarms[0].startsAt == at(6, 40))
    }

    @Test func aStepCheckedOffDoesNotRingThatCycleAndRingsTheNext() {
        let done = RoutineCompletion(
            routineId: routineID, stepId: medication.id, cycle: "2026-11-19T06:00", completedAt: at(5, 58))
        let alarms = stepAlarms(state([wake], completions: [done]), now: at(5, 59))
        #expect(!alarms.map(\.key).contains(stepKey(medication, "2026-11-19T06:00")))
        #expect(alarms.map(\.key).contains(stepKey(beauty, "2026-11-19T06:00")))
        #expect(alarms.map(\.key).contains(stepKey(medication, "2026-11-20T06:00")))
    }

    @Test func aStepStoppedAnywhereIsNotSetAgain() {
        let key = stepKey(beauty, "2026-11-19T06:00")
        let ring = RoutineRing(
            key: key, routineId: routineID, label: "Beauty care routine", alertAt: at(6, 10), startsAt: at(6, 40),
            acknowledged: true, stepId: beauty.id)
        #expect(!stepAlarms(state([wake], rings: [ring]), now: at(6, 7)).map(\.key).contains(key))
        #expect(!stepAlarms(state([wake]), now: at(6, 7), here: [key]).map(\.key).contains(key))
    }

    @Test func aRoutineSwitchedOffHoldsNoSteps() {
        var off = wake
        off.enabled = false
        #expect(stepAlarms(state([off]), now: at(6, 7)).isEmpty)
    }

    @Test func aRingingStepRingsUntilItIsCheckedOff() {
        let key = stepKey(medication, "2026-11-19T06:00")
        let id = AlarmID.of(key: key)
        let held = DesiredAlarm(
            id: id, key: key, title: "Take medication", location: nil, fireAt: at(6, 5), startsAt: at(6, 35))
        let ringing = Reconciler.stillRinging(state([wake]), ringing: [id], ledger: [id: held], acknowledgedHere: [])
        #expect(ringing == [held])
        let done = RoutineCompletion(
            routineId: routineID, stepId: medication.id, cycle: "2026-11-19T06:00", completedAt: at(6, 6))
        #expect(
            Reconciler.stillRinging(
                state([wake], completions: [done]), ringing: [id], ledger: [id: held], acknowledgedHere: []
            ).isEmpty)
        var off = wake
        off.enabled = false
        #expect(Reconciler.stillRinging(state([off]), ringing: [id], ledger: [id: held], acknowledgedHere: []).isEmpty)
    }

    // MARK: Check-offs waiting on the phone

    func draft(_ step: RoutineStep, _ stamp: String, note: String? = nil, photo: String? = nil) -> CompletionDraft {
        CompletionDraft(
            routineId: routineID, stepId: step.id, cycle: stamp, note: note, photoName: photo, completedAt: at(6, 6))
    }

    @Test func aSecondCheckOffKeepsTheFirstPhoto() {
        let changes = CompletionChange.coalesce([
            .complete(draft(medication, "c", photo: "p1")), .complete(draft(medication, "c", note: "2 pills")),
        ])
        #expect(changes == [.complete(draft(medication, "c", note: "2 pills", photo: "p1"))])
        let undone = CompletionChange.coalesce([
            .complete(draft(medication, "c")), .undo(routineId: routineID, stepId: medication.id, cycle: "c"),
        ])
        #expect(undone == [.undo(routineId: routineID, stepId: medication.id, cycle: "c")])
    }

    @Test func theNoteIsTrimmedAndBounded() {
        #expect(draft(medication, "c", note: "  ").sentNote == nil)
        #expect(draft(medication, "c", note: " Lisinopril ").sentNote == "Lisinopril")
        #expect(!draft(medication, "c", note: String(repeating: "x", count: 2001)).problems.isEmpty)
        #expect(CompletionDraft.isJPEG(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        #expect(!CompletionDraft.isJPEG(Data([0x89, 0x50, 0x4E, 0x47])))
    }

    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + Data(repeating: 7, count: 100)

    struct StepRig {
        let server: FakeAlertsServer
        let alarms: MemoryAlarms
        let documents: MemoryDocuments
        let sync: AlarmSync
        let clock: Fixtures.TestClock
    }

    func rig(_ routines: [Routine], now: Date) -> StepRig {
        let clock = Fixtures.TestClock(now)
        let server = FakeAlertsServer(state: state(routines), token: Fixtures.token, now: { clock.now })
        let alarms = MemoryAlarms()
        let documents = MemoryDocuments()
        let sync = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: server, alarms: alarms,
            documents: documents, now: { clock.now }, calendar: calendar)
        return StepRig(server: server, alarms: alarms, documents: documents, sync: sync, clock: clock)
    }

    @Test func checkingOffOfflineCancelsTheAlarmAtOnceAndSendsThePhotoLater() async throws {
        let rig = rig([wake], now: at(5, 50))
        _ = await rig.sync.sync()
        let key = stepKey(medication, "2026-11-19T06:00")
        #expect(await rig.alarms.alarms[AlarmID.of(key: key)] != nil)

        await rig.server.setOffline(true)
        let offline = await rig.sync.completeStep(
            draft(medication, "2026-11-19T06:00", note: "Lisinopril 10 mg"), photo: Self.jpeg)
        #expect(offline.error == .offline)
        #expect(await rig.sync.completionChanges().count == 1)
        #expect(await rig.alarms.alarms[AlarmID.of(key: key)] == nil)
        #expect(offline.state?.routineCompletions.map(\.stepKey) == [key])
        #expect(await rig.sync.lastState()?.routineCompletions.map(\.stepKey) == [key])
        // The next cycle still rings.
        #expect(await rig.alarms.alarms[AlarmID.of(key: stepKey(medication, "2026-11-20T06:00"))] != nil)

        await rig.server.setOffline(false)
        let online = await rig.sync.sync()
        #expect(online.error == nil)
        #expect(online.waitingCompletions == 0)
        let stored = try #require(await rig.server.completions.first)
        #expect(stored.note == "Lisinopril 10 mg")
        #expect(stored.photo == Self.jpeg)
        #expect(stored.cycle == "2026-11-19T06:00")
        #expect(await rig.alarms.alarms[AlarmID.of(key: key)] == nil)
        // The photo waited as a document, and is gone once sent.
        #expect(await rig.documents.files.keys.filter { $0.hasPrefix(AlarmSync.photoPrefix) }.isEmpty)
    }

    @Test func undoingACheckOffSetsTheStepAgain() async throws {
        let rig = rig([wake], now: at(5, 50))
        _ = await rig.sync.completeStep(draft(medication, "2026-11-19T06:00"), photo: nil)
        let key = stepKey(medication, "2026-11-19T06:00")
        #expect(await rig.alarms.alarms[AlarmID.of(key: key)] == nil)
        #expect(await rig.server.completions.count == 1)
        let report = await rig.sync.undoStep(routineId: routineID, stepId: medication.id, cycle: "2026-11-19T06:00")
        #expect(report.error == nil)
        #expect(await rig.server.completions.isEmpty)
        #expect(await rig.alarms.alarms[AlarmID.of(key: key)]?.fireAt == at(6, 5))
    }

    @Test func aCheckOffKeepsThePhotoUntilOneReplacesOrRemovesIt() async throws {
        let rig = rig([wake], now: at(6, 6))
        _ = await rig.sync.completeStep(draft(medication, "2026-11-19T06:00"), photo: Self.jpeg)
        _ = await rig.sync.completeStep(draft(medication, "2026-11-19T06:00", note: "Late"), photo: nil)
        #expect(await rig.server.completions.first?.photo == Self.jpeg)
        #expect(await rig.server.completions.first?.note == "Late")
        var remove = draft(medication, "2026-11-19T06:00")
        remove.removePhoto = true
        _ = await rig.sync.completeStep(remove, photo: Self.jpeg)
        #expect(await rig.server.completions.first?.photo == nil)
    }

    @Test func aCheckOffOfAStepThatIsGoneIsDropped() async throws {
        let rig = rig([wake], now: at(6, 6))
        let gone = RoutineStep(label: "Gone", offsetMinutes: 1)
        let report = await rig.sync.completeStep(draft(gone, "2026-11-19T06:00"), photo: Self.jpeg)
        #expect(report.error == nil)
        #expect(report.waitingCompletions == 0)
        #expect(await rig.documents.files.keys.filter { $0.hasPrefix(AlarmSync.photoPrefix) }.isEmpty)
    }

    @Test func aRoutineMadeOfflineTakesItsCheckOffsAlong() async throws {
        let rig = rig([], now: at(5, 0))
        await rig.server.setOffline(true)
        let local = UUID()
        var draftRoutine = wake.draft
        draftRoutine.label = "Made offline"
        _ = await rig.sync.changeRoutine(.create(local: local, draft: draftRoutine))
        var check = draft(medication, "2026-11-19T06:00")
        check.routineId = local
        _ = await rig.sync.completeStep(check, photo: nil)
        await rig.server.setOffline(false)
        let report = await rig.sync.sync()
        #expect(report.error == nil)
        let made = try #require(await rig.server.state.routines.first)
        #expect(await rig.server.completions.map(\.routineId) == [made.id])
    }

    @Test func unpairingDropsWaitingCheckOffsAndTheirPhotos() async {
        let rig = rig([wake], now: at(5, 50))
        await rig.server.setOffline(true)
        _ = await rig.sync.completeStep(draft(medication, "2026-11-19T06:00"), photo: Self.jpeg)
        #expect(await rig.documents.files.keys.contains { $0.hasPrefix(AlarmSync.photoPrefix) })
        await rig.sync.unpair()
        #expect(await rig.sync.completionChanges().isEmpty)
        #expect(await rig.documents.files.keys.filter { $0.hasPrefix(AlarmSync.photoPrefix) }.isEmpty)
    }

    @Test func aRingOnceRoutineWithStepsStaysUntilItsStepsAreDone() async throws {
        var once = wake
        once.days = []
        once.updatedAt = at(5, 0)
        let rig = rig([once], now: at(5, 50))
        _ = await rig.sync.sync()
        // It rings at 06:00 and the system lets it go.
        await rig.alarms.ring(routineID)
        rig.clock.advance(minutes: 11)  // 06:01
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.map(\.id) == [routineID])
        #expect(await rig.alarms.alarms[AlarmID.of(key: stepKey(beauty, "2026-11-19T06:00"))] != nil)
        // Both steps checked off: the routine goes.
        _ = await rig.sync.completeStep(draft(medication, "2026-11-19T06:00"), photo: nil)
        _ = await rig.sync.completeStep(draft(beauty, "2026-11-19T06:00"), photo: nil)
        #expect(await rig.server.state.routines.isEmpty)
    }

    @Test func aRingOnceRoutineWithStepsGoesOnceItsLastStepRangOut() async throws {
        var once = wake
        once.days = []
        once.updatedAt = at(5, 0)
        let rig = rig([once], now: at(5, 50))
        _ = await rig.sync.sync()
        await rig.alarms.ring(routineID)
        rig.clock.advance(minutes: 11)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.count == 1)
        rig.clock.advance(minutes: 40)  // 06:41, past 06:10 plus the 30 minute window
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.isEmpty)
    }

    // MARK: Requests

    @Test func theCheckOffIsAPutWithTheNoteAndTheJPEGInBase64() throws {
        let client = AlertsClient(pairing: Fixtures.pairing, transport: FakeAlertsServer(state: state([]), token: ""))
        #expect(
            AlertsClient.completionPath(routineId: routineID, stepId: medication.id, cycle: "2026-11-19T06:00")
                == "routines/00000000-0000-4000-8000-0000000000a1/steps/00000000-0000-4000-8000-0000000000b1/cycles/2026-11-19T06:00/completion"
        )
        _ = client
        let body = CompletionBody(note: "x", photo: Self.jpeg.base64EncodedString(), completedAt: at(6, 6))
        let json = try #require(
            try JSONSerialization.jsonObject(with: ServerDates.encoder().encode(body)) as? [String: Any])
        #expect(json["note"] as? String == "x")
        #expect((json["photo"] as? String).flatMap { Data(base64Encoded: $0) } == Self.jpeg)
        #expect(json["completedAt"] is String)
        let keep = try #require(
            try JSONSerialization.jsonObject(
                with: ServerDates.encoder().encode(CompletionBody(note: nil, photo: nil, completedAt: at(6, 6))))
                as? [String: Any])
        #expect(keep["photo"] is NSNull)
    }

    @Test func aRoutineEditWithoutStepsKeepsThemOnAbearaTech() async throws {
        let server = FakeAlertsServer(state: state([wake]), token: Fixtures.token)
        var request = URLRequest(url: Pairing.production.appending(path: "api/alerts/routines/\(routineID)"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(Fixtures.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(
            #"{"label":"Wake","hour":7,"minute":0,"days":[1],"enabled":true,"snoozeMinutes":9}"#.utf8)
        _ = try await server.send(request)
        #expect(await server.state.routines.first?.steps == [medication, beauty])
        #expect(await server.state.routines.first?.hour == 7)
    }

    // MARK: Two weeks of history

    @Test func historyListsEachCycleWithItsStepsDoneOrMissed() async throws {
        let rig = rig([wake], now: at(6, 6))
        _ = await rig.sync.completeStep(draft(medication, "2026-11-19T06:00", note: "10 mg"), photo: Self.jpeg)
        let history = try await rig.sync.history().get()
        #expect(history.days == 14)
        #expect(history.cycles.count == 14)
        let today = try #require(history.cycles.first)
        #expect(today.cycle == "2026-11-19T06:00")
        #expect(today.doneText == "1 of 2 done")
        let done = try #require(today.steps.first?.completion)
        #expect(done.note == "10 mg")
        #expect(done.hasPhoto)
        #expect(try await rig.sync.photo(completionId: done.id).get() == Self.jpeg)
        #expect(history.cycles[1].doneText == "0 of 2 done")
        let tally = history.tally
        #expect(tally.map(\.label) == ["Beauty care routine", "Take medication"])
        #expect(tally.map(\.done) == [0, 1])
        #expect(tally.map(\.of) == [14, 14])
    }

    @Test func historyAndPhotosNeedAPairing() async {
        let server = FakeAlertsServer(state: state([]), token: Fixtures.token)
        let sync = AlarmSync(
            credentials: MemoryCredentials(nil), transport: server, alarms: MemoryAlarms(),
            documents: MemoryDocuments())
        #expect(await sync.history() == .failure(.unpaired))
        #expect(await sync.photo(completionId: UUID()) == .failure(.unpaired))
        let missing = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: server, alarms: MemoryAlarms(),
            documents: MemoryDocuments())
        #expect(await missing.photo(completionId: UUID()) == .failure(.notFound))
    }
}
