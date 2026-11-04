import Foundation

/// The unit a countdown repeats in: never, or every N hours, days, weeks,
/// months or years. Days, weeks, months and years keep the time on its
/// zone's clock. Hours are elapsed time. A date a month or year lacks (the
/// 31st in a short month, 29 February in a common year) is skipped, as
/// abera.tech and Google Calendar skip it.
public enum CountdownRepeat: String, Codable, CaseIterable, Sendable, Hashable {
    case none, hourly, daily, weekly, monthly, yearly

    /// The most units between two dates, as abera.tech takes it.
    public static let maxEvery = 999

    /// The unit's name, singular for 1 and plural for more. "Never" for none.
    public func unit(_ every: Int) -> String {
        let one: String
        switch self {
        case .none: return "Never"
        case .hourly: one = "hour"
        case .daily: one = "day"
        case .weekly: one = "week"
        case .monthly: one = "month"
        case .yearly: one = "year"
        }
        return every == 1 ? one : "\(one)s"
    }

    /// "Every 2 weeks", "Every year". Nil when it does not repeat.
    public func describe(every: Int) -> String? {
        guard self != .none else { return nil }
        return every == 1 ? "Every \(unit(1))" : "Every \(every) \(unit(every))"
    }

    /// The first date after `now` in the series that `start` is a date of,
    /// every `every` units. `start` itself when it has not passed or
    /// nothing repeats.
    public func next(after now: Date, from start: Date, every: Int = 1, in zone: TimeZone) -> Date {
        guard self != .none, start <= now else { return start }
        let every = min(max(every, 1), Self.maxEvery)
        if self == .hourly {
            let step = Double(every) * 3600
            let steps = (now.timeIntervalSince(start) / step).rounded(.down) + 1
            return start.addingTimeInterval(steps * step)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.component(.day, from: start)
        let (component, days): (Calendar.Component, Double) =
            switch self {
            case .daily: (.day, 1)
            case .weekly: (.weekOfYear, 7)
            case .monthly: (.month, 31)
            default: (.year, 366)
            }
        let guess = max(Int(now.timeIntervalSince(start) / (days * Double(every) * 86_400)), 1)
        for n in guess..<(guess + 400) {
            guard let at = calendar.date(byAdding: component, value: n * every, to: start) else { continue }
            // A month or year without the day is skipped. A day and a week always have it.
            if self == .monthly || self == .yearly, calendar.component(.day, from: at) != day { continue }
            if at > now { return at }
        }
        return start
    }
}
