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

    /// The readiness checks that fail, blocking ones first.
    private(set) var checks: [ReadinessCheck] = []
    /// When the test alarm rings, while the owner has not said it was heard.
    private(set) var testRingsAt: Date?
    private(set) var testError: String?
    /// The owner said the last test alarm was silent.
    private(set) var testMissed = false
    /// When the running timer rings, and its label. Nil when none runs.
    private(set) var timerEndsAt: Date?
    private(set) var timerLabel = "Timer"
    private(set) var timerError: String?

    /// A paired phone stays on the setup screen while a blocking check fails.
    var blocked: Bool { paired && checks.contains { $0.severity == .blocking } }

    private let dependencies: Dependencies

    init(dependencies: Dependencies = .shared) {
        self.dependencies = dependencies
    }

    /// All events, or only the ones that ring on this phone.
    var showAll = true
    private(set) var eventError: String?
    private(set) var routineError: String?

    /// The Clock-style alarms, as abera.tech holds them, with the changes
    /// tapped on this phone already in place.
    var routines: [Routine] { sending.shown(state)?.routines ?? [] }

    /// Changes on their way to abera.tech, and the mark under each row.
    private(set) var sending = RoutineSending()

    func syncStatus(_ routine: Routine) -> RoutineSyncStatus? { sending.status[routine.id] }

    /// The events not yet over: every one, or the alarms alone. An event
    /// stays listed until its end.
    var events: [PlannedAlert] {
        let now = Date()
        return (state?.alerts ?? []).filter { $0.isListed(at: now) && (showAll || $0.isAlarm) }
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
        let now = Date()
        let others = (state?.alerts ?? []).filter { !$0.isAlarm && $0.isListed(at: now) }.count
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
        if paired { await sync() } else { await checkReadiness() }
        await WidgetFeed.publish(dependencies)
    }

    /// Reads every setting an alarm depends on. Runs on launch, after every
    /// sync and each time the app comes back from Settings.
    func checkReadiness() async {
        await readTimer()
        permission = await dependencies.permissions.current()
        let device = dependencies.device.read()
        let inputs = ReadinessInputs(
            alarmsAllowed: permission == .allowed, backgroundRefresh: device.backgroundRefresh,
            pushRegistered: device.pushRegistered, lowPowerMode: device.lowPower,
            lastSyncedAt: await dependencies.sync.lastSyncedAt(), testHeardAt: dependencies.device.testHeardAt,
            refused: report?.refused.count ?? 0, pushoverInstalled: device.pushover)
        checks = Readiness.failing(inputs, now: Date())
    }

    /// Sets the test alarm 10 seconds out, with the sound every alarm plays.
    func ringTestAlarm() async {
        testError = nil
        testMissed = false
        if await dependencies.device.ringTest(sound: phone.sound) {
            testRingsAt = Date().addingTimeInterval(10)
        } else {
            testRingsAt = nil
            testError = "iOS refused the test alarm. Check that alarms are on for this app."
        }
    }

    func heardTest() async {
        dependencies.device.markTestHeard(Date())
        testRingsAt = nil
        testMissed = false
        await checkReadiness()
    }

    /// The test alarm was silent: the setup check stays open and the app
    /// says what to change.
    func missedTest() {
        testRingsAt = nil
        testMissed = true
    }

    func dismissTestHelp() { testMissed = false }
    /// Starts the timer, replacing one already running. True when it runs.
    func startTimer(_ length: TimerLength, label: String) async -> Bool {
        timerError = nil
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        timerLabel = name.isEmpty ? "Timer" : name
        timerEndsAt = await dependencies.device.startTimer(
            seconds: length.seconds, label: timerLabel, sound: phone.sound)
        if timerEndsAt == nil { timerError = "iOS refused the timer. Check that alarms are on for this app." }
        await WidgetFeed.publish(dependencies)
        return timerEndsAt != nil
    }

    func cancelTimer() async {
        await dependencies.device.cancelTimer()
        timerEndsAt = nil
        await WidgetFeed.publish(dependencies)
    }

    /// Reads the running timer back after a launch. A timer that rang and was stopped is gone.
    func readTimer() async {
        let before = timerEndsAt
        timerEndsAt = await dependencies.device.timerEndsAt()
        if timerEndsAt != before { await WidgetFeed.publish(dependencies) }
    }

    /// Waits for the timer's ring, then reads the timer each second, so its
    /// row goes once the ring is stopped on the Lock Screen.
    func followTimer() async {
        guard let endsAt = timerEndsAt else { return }
        try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
        while !Task.isCancelled, timerEndsAt == endsAt {
            await readTimer()
            try? await Task.sleep(for: .seconds(1))
        }
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
        await WidgetFeed.publish(dependencies)
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

    /// The sound and snooze abera.tech holds for this phone.
    var phone: PhoneSettings { state?.phone ?? PhoneSettings() }
    private(set) var settingsError: String?

    /// The rules for what an event sends, as abera.tech holds them.
    var rules: [TypeRule] { state?.rules ?? [] }
    private(set) var rulesError: String?

    /// Replaces every rule on abera.tech. True when it saved.
    func saveRules(_ rules: [TypeRule]) async -> Bool {
        rulesError = nil
        await perform { client throws(APIError) in try await client.saveRules(rules) }
        if let error = report?.error { rulesError = Self.describe(error) }
        return rulesError == nil
    }

    func clearRulesError() { rulesError = nil }

    func savePhoneSettings(_ settings: PhoneSettings) async {
        settingsError = nil
        await perform { client throws(APIError) in try await client.updatePhoneSettings(settings) }
        if let error = report?.error { settingsError = Self.describe(error) }
    }

    /// True when abera.tech changed the event.
    /// A new alert type, when given, is set first, for every event in the
    /// series, as the type menu beside the event sets it. The key it names
    /// changes once the start moves.
    /// An edit that changes nothing on the calendar is not sent: abera.tech
    /// keeps the type itself, and Google refuses any edit of an event
    /// someone else organized. On 12 Nov 2026 that refusal read as the
    /// alarm not being set.
    func updateEvent(_ edit: EventEdit, of alert: PlannedAlert, type: String? = nil) async -> Bool {
        eventError = nil
        let changes = edit.changesEvent(alert)
        await perform { client throws(APIError) in
            if let type {
                let state = try await client.setType(key: edit.key, type: type)
                if !changes { return state }
            }
            return changes ? try await client.updateEvent(edit) : try await client.status()
        }
        if let error = report?.error {
            eventError = Self.describe(error)
            return false
        }
        return true
    }

    /// True when abera.tech deleted the event.
    func deleteEvent(_ alert: PlannedAlert, scope: EditScope) async -> Bool {
        eventError = nil
        let key = alert.key
        await perform { client throws(APIError) in try await client.deleteEvent(key: key, scope: scope) }
        if let error = report?.error {
            eventError = Self.describe(error)
            return false
        }
        return true
    }

    /// Routine changes waiting for a connection to reach abera.tech.
    private(set) var waitingRoutineChanges = 0

    /// Adds a routine, or replaces the one with this id. The list shows it
    /// at once, it is set on the phone with or without a connection, and it
    /// reaches abera.tech when it can. False only when abera.tech refused it.
    @discardableResult
    func saveRoutine(id: UUID?, _ draft: RoutineDraft) async -> Bool {
        let change: RoutineChange = id.map { .update(id: $0, draft: draft) } ?? .create(local: UUID(), draft: draft)
        return await changeRoutine(change)
    }

    func setRoutine(_ routine: Routine, enabled: Bool) async {
        var draft = routine.draft
        draft.enabled = enabled
        _ = await saveRoutine(id: routine.id, draft)
    }

    func deleteRoutine(_ routine: Routine) async {
        _ = await changeRoutine(.delete(id: routine.id))
    }

    /// Deletes each alarm in turn. Each one works offline like a single delete.
    func deleteRoutines(_ ids: Set<UUID>) async {
        for routine in routines where ids.contains(routine.id) {
            await deleteRoutine(routine)
        }
    }

    private func changeRoutine(_ change: RoutineChange) async -> Bool {
        routineError = nil
        sending.begin(change)
        let result = await runReturning { await self.dependencies.sync.changeRoutine(change) }
        let waiting = Set(await dependencies.sync.routineChanges().map(\.id))
        sending.finish(change, error: result.error, waiting: waiting)
        clearSavedSoon(change.id)
        switch result.error {
        case .refused(let reason)?:
            routineError = reason
            return false
        case .unpaired?:
            routineError = Self.describe(APIError.unpaired)
            return false
        default:
            // Offline or a server error: the change is on the phone and waits.
            return true
        }
    }

    // MARK: Steps

    /// The steps checked off, with the phone's own check-offs not yet sent laid over them.
    var completions: [RoutineCompletion] { state?.routineCompletions ?? [] }
    /// Check-offs waiting for a connection to reach abera.tech.
    private(set) var waitingCompletions = 0
    private(set) var stepError: String?

    func completion(_ routine: Routine, _ ring: RoutineCycle.StepRing) -> RoutineCompletion? {
        completions.first { $0.stepKey == ring.key }
    }

    /// Checks a step off for one cycle. Its alarm for that cycle is cancelled
    /// at once, offline too. The photo is a JPEG.
    func completeStep(
        _ routine: Routine, cycle: RoutineCycle, step: RoutineStep, note: String? = nil, photo: Data? = nil,
        removePhoto: Bool = false
    ) async {
        stepError = nil
        let draft = CompletionDraft(
            routineId: routine.id, stepId: step.id, cycle: cycle.stamp, note: note, removePhoto: removePhoto,
            completedAt: completion(routine, cycle, step)?.completedAt ?? Date())
        let result = await runReturning { await self.dependencies.sync.completeStep(draft, photo: photo) }
        noteStepError(result.error)
    }

    func undoStep(_ routine: Routine, cycle: RoutineCycle, step: RoutineStep) async {
        stepError = nil
        let result = await runReturning {
            await self.dependencies.sync.undoStep(routineId: routine.id, stepId: step.id, cycle: cycle.stamp)
        }
        noteStepError(result.error)
    }

    private func completion(_ routine: Routine, _ cycle: RoutineCycle, _ step: RoutineStep) -> RoutineCompletion? {
        completions.first { $0.routineId == routine.id && $0.stepId == step.id && $0.cycle == cycle.stamp }
    }

    private func noteStepError(_ error: APIError?) {
        switch error {
        case .refused(let reason)?: stepError = reason
        case .unpaired?: stepError = Self.describe(APIError.unpaired)
        default: break
        }
    }

    /// Makes `child` a step of `parent`, at the time it rang on its own, and
    /// deletes it as an alarm. Works offline like any alarm change.
    func subordinate(_ child: Routine, under parent: Routine) async {
        switch RoutineChaining.subordinate(child, under: parent) {
        case .failure(let refusal):
            routineError = refusal.message
        case .success(let draft):
            guard await saveRoutine(id: parent.id, draft) else { return }
            await deleteRoutine(child)
        }
    }

    /// Makes a step an alarm of its own, at the time it rang as a step.
    func separate(_ step: RoutineStep, from parent: Routine) async {
        guard let (remaining, alarm) = RoutineChaining.separate(step.id, from: parent) else { return }
        guard await saveRoutine(id: nil, alarm) else { return }
        await saveRoutine(id: parent.id, remaining)
    }

    /// Deletes one step. The step after it keeps its time.
    func deleteStep(_ step: RoutineStep, from parent: Routine) async {
        var draft = parent.draft
        draft.steps = RoutineChaining.remove(step.id, from: parent.steps)
        await saveRoutine(id: parent.id, draft)
    }

    /// The cycle the Alarms tab shows under an alarm.
    func shownCycle(_ routine: Routine, at now: Date) -> RoutineCycle? {
        let window = TimeInterval((state?.stopAfterMinutes ?? AlertsState.defaultStopAfterMinutes) * 60)
        return RoutineCycle.shown(routine, now: now, window: window, calendar: .current)
    }

    /// The last two weeks from abera.tech, or why they could not be read.
    func history() async -> Result<RoutineHistory, APIError> {
        await dependencies.sync.history()
    }

    func photo(_ id: UUID) async -> Data? {
        try? await dependencies.sync.photo(completionId: id).get()
    }

    // MARK: Countdowns

    /// The dates counted down to, as abera.tech holds them.
    var countdowns: [Countdown] { state?.countdowns ?? [] }
    private(set) var countdownError: String?

    func clearCountdownError() { countdownError = nil }

    /// Adds a countdown, or replaces the one with this id. Countdowns need a
    /// connection: nothing is kept on the phone to send later. True when
    /// abera.tech took it.
    func saveCountdown(id: UUID?, _ draft: CountdownDraft) async -> Bool {
        await changeCountdown { client throws(APIError) in
            if let id {
                try await client.updateCountdown(id: id, draft)
            } else {
                try await client.createCountdown(draft)
            }
        }
    }

    /// True when abera.tech deleted it, or no longer had it.
    @discardableResult
    func deleteCountdown(_ countdown: Countdown) async -> Bool {
        let id = countdown.id
        return await changeCountdown { client throws(APIError) in try await client.deleteCountdown(id: id) }
    }

    private func changeCountdown(
        _ action: @escaping @Sendable (AlertsClient) async throws(APIError) -> AlertsState
    ) async -> Bool {
        countdownError = nil
        await perform(action)
        switch report?.error {
        case nil:
            return true
        case .offline?:
            countdownError = "No connection to abera.tech. Countdown changes need one. Try again when online."
        case .notFound?:
            countdownError = "abera.tech no longer has that countdown. Pull to refresh."
            await sync()
        case let error?:
            countdownError = Self.describe(error)
        }
        return false
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
        await WidgetFeed.publish()
    }

    // MARK: Private

    private func perform(_ action: @escaping @Sendable (AlertsClient) async throws(APIError) -> AlertsState) async {
        await run { await self.dependencies.sync.perform(action) }
    }

    private func run(_ work: @escaping () async -> SyncReport) async {
        _ = await runReturning(work)
    }

    /// The report of this run. `report` may already hold a later one.
    private func runReturning(_ work: @escaping () async -> SyncReport) async -> SyncReport {
        busy = true
        let result = await work()
        report = result
        if let state = result.state { self.state = state }
        if result.error == .unpaired, await dependencies.sync.pairing() == nil { paired = false }
        let waiting = await dependencies.sync.routineChanges().map(\.id)
        waitingRoutineChanges = waiting.count
        waitingCompletions = await dependencies.sync.completionChanges().count
        let before = sending.status
        sending.settle(waiting: Set(waiting))
        for (id, status) in sending.status where status == .saved && before[id] != .saved { clearSavedSoon(id) }
        await checkReadiness()
        await WidgetFeed.publish(dependencies)
        busy = false
        return result
    }

    /// A saved mark shows for 2 s.
    private func clearSavedSoon(_ id: UUID) {
        guard sending.status[id] == .saved else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            sending.clearSaved(id)
        }
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
