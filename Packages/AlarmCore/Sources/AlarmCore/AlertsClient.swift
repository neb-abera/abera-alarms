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
    /// 400 or 409 on a new event or a type change, with the server's reason.
    case refused(String)
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
        try await call("POST", "unmute", body: [String: String]())
    }

    /// Alarm, notification or none for every occurrence of the event, or
    /// "default" to drop the choice. abera.tech writes an alarm back to
    /// Google Calendar as #critical.
    public func setType(key: String, type: String) async throws(APIError) -> AlertsState {
        try await call("PUT", "event-type", body: ["key": key, "type": type])
    }

    /// A new event on the connected Google calendar, planned at once.
    public func createEvent(_ event: NewEvent) async throws(APIError) -> AlertsState {
        try await call("POST", "events", body: event)
    }

    /// Changes the event in Google Calendar through abera.tech.
    public func updateEvent(_ edit: EventEdit) async throws(APIError) -> AlertsState {
        try await call("PUT", "events", body: edit)
    }

    /// Deletes this occurrence, or the whole series, from Google Calendar.
    public func deleteEvent(key: String, scope: EditScope) async throws(APIError) -> AlertsState {
        try await call("POST", "events/delete", body: ["key": key, "scope": scope.rawValue])
    }

    /// The sound every alarm plays and the calendar alarms' snooze.
    public func updatePhoneSettings(_ settings: PhoneSettings) async throws(APIError) -> AlertsState {
        try await call("PUT", "phone-settings", body: settings.body)
    }

    public func createRoutine(_ draft: RoutineDraft) async throws(APIError) -> AlertsState {
        try await call("POST", "routines", body: draft.body)
    }

    public func updateRoutine(id: UUID, _ draft: RoutineDraft) async throws(APIError) -> AlertsState {
        try await call("PUT", "routines/\(id.uuidString.lowercased())", body: draft.body)
    }

    public func deleteRoutine(id: UUID) async throws(APIError) -> AlertsState {
        try await call("DELETE", "routines/\(id.uuidString.lowercased())", body: nil)
    }

    /// Where abera.tech sends a push when this phone's alarms change.
    public func registerPush(token: String, environment: PushEnvironment) async throws(APIError) {
        try await callNoContent(
            "PUT", "devices/me/push", body: ["apnsToken": token, "environment": environment.rawValue])
    }

    /// Stops the pushes, on Unpair.
    public func unregisterPush() async throws(APIError) {
        try await callNoContent("DELETE", "devices/me/push", body: nil)
    }

    func request(_ method: String, _ action: String, body: (any Encodable & Sendable)?) -> URLRequest {
        var request = URLRequest(url: pairing.server.appending(path: "api/alerts/\(action)"))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? ServerDates.encoder().encode(body)
        }
        return request
    }

    private func call(_ method: String, _ action: String, body: (any Encodable & Sendable)?) async throws(APIError)
        -> AlertsState
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
        case 200, 201:
            guard data.count <= Self.maxResponseBytes,
                let state = try? ServerDates.decoder().decode(AlertsState.self, from: data)
            else { throw .badResponse }
            return state
        case 401: throw .unpaired
        case 404: throw .notFound
        case 400, 409: throw .refused(Self.reason(data))
        case 429: throw .rateLimited
        default: throw .status(response.statusCode)
        }
    }

    private func callNoContent(_ method: String, _ action: String, body: (any Encodable & Sendable)?)
        async throws(APIError)
    {
        let response: HTTPURLResponse
        do {
            (_, response) = try await transport.send(request(method, action, body: body))
        } catch let error as APIError {
            throw error
        } catch {
            throw .offline
        }
        switch response.statusCode {
        case 200, 204: return
        case 401: throw .unpaired
        case 404: throw .notFound
        case 429: throw .rateLimited
        default: throw .status(response.statusCode)
        }
    }

    /// The server's reason from a ValidationProblem or a problem detail,
    /// cut to one line a person can read.
    static func reason(_ data: Data) -> String {
        struct Problem: Decodable {
            var detail: String?
            var title: String?
            var errors: [String: [String]]?
        }
        guard data.count <= 64_000, let problem = try? JSONDecoder().decode(Problem.self, from: data) else {
            return "abera.tech refused the request."
        }
        let first = problem.errors?.sorted { $0.key < $1.key }.first?.value.first
        let text = problem.detail ?? first ?? problem.title ?? "abera.tech refused the request."
        return String(text.prefix(200))
    }
}

