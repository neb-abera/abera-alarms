import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// In-memory stand-ins for the server and the phone. The unit tests use them,
// and the app's UI tests launch with them (`-demo`) so the suite needs
// neither abera.tech nor a real alarm.

public actor MemoryDocuments: DocumentStore {
    var files: [String: Data] = [:]

    public init() {}

    public func load(_ name: String) -> Data? { files[name] }
    public func save(_ data: Data, as name: String) { files[name] = data }
    public func remove(_ name: String) { files[name] = nil }
}

public actor MemoryCredentials: CredentialStore {
    var pairing: Pairing?

    public init(_ pairing: Pairing? = nil) { self.pairing = pairing }

    public func load() -> Pairing? { pairing }
    public func save(_ pairing: Pairing) { self.pairing = pairing }
    public func remove() { pairing = nil }
}

public struct AlarmSystemError: Error, Equatable, Sendable {}

public actor MemoryAlarms: AlarmScheduling {
    public private(set) var alarms: [UUID: DesiredAlarm] = [:]
    /// Keys the system refuses, as a full alarm list would.
    var refusing: Set<String> = []

    public init() {}

    public func scheduledIDs() -> Set<UUID> { Set(alarms.keys) }

    public func schedule(_ alarm: DesiredAlarm) throws {
        if refusing.contains(alarm.key) { throw AlarmSystemError() }
        alarms[alarm.id] = alarm
    }

    public func cancel(_ id: UUID) { alarms[id] = nil }

    /// The alarm went off and the owner stopped it: the system drops it.
    public func ring(_ id: UUID) { alarms[id] = nil }

    public func refuse(_ key: String) { refusing.insert(key) }
}

/// abera.tech's alerts API in memory: the same routes, the same answers.
public actor FakeAlertsServer: HTTPTransport {
    public var state: AlertsState
    public var token: String
    public var offline = false
    public private(set) var requests: [String] = []
    public private(set) var acknowledgements: [String] = []

    public init(state: AlertsState, token: String, offline: Bool = false) {
        self.state = state
        self.token = token
        self.offline = offline
    }

    public func setOffline(_ offline: Bool) { self.offline = offline }
    public func setState(_ state: AlertsState) { self.state = state }
    public func revoke() { token = "" }

    public func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard !offline else { throw URLError(.notConnectedToInternet) }
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        requests.append("\(method) \(path)")

        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)", !token.isEmpty else {
            return respond(request, 401, Data())
        }

        let body = request.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let key = body["key"] ?? ""
        let listed = state.alerts.firstIndex { $0.key == key }

        switch (method, path) {
        case ("GET", "/api/alerts/status"):
            break
        case ("POST", "/api/alerts/ack"):
            guard let index = listed else { return respond(request, 404, Data()) }
            state.alerts[index].acknowledged = true
            state.alerts[index].acknowledgedVia = body["via"]
            acknowledgements.append(key)
        case ("POST", "/api/alerts/skip"):
            guard let index = listed else { return respond(request, 404, Data()) }
            state.alerts[index].skipped = true
        case ("POST", "/api/alerts/unskip"):
            if let index = listed { state.alerts[index].skipped = false }
        case ("POST", "/api/alerts/mute"):
            let now = Date()
            let until = body["until"] == "hour" ? now.addingTimeInterval(3600) : now.addingTimeInterval(12 * 3600)
            state.mutedUntil = until
            for index in state.alerts.indices { state.alerts[index].muted = state.alerts[index].alertAt < until }
        case ("POST", "/api/alerts/unmute"):
            state.mutedUntil = nil
            for index in state.alerts.indices { state.alerts[index].muted = false }
        default:
            return respond(request, 404, Data())
        }
        return respond(request, 200, (try? ServerDates.encoder().encode(state)) ?? Data())
    }

    private func respond(_ request: URLRequest, _ status: Int, _ data: Data) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
