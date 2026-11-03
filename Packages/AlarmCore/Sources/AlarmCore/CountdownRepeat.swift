import Foundation

/// How a countdown repeats: never, or every week, month or year at the same
/// time on its zone's clock. A date the period lacks (the 31st in a short
/// month, 29 February in a common year) is skipped, as abera.tech and
/// Google Calendar skip it.
public enum CountdownRepeat: String, Codable, CaseIterable, Sendable, Hashable {
    case none, yearly, monthly, weekly

    /// What the editor and the list call it.
    public var label: String {
        switch self {
        case .none: "Never"
        case .yearly: "Every year"
        case .monthly: "Every month"
        case .weekly: "Every week"
        }
    }

    /// The first date after `now` in the series that `start` is a date of.
    /// `start` itself when it has not passed or nothing repeats.
    public func next(after now: Date, from start: Date, in zone: TimeZone) -> Date {
        guard self != .none, start <= now else { return start }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.component(.day, from: start)
        let (component, size): (Calendar.Component, Double) =
            switch self {
            case .weekly: (.weekOfYear, 7 * 86_400)
            case .monthly: (.month, 31 * 86_400)
            default: (.year, 366 * 86_400)
            }
        let guess = max(Int(now.timeIntervalSince(start) / size), 1)
        for n in guess..<(guess + 400) {
            guard let at = calendar.date(byAdding: component, value: n, to: start) else { continue }
            // A month or year without the day is skipped. A week always has it.
            if self != .weekly, calendar.component(.day, from: at) != day { continue }
            if at > now { return at }
        }
        return start
    }
}
