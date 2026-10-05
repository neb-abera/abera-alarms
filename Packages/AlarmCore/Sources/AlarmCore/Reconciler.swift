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
    /// Set for a routine: the alarm repeats on its days, or rings once at
    /// the next hour:minute, in whatever zone the phone is in. Nil for a
    /// calendar alert, which rings once at fireAt.
    public var routine: RoutineSchedule?
    /// The bundled sound's name, or "default".
    public var sound: String
    /// Snooze minutes for a calendar alarm. A routine carries its own.
    public var snoozeMinutes: Int?
    /// How the app set the alarm up in the alarm system, such as what its
    /// Stop button does. An alarm held with an older setup is scheduled again.
    public var setup: Int

    /// 1: routine alarms had no Stop acknowledgement (build 16 and before).
    /// 2: Stop on a routine alarm acknowledges its ring on abera.tech.
    public static let currentSetup = 2

    public init(
        id: UUID, key: String, title: String, location: String?, fireAt: Date, startsAt: Date,
        routine: RoutineSchedule? = nil, sound: String = "default", snoozeMinutes: Int? = nil,
        setup: Int = DesiredAlarm.currentSetup
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.location = location
        self.fireAt = fireAt
        self.startsAt = startsAt
        self.routine = routine
        self.sound = sound
        self.snoozeMinutes = snoozeMinutes
        self.setup = setup
    }

    enum CodingKeys: String, CodingKey {
        case id, key, title, location, fireAt, startsAt, routine, sound, snoozeMinutes, setup
    }

    /// A ledger from an older build has no sound. It reads as "default".
    /// It has no setup either, and reads as setup 1.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        fireAt = try container.decode(Date.self, forKey: .fireAt)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        routine = try container.decodeIfPresent(RoutineSchedule.self, forKey: .routine)
        sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? "default"
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes)
        setup = try container.decodeIfPresent(Int.self, forKey: .setup) ?? 1
    }

    /// The same alarm to the alarm system. A routine's next fire time moves
    /// every day while its schedule stays the same, so it is compared by
    /// schedule and title.
    func sameAlarm(as other: DesiredAlarm) -> Bool {
        guard let routine else { return self == other }
        return routine == other.routine && title == other.title && key == other.key && sound == other.sound
            && setup == other.setup
    }

    public static let routinePrefix = "routine:"

    public var isRoutine: Bool { routine != nil }
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
    public static func desired(
        from state: AlertsState, now: Date, acknowledgedHere: Set<String>, calendar: Calendar = .current
    ) -> [DesiredAlarm] {
        guard state.configured else { return [] }
        let sound = state.phone.sound
        return
            (alerts(from: state, now: now, acknowledgedHere: acknowledgedHere)
            .map { alarm in
                var alarm = alarm
                alarm.snoozeMinutes = state.phone.snoozeMinutes
                return alarm
            }
            + routines(from: state, now: now, calendar: calendar))
            .map { alarm in
                var alarm = alarm
                alarm.sound = sound
                return alarm
            }
    }

    /// Every switched-on routine. The abera.tech mute does not touch them,
    /// as the Clock app's alarms are not touched by a notification mute.
    static func routines(from state: AlertsState, now: Date, calendar: Calendar) -> [DesiredAlarm] {
        state.routines
            .filter(\.enabled)
            .compactMap { routine in
                guard let next = routine.nextFire(after: now, calendar: calendar) else { return nil }
                return DesiredAlarm(
                    id: routine.id, key: DesiredAlarm.routinePrefix + routine.id.uuidString.lowercased(),
                    title: routine.label, location: nil, fireAt: next, startsAt: next, routine: routine.schedule)
            }
            .sorted { ($0.fireAt, $0.key) < ($1.fireAt, $1.key) }
    }

    static func alerts(from state: AlertsState, now: Date, acknowledgedHere: Set<String>) -> [DesiredAlarm] {
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
            if held, let known = ledger[alarm.id], known.sameAlarm(as: alarm) { continue }
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
