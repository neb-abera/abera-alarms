import Foundation

/// One ring of an alarm, and every step of it, moved later. On 2026-11-23
/// Neb's 07:00 wake up alarm rang before his workout, and he wanted the
/// beauty routine after it. The ring keeps its stamp, so check-offs and
/// marks still name it. Only the times move.
public struct RoutineDelay: Codable, Equatable, Hashable, Sendable {
    /// From 1 minute to 7 days after the planned time, as abera.tech takes
    /// it. Neb asked on 2026-11-26 to delay past 3 hours, by a number and
    /// a unit. It was 12 hours, and the menu stopped at 3.
    public static let minutes = 1...10080
    /// The presets beside the typed delay, each one tap.
    public static let choices = [15, 30, 60, 120, 1440]

    /// The delay from the planned time once `minutes` more are added to
    /// the `already` the ring was moved.
    public static func total(adding minutes: Int, to already: Int) -> Int {
        let (sum, overflow) = already.addingReportingOverflow(max(minutes, 0))
        return overflow ? .max : sum
    }

    /// Why that delay cannot be saved, or nil.
    public static func problem(adding minutes: Int, to already: Int) -> String? {
        if minutes < 1 { return "Type at least 1 minute." }
        if total(adding: minutes, to: already) > self.minutes.upperBound {
            let left = self.minutes.upperBound - already
            return "At most 7 days after the planned time: \(words(left)) more."
        }
        return nil
    }

    public var routineId: UUID
    /// The ring's planned stamp, "yyyy-MM-ddTHH:mm".
    public var cycle: String
    /// Minutes after the planned time.
    public var minutes: Int
    /// When the delay was saved.
    public var at: Date

    public init(routineId: UUID, cycle: String, minutes: Int, at: Date) {
        self.routineId = routineId
        self.cycle = cycle
        self.minutes = minutes
        self.at = at
    }

    /// "15 min", "1 h", "1 h 30 min", "1 day", "2 days 3 h".
    public static func words(_ minutes: Int) -> String {
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        let rest = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append("\(hours) h") }
        if rest > 0 || parts.isEmpty { parts.append("\(rest) min") }
        return parts.joined(separator: " ")
    }
}

/// What PUT .../delay carries.
struct DelayBody: Codable {
    var minutes: Int
}

extension AlertsState {
    /// The delays by routine, each by its ring's stamp.
    func delaysByRoutine() -> [UUID: [String: Int]] {
        var out: [UUID: [String: Int]] = [:]
        for delay in routineDelays { out[delay.routineId, default: [:]][delay.cycle] = delay.minutes }
        return out
    }

    /// Each routine carries its own delays, so every ring worked out from
    /// it lands at the delayed time.
    mutating func attachDelays() {
        let delays = delaysByRoutine()
        for index in routines.indices {
            let own = delays[routines[index].id] ?? [:]
            if routines[index].delays != own { routines[index].delays = own }
        }
    }
}

extension RoutineCycle {
    /// Minutes this ring was moved, or nil.
    public func delay(in routine: Routine) -> Int? { routine.delays[stamp] }
}
