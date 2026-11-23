import Foundation

/// The day a ring falls on, in words, so a time never leaves the day to
/// guess. On 2026-11-22 at 21:36 the steps of the night routine read
/// "Rings at 21:31" for Tuesday's ring, and Neb could not tell whether the
/// time was tonight's or a later one.
public enum RingDay {
    /// "today", "tomorrow", "yesterday", or "Tue 24 Nov".
    public static func word(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
            ).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default:
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            format.dateFormat = "EEE d MMM"
            return format.string(from: date)
        }
    }
}
