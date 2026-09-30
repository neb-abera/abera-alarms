import AlarmCore
import BackgroundTasks
import Foundation
import Observation

/// The screen's state. Every button calls one method here, and each method
/// ends in the one sync path (AlarmSync).
@MainActor
@Observable
final class AppModel {
    nonisolated static let refreshTask = "tech.abera.alarms.refresh"

    private(set) var paired = false
    private(set) var started = false
    private(set) var busy = false
    private(set) var state: AlertsState?
    private(set) var report: SyncReport?
    private(set) var permission: AlarmPermission = .notAsked
    private(set) var pairingError: String?

    private let dependencies: Dependencies

    init(dependencies: Dependencies = .shared) {
        self.dependencies = dependencies
    }

    /// All events, or only the ones that ring on this phone.
    var showAll = false
    private(set) var eventError: String?
    private(set) var routineError: String?

    /// The Clock-style alarms, as abera.tech holds them.
    var routines: [Routine] { state?.routines ?? [] }

    /// The events still ahead: every one, or the alarms alone.
    var events: [PlannedAlert] {
        let now = Date()
        return (state?.alerts ?? []).filter { $0.startsAt > now && (showAll || $0.isAlarm) }
    }

    /// The events grouped by the day their alert goes off, in order.
    var days: [(day: Date, alerts: [PlannedAlert])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.alertAt) }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]!.sorted { ($0.alertAt, $0.key) < ($1.alertAt, $1.key) })
        }
    }

    var emptyMessage: String {
        if showAll { return "No events in the next 48 hours. Tap + to add one." }
        let others = (state?.alerts ?? []).filter { !$0.isAlarm && $0.startsAt > Date() }.count
        let hint =
            "Show All events and set one to Ring until stopped with the icon beside it, add #critical to it in Google Calendar, or tap + for a new alarm."
        return others == 0
            ? "No alarms in the next 48 hours."
            : "No alarms in the next 48 hours. \(others) other event(s) are not alarms. \(hint)"
    }

    /// How many listed alerts go to Pushover alone.
    var notificationCount: Int {
        (state?.alerts ?? []).filter { $0.type == AlertType.notification }.count
    }

    func isHeld(_ alert: PlannedAlert) -> Bool {
        report?.held.contains { $0.key == alert.key } ?? false
    }

    func start() async {
        paired = await dependencies.sync.pairing() != nil
        state = await dependencies.sync.lastState()
        permission = await dependencies.permissions.current()
        started = true
        if paired { await sync() }
    }

    func sync() async {
        await run { await self.dependencies.sync.sync() }
    }

    func pair(link: String) async {
        pairingError = nil
        let pairing: Pairing
        do {
            pairing = try PairingLink.parse(link, allowedServers: dependencies.allowedServers)
        } catch {
            pairingError = Self.describe(error)
            return
        }
        if permission == .notAsked { permission = await dependencies.permissions.request() }
        await run { await self.dependencies.sync.pair(pairing) }
        if let error = report?.error {
            pairingError = Self.describe(error)
        } else {
            paired = true
            await PushRegistration.shared.send()
        }
    }

    func unpair() async {
        busy = true
        await dependencies.sync.unpair()
        paired = false
        state = nil
        report = nil
        busy = false
    }

    func requestPermission() async {
        permission = await dependencies.permissions.request()
        await sync()
    }

    func skip(_ alert: PlannedAlert) async {
        let key = alert.key
        await perform { client throws(APIError) in try await client.skip(key: key) }
    }

    func unskip(_ alert: PlannedAlert) async {
        let key = alert.key
        await perform { client throws(APIError) in try await client.unskip(key: key) }
    }

    func setType(_ alert: PlannedAlert, _ type: String) async {
        let key = alert.key
        await perform { client throws(APIError) in try await client.setType(key: key, type: type) }
    }

    /// True when abera.tech made the event, so the form can close.
    func createEvent(_ event: NewEvent) async -> Bool {
        eventError = nil
        await perform { client throws(APIError) in try await client.createEvent(event) }
        if let error = report?.error {
            eventError = Self.describe(error)
            return false
        }
        showAll = showAll || event.type != AlertType.alarm
        return true
    }

    func clearEventError() { eventError = nil }

    func clearRoutineError() { routineError = nil }

    /// Adds a routine, or replaces the one with this id. True when abera.tech took it.
    func saveRoutine(id: UUID?, _ draft: RoutineDraft) async -> Bool {
        routineError = nil
        if let id {
            await perform { client throws(APIError) in try await client.updateRoutine(id: id, draft) }
        } else {
            await perform { client throws(APIError) in try await client.createRoutine(draft) }
        }
        if let error = report?.error {
            routineError = Self.describe(error)
            return false
        }
        return true
    }

    func setRoutine(_ routine: Routine, enabled: Bool) async {
        var draft = routine.draft
        draft.enabled = enabled
        _ = await saveRoutine(id: routine.id, draft)
    }

    func deleteRoutine(_ routine: Routine) async {
        routineError = nil
        let id = routine.id
        await perform { client throws(APIError) in try await client.deleteRoutine(id: id) }
        if let error = report?.error { routineError = Self.describe(error) }
    }

    func mute(_ length: AlertsClient.MuteLength) async {
        await perform { client throws(APIError) in try await client.mute(length) }
    }

    func unmute() async {
        await perform { client throws(APIError) in try await client.unmute() }
    }

    // MARK: Background refresh

    /// Asks iOS to wake the app in about 15 minutes. iOS decides when, from
    /// how the phone is used, and may wait hours.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated static func backgroundRefresh() async {
        scheduleRefresh()
        _ = await Dependencies.shared.sync.sync()
    }

    // MARK: Private

    private func perform(_ action: @escaping @Sendable (AlertsClient) async throws(APIError) -> AlertsState) async {
        await run { await self.dependencies.sync.perform(action) }
    }

    private func run(_ work: @escaping () async -> SyncReport) async {
        busy = true
        let result = await work()
        report = result
        if let state = result.state { self.state = state }
        if result.error == .unpaired, await dependencies.sync.pairing() == nil { paired = false }
        busy = false
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case PairingError.notAPairingLink:
            "That is not a pairing link. Copy the whole link from abera.tech/alerts."
        case PairingError.badToken:
            "The link has no valid token. Press Pair a phone on abera.tech/alerts again."
        case PairingError.serverNotAllowed:
            "The link points somewhere other than abera.tech."
        case APIError.unpaired:
            "abera.tech refused the token. It may have been revoked. Pair again."
        case APIError.offline:
            "No connection to abera.tech."
        case APIError.rateLimited:
            "Too many requests. Wait a minute."
        case APIError.refused(let reason):
            reason
        case APIError.status(let code):
            "abera.tech answered \(code)."
        default:
            "abera.tech sent something this app cannot read."
        }
    }
}
