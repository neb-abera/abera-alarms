import Foundation

/// A date to count down to, such as the day home from a deployment. Kept on
/// abera.tech, so the page and the phone show the same one.
public struct Countdown: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var targetAt: Date
    /// The IANA zone the target was set in. The target is written in it.
    public var timeZone: String
    public var updatedAt: Date?

    public init(id: UUID, label: String, targetAt: Date, timeZone: String, updatedAt: Date? = nil) {
        self.id = id
        self.label = label
        self.targetAt = targetAt
        self.timeZone = timeZone
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? CountdownDraft.defaultLabel
        targetAt = try container.decode(Date.self, forKey: .targetAt)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone) ?? "UTC"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// The draft that recreates this countdown, for an edit.
    public var draft: CountdownDraft { CountdownDraft(label: label, targetAt: targetAt, timeZone: timeZone) }

    /// The zone, or UTC when this phone does not know it.
    public var zone: TimeZone { TimeZone(identifier: zoneName)! }

    /// The zone's name, or "UTC" when this phone does not know it.
    public var zoneName: String { TimeZone(identifier: timeZone) == nil ? "UTC" : timeZone }

    /// "Fri 2026-11-13 17:00 Asia/Amman": the target in its own zone, named.
    public var targetText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = CivilDate(targetAt, in: zone)
        let time = String(
            format: "%02d:%02d", calendar.component(.hour, from: targetAt), calendar.component(.minute, from: targetAt))
        return "\(day.weekdayName) \(day.iso) \(time) \(zoneName)"
    }

    public func remaining(at now: Date) -> Remaining { Remaining(from: now, to: targetAt) }
}

/// The time from now to a target, or since it, in days and h:m:s.
public struct Remaining: Equatable, Sendable {
    /// True from the target's second on.
    public var passed: Bool
    public var days: Int
    public var hours: Int
    public var minutes: Int
    public var seconds: Int

    public init(from now: Date, to target: Date) {
        let interval = target.timeIntervalSince(now)
        passed = interval <= 0
        // Whole seconds. A target 59.9 s away shows 00:00:59 until it is 59 s away.
        let total = Int(min(abs(interval), 1e15).rounded(.down))
        days = total / 86_400
        hours = total % 86_400 / 3600
        minutes = total % 3600 / 60
        seconds = total % 60
    }

    /// "41 days 05:12:33".
    public var clock: String {
        "\(days) \(days == 1 ? "day" : "days") " + String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// The clock, or "Passed 2 days 03:04:05 ago" once the target has gone.
    public var text: String { passed ? "Passed \(clock) ago" : clock }
}

/// What the phone sends to add or change a countdown.
public struct CountdownDraft: Codable, Equatable, Sendable {
    public static let defaultLabel = "Countdown"
    public static let maxCountdowns = 50
    /// The server's bounds: 1900-01-01 up to, not including, 2200-01-01.
    static let earliest = Date(timeIntervalSince1970: -2_208_988_800)
    static let latest = Date(timeIntervalSince1970: 7_258_118_400)

    public var label: String
    public var targetAt: Date
    public var timeZone: String

    public init(label: String = "", targetAt: Date, timeZone: String) {
        self.label = label
        self.targetAt = targetAt
        self.timeZone = timeZone
    }

    /// The label as sent: trimmed, and "Countdown" when empty.
    public var sentLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel : trimmed
    }

    /// The same bounds the server checks. Empty when the draft can be sent.
    public var problems: [String] {
        var problems: [String] = []
        if sentLabel.count > 60 { problems.append("The label is longer than 60 characters.") }
        if sentLabel.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            problems.append("The label cannot hold control characters.")
        }
        if !(Self.earliest..<Self.latest).contains(targetAt) {
            problems.append("The date must be between 1900 and 2199.")
        }
        if TimeZone(identifier: timeZone) == nil { problems.append("Choose a time zone the tz database knows.") }
        return problems
    }

    /// The same date and time on the clock in another zone: 17:00 in Amman
    /// becomes 17:00 in New York when the editor's zone changes. An unknown
    /// zone leaves the instant as it is.
    public static func sameWallClock(_ date: Date, from old: String, to new: String) -> Date {
        guard let from = TimeZone(identifier: old), let to = TimeZone(identifier: new) else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = from
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        calendar.timeZone = to
        return calendar.date(from: parts) ?? date
    }

    /// The body the server expects: the label trimmed.
    var body: CountdownDraft {
        var body = self
        body.label = sentLabel
        return body
    }
}
