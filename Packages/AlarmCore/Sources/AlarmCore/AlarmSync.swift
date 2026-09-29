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

        do {
            let state = try await client.status()
            return await apply(state)
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

    /// The last state the server sent, for the screen before the first sync.
    public func lastState() async -> AlertsState? {
        guard let data = try? await documents.load(Self.stateName) else { return nil }
        return try? ServerDates.decoder().decode(AlertsState.self, from: data)
    }

    // MARK: Applying

    private func apply(_ state: AlertsState) async -> SyncReport {
        let at = now()
        let desired = Reconciler.desired(from: state, now: at, acknowledgedHere: Set(await pending()))
        let ledger = await loadLedger()
        let system: Set<UUID>
        do {
            system = try await alarms.scheduledIDs()
        } catch {
            return report(error: nil, state: state, refused: desired.map(\.key))
        }

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
        if let data = try? ServerDates.encoder().encode(state) {
            try? await documents.save(data, as: Self.stateName)
        }

        return SyncReport(
            at: at, state: state, scheduled: scheduled, cancelled: cancelled,
            held: held.values.sorted { ($0.fireAt, $0.key) < ($1.fireAt, $1.key) },
            waitingAcknowledgements: await pending().count, error: nil, refused: refused)
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
