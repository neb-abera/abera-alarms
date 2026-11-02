import Foundation

/// The rest timer: a countdown between sets that rings at 0:00. Restart
/// counts down the full rest again. The minus and plus buttons take time
/// off or add it to the running countdown, or change the rest's length
/// while none runs. It lives on the phone alone, and on the Lock Screen.
public struct Rest: Codable, Equatable, Sendable {
    /// Seconds each minus or plus press takes off or adds.
    public static let step = 15
    /// The shortest and longest rest, in seconds.
    public static let shortest = 15
    public static let longest = 3600

    /// The full rest, in seconds. Restart counts down this much.
    public var length: Int
    /// When the running countdown reaches 0:00. Nil while none runs.
    public var endsAt: Date?

    public init(length: Int = 90, endsAt: Date? = nil) {
        self.length = Self.clamped(length)
        self.endsAt = endsAt
    }

    /// True while the countdown has time left.
    public func running(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return endsAt > now
    }

    /// Seconds left on the countdown. The full length while none runs.
    public func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return TimeInterval(length) }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// Counts down the full rest from now.
    public mutating func restart(at now: Date) {
        endsAt = now.addingTimeInterval(TimeInterval(length))
    }

    /// Moves the running countdown by `seconds`. Taking it to 0:00 or past
    /// ends it without a ring. While none runs, changes the length.
    public mutating func adjust(by seconds: Int, at now: Date) {
        guard let endsAt, endsAt > now else {
            length = Self.clamped(length + seconds)
            self.endsAt = nil
            return
        }
        let moved = endsAt.addingTimeInterval(TimeInterval(seconds))
        self.endsAt = moved > now ? min(moved, now.addingTimeInterval(TimeInterval(Self.longest))) : nil
    }

    /// Ends the countdown. The length stays.
    public mutating func end() {
        endsAt = nil
    }

    /// The countdown as the Lock Screen and the app show it: "1:30".
    public func clock(at now: Date) -> String {
        Workout.clock(remaining(at: now).rounded(.up))
    }

    private static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, shortest), longest)
    }
}