/// Which APNs host abera.tech must use for this build: an Xcode install
/// is "sandbox", TestFlight and the App Store are "production".
public enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

/// An APNs device token as the server stores it: lowercase hex.
public enum PushToken {
    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func isValid(_ text: String) -> Bool {
        (64...200).contains(text.utf8.count)
            && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}

/// Which part of a repeating event a change covers.
public enum EditScope: String, Codable, Sendable, CaseIterable {
    case occurrence
    case series
}

/// What the phone sends to change an event.
public struct EventEdit: Codable, Equatable, Sendable {
    public var key: String
    public var scope: EditScope
    public var title: String
    public var startsAt: Date
    /// Nil keeps the event's length.
    public var durationMinutes: Int?
    public var location: String?
    public var leadMinutes: Int?

    public init(
        key: String, scope: EditScope, title: String, startsAt: Date, durationMinutes: Int?, location: String?,
        leadMinutes: Int?
    ) {
        self.key = key
        self.scope = scope
        self.title = title
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.location = location
        self.leadMinutes = leadMinutes
    }

    /// Location is always sent: null clears it on the server, where a
    /// missing field would leave the old one in place.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(scope, forKey: .scope)
        try container.encode(title, forKey: .title)
        try container.encode(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(leadMinutes, forKey: .leadMinutes)
    }

    /// The bounds the server checks, so the editor can say what is wrong first.
    public func problems(now: Date) -> [String] {
        var problems: [String] = []
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { problems.append("Give the event a title.") }
        if title.count > 200 { problems.append("The title is longer than 200 characters.") }
        if startsAt <= now { problems.append("The start is in the past.") }
        if let durationMinutes, !(5...1440).contains(durationMinutes) {
            problems.append("The length must be 5 minutes to 24 hours.")
        }
        if let location, location.count > 200 { problems.append("The location is longer than 200 characters.") }
        if let leadMinutes, !(0...1440).contains(leadMinutes) {
            problems.append("The alert must be 0 to 1440 minutes before the start.")
        }
        return problems
    }
}

/// What the phone sends to make a new event.
public struct NewEvent: Codable, Equatable, Sendable {
    public var title: String
    public var startsAt: Date
    public var durationMinutes: Int
    public var location: String?
    public var type: String
    public var leadMinutes: Int?

    public init(
        title: String, startsAt: Date, durationMinutes: Int, location: String?, type: String, leadMinutes: Int?
    ) {
        self.title = title
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.location = location
        self.type = type
        self.leadMinutes = leadMinutes
    }

    /// The same bounds the server checks, so the form can say what is wrong
    /// before it sends. Empty when the event can be sent.
    public func problems(now: Date) -> [String] {
        var problems: [String] = []
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { problems.append("Give the event a title.") }
        if title.count > 200 { problems.append("The title is longer than 200 characters.") }
        if startsAt <= now { problems.append("The start is in the past.") }
        if startsAt > now.addingTimeInterval(366 * 86_400) { problems.append("The start is more than a year away.") }
        if !(5...1440).contains(durationMinutes) { problems.append("The length must be 5 minutes to 24 hours.") }
        if let location, location.count > 200 { problems.append("The location is longer than 200 characters.") }
        if ![AlertType.alarm, AlertType.notification, AlertType.none].contains(type) {
            problems.append("Choose Alarm, Notification or None.")
        }
        if let leadMinutes, !(0...1440).contains(leadMinutes) {
            problems.append("The alert must be 0 to 1440 minutes before the start.")
        }
        return problems
    }
}
