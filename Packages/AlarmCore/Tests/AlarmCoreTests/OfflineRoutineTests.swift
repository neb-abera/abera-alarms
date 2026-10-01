import Foundation
import Testing

@testable import AlarmCore

/// Routine alarms changed with no connection, as the Clock app allows.
@Suite struct OfflineRoutineTests {
    let a = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
    let b = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!

    func draft(_ hour: Int, enabled: Bool = true, label: String = "Wake") -> RoutineDraft {
        RoutineDraft(label: label, hour: hour, minute: 0, days: [1, 2, 3, 4, 5], enabled: enabled)
    }

    // MARK: Folding changes together

    @Test func anEditToAnUnsentRoutineFoldsIntoItsCreation() {
        let changes = RoutineChange.coalesce([.create(local: a, draft: draft(6)), .update(id: a, draft: draft(7))])
        #expect(changes == [.create(local: a, draft: draft(7))])
    }

    @Test func deletingAnUnsentRoutineSendsNothing() {
        #expect(RoutineChange.coalesce([.create(local: a, draft: draft(6)), .delete(id: a)]).isEmpty)
    }

    @Test func onlyTheLastEditOfARoutineIsKept() {
        let changes = RoutineChange.coalesce([
            .update(id: b, draft: draft(6)), .update(id: a, draft: draft(5)), .update(id: b, draft: draft(8)),
        ])
        #expect(changes == [.update(id: a, draft: draft(5)), .update(id: b, draft: draft(8))])
    }

    @Test func aDeleteReplacesTheEditsBeforeIt() {
        let changes = RoutineChange.coalesce([.update(id: b, draft: draft(6)), .delete(id: b)])
        #expect(changes == [.delete(id: b)])
    }

    @Test func overlayShowsTheStateAbearaTechWillHave() {
        var state = Fixtures.state([])
        state.routines = [Routine(id: b, label: "Gym", hour: 5, minute: 0, days: [2])]
        let shown = RoutineChange.overlay(
            state, [.create(local: a, draft: draft(4)), .update(id: b, draft: draft(9, enabled: false, label: "Gym"))])
        #expect(shown.routines.map(\.id) == [a, b])
        #expect(shown.routines[1].enabled == false)
        #expect(RoutineChange.overlay(state, [.delete(id: b)]).routines.isEmpty)
    }

    // MARK: Through the sync

    func held(_ rig: Fixtures.Rig) async -> [UUID: DesiredAlarm] { await rig.alarms.alarms }

    @Test func addingOfflineRingsAtOnceAndReachesAbearaTechLater() async throws {
        let rig = Fixtures.rig([])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)

        let offline = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        #expect(offline.error == .offline)
        #expect(offline.state?.routines.map(\.id) == [a])
        #expect(await held(rig)[a]?.title == "Wake")
        #expect(await rig.sync.lastState()?.routines.map(\.id) == [a])

        await rig.server.setOffline(false)
        let online = await rig.sync.sync()
        #expect(online.error == nil)
        let made = try #require(await rig.server.state.routines.first)
        #expect(made.id != a)
        #expect(online.state?.routines.map(\.id) == [made.id])
        #expect(Set(await held(rig).keys) == [made.id])
        #expect(await rig.sync.routineChanges().isEmpty)
    }

    @Test func aPhoneThatNeverSyncedStillSetsTheAlarm() async {
        let rig = Fixtures.rig([])
        await rig.server.setOffline(true)
        let report = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        #expect(report.state?.routines.map(\.id) == [a])
        #expect(await held(rig)[a] != nil)
        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.count == 1)
    }

    @Test func addThenEditOfflineSendsOneCreation() async {
        let rig = Fixtures.rig([])
        await rig.server.setOffline(true)
        _ = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        _ = await rig.sync.changeRoutine(.update(id: a, draft: draft(7)))
        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.map(\.hour) == [7])
        #expect(await rig.server.requests.filter { $0.contains("routines") } == ["POST /api/alerts/routines"])
    }

    @Test func addThenDeleteOfflineSendsNothing() async {
        let rig = Fixtures.rig([])
        await rig.server.setOffline(true)
        _ = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        _ = await rig.sync.changeRoutine(.delete(id: a))
        #expect(await held(rig).isEmpty)
        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.requests.filter { $0.contains("routines") }.isEmpty)
    }

    @Test func switchingOffOfflineSilencesItAtOnce() async {
        let rig = Fixtures.rig([])
        await rig.server.setRoutines([Routine(id: b, label: "Wake", hour: 6, minute: 0, days: [1])])
        _ = await rig.sync.sync()
        #expect(await held(rig)[b] != nil)

        await rig.server.setOffline(true)
        _ = await rig.sync.changeRoutine(.update(id: b, draft: draft(6, enabled: false)))
        #expect(await held(rig)[b] == nil)

        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.first?.enabled == false)
        #expect(await held(rig)[b] == nil)
    }

    @Test func deletingOfflineTakesItOffAtOnce() async {
        let rig = Fixtures.rig([])
        await rig.server.setRoutines([Routine(id: b, label: "Wake", hour: 6, minute: 0, days: [1])])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        let report = await rig.sync.changeRoutine(.delete(id: b))
        #expect(report.state?.routines.isEmpty == true)
        #expect(await held(rig).isEmpty)
        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.state.routines.isEmpty)
    }

    @Test func anOtherActionKeepsTheWaitingChangeOnScreen() async {
        let rig = Fixtures.rig([Fixtures.alert("x", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        _ = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        await rig.server.setOffline(false)
        // The queue is sent by sync. A skip on the way answers with the
        // server's state, and the waiting routine stays shown and set.
        let skipped = await rig.sync.perform { client throws(APIError) in try await client.skip(key: "x") }
        #expect(skipped.state?.routines.count == 1)
        #expect(await held(rig).values.contains { $0.isRoutine })
    }

    @Test func aChangeAbearaTechRefusesIsDroppedWithItsReason() async {
        let rig = Fixtures.rig([])
        let full = (0..<50).map { Routine(id: UUID(), label: "R\($0)", hour: $0 % 24, minute: 0, days: [1]) }
        await rig.server.setRoutines(full)
        let report = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        #expect(report.error == .refused("At most 50 routine alarms."))
        #expect(await rig.sync.routineChanges().isEmpty)
        #expect(report.state?.routines.count == 50)
    }

    @Test func unpairingDropsTheWaitingChanges() async {
        let rig = Fixtures.rig([])
        await rig.server.setOffline(true)
        _ = await rig.sync.changeRoutine(.create(local: a, draft: draft(6)))
        await rig.sync.unpair()
        #expect(await rig.sync.routineChanges().isEmpty)
    }
}
