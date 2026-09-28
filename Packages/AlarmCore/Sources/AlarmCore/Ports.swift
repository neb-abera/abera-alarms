import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends one HTTP request. The app passes URLSession. Tests pass a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The phone's alarm system. The app passes AlarmKit. Tests pass a fake.
public protocol AlarmScheduling: Sendable {
    /// The ids of the alarms the system holds for this app.
    func scheduledIDs() async throws -> Set<UUID>
    func schedule(_ alarm: DesiredAlarm) async throws
    func cancel(_ id: UUID) async throws
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
