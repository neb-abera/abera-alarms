import Foundation

@testable import AlarmCore

enum Fixtures {
    static let token = "aat_" + String(repeating: "A", count: 43)
    static let pairing = Pairing(server: Pairing.production, token: token)
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func alert(
        _ key: String,
        inMinutes minutes: Double,
        lead: Double = 10,
        type: String = AlertType.alarm,
        skipped: Bool = false,
        muted: Bool = false,
        acknowledged: Bool = false
    ) -> PlannedAlert {
        let start = now.addingTimeInterval((minutes + lead) * 60)
        return PlannedAlert(
            key: key, title: "Event \(key)", location: nil,
            startsAt: start, alertAt: now.addingTimeInterval(minutes * 60),
            skipped: skipped, muted: muted, type: type, acknowledged: acknowledged)
    }

    static func state(_ alerts: [PlannedAlert], mutedUntil: Date? = nil) -> AlertsState {
        AlertsState(configured: true, timeZone: "America/New_York", mutedUntil: mutedUntil, alerts: alerts)
    }

    struct Rig {
        let server: FakeAlertsServer
        let alarms: MemoryAlarms
        let documents: MemoryDocuments
        let credentials: MemoryCredentials
        let sync: AlarmSync
    }

    static func rig(_ alerts: [PlannedAlert], paired: Bool = true) -> Rig {
        let server = FakeAlertsServer(state: state(alerts), token: token)
        let alarms = MemoryAlarms()
        let documents = MemoryDocuments()
        let credentials = MemoryCredentials(paired ? pairing : nil)
        let sync = AlarmSync(
            credentials: credentials, transport: server, alarms: alarms, documents: documents,
            now: { Fixtures.now })
        return Rig(server: server, alarms: alarms, documents: documents, credentials: credentials, sync: sync)
    }
}
