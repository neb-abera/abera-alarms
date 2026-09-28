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
    public var alerts: [Alert]

    public init(
        configured: Bool = true,
        timeZone: String? = nil,
        mutedUntil: Date? = nil,
        lastFetchAt: Date? = nil,
        lastFetchError: String? = nil,
        lastSuccessAt: Date? = nil,
        alerts: [Alert] = []
    ) {
        self.configured = configured
        self.timeZone = timeZone
        self.mutedUntil = mutedUntil
        self.lastFetchAt = lastFetchAt
        self.lastFetchError = lastFetchError
        self.lastSuccessAt = lastSuccessAt
        self.alerts = alerts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configured = try container.decode(Bool.self, forKey: .configured)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        mutedUntil = try container.decodeIfPresent(Date.self, forKey: .mutedUntil)
        lastFetchAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchAt)
        lastFetchError = try container.decodeIfPresent(String.self, forKey: .lastFetchError)
        lastSuccessAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        alerts = try container.decodeIfPresent([Alert].self, forKey: .alerts) ?? []
    }
}

/// One occurrence of one event and when its alert goes off.
public struct Alert: Codable, Equatable, Hashable, Sendable, Identifiable {
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
    public var acknowledged: Bool
    public var acknowledgedAt: Date?
    /// "phone" or "browser".
    public var acknowledgedVia: String?

    public var id: String { key }

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
        acknowledged = try container.decodeIfPresent(Bool.self, forKey: .acknowledged) ?? false
        acknowledgedAt = try container.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        acknowledgedVia = try container.decodeIfPresent(String.self, forKey: .acknowledgedVia)
    }
}

public enum AlertType {
    public static let alarm = "alarm"
    public static let notification = "notification"
    public static let none = "none"
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
