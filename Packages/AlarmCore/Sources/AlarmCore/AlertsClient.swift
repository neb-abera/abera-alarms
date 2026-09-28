import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum APIError: Error, Equatable, Sendable {
    /// 401: the token was revoked or never existed. The phone must pair again.
    case unpaired
    /// 404 on an action: the alert is no longer on the server's list.
    case notFound
    case rateLimited
    case status(Int)
    case badResponse
    case notHTTP
    /// No connection, a timeout, DNS: worth trying again later.
    case offline
}

/// How the phone was told an alert is done.
public enum AcknowledgedVia: String, Codable, Sendable {
    case phone
}

/// abera.tech's alerts API, with the phone's device token.
///
/// Every action answers with the page's whole state, as the page's own
/// buttons do, so the phone never shows a mute or a skip the server did
/// not store.
public struct AlertsClient: Sendable {
    public static let maxResponseBytes = 1_000_000

    public let pairing: Pairing
    let transport: any HTTPTransport

    public init(pairing: Pairing, transport: any HTTPTransport) {
        self.pairing = pairing
        self.transport = transport
    }

    public func status() async throws(APIError) -> AlertsState {
        try await call("GET", "status", body: nil)
    }

    public func acknowledge(key: String) async throws(APIError) -> AlertsState {
        try await call("POST", "ack", body: ["key": key, "via": AcknowledgedVia.phone.rawValue])
    }

    public func skip(key: String) async throws(APIError) -> AlertsState {
        try await call("POST", "skip", body: ["key": key])
    }

    public func unskip(key: String) async throws(APIError) -> AlertsState {
        try await call("POST", "unskip", body: ["key": key])
    }

    public enum MuteLength: String, Sendable {
        case hour
        case morning
    }

    public func mute(_ length: MuteLength) async throws(APIError) -> AlertsState {
        try await call("POST", "mute", body: ["until": length.rawValue])
    }

    public func unmute() async throws(APIError) -> AlertsState {
        try await call("POST", "unmute", body: [:])
    }

    func request(_ method: String, _ action: String, body: [String: String]?) -> URLRequest {
        var request = URLRequest(url: pairing.server.appending(path: "api/alerts/\(action)"))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private func call(_ method: String, _ action: String, body: [String: String]?) async throws(APIError) -> AlertsState
    {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request(method, action, body: body))
        } catch let error as APIError {
            throw error
        } catch {
            throw .offline
        }

        switch response.statusCode {
        case 200:
            guard data.count <= Self.maxResponseBytes,
                let state = try? ServerDates.decoder().decode(AlertsState.self, from: data)
            else { throw .badResponse }
            return state
        case 401: throw .unpaired
        case 404: throw .notFound
        case 429: throw .rateLimited
        default: throw .status(response.statusCode)
        }
    }
}
