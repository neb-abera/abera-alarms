import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// One alarm the phone should hold.
public struct DesiredAlarm: Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var key: String
    public var title: String
    public var location: String?
    public var fireAt: Date
    public var startsAt: Date

    public init(id: UUID, key: String, title: String, location: String?, fireAt: Date, startsAt: Date) {
        self.id = id
        self.key = key
        self.title = title
        self.location = location
        self.fireAt = fireAt
        self.startsAt = startsAt
    }
}

/// What to change on the phone to match the server.
public struct AlarmChanges: Equatable, Sendable {
    public var cancel: [UUID]
    public var schedule: [DesiredAlarm]

    public var isEmpty: Bool { cancel.isEmpty && schedule.isEmpty }
}

/// The alarm id for an occurrence key. The same key gives the same id on
/// every sync and every install, so a sync can never schedule the same
/// occurrence twice under two ids.
public enum AlarmID {
    public static func of(key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        // RFC 9562 version 8 (custom) and the RFC variant.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

/// Pure: the server's state and the phone's in, the changes out.
public enum Reconciler {
    /// The alarms the phone should hold at `now`. An alert rings on the phone
    /// when its type is alarm, it is not skipped, muted or acknowledged
    /// anywhere, nobody acknowledged it on this phone while offline, and its
    /// time is still ahead.
    public static func desired(from state: AlertsState, now: Date, acknowledgedHere: Set<String>) -> [DesiredAlarm] {
        guard state.configured else { return [] }
        var seen = Set<UUID>()
        return state.alerts
            .filter { alert in
                alert.isAlarm && !alert.skipped && !alert.muted && !alert.acknowledged
                    && !acknowledgedHere.contains(alert.key)
                    && alert.alertAt > now && alert.startsAt > now
                    && !mutedAt(alert.alertAt, until: state.mutedUntil)
            }
            .sorted { ($0.alertAt, $0.key) < ($1.alertAt, $1.key) }
            .compactMap { alert in
                let id = AlarmID.of(key: alert.key)
                guard seen.insert(id).inserted else { return nil }
                return DesiredAlarm(
                    id: id, key: alert.key, title: alert.title, location: alert.location,
                    fireAt: alert.alertAt, startsAt: alert.startsAt)
            }
    }

    /// What to cancel and schedule so the phone holds exactly `desired`.
    ///
    /// `ledger` is what this app scheduled and still believes is there.
    /// `system` is the ids the alarm system reports. An alarm in the ledger
    /// that the system no longer has already rang or was removed, and is
    /// scheduled again only if it is still wanted and still ahead. An alarm
    /// the system has that is not wanted is cancelled, whoever made it.
    public static func changes(desired: [DesiredAlarm], ledger: [UUID: DesiredAlarm], system: Set<UUID>) -> AlarmChanges
    {
        let wanted = Dictionary(desired.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cancel = Set(system.subtracting(wanted.keys))
        var schedule: [DesiredAlarm] = []

        for alarm in desired {
            let held = system.contains(alarm.id)
            if held, ledger[alarm.id] == alarm { continue }
            if held { cancel.insert(alarm.id) }
            schedule.append(alarm)
        }
        return AlarmChanges(cancel: cancel.sorted { $0.uuidString < $1.uuidString }, schedule: schedule)
    }

    private static func mutedAt(_ time: Date, until: Date?) -> Bool {
        guard let until else { return false }
        return time < until
    }
}
