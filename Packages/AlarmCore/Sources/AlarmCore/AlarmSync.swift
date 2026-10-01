import Foundation

/// What the last sync did, for the screen.
public struct SyncReport: Equatable, Sendable {
    public var at: Date
    public var state: AlertsState?
    public var scheduled: Int
    public var cancelled: Int
    public var held: [DesiredAlarm]
    public var waitingAcknowledgements: Int
    public var error: APIError?
    /// An alarm the system refused to schedule, with its key.
    public var refused: [String]
    /// Routine changes made on the phone that abera.tech has not taken yet.
    public var waitingRoutineChanges: Int = 0
}

/// The one path from the server's state to the phone's alarms. The app's
/// launch, pull to refresh, background refresh, a pairing, the Stop button
/// on a ringing alarm and every action button all end here.
public actor AlarmSync {
    static let ledgerName = "ledger.json"
    static let pendingName = "pending-acknowledgements.json"
    static let stateName = "last-state.json"

    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let alarms: any AlarmScheduling
    let documents: any DocumentStore
    let now: @Sendable () -> Date

    public init(
        credentials: any CredentialStore,
        transport: any HTTPTransport,
        alarms: any AlarmScheduling,
        documents: any DocumentStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.transport = transport
        self.alarms = alarms
        self.documents = documents
        self.now = now
    }

    // MARK: Pairing

    public func pairing() async -> Pairing? {
        try? await credentials.load()
    }

    /// Stores the pairing only once the server has accepted the token.
    public func pair(_ pairing: Pairing) async -> SyncReport {
        let client = AlertsClient(pairing: pairing, transport: transport)
        do {
            let state = try await client.status()
            try await credentials.save(pairing)
            return await apply(state)
        } catch let error as APIError {
            return report(error: error, state: nil)
        } catch {
            return report(error: .badResponse, state: nil)
        }
    }

    /// Tells abera.tech where to push when this phone's alarms change. Safe
    /// to call on every launch: the server keeps the latest token.
    @discardableResult
    public func registerPush(token: String, environment: PushEnvironment) async -> APIError? {
        guard PushToken.isValid(token) else { return .badResponse }
        guard let pairing = await pairing() else { return .unpaired }
        do {
            try await AlertsClient(pairing: pairing, transport: transport)
                .registerPush(token: token, environment: environment)
            return nil
        } catch {
            return error
        }
    }

    /// Forgets the token and removes every alarm this app holds.
    public func unpair() async {
        if let pairing = await pairing() {
            // Best effort: a phone with no signal still unpairs. Revoking the
            // phone on the page drops its push token as well.
            try? await AlertsClient(pairing: pairing, transport: transport).unregisterPush()
        }
        try? await credentials.remove()
        try? await documents.remove(Self.pendingName)
        try? await documents.remove(Self.pendingOffName)
        try? await documents.remove(Self.routineChangesName)
        _ = await apply(AlertsState(configured: false))
        try? await documents.remove(Self.stateName)
    }

    // MARK: Sync

    /// Sends the acknowledgements that waited, reads the server, and makes
    /// the phone's alarms match. Offline, the alarms already scheduled stay:
    /// that is the point of holding them on the phone.
    public func sync() async -> SyncReport {
        guard let pairing = await pairing() else { return report(error: .unpaired, state: nil) }
        let client = AlertsClient(pairing: pairing, transport: transport)

        var latest: AlertsState?
        for key in await pending() {
            do {
                latest = try await client.acknowledge(key: key)
                await removePending(key)
            } catch .notFound {
                // The server no longer lists it: it started, or the event
                // is gone. Nothing is left to acknowledge.
                await removePending(key)
            } catch {
                if error == .unpaired { return await unpaired() }
                return report(error: error, state: await lastState())
            }
        }

        if let system = try? await alarms.scheduledIDs() {
            await noteRungOnce(ledger: await loadLedger(), system: system, at: now())
        }

        do {
            var state = try await client.status()
            // Routine changes made on the phone, in order, then the answer
            // to the last one is the state.
            var refusal: APIError?
            (state, refusal) = await flushRoutineChanges(client, from: state)
            // A ring-once routine that rang is switched off on abera.tech, as
            // the Clock app switches off a one-time alarm.
            for id in await pendingOff() {
                if let routine = state.routines.first(where: { $0.id == id }), routine.enabled, !routine.repeats {
                    var off = routine.draft
                    off.enabled = false
                    do {
                        state = try await client.updateRoutine(id: id, off)
                    } catch .notFound {
                        // Deleted meanwhile: nothing to switch off.
                    }
                }
                await removePendingOff(id)
            }
            var report = await apply(state)
            if report.error == nil { report.error = refusal }
            return report
        } catch .unpaired {
            return await unpaired()
        } catch {
            let fallback = await lastState()
            return report(error: error, state: latest ?? fallback)
        }
    }

    /// The Stop button on a ringing alarm. The phone remembers the key
    /// before it tries the network, so an acknowledgement made with no
    /// signal is sent on the next sync and the alarm is not scheduled again.
    public func acknowledge(key: String) async -> SyncReport {
        await addPending(key)
        return await sync()
    }

    /// Skip, unskip, mute and unmute: the server stores it, then the phone
    /// matches what the server answered.
    public func perform(_ action: @Sendable (AlertsClient) async throws(APIError) -> AlertsState) async -> SyncReport {
        guard let pairing = await pairing() else { return report(error: .unpaired, state: nil) }
        do {
            return await apply(try await action(AlertsClient(pairing: pairing, transport: transport)))
        } catch .unpaired {
            return await unpaired()
        } catch {
            return report(error: error, state: await lastState())
        }
    }

    /// The last state the server sent, with the routine changes still
    /// waiting to reach it, for the screen before the first sync and offline.
    public func lastState() async -> AlertsState? {
        let changes = await routineChanges()
        // A phone that has never reached abera.tech still shows the alarms
        // made on it.
        guard let raw = await lastServerState() ?? (changes.isEmpty ? nil : AlertsState()) else { return nil }
        return RoutineChange.overlay(raw, changes)
    }

    private func lastServerState() async -> AlertsState? {
        guard let data = try? await documents.load(Self.stateName) else { return nil }
        return try? ServerDates.decoder().decode(AlertsState.self, from: data)
    }

    // MARK: Routine changes

    static let routineChangesName = "pending-routine-changes.json"

    /// Adds, changes, switches or deletes a routine alarm. The phone applies
    /// it to its own copy and its alarms at once, offline too, then sends it.
    /// A change abera.tech has not taken yet waits, in order, for the next sync.
    public func changeRoutine(_ change: RoutineChange) async -> SyncReport {
        guard await pairing() != nil else { return report(error: .unpaired, state: nil) }
        await saveRoutineChanges(RoutineChange.coalesce(await routineChanges() + [change]))
        _ = await apply(await lastServerState() ?? AlertsState(), keep: false)
        return await sync()
    }

    public func routineChanges() async -> [RoutineChange] {
        guard let data = try? await documents.load(Self.routineChangesName),
            let changes = try? JSONDecoder().decode([RoutineChange].self, from: data)
        else { return [] }
        return changes
    }

    private func saveRoutineChanges(_ changes: [RoutineChange]) async {
        if let data = try? JSONEncoder().encode(Array(changes.suffix(Self.maxPending))) {
            try? await documents.save(data, as: Self.routineChangesName)
        }
    }

    /// Sends the waiting routine changes in order. Stops at the first that
    /// cannot reach abera.tech, which waits for the next sync. A change
    /// abera.tech refuses is dropped and its reason returned.
    private func flushRoutineChanges(_ client: AlertsClient, from start: AlertsState) async -> (AlertsState, APIError?)
    {
        var state = start
        var refusal: APIError?
        var ids: [UUID: UUID] = [:]
        var changes = await routineChanges()
        while let change = changes.first {
            do {
                switch change {
                case .create(let local, let draft):
                    let known = Set(state.routines.map(\.id))
                    state = try await client.createRoutine(draft)
                    if let made = state.routines.first(where: { !known.contains($0.id) }) { ids[local] = made.id }
                case .update(let id, let draft):
                    state = try await client.updateRoutine(id: ids[id] ?? id, draft)
                case .delete(let id):
                    state = try await client.deleteRoutine(id: ids[id] ?? id)
                }
            } catch .notFound {
                // Deleted elsewhere: nothing left to change.
            } catch .refused(let reason) {
                refusal = .refused(reason)
            } catch {
                break
            }
            changes.removeFirst()
            // Later changes to a routine made offline name its server id now.
            changes = changes.map { $0.renaming(ids) }
            await saveRoutineChanges(changes)
        }
        return (state, refusal)
    }

    // MARK: Applying

    /// `keep` false applies a state without storing it as the server's: the
    /// empty one a phone that never synced starts from.
    private func apply(_ server: AlertsState, keep: Bool = true) async -> SyncReport {
        let at = now()
        let state = RoutineChange.overlay(server, await routineChanges())
        let ledger = await loadLedger()
        let system: Set<UUID>
        do {
            system = try await alarms.scheduledIDs()
        } catch {
            let desired = Reconciler.desired(from: state, now: at, acknowledgedHere: Set(await pending()))
            return report(error: nil, state: state, refused: desired.map(\.key))
        }

        await noteRungOnce(ledger: ledger, system: system, at: at)
        let off = Set(await pendingOff())
        let desired = Reconciler.desired(from: state, now: at, acknowledgedHere: Set(await pending()))
            .filter { !off.contains($0.id) }

        let changes = Reconciler.changes(desired: desired, ledger: ledger, system: system)
        var held = ledger.filter { system.contains($0.key) }
        var cancelled = 0
        for id in changes.cancel {
            if (try? await alarms.cancel(id)) != nil {
                held[id] = nil
                cancelled += 1
            }
        }
        var refused: [String] = []
        var scheduled = 0
        for alarm in changes.schedule {
            do {
                try await alarms.schedule(alarm)
                held[alarm.id] = alarm
                scheduled += 1
            } catch {
                refused.append(alarm.key)
            }
        }

        await saveLedger(held)
        // The server's own state is kept. The waiting changes are laid over
        // it again on every read, so none is applied twice.
        if keep, server.configured, let data = try? ServerDates.encoder().encode(server) {
            try? await documents.save(data, as: Self.stateName)
        }

        return SyncReport(
            at: at, state: state, scheduled: scheduled, cancelled: cancelled,
            held: held.values.sorted { ($0.fireAt, $0.key) < ($1.fireAt, $1.key) },
            waitingAcknowledgements: await pending().count, error: nil, refused: refused,
            waitingRoutineChanges: await routineChanges().count)
    }

    private func unpaired() async -> SyncReport {
        // A revoked token: the server will never say what to ring again, so
        // the alarms it last asked for are all this phone knows. They stay
        // until the owner unpairs or pairs again, and the screen says so.
        report(error: .unpaired, state: await lastState())
    }

    private func report(error: APIError?, state: AlertsState?, refused: [String] = []) -> SyncReport {
        SyncReport(
            at: now(), state: state, scheduled: 0, cancelled: 0, held: [],
            waitingAcknowledgements: 0, error: error, refused: refused)
    }

    // MARK: Documents

    private func loadLedger() async -> [UUID: DesiredAlarm] {
        guard let data = try? await documents.load(Self.ledgerName),
            let list = try? ServerDates.decoder().decode([DesiredAlarm].self, from: data)
        else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func saveLedger(_ ledger: [UUID: DesiredAlarm]) async {
        let list = ledger.values.sorted { $0.id.uuidString < $1.id.uuidString }
        if let data = try? ServerDates.encoder().encode(list) {
            try? await documents.save(data, as: Self.ledgerName)
        }
    }

    static let pendingOffName = "pending-routines-off.json"

    /// A ring-once routine the phone held that is gone from the alarm system
    /// and whose time has passed has rung. It is not set again for tomorrow,
    /// and a sync switches it off on abera.tech.
    private func noteRungOnce(ledger: [UUID: DesiredAlarm], system: Set<UUID>, at: Date) async {
        for alarm in ledger.values where alarm.routine?.days.isEmpty == true {
            if alarm.fireAt <= at, !system.contains(alarm.id) { await addPendingOff(alarm.id) }
        }
    }

    func pendingOff() async -> [UUID] {
        guard let data = try? await documents.load(Self.pendingOffName),
            let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return ids
    }

    private func addPendingOff(_ id: UUID) async {
        var ids = await pendingOff()
        guard !ids.contains(id) else { return }
        ids.append(id)
        if let data = try? JSONEncoder().encode(Array(ids.suffix(Self.maxPending))) {
            try? await documents.save(data, as: Self.pendingOffName)
        }
    }

    private func removePendingOff(_ id: UUID) async {
        let ids = await pendingOff().filter { $0 != id }
        if let data = try? JSONEncoder().encode(ids) {
            try? await documents.save(data, as: Self.pendingOffName)
        }
    }

    /// At most this many acknowledgements wait. A phone offline for days
    /// holds at most two days of alarms.
    static let maxPending = 100

    func pending() async -> [String] {
        guard let data = try? await documents.load(Self.pendingName),
            let keys = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return keys
    }

    private func addPending(_ key: String) async {
        var keys = await pending()
        guard !keys.contains(key), key.utf8.count <= 200 else { return }
        keys.append(key)
        if let data = try? JSONEncoder().encode(Array(keys.suffix(Self.maxPending))) {
            try? await documents.save(data, as: Self.pendingName)
        }
    }

    private func removePending(_ key: String) async {
        let keys = await pending().filter { $0 != key }
        if let data = try? JSONEncoder().encode(keys) {
            try? await documents.save(data, as: Self.pendingName)
        }
    }
}
