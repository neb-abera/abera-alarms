import Foundation

/// The day a ring falls on, in words, so a time never leaves the day to
/// guess. On 2026-11-22 at 21:36 the steps of the night routine read
/// "Rings at 21:31" for Tuesday's ring, and Neb could not tell whether the
/// time was tonight's or a later one.
public enum RingDay {
    /// "today, Sun 22 Nov", "tomorrow, Mon 23 Nov", "yesterday, Sat 21
    /// Nov", or "Tue 24 Nov". The date always shows: at 21:36 the alarm's
    /// countdown pointed at Tuesday while its steps listed tonight, and Neb
    /// asked for the date on each.
    public static func word(_ date: Date, now: Date, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "EEE d MMM"
        let day = format.string(from: date)
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
            ).day ?? 0
        switch days {
        case 0: return "today, " + day
        case 1: return "tomorrow, " + day
        case -1: return "yesterday, " + day
        default: return day
        }
    }

    /// "today, Sun 22 Nov at 21:31".
    public static func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return word(date, now: now, calendar: calendar)
            + String(format: " at %02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }
}
