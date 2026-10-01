import Foundation

/// What `GET /api/alerts/status` on abera.tech answers: the page's whole
/// state. Only the fields the phone uses are decoded. A field the server
/// adds later is ignored, and one it has not shipped yet has a default.
public struct AlertsState: Codable, Equatable, Sendable {
    /// False when the server is missing a secret. Nothing else is sent then.
    public var configured: Bool
    /// The zone the alert text is written in: the calendar's own.
    public var timeZone: String?
    public var mutedUntil: Date?
    public var lastFetchAt: Date?
    public var lastFetchError: String?
    public var lastSuccessAt: Date?
    /// Why the last type change or new event did not reach Google Calendar.
    /// Null when it did, or when nothing was written.
    public var calendarWrite: String?
    public var alerts: [PlannedAlert]
    /// The Clock-style alarms, on or off.
    public var routines: [Routine]
    /// Dates counted down to, sorted by target then label. An older server
    /// sends none.
    public var countdowns: [Countdown]
    /// The sound and snooze every alarm on the phone uses.
    public var phone: PhoneSettings

    public init(
        configured: Bool = true,
        timeZone: String? = nil,
        mutedUntil: Date? = nil,
        lastFetchAt: Date? = nil,
        lastFetchError: String? = nil,
        lastSuccessAt: Date? = nil,
        calendarWrite: String? = nil,
        alerts: [PlannedAlert] = [],
        routines: [Routine] = [],
        countdowns: [Countdown] = [],
        phone: PhoneSettings = PhoneSettings()
    ) {
        self.configured = configured
        self.timeZone = timeZone
        self.mutedUntil = mutedUntil
        self.lastFetchAt = lastFetchAt
        self.lastFetchError = lastFetchError
        self.lastSuccessAt = lastSuccessAt
        self.calendarWrite = calendarWrite
        self.alerts = alerts
        self.routines = routines
        self.countdowns = countdowns
        self.phone = phone
    }

    enum CodingKeys: String, CodingKey {
        case configured, timeZone, mutedUntil, lastFetchAt, lastFetchError, lastSuccessAt, calendarWrite, alerts,
            routines, countdowns, phone, settings
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(configured, forKey: .configured)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(mutedUntil, forKey: .mutedUntil)
        try container.encodeIfPresent(lastFetchAt, forKey: .lastFetchAt)
        try container.encodeIfPresent(lastFetchError, forKey: .lastFetchError)
        try container.encodeIfPresent(lastSuccessAt, forKey: .lastSuccessAt)
        try container.encodeIfPresent(calendarWrite, forKey: .calendarWrite)
        try container.encode(alerts, forKey: .alerts)
        try container.encode(routines, forKey: .routines)
        try container.encode(countdowns, forKey: .countdowns)
        try container.encode(phone, forKey: .phone)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configured = try container.decode(Bool.self, forKey: .configured)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        mutedUntil = try container.decodeIfPresent(Date.self, forKey: .mutedUntil)
        lastFetchAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchAt)
        lastFetchError = try container.decodeIfPresent(String.self, forKey: .lastFetchError)
        lastSuccessAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        calendarWrite = try container.decodeIfPresent(String.self, forKey: .calendarWrite)
        alerts = try container.decodeIfPresent([PlannedAlert].self, forKey: .alerts) ?? []
        routines = try container.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        countdowns = try container.decodeIfPresent([Countdown].self, forKey: .countdowns) ?? []
        // The server sends these inside `settings`. The phone keeps them as
        // `phone` in its own copy of the state.
        if let saved = try container.decodeIfPresent(PhoneSettings.self, forKey: .phone) {
            phone = saved
        } else {
            phone = try container.decodeIfPresent(PhoneSettings.self, forKey: .settings) ?? PhoneSettings()
        }
    }
}

