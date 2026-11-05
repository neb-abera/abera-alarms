import Foundation

/// A timer's length, typed as a number and a unit: 90 seconds, 25 minutes, 2 hours.
public struct TimerLength: Equatable, Sendable {
    public enum Unit: String, CaseIterable, Sendable {
        case seconds, minutes, hours

        public var seconds: Int {
            switch self {
            case .seconds: 1
            case .minutes: 60
            case .hours: 3600
            }
        }

        /// "minute" or "minutes", for the amount shown.
        public func name(_ amount: Int) -> String {
            amount == 1 ? String(rawValue.dropLast()) : rawValue
        }
    }

    /// The longest timer: 7 days.
    public static let longest = 7 * 86_400
    public static let standard = TimerLength(10, .minutes)

    public var amount: Int
    public var unit: Unit

    public init(_ amount: Int, _ unit: Unit) {
        self.amount = amount
        self.unit = unit
    }

    public var seconds: Int {
        amount.multipliedReportingOverflow(by: unit.seconds).overflow ? .max : amount * unit.seconds
    }

    /// Empty when the timer can start.
    public var problems: [String] {
        if seconds < 1 { return ["Enter a length of at least 1 second."] }
        if seconds > Self.longest { return ["A timer runs at most 7 days."] }
        return []
    }

    /// "1:05:09" or "4:59": hours only when there are any.
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
