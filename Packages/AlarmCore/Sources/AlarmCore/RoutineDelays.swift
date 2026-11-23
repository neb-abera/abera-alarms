import Foundation

/// One ring of an alarm, and every step of it, moved later. On 2026-11-23
/// Neb's 07:00 wake up alarm rang before his workout, and he wanted the
/// beauty routine after it. The ring keeps its stamp, so check-offs and
/// marks still name it. Only the times move.
public struct RoutineDelay: Codable, Equatable, Hashable, Sendable {
    /// From 1 minute to 12 hours after the planned time.
    public static let minutes = 1...720
    /// The choices the Alarms tab offers.
    public static let choices = [15, 30, 45, 60, 90, 120, 180]

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

    /// "15 min", "1 h", "1 h 30 min".
    public static func words(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
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
