import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends one HTTP request. The app passes URLSession. Tests pass a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Hands a request to the system to send. iOS sends it after the app is
/// suspended or ended, and retries it. The app passes a background
/// URLSession. Tests pass a fake.
public protocol BackgroundUploading: Sendable {
    /// `label` comes back with the result, to `AlarmSync.uploadFinished`.
    func upload(_ request: URLRequest, label: String) async throws
}

/// The phone's alarm system. The app passes AlarmKit. Tests pass a fake.
public protocol AlarmScheduling: Sendable {
    /// The ids of the alarms the system holds for this app.
    func scheduledIDs() async throws -> Set<UUID>
    func schedule(_ alarm: DesiredAlarm) async throws
    /// Removes the alarm, a repeating one included. AlarmKit does not say
    /// whether this silences an alarm that is ringing, so the sync stops a
    /// ringing alarm before it cancels it.
    func cancel(_ id: UUID) async throws
    /// The ids of the alarms ringing now or counting down a snooze.
    func ringingIDs() async throws -> Set<UUID>
    /// Silences a ringing or snoozed alarm. A repeating alarm stays set for
    /// its next time. A one-time alarm is removed.
    func stop(_ id: UUID) async throws
}

/// Small documents that must survive a restart: the ledger and the
/// acknowledgements waiting for a connection. The app keeps them in
/// Application Support. Tests keep them in memory.
public protocol DocumentStore: Sendable {
    func load(_ name: String) async throws -> Data?
    func save(_ data: Data, as name: String) async throws
    func remove(_ name: String) async throws
}

/// Where the pairing lives. The app uses the Keychain, this device only.
public protocol CredentialStore: Sendable {
    func load() async throws -> Pairing?
    func save(_ pairing: Pairing) async throws
    func remove() async throws
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.notHTTP }
        return (data, http)
    }
}
