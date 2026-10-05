import Foundation
import Testing

@testable import AlarmCore

/// An alarm the alarm system holds keeps the setup it was scheduled with,
/// whatever build is running now. Build 16 scheduled routine alarms with no
/// Stop acknowledgement. On 2026-10-05 a "wake up" routine scheduled by it
/// was stopped on a phone running build 17, abera.tech never heard, and
/// Pushover rang 10 minutes later.
@Suite struct SetupTests {
    let now = Fixtures.now

    func wake() -> DesiredAlarm {
        let schedule = RoutineSchedule(hour: 4, minute: 30, days: [1, 2, 3, 4, 5, 6, 7], snoozeMinutes: 9)
        let id = UUID(uuidString: "25882594-2763-431E-A6BA-BE4960D53000")!
        return DesiredAlarm(
            id: id, key: DesiredAlarm.routinePrefix + id.uuidString.lowercased(), title: "wake up", location: nil,
            fireAt: now.addingTimeInterval(3600), startsAt: now.addingTimeInterval(3600), routine: schedule)
    }

    /// The ledger entry as an older build wrote it: every field but the setup.
    func olderLedgerEntry(_ alarm: DesiredAlarm) throws -> DesiredAlarm {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(alarm)) as! [String: Any]
        json["setup"] = nil
        return try JSONDecoder().decode(DesiredAlarm.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func aRoutineAnOlderBuildScheduledIsScheduledAgain() throws {
        let alarm = wake()
        let old = try olderLedgerEntry(alarm)
        #expect(old.setup < DesiredAlarm.currentSetup)
        let changes = Reconciler.changes(desired: [alarm], ledger: [alarm.id: old], system: [alarm.id])
        #expect(changes == AlarmChanges(cancel: [alarm.id], schedule: [alarm]))
    }

    @Test func aCalendarAlarmAnOlderBuildScheduledIsScheduledAgain() throws {
        let alert = Fixtures.alert("standup", inMinutes: 30)
        let alarm = DesiredAlarm(
            id: AlarmID.of(key: alert.key), key: alert.key, title: alert.title, location: nil,
            fireAt: alert.alertAt, startsAt: alert.startsAt)
        let changes = Reconciler.changes(
            desired: [alarm], ledger: [alarm.id: try olderLedgerEntry(alarm)], system: [alarm.id])
        #expect(changes == AlarmChanges(cancel: [alarm.id], schedule: [alarm]))
    }

    @Test func anAlarmThisBuildScheduledStaysAfterARestart() throws {
        let alarm = wake()
        let stored = try JSONDecoder().decode(DesiredAlarm.self, from: JSONEncoder().encode(alarm))
        #expect(stored.setup == DesiredAlarm.currentSetup)
        #expect(Reconciler.changes(desired: [alarm], ledger: [alarm.id: stored], system: [alarm.id]).isEmpty)
    }
}
