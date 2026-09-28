import Foundation
import Testing

@testable import AlarmCore

@Suite struct ReconcilerTests {
    let now = Fixtures.now

    func keys(_ alarms: [DesiredAlarm]) -> [String] { alarms.map(\.key) }

    @Test func ringsOnlyWhatIsStillAnAlarm() {
        let state = Fixtures.state([
            Fixtures.alert("alarm", inMinutes: 30),
            Fixtures.alert("notification", inMinutes: 30, type: AlertType.notification),
            Fixtures.alert("none", inMinutes: 30, type: AlertType.none),
            Fixtures.alert("skipped", inMinutes: 30, skipped: true),
            Fixtures.alert("muted", inMinutes: 30, muted: true),
            Fixtures.alert("acknowledged", inMinutes: 30, acknowledged: true),
            Fixtures.alert("acknowledged-here", inMinutes: 30),
            Fixtures.alert("past", inMinutes: -1),
            Fixtures.alert("now", inMinutes: 0),
        ])
        let desired = Reconciler.desired(from: state, now: now, acknowledgedHere: ["acknowledged-here"])
        #expect(keys(desired) == ["alarm"])
    }

    @Test func honoursTheMuteEvenWhenTheListIsStale() {
        let state = Fixtures.state(
            [Fixtures.alert("inside", inMinutes: 30), Fixtures.alert("after", inMinutes: 90)],
            mutedUntil: now.addingTimeInterval(3600))
        #expect(keys(Reconciler.desired(from: state, now: now, acknowledgedHere: [])) == ["after"])
    }

    @Test func ringsNothingForAnUnconfiguredServer() {
        var state = Fixtures.state([Fixtures.alert("a", inMinutes: 30)])
        state.configured = false
        #expect(Reconciler.desired(from: state, now: now, acknowledgedHere: []).isEmpty)
    }

    @Test func ordersByTimeThenKeyAndDropsDuplicates() {
        let state = Fixtures.state([
            Fixtures.alert("b", inMinutes: 20), Fixtures.alert("a", inMinutes: 20),
            Fixtures.alert("c", inMinutes: 10), Fixtures.alert("a", inMinutes: 20),
        ])
        #expect(keys(Reconciler.desired(from: state, now: now, acknowledgedHere: [])) == ["c", "a", "b"])
    }

    @Test func alarmIDsAreStableAndDistinct() {
        let first = AlarmID.of(key: "uid|2026-09-21T15:00:00Z")
        #expect(first == AlarmID.of(key: "uid|2026-09-21T15:00:00Z"))
        #expect(first != AlarmID.of(key: "uid|2026-09-22T15:00:00Z"))
        let text = first.uuidString
        #expect(text[text.index(text.startIndex, offsetBy: 14)] == "8")
        #expect("89AB".contains(text[text.index(text.startIndex, offsetBy: 19)]))
    }

    func alarm(_ key: String, inMinutes minutes: Double) -> DesiredAlarm {
        let alert = Fixtures.alert(key, inMinutes: minutes)
        return DesiredAlarm(
            id: AlarmID.of(key: key), key: key, title: alert.title, location: nil,
            fireAt: alert.alertAt, startsAt: alert.startsAt)
    }

    @Test func schedulesWhatIsMissing() {
        let a = alarm("a", inMinutes: 10)
        let changes = Reconciler.changes(desired: [a], ledger: [:], system: [])
        #expect(changes == AlarmChanges(cancel: [], schedule: [a]))
    }

    @Test func leavesWhatAlreadyMatches() {
        let a = alarm("a", inMinutes: 10)
        #expect(Reconciler.changes(desired: [a], ledger: [a.id: a], system: [a.id]).isEmpty)
    }

    @Test func movesAnAlarmWhoseTimeChanged() {
        let before = alarm("a", inMinutes: 10)
        var after = before
        after.fireAt = before.fireAt.addingTimeInterval(300)
        let changes = Reconciler.changes(desired: [after], ledger: [before.id: before], system: [before.id])
        #expect(changes == AlarmChanges(cancel: [before.id], schedule: [after]))
    }

    @Test func retitlesAnAlarmWhoseEventWasRenamed() {
        let before = alarm("a", inMinutes: 10)
        var after = before
        after.title = "Renamed"
        let changes = Reconciler.changes(desired: [after], ledger: [before.id: before], system: [before.id])
        #expect(changes == AlarmChanges(cancel: [before.id], schedule: [after]))
    }

    @Test func cancelsWhatIsNoLongerWantedWhoeverMadeIt() {
        let stranger = UUID()
        let old = alarm("old", inMinutes: 10)
        let changes = Reconciler.changes(desired: [], ledger: [old.id: old], system: [old.id, stranger])
        #expect(Set(changes.cancel) == [old.id, stranger])
        #expect(changes.schedule.isEmpty)
    }

    @Test func schedulesAgainWhatTheSystemDropped() {
        let a = alarm("a", inMinutes: 10)
        let changes = Reconciler.changes(desired: [a], ledger: [a.id: a], system: [])
        #expect(changes == AlarmChanges(cancel: [], schedule: [a]))
    }

    /// For any server list and any phone, applying the changes leaves the
    /// phone holding exactly the wanted alarms, and a second pass changes
    /// nothing.
    @Test func applyingTheChangesConverges() {
        var generator = SeededGenerator(seed: 0x5EED)
        for _ in 0..<500 {
            let alerts = (0..<Int.random(in: 0...12, using: &generator)).map { index in
                Fixtures.alert(
                    "k\(Int.random(in: 0...8, using: &generator))",
                    inMinutes: Double(Int.random(in: -30...600, using: &generator)),
                    type: [AlertType.alarm, AlertType.notification, AlertType.none][index % 3],
                    skipped: Bool.random(using: &generator) && Bool.random(using: &generator),
                    muted: Bool.random(using: &generator) && Bool.random(using: &generator),
                    acknowledged: Bool.random(using: &generator) && Bool.random(using: &generator))
            }
            let state = Fixtures.state(alerts)
            let desired = Reconciler.desired(from: state, now: now, acknowledgedHere: [])

            var ledger: [UUID: DesiredAlarm] = [:]
            var system = Set<UUID>()
            for index in 0..<Int.random(in: 0...6, using: &generator) {
                let stale = alarm("k\(index)", inMinutes: Double(Int.random(in: 1...600, using: &generator)))
                if Bool.random(using: &generator) { ledger[stale.id] = stale }
                if Bool.random(using: &generator) { system.insert(stale.id) }
            }
            if Bool.random(using: &generator) { system.insert(UUID()) }

            let changes = Reconciler.changes(desired: desired, ledger: ledger, system: system)
            for id in changes.cancel {
                system.remove(id)
                ledger[id] = nil
            }
            for alarm in changes.schedule {
                system.insert(alarm.id)
                ledger[alarm.id] = alarm
            }

            #expect(system == Set(desired.map(\.id)))
            #expect(Reconciler.changes(desired: desired, ledger: ledger, system: system).isEmpty)
        }
    }
}
