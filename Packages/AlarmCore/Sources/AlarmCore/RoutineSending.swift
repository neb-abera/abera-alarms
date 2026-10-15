import Foundation

/// Where a routine change stands, for the line under its row.
public enum RoutineSyncStatus: Equatable, Sendable {
    /// Set on the phone and on its way to abera.tech.
    case sending
    /// Set on the phone. abera.tech could not be reached, so it goes at the next sync.
    case waiting
    /// abera.tech has it. Shown for a moment, then cleared.
    case saved
}

/// The routine changes the screen shows before the sync that carries them
/// returns. A switch moves when it is tapped, not when abera.tech answers.
/// With no connection a request waits up to 20 s, and until 2026-10-15 the
/// switch sat in its old place for all of it.
public struct RoutineSending: Equatable, Sendable {
    /// Changes tapped whose sync has not returned, in order.
    public private(set) var inFlight: [RoutineChange] = []
    public private(set) var status: [UUID: RoutineSyncStatus] = [:]

    public init() {}

    public mutating func begin(_ change: RoutineChange) {
        inFlight.append(change)
        status[change.id] = .sending
    }

    /// The state with every change still on its way laid over it, so a sync
    /// that read abera.tech before a tap does not put a switch back.
    public func shown(_ state: AlertsState?) -> AlertsState? {
        guard let state else { return nil }
        return RoutineChange.overlay(state, inFlight)
    }

    /// The sync carrying `change` returned with `error`. `waiting` holds the
    /// routines whose changes abera.tech has not taken yet.
    public mutating func finish(_ change: RoutineChange, error: APIError?, waiting: Set<UUID>) {
        if let index = inFlight.firstIndex(of: change) { inFlight.remove(at: index) }
        let id = change.id
        if inFlight.contains(where: { $0.id == id }) { return }
        switch error {
        case .refused?, .unpaired?:
            status[id] = nil
        case _ where waiting.contains(id):
            status[id] = .waiting
        case nil:
            status[id] = .saved
        default:
            status[id] = nil
        }
    }

    /// After any sync: a waiting change abera.tech has now taken is saved.
    public mutating func settle(waiting: Set<UUID>) {
        for (id, value) in status where value == .waiting && !waiting.contains(id) {
            status[id] = .saved
        }
    }

    /// Takes down a saved mark. A change tapped since keeps its own.
    public mutating func clearSaved(_ id: UUID) {
        if status[id] == .saved { status[id] = nil }
    }
}
