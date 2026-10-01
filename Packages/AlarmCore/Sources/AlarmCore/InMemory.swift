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
    public private(set) var typeChanges: [String] = []
    public private(set) var routineUpdates: [Routine] = []
    public private(set) var edits: [EventEdit] = []
    public private(set) var deletions: [String] = []
    /// "<token> <environment>" as the phone last registered it.
    public private(set) var pushRegistration: String?
    public private(set) var created: [NewEvent] = []
    /// What the server says when Google refuses the write. Nil writes cleanly.
    public var calendarWriteFailure: String?
    /// A 409 detail for new events, as when no calendar has edit access.
    public var createRefusal: String?

    public init(state: AlertsState, token: String, offline: Bool = false) {
        self.state = state
        self.token = token
        self.offline = offline
    }

    public func setOffline(_ offline: Bool) { self.offline = offline }
    public func setState(_ state: AlertsState) { self.state = state }
    public func revoke() { token = "" }
    public func failCalendarWrites(_ reason: String?) { calendarWriteFailure = reason }
    public func refuseNewEvents(_ reason: String?) { createRefusal = reason }

    private func routineDraft(_ request: URLRequest) -> RoutineDraft? {
        guard let data = request.httpBody, let draft = try? JSONDecoder().decode(RoutineDraft.self, from: data),
            draft.problems.isEmpty
        else { return nil }
        return draft
    }

    private func routineIndex(_ path: String) -> Int? {
        let id = path.split(separator: "/").last.flatMap { UUID(uuidString: String($0)) }
        return state.routines.firstIndex { $0.id == id }
    }

    private func sortRoutines() {
        state.routines.sort { ($0.hour, $0.minute, $0.label) < ($1.hour, $1.minute, $1.label) }
    }

    public func setRoutines(_ routines: [Routine]) { state.routines = routines }

    static func event(of key: String) -> Substring {
        key.split(separator: "|", maxSplits: 1).first ?? Substring(key)
    }

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
        case ("PUT", "/api/alerts/phone-settings"):
            guard let data = request.httpBody,
                let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let sound = raw["sound"] as? String, PhoneSettings.sounds.contains(where: { $0.value == sound }),
                let snooze = raw["snoozeMinutes"] as? Int, (1...30).contains(snooze)
            else { return respond(request, 400, Data()) }
            state.phone = PhoneSettings(sound: sound, snoozeMinutes: snooze)
        case ("PUT", "/api/alerts/events"):
            guard let data = request.httpBody, let edit = try? ServerDates.decoder().decode(EventEdit.self, from: data)
            else { return respond(request, 400, Data()) }
            guard let index = state.alerts.firstIndex(where: { $0.key == edit.key }) else {
                return respond(request, 404, Data())
            }
            if let refusal = createRefusal {
                return respond(request, 409, Data(#"{"detail":"\#(refusal)"}"#.utf8))
            }
            let event = Self.event(of: edit.key)
            let lead = Double(edit.leadMinutes ?? state.alerts[index].leadMinutes) * 60
            let indices =
                edit.scope == .series
                ? state.alerts.indices.filter { Self.event(of: state.alerts[$0].key) == event } : [index]
            let shift = edit.startsAt.timeIntervalSince(state.alerts[index].startsAt)
            for i in indices {
                let start = state.alerts[i].startsAt.addingTimeInterval(shift)
                state.alerts[i].title = edit.title
                state.alerts[i].location = edit.location
                state.alerts[i].startsAt = start
                state.alerts[i].alertAt = start.addingTimeInterval(-lead)
                if let minutes = edit.durationMinutes {
                    state.alerts[i].endsAt = start.addingTimeInterval(Double(minutes) * 60)
                }
            }
            edits.append(edit)
        case ("POST", "/api/alerts/events/delete"):
            guard listed != nil, let scope = EditScope(rawValue: body["scope"] ?? "") else {
                return respond(request, listed == nil ? 404 : 400, Data())
            }
            if let refusal = createRefusal {
                return respond(request, 409, Data(#"{"detail":"\#(refusal)"}"#.utf8))
            }
            let event = Self.event(of: key)
            state.alerts.removeAll { scope == .series ? Self.event(of: $0.key) == event : $0.key == key }
            deletions.append("\(key) \(scope.rawValue)")
        case ("POST", "/api/alerts/routines"):
            guard let draft = routineDraft(request) else { return respond(request, 400, Data()) }
            guard state.routines.count < RoutineDraft.maxRoutines else {
                return respond(request, 409, Data(#"{"detail":"At most 50 routine alarms."}"#.utf8))
            }
            state.routines.append(
                Routine(
                    id: UUID(), label: draft.sentLabel, hour: draft.hour, minute: draft.minute, days: draft.days,
                    enabled: draft.enabled, snoozeMinutes: draft.snoozeMinutes))
            sortRoutines()
            return respond(request, 201, (try? ServerDates.encoder().encode(state)) ?? Data())
        case ("PUT", _) where path.hasPrefix("/api/alerts/routines/"):
            guard let index = routineIndex(path) else { return respond(request, 404, Data()) }
            guard let draft = routineDraft(request) else { return respond(request, 400, Data()) }
            state.routines[index].label = draft.sentLabel
            state.routines[index].hour = draft.hour
            state.routines[index].minute = draft.minute
            state.routines[index].days = draft.days
            state.routines[index].enabled = draft.enabled
            state.routines[index].snoozeMinutes = draft.snoozeMinutes
            routineUpdates.append(state.routines[index])
            sortRoutines()
        case ("DELETE", _) where path.hasPrefix("/api/alerts/routines/"):
            guard let index = routineIndex(path) else { return respond(request, 404, Data()) }
            state.routines.remove(at: index)
        case ("PUT", "/api/alerts/devices/me/push"):
            guard let token = body["apnsToken"], PushToken.isValid(token),
                let environment = body["environment"], PushEnvironment(rawValue: environment) != nil
            else { return respond(request, 400, Data()) }
            pushRegistration = "\(token) \(environment)"
            return respond(request, 204, Data())
        case ("DELETE", "/api/alerts/devices/me/push"):
            pushRegistration = nil
            return respond(request, 204, Data())
        case ("PUT", "/api/alerts/event-type"):
            guard listed != nil else { return respond(request, 404, Data()) }
            let type = body["type"] ?? ""
            guard [AlertType.alarm, AlertType.notification, AlertType.none, AlertType.default].contains(type) else {
                return respond(request, 400, Data(#"{"errors":{"type":["Not a type."]}}"#.utf8))
            }
            // Every occurrence of the event: the key is the UID, a bar, and the start.
            let event = Self.event(of: key)
            for index in state.alerts.indices where Self.event(of: state.alerts[index].key) == event {
                state.alerts[index].type = type == AlertType.default ? AlertType.none : type
                state.alerts[index].typeFrom = type == AlertType.default ? "default" : "set"
            }
            state.calendarWrite = calendarWriteFailure
            typeChanges.append("\(event) \(type)")
        case ("POST", "/api/alerts/events"):
            guard let data = request.httpBody,
                let event = try? ServerDates.decoder().decode(NewEvent.self, from: data)
            else { return respond(request, 400, Data(#"{"title":"Not an event."}"#.utf8)) }
            if let problem = event.problems(now: Date()).first {
                return respond(request, 400, Data(#"{"errors":{"event":["\#(problem)"]}}"#.utf8))
            }
            if let refusal = createRefusal {
                return respond(request, 409, Data(#"{"detail":"\#(refusal)"}"#.utf8))
            }
            created.append(event)
            let lead = Double(event.leadMinutes ?? 10) * 60
            state.alerts.append(
                PlannedAlert(
                    key: "created-\(created.count)|\(event.startsAt.timeIntervalSince1970)",
                    title: event.title, location: event.location, startsAt: event.startsAt,
                    alertAt: event.startsAt.addingTimeInterval(-lead), type: event.type, typeFrom: "set"))
            state.alerts.sort { $0.alertAt < $1.alertAt }
            state.calendarWrite = calendarWriteFailure
            return respond(request, 201, (try? ServerDates.encoder().encode(state)) ?? Data())
        default:
            return respond(request, 404, Data())
        }
        return respond(request, 200, (try? ServerDates.encoder().encode(state)) ?? Data())
    }

    private func respond(_ request: URLRequest, _ status: Int, _ data: Data) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