/// One occurrence of one event and when its alert goes off.
public struct PlannedAlert: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The event's UID and this occurrence's start. Stable across reads.
    public var key: String
    public var title: String
    public var location: String?
    public var startsAt: Date
    public var alertAt: Date
    public var skipped: Bool
    public var muted: Bool
    /// "alarm", "notification" or "none". A server from before the type
    /// existed sends every alert as an alarm, so a missing type is "alarm".
    public var type: String
    /// Where the type came from: "set" on the page or phone, "critical"
    /// from the calendar, "default" from the settings.
    public var typeFrom: String?
    /// Part of a repeating series: an edit or a delete asks which.
    public var recurring: Bool
    /// Null when the feed gives no end.
    public var endsAt: Date?
    public var acknowledged: Bool
    public var acknowledgedAt: Date?
    /// "phone" or "browser".
    public var acknowledgedVia: String?

    public var id: String { key }

    /// Minutes from start to end, when the feed gives an end.
    public var durationMinutes: Int? {
        endsAt.map { Int(($0.timeIntervalSince(startsAt) / 60).rounded()) }
    }

    /// Minutes from the alert to the start.
    public var leadMinutes: Int { max(0, Int((startsAt.timeIntervalSince(alertAt) / 60).rounded())) }

    public var isAlarm: Bool { type == AlertType.alarm }

    public init(
        key: String,
        title: String,
        location: String? = nil,
        startsAt: Date,
        alertAt: Date,
        skipped: Bool = false,
        muted: Bool = false,
        type: String = AlertType.alarm,
        typeFrom: String? = nil,
        recurring: Bool = false,
        endsAt: Date? = nil,
        acknowledged: Bool = false,
        acknowledgedAt: Date? = nil,
        acknowledgedVia: String? = nil
    ) {
        self.key = key
        self.title = title
        self.location = location
        self.startsAt = startsAt
        self.alertAt = alertAt
        self.skipped = skipped
        self.muted = muted
        self.type = type
        self.typeFrom = typeFrom
        self.recurring = recurring
        self.endsAt = endsAt
        self.acknowledged = acknowledged
        self.acknowledgedAt = acknowledgedAt
        self.acknowledgedVia = acknowledgedVia
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        alertAt = try container.decode(Date.self, forKey: .alertAt)
        skipped = try container.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? AlertType.alarm
        typeFrom = try container.decodeIfPresent(String.self, forKey: .typeFrom)
        recurring = try container.decodeIfPresent(Bool.self, forKey: .recurring) ?? false
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        acknowledged = try container.decodeIfPresent(Bool.self, forKey: .acknowledged) ?? false
        acknowledgedAt = try container.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        acknowledgedVia = try container.decodeIfPresent(String.self, forKey: .acknowledgedVia)
    }
}

/// The sound every alarm on the phone plays, and how long Snooze waits on a
/// calendar alarm. Saved on abera.tech, set from the page or the phone.
public struct PhoneSettings: Codable, Equatable, Hashable, Sendable {
    public var sound: String
    public var snoozeMinutes: Int

    /// The sounds the app bundles, as the server names them, with their labels.
    public static let sounds: [(value: String, label: String)] = [
        ("default", "iPhone default"), ("pulse", "Pulse"), ("chime", "Chime"), ("rise", "Rise"), ("siren", "Siren"),
        ("beacon", "Beacon"),
    ]

    public init(sound: String = "default", snoozeMinutes: Int = 9) {
        self.sound = sound
        self.snoozeMinutes = snoozeMinutes
    }

    enum CodingKeys: String, CodingKey {
        case sound, snoozeMinutes, phoneSound, phoneSnoozeMinutes
    }

    /// Reads the phone's own copy ({sound, snoozeMinutes}) or the server's
    /// settings object ({phoneSound, phoneSnoozeMinutes, ...}). A sound this
    /// build does not bundle plays the iPhone default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sound =
            try container.decodeIfPresent(String.self, forKey: .sound)
            ?? container.decodeIfPresent(String.self, forKey: .phoneSound) ?? "default"
        let snooze =
            try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .phoneSnoozeMinutes) ?? 9
        self.sound = Self.sounds.contains { $0.value == sound } ? sound : "default"
        self.snoozeMinutes = min(30, max(1, snooze))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sound, forKey: .sound)
        try container.encode(snoozeMinutes, forKey: .snoozeMinutes)
    }

    /// The body PUT /api/alerts/phone-settings takes.
    var body: [String: AnyCodableValue] { ["sound": .string(sound), "snoozeMinutes": .int(snoozeMinutes)] }
}

/// A string or an integer in a JSON body.
enum AnyCodableValue: Encodable, Sendable {
    case string(String)
    case int(Int)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}

public enum AlertType {
    public static let alarm = "alarm"
    public static let notification = "notification"
    public static let none = "none"
    /// Sent to drop a choice, so the event follows #critical and the default again.
    public static let `default` = "default"
}

/// The server's dates: ISO 8601 with an offset, with or without fractional
/// seconds. .NET writes up to seven digits of fraction and `+00:00`.
public enum ServerDates {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Not an ISO 8601 date with an offset.")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(withFraction))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    public static func parse(_ text: String) -> Date? {
        // A date is short. Past this it is not one, and the parser is not
        // asked to find out.
        guard text.utf8.count <= 40 else { return nil }
        guard let dot = text.firstIndex(of: ".") else { return try? withoutFraction.parse(text) }

        // Milliseconds are all a phone alarm needs, and the parser's handling
        // of seven digits differs between Foundation builds. Keep three.
        let digits = text[text.index(after: dot)...].prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = text[digits.endIndex...]
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return try? withFraction.parse(text[..<dot] + "." + millis + rest)
    }
}
