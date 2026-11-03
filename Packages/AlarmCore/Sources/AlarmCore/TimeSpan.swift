import Foundation

/// A length typed as a number and a unit, such as an event's length or how
/// long before the start it rings. Stored and sent in minutes.
public struct TimeSpan: Equatable, Hashable, Sendable {
    public enum Unit: String, CaseIterable, Sendable {
        case minutes, hours, days

        public var minutes: Int {
            switch self {
            case .minutes: 1
            case .hours: 60
            case .days: 1440
            }
        }

        /// "minute" or "minutes", for the amount shown.
        public func name(_ amount: Int) -> String {
            let plural = rawValue
            return amount == 1 ? String(plural.dropLast()) : plural
        }
    }

    public var amount: Int
    public var unit: Unit

    public init(_ amount: Int, _ unit: Unit) {
        self.amount = amount
        self.unit = unit
    }

    /// The largest unit that holds the minutes whole: 90 is 90 minutes, 120 is 2 hours.
    public init(minutes: Int) {
        let unit = Unit.allCases.reversed().first { minutes != 0 && minutes % $0.minutes == 0 } ?? .minutes
        self.init(minutes / unit.minutes, unit)
    }

    public var minutes: Int {
        amount.multipliedReportingOverflow(by: unit.minutes).overflow ? .max : amount * unit.minutes
    }

    /// The amount as typed: digits only, so a paste of "30 min" keeps 30.
    /// An empty field is 0.
    public static func amount(typed text: String) -> Int {
        Int(text.filter(\.isWholeNumber).prefix(9)) ?? 0
    }
}

extension NewEvent {
    /// A new event's start: the next whole or half hour after now.
    public static func defaultStart(after now: Date = Date()) -> Date {
        let seconds = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: ((seconds / 1800).rounded(.down) + 1) * 1800)
    }

    /// A new event's length: 30 minutes.
    public static let defaultLength = TimeSpan(30, .minutes)
}
