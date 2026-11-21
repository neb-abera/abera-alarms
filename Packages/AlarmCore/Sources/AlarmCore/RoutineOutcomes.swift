import Foundation

/// One ring of an alarm marked Done or Skipped, ahead of it or after it.
/// Done keeps the alarm's own ring from sounding. Skipped also keeps its
/// steps from ringing. The next ring is set as usual.
public struct RoutineOutcome: Codable, Equatable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case done
        case skipped
    }

    public var routineId: UUID
    /// The ring's stamp, "yyyy-MM-ddTHH:mm".
    public var cycle: String
    public var status: Status
    public var at: Date
    public var note: String?

    public init(routineId: UUID, cycle: String, status: Status, at: Date, note: String? = nil) {
        self.routineId = routineId
        self.cycle = cycle
        self.status = status
        self.at = at
        self.note = note
    }

    /// The alarm's own ring it answers: `routine:{id}:{stamp}`.
    public var ringKey: String { RoutineCycle.parentKey(routineID: routineId, stamp: cycle) }
}

/// What the phone sends to mark a ring Done or Skipped.
public struct OutcomeDraft: Codable, Equatable, Sendable {
    public var routineId: UUID
    public var cycle: String
    public var status: RoutineOutcome.Status
    public var note: String?
    public var at: Date

    public init(routineId: UUID, cycle: String, status: RoutineOutcome.Status, note: String? = nil, at: Date) {
        self.routineId = routineId
        self.cycle = cycle
        self.status = status
        self.note = note
        self.at = at
    }

    var body: OutcomeBody {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return OutcomeBody(status: status.rawValue, note: trimmed?.isEmpty == false ? trimmed : nil, at: at)
    }
}

/// What PUT .../outcome carries.
struct OutcomeBody: Encodable {
    var status: String
    var note: String?
    var at: Date

    enum CodingKeys: String, CodingKey { case status, note, at }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(note, forKey: .note)
        try container.encode(at, forKey: .at)
    }
}

extension RoutineCycle {
    /// The alarm's ring key of `key` when it names one (`routine:{id}:{stamp}`),
    /// never a step's or a routine's own alarm key.
    public static func parseParentKey(_ key: String) -> (routineID: UUID, stamp: String)? {
        guard key.hasPrefix(DesiredAlarm.routinePrefix), !key.contains(":step:") else { return nil }
        let rest = key.dropFirst(DesiredAlarm.routinePrefix.count)
        guard rest.count > 37, let routine = UUID(uuidString: String(rest.prefix(36))),
            rest[rest.index(rest.startIndex, offsetBy: 36)] == ":"
        else { return nil }
        return (routine, String(rest.dropFirst(37)))
    }

    /// The ring's outcome, if it has one.
    public func outcome(in state: AlertsState) -> RoutineOutcome? {
        state.routineOutcomes.first { $0.routineId == routineID && $0.cycle == stamp }
    }

    /// True once nothing in this ring is left to do: it was skipped, or it
    /// was marked Done or its time has passed, and every step was checked
    /// off. The list under the alarm then moves to the next ring. A Stop is
    /// not needed: abera.tech lists a ring only for its stop window, so a
    /// 07:00 Stop was out of sight by 10:06, and the list kept offering Done
    /// for a ring that had rung (Neb's iPhone, 2026-11-21).
    public func isSettled(in state: AlertsState, acknowledgedHere: Set<String> = [], now: Date) -> Bool {
        let outcome = outcome(in: state)
        if outcome?.status == .skipped { return true }
        guard outcome?.status == .done || at <= now || acknowledgedHere.contains(key) else { return false }
        let completed = Set(state.routineCompletions.map(\.stepKey))
        return steps.allSatisfy { completed.contains($0.key) }
    }
}

extension AlertsState {
    /// The ring keys with an outcome, and the step keys of every skipped ring.
    func answeredByOutcome() -> (rings: Set<String>, steps: Set<String>) {
        var rings = Set<String>()
        var steps = Set<String>()
        for outcome in routineOutcomes {
            rings.insert(outcome.ringKey)
            guard outcome.status == .skipped,
                let routine = routines.first(where: { $0.id == outcome.routineId })
            else { continue }
            for step in routine.steps {
                steps.insert(RoutineCycle.stepKey(routineID: routine.id, stamp: outcome.cycle, stepID: step.id))
            }
        }
        return (rings, steps)
    }
}
