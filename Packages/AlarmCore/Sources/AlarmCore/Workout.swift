import Foundation

/// The workout timer: a clock that counts up from the start of each set,
/// and the sets already done. Next set records the set's time and starts
/// the next at 0:00. Every `interval` seconds on the clock, the phone says
/// the time. It lives on the phone alone.
public struct Workout: Codable, Equatable, Sendable {
    /// The choices for the spoken time, in seconds. 0 says nothing.
    public static let intervals = [0, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300]

    /// Seconds on the clock between spoken times. 0 says nothing.
    public var interval: Int
    /// When the running set's clock read 0:00. Nil while paused.
    public var startedAt: Date?
    /// The clock while paused.
    public var held: TimeInterval
    /// The time of each set already done, first to last.
    public var sets: [TimeInterval]

    public init(interval: Int = 30, startedAt: Date? = nil, held: TimeInterval = 0, sets: [TimeInterval] = []) {
        self.interval = interval
        self.startedAt = startedAt
        self.held = held
        self.sets = sets
    }

    public var running: Bool { startedAt != nil }

    /// The set the clock is timing, from 1.
    public var set: Int { sets.count + 1 }

    /// True once the clock has started: Next set has a set to record.
    public var started: Bool { running || held > 0 }

    /// The running set's time.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return held }
        return max(0, now.timeIntervalSince(startedAt))
    }

    /// Every set done plus the running one.
    public func total(at now: Date) -> TimeInterval {
        sets.reduce(0, +) + elapsed(at: now)
    }

    public mutating func start(at now: Date) {
        guard startedAt == nil else { return }
        startedAt = now.addingTimeInterval(-held)
        held = 0
    }

    public mutating func pause(at now: Date) {
        guard startedAt != nil else { return }
        held = elapsed(at: now)
        startedAt = nil
    }

    /// Records the running set and starts the next at 0:00, running.
    public mutating func nextSet(at now: Date) {
        guard started else { return }
        sets.append(elapsed(at: now))
        held = 0
        startedAt = now
    }

    /// Back to set 1 at 0:00, stopped. The interval stays.
    public mutating func resetSession() {
        sets = []
        held = 0
        startedAt = nil
    }

    /// The next time to say, strictly after `now`: the next whole multiple
    /// of the interval on the clock, and when the clock reaches it. Nil when
    /// paused or silent. A mark the app slept through is not said late.
    public func nextAnnouncement(after now: Date) -> (at: Date, seconds: Int)? {
        guard interval > 0, let startedAt else { return nil }
        // Whole milliseconds, so waking at a mark does not say it twice.
        let elapsed = (now.timeIntervalSince(startedAt) * 1000).rounded() / 1000
        let count = max(0, Int((elapsed / Double(interval)).rounded(.down))) + 1
        let seconds = count * interval
        return (startedAt.addingTimeInterval(TimeInterval(seconds)), seconds)
    }

    /// "0:42", "12:05" or "1:02:03".
    public static func clock(_ elapsed: TimeInterval) -> String {
        let whole = Int(max(0, elapsed).rounded(.down))
        let hours = whole / 3600
        let minutes = whole / 60 % 60
        let seconds = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// What the phone says at a mark: "30 seconds", "1 minute",
    /// "1 minute 30", "1 hour 2 minutes".
    public static func spoken(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let rest = seconds % 60
        if hours == 0 && minutes == 0 { return plural(rest, "second") }
        var parts: [String] = []
        if hours > 0 { parts.append(plural(hours, "hour")) }
        if minutes > 0 { parts.append(plural(minutes, "minute")) }
        if rest > 0 { parts.append(String(rest)) }
        return parts.joined(separator: " ")
    }

    /// The interval as the picker shows it: "Off", "30 s", "1 min", "1 min 30 s".
    public static func intervalText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Off" }
        let minutes = seconds / 60
        let rest = seconds % 60
        switch (minutes, rest) {
        case (0, _): return "\(rest) s"
        case (_, 0): return "\(minutes) min"
        default: return "\(minutes) min \(rest) s"
        }
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
