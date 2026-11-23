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
    /// Alarms ringing or snoozed now.
    var ringing: Set<UUID> = []
    /// Every stop, in order.
    public private(set) var stops: [UUID] = []
    var ringingUnreadable = false
    var systemUnreadable = false

    public init() {}

    public func scheduledIDs() throws -> Set<UUID> {
        if systemUnreadable { throw AlarmSystemError() }
        return Set(alarms.keys)
    }

    public func schedule(_ alarm: DesiredAlarm) throws {
        if refusing.contains(alarm.key) { throw AlarmSystemError() }
        alarms[alarm.id] = alarm
    }

    public func cancel(_ id: UUID) {
        alarms[id] = nil
        ringing.remove(id)
    }

    public func ringingIDs() throws -> Set<UUID> {
        if ringingUnreadable { throw AlarmSystemError() }
        return ringing.intersection(alarms.keys)
    }

    /// As AlarmKit's stop: a repeating routine stays set, anything else goes.
    public func stop(_ id: UUID) throws {
        guard alarms[id] != nil else { throw AlarmSystemError() }
        stops.append(id)
        ringing.remove(id)
        if alarms[id]?.routine?.days.isEmpty != false { alarms[id] = nil }
    }

    /// The alarm's time came: it rings until stopped or snoozed.
    public func startRinging(_ id: UUID) { ringing.insert(id) }

    public func failRingingReads() { ringingUnreadable = true }

    /// The alarm system cannot be read, as when the owner has not allowed alarms.
    public func failSystemReads() { systemUnreadable = true }

    /// The alarm went off and the owner stopped it: the system drops it.
    public func ring(_ id: UUID) { alarms[id] = nil }

    public func refuse(_ key: String) { refusing.insert(key) }
}

/// The system's background uploads in memory. A request waits until
/// `deliver` sends it, as iOS sends one after the app is suspended.
public actor MemoryUploads: BackgroundUploading {
    public struct Upload: Sendable {
        public let label: String
        public let request: URLRequest
    }

    public private(set) var waiting: [Upload] = []
    var refusing = false

    public init() {}

    /// The system will not take an upload, as with no disk space.
    public func refuse() { refusing = true }

    public func upload(_ request: URLRequest, label: String) throws {
        if refusing { throw URLError(.cannotCreateFile) }
        waiting.append(Upload(label: label, request: request))
    }

    /// Sends every waiting upload. Each label comes back with the status,
    /// nil when there was no connection, and the upload is done.
    public func deliver(to server: any HTTPTransport) async -> [(label: String, status: Int?)] {
        var results: [(label: String, status: Int?)] = []
        for upload in waiting {
            let status = try? await server.send(upload.request).1.statusCode
            results.append((upload.label, status))
        }
        waiting = []
        return results
    }
}

/// abera.tech's alerts API in memory: the same routes, the same answers.
public actor FakeAlertsServer: HTTPTransport {
    public var state: AlertsState
    public var token: String
    public var offline = false
    /// How long each request takes, as on a slow or failing connection.
    public var latency: Duration = .zero
    public private(set) var requests: [String] = []
    public private(set) var acknowledgements: [String] = []
    /// The X-Time-Zone of every request.
    public private(set) var timeZones: [String] = []
    public private(set) var typeChanges: [String] = []
    public private(set) var routineUpdates: [Routine] = []
    public private(set) var routineDeletes: [UUID] = []
    public private(set) var edits: [EventEdit] = []
    public private(set) var deletions: [String] = []
    /// "<token> <environment>" as the phone last registered it.
    public private(set) var pushRegistration: String?
    public private(set) var created: [NewEvent] = []
    /// What the server says when Google refuses the write. Nil writes cleanly.
    public var calendarWriteFailure: String?
    /// A 409 detail for new events, as when no calendar has edit access.
    public var createRefusal: String?
    /// The server's clock, for the bounds an edit is checked against.
    private let now: @Sendable () -> Date

    public init(
        state: AlertsState, token: String, offline: Bool = false, latency: Duration = .zero,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.state = state
        self.token = token
        self.offline = offline
        self.latency = latency
        self.now = now
    }

    /// As abera.tech resolves a type: an event with no choice of its own
    /// and no #critical mark takes the first rule that matches, else the
    /// default, which the demo holds as none.
    private func applyRules() {
        for index in state.alerts.indices where [nil, "default", "rule"].contains(state.alerts[index].typeFrom) {
            let alert = state.alerts[index]
            if let rule = state.rules.first(where: {
                $0.matches(title: alert.title, organizer: nil, location: alert.location)
            }) {
                state.alerts[index].type = rule.type
                state.alerts[index].typeFrom = "rule"
            } else if alert.typeFrom == "rule" {
                state.alerts[index].type = AlertType.none
                state.alerts[index].typeFrom = "default"
            }
        }
    }

    public func setOffline(_ offline: Bool) { self.offline = offline }
    public func setLatency(_ latency: Duration) { self.latency = latency }
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

    /// The zone abera.tech plans in: the phone's.
    public private(set) var calendar = Calendar.current
    public func setCalendar(_ calendar: Calendar) { self.calendar = calendar }

    static func hasKey(_ key: String, in request: URLRequest) -> Bool {
        guard let data = request.httpBody,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object[key] != nil && !(object[key] is NSNull)
    }

    /// A check-off as abera.tech stores it.
    public struct StoredCompletion: Sendable, Equatable {
        public var id: UUID
        public var routineId: UUID
        public var stepId: UUID
        public var cycle: String
        public var completedAt: Date
        public var note: String?
        public var photo: Data?

        public init(
            id: UUID, routineId: UUID, stepId: UUID, cycle: String, completedAt: Date, note: String? = nil,
            photo: Data? = nil
        ) {
            self.id = id
            self.routineId = routineId
            self.stepId = stepId
            self.cycle = cycle
            self.completedAt = completedAt
            self.note = note
            self.photo = photo
        }
    }

    public private(set) var completions: [StoredCompletion] = []

    public func setCompletions(_ completions: [StoredCompletion]) {
        self.completions = completions
        publishCompletions()
    }

    private func publishCompletions() {
        state.routineCompletions = completions.map {
            RoutineCompletion(
                routineId: $0.routineId, stepId: $0.stepId, cycle: $0.cycle, completedAt: $0.completedAt, id: $0.id,
                note: $0.note, hasPhoto: $0.photo != nil)
        }
    }

    private struct CompletionRequest: Decodable {
        var note: String?
        var photo: String?
        var completedAt: Date?
    }

    private struct OutcomeRequest: Decodable {
        var status: String
        var note: String?
        var at: Date?
    }

    /// PUT or DELETE `routines/{id}/cycles/{cycle}/delay`. A delay makes the
    /// cycle's rings still ahead ring again, as abera.tech does.
    private func delay(_ request: URLRequest, path: String, remove: Bool) -> (Data, HTTPURLResponse) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 7, let routineId = UUID(uuidString: parts[3]),
            state.routines.contains(where: { $0.id == routineId })
        else { return respond(request, 404, Data()) }
        let cycle = parts[5].removingPercentEncoding ?? parts[5]
        state.routineDelays.removeAll { $0.routineId == routineId && $0.cycle == cycle }
        if !remove {
            guard let data = request.httpBody, let body = try? JSONDecoder().decode(DelayBody.self, from: data),
                RoutineDelay.minutes.contains(body.minutes)
            else { return respond(request, 400, Data(#"{"errors":{"minutes":["1 to 720."]}}"#.utf8)) }
            state.routineDelays.append(
                RoutineDelay(routineId: routineId, cycle: cycle, minutes: body.minutes, at: now()))
            let prefix = RoutineCycle.parentKey(routineID: routineId, stamp: cycle)
            for index in state.routineRings.indices where state.routineRings[index].key.hasPrefix(prefix) {
                state.routineRings[index].alertAt += TimeInterval(body.minutes * 60)
                state.routineRings[index].acknowledged = false
            }
        }
        return respond(request, 200, (try? ServerDates.encoder().encode(state)) ?? Data())
    }

    /// PUT or DELETE `routines/{id}/cycles/{cycle}/outcome`.
    private func outcome(_ request: URLRequest, path: String, remove: Bool) -> (Data, HTTPURLResponse) {
        let parts = path.split(separator: "/").map(String.init)
        // api alerts routines {id} cycles {cycle} outcome
        guard parts.count == 7, let routineId = UUID(uuidString: parts[3]),
            state.routines.contains(where: { $0.id == routineId })
        else { return respond(request, 404, Data()) }
        let cycle = parts[5].removingPercentEncoding ?? parts[5]
        state.routineOutcomes.removeAll { $0.routineId == routineId && $0.cycle == cycle }
        if !remove {
            guard let data = request.httpBody,
                let body = try? ServerDates.decoder().decode(OutcomeRequest.self, from: data),
                let status = RoutineOutcome.Status(rawValue: body.status)
            else { return respond(request, 400, Data(#"{"errors":{"status":["done or skipped."]}}"#.utf8)) }
            state.routineOutcomes.append(
                RoutineOutcome(
                    routineId: routineId, cycle: cycle, status: status, at: body.at ?? now(), note: body.note))
        }
        return respond(request, 200, (try? ServerDates.encoder().encode(state)) ?? Data())
    }

    /// PUT or DELETE `routines/{id}/steps/{stepId}/cycles/{cycle}/completion`.
    private func completion(_ request: URLRequest, path: String, remove: Bool) -> (Data, HTTPURLResponse) {
        let parts = path.split(separator: "/").map(String.init)
        // api alerts routines {id} steps {stepId} cycles {cycle} completion
        guard parts.count == 9, let routineId = UUID(uuidString: parts[3]), let stepId = UUID(uuidString: parts[5])
        else { return respond(request, 404, Data()) }
        let cycle = parts[7].removingPercentEncoding ?? parts[7]
        guard let routine = state.routines.first(where: { $0.id == routineId }),
            routine.steps.contains(where: { $0.id == stepId })
        else { return respond(request, 404, Data()) }
        let existing = completions.firstIndex { $0.routineId == routineId && $0.stepId == stepId && $0.cycle == cycle }
        if remove {
            if let existing { completions.remove(at: existing) }
        } else {
            guard let data = request.httpBody,
                let body = try? ServerDates.decoder().decode(CompletionRequest.self, from: data)
            else { return respond(request, 400, Data()) }
            var photo: Data? = existing.flatMap { completions[$0].photo }
            if let text = body.photo {
                if text.isEmpty {
                    photo = nil
                } else {
                    guard let bytes = Data(base64Encoded: text), CompletionDraft.isJPEG(bytes),
                        bytes.count <= CompletionDraft.maxPhotoBytes
                    else {
                        return respond(request, 400, Data(#"{"errors":{"photo":["A JPEG of at most 2 MB."]}}"#.utf8))
                    }
                    photo = bytes
                }
            }
            let stored = StoredCompletion(
                id: existing.map { completions[$0].id } ?? UUID(), routineId: routineId, stepId: stepId, cycle: cycle,
                completedAt: body.completedAt ?? now(), note: body.note, photo: photo)
            if let existing { completions[existing] = stored } else { completions.append(stored) }
        }
        publishCompletions()
        return respond(request, 200, (try? ServerDates.encoder().encode(state)) ?? Data())
    }

    /// Two weeks of cycles of the routines with steps, newest first.
    func history() -> RoutineHistory {
        let at = now()
        let from = at.addingTimeInterval(-Double(RoutineHistory.days) * 86_400)
        let acknowledged = Dictionary(
            state.routineRings.filter(\.acknowledged).map { ($0.key, $0.acknowledgedAt ?? at) },
            uniquingKeysWith: { first, _ in first })
        var cycles: [RoutineHistory.Cycle] = []
        for routine in state.routines where !routine.steps.isEmpty {
            var ring = routine.schedule.nextFire(after: from, calendar: calendar)
            while let time = ring, time <= at {
                let cycle = RoutineCycle.make(routine, at: time, calendar: calendar)
                cycles.append(
                    RoutineHistory.Cycle(
                        routineId: routine.id, label: routine.label, cycle: cycle.stamp, at: time,
                        acknowledgedAt: acknowledged[cycle.key],
                        steps: cycle.steps.map { step in
                            let done = completions.first {
                                $0.routineId == routine.id && $0.stepId == step.step.id && $0.cycle == cycle.stamp
                            }
                            return RoutineHistory.Step(
                                stepId: step.step.id, label: step.step.sentLabel, at: step.at,
                                acknowledgedAt: acknowledged[step.key],
                                completion: done.map {
                                    RoutineHistory.Completion(
                                        id: $0.id, completedAt: $0.completedAt, note: $0.note, hasPhoto: $0.photo != nil
                                    )
                                })
                        },
                        outcome: state.routineOutcomes.first {
                            $0.routineId == routine.id && $0.cycle == cycle.stamp
                        }.map { RoutineHistory.Outcome(status: $0.status, at: $0.at, note: $0.note) }))
                guard routine.repeats else { break }
                ring = routine.schedule.nextFire(after: time, calendar: calendar)
            }
        }
        return RoutineHistory(cycles: cycles.sorted { $0.at > $1.at })
    }

    /// A countdown body checked as abera.tech checks it: nil and a 400 problem
    /// keyed by field when it is refused.
    private func countdownDraft(_ request: URLRequest) -> (CountdownDraft?, Data) {
        guard let data = request.httpBody,
            let draft = try? ServerDates.decoder().decode(CountdownDraft.self, from: data)
        else { return (nil, Data(#"{"title":"Not a countdown."}"#.utf8)) }
        if let problem = draft.problems.first {
            let field = problem.contains("zone") ? "timeZone" : problem.contains("date") ? "targetAt" : "label"
            return (nil, Data(#"{"errors":{"\#(field)":["\#(problem)"]}}"#.utf8))
        }
        return (draft, Data())
    }

    private func countdownIndex(_ path: String) -> Int? {
        let id = path.split(separator: "/").last.flatMap { UUID(uuidString: String($0)) }
        return state.countdowns.firstIndex { $0.id == id }
    }

    private func sortCountdowns() {
        state.countdowns.sort { ($0.targetAt, $0.label) < ($1.targetAt, $1.label) }
    }

    static func event(of key: String) -> Substring {
        key.split(separator: "|", maxSplits: 1).first ?? Substring(key)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if latency > .zero { try? await Task.sleep(for: latency) }
        guard !offline else { throw URLError(.notConnectedToInternet) }
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        requests.append("\(method) \(path)")
        timeZones.append(request.value(forHTTPHeaderField: "X-Time-Zone") ?? "")

        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)", !token.isEmpty else {
            return respond(request, 401, Data())
        }

        let body = request.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let key = body["key"] ?? ""
        let listed = state.alerts.firstIndex { $0.key == key }

        switch (method, path) {
        case ("GET", "/api/alerts/status"):
            break
        case ("POST", "/api/alerts/ack") where key.hasPrefix(DesiredAlarm.routinePrefix):
            guard let index = state.routineRings.firstIndex(where: { $0.key == key }) else {
                return respond(request, 404, Data())
            }
            state.routineRings[index].acknowledged = true
            state.routineRings[index].acknowledgedAt = Date()
            state.routineRings[index].acknowledgedVia = body["via"]
            acknowledgements.append(key)
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
        case ("PUT", "/api/alerts/rules"):
            guard let data = request.httpBody, let body = try? JSONDecoder().decode(RulesRequest.self, from: data),
                TypeRule.problems(body.rules).isEmpty,
                body.rules.allSatisfy({ [AlertType.alarm, AlertType.notification, AlertType.none].contains($0.type) })
            else { return respond(request, 400, Data()) }
            state.rules = body.rules.map(\.trimmed)
            applyRules()
        case ("PUT", "/api/alerts/events"):
            guard let data = request.httpBody, let edit = try? ServerDates.decoder().decode(EventEdit.self, from: data)
            else { return respond(request, 400, Data()) }
            guard let index = state.alerts.firstIndex(where: { $0.key == edit.key }) else {
                return respond(request, 404, Data())
            }
            // abera.tech's bounds: a started event may keep its own start.
            if let problem = edit.problems(now: now(), listedStart: state.alerts[index].startsAt).first {
                return respond(request, 400, Data(#"{"errors":{"startsAt":["\#(problem)"]}}"#.utf8))
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
        case ("PUT", _) where path.hasSuffix("/delay"):
            return delay(request, path: path, remove: false)
        case ("DELETE", _) where path.hasSuffix("/delay"):
            return delay(request, path: path, remove: true)
        case ("PUT", _) where path.hasSuffix("/outcome"):
            return outcome(request, path: path, remove: false)
        case ("DELETE", _) where path.hasSuffix("/outcome"):
            return outcome(request, path: path, remove: true)
        case ("PUT", _) where path.hasSuffix("/completion"):
            return completion(request, path: path, remove: false)
        case ("DELETE", _) where path.hasSuffix("/completion"):
            return completion(request, path: path, remove: true)
        case ("GET", "/api/alerts/history"):
            return respond(request, 200, (try? ServerDates.encoder().encode(history())) ?? Data())
        case ("GET", _) where path.hasPrefix("/api/alerts/completions/") && path.hasSuffix("/photo"):
            let id = path.split(separator: "/").dropLast().last.flatMap { UUID(uuidString: String($0)) }
            guard let id, let photo = completions.first(where: { $0.id == id })?.photo else {
                return respond(request, 404, Data())
            }
            return respond(request, 200, photo)
        case ("POST", "/api/alerts/routines"):
            guard let draft = routineDraft(request) else { return respond(request, 400, Data()) }
            guard state.routines.count < RoutineDraft.maxRoutines else {
                return respond(request, 409, Data(#"{"detail":"At most 50 routine alarms."}"#.utf8))
            }
            state.routines.append(
                Routine(
                    id: UUID(), label: draft.sentLabel, hour: draft.hour, minute: draft.minute, days: draft.days,
                    enabled: draft.enabled, snoozeMinutes: draft.snoozeMinutes, steps: draft.steps.map(\.sent),
                    updatedAt: now()))
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
            // As abera.tech: a body with no steps keeps the ones stored.
            if Self.hasKey("steps", in: request) { state.routines[index].steps = draft.steps.map(\.sent) }
            state.routines[index].updatedAt = now()
            routineUpdates.append(state.routines[index])
            sortRoutines()
        case ("DELETE", _) where path.hasPrefix("/api/alerts/routines/"):
            guard let index = routineIndex(path) else { return respond(request, 404, Data()) }
            routineDeletes.append(state.routines[index].id)
            state.routines.remove(at: index)
        case ("POST", "/api/alerts/countdowns"):
            let (draft, problem) = countdownDraft(request)
            guard let draft else { return respond(request, 400, problem) }
            guard state.countdowns.count < CountdownDraft.maxCountdowns else {
                return respond(request, 409, Data(#"{"detail":"At most 50 countdowns."}"#.utf8))
            }
            state.countdowns.append(
                Countdown(
                    id: UUID(), label: draft.sentLabel, targetAt: draft.targetAt, timeZone: draft.timeZone,
                    updatedAt: Date(), alarm: draft.alarm, onCalendar: true, repeats: draft.repeats,
                    repeatEvery: draft.repeatEvery))
            sortCountdowns()
            return respond(request, 201, (try? ServerDates.encoder().encode(state)) ?? Data())
        case ("PUT", _) where path.hasPrefix("/api/alerts/countdowns/"):
            guard let index = countdownIndex(path) else { return respond(request, 404, Data()) }
            let (draft, problem) = countdownDraft(request)
            guard let draft else { return respond(request, 400, problem) }
            state.countdowns[index].label = draft.sentLabel
            state.countdowns[index].targetAt = draft.targetAt
            state.countdowns[index].timeZone = draft.timeZone
            state.countdowns[index].alarm = draft.alarm
            state.countdowns[index].repeats = draft.repeats
            state.countdowns[index].repeatEvery = draft.repeatEvery
            state.countdowns[index].onCalendar = true
            state.countdowns[index].updatedAt = Date()
            sortCountdowns()
        case ("DELETE", _) where path.hasPrefix("/api/alerts/countdowns/"):
            guard let index = countdownIndex(path) else { return respond(request, 404, Data()) }
            state.countdowns.remove(at: index)
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
                    alertAt: event.startsAt.addingTimeInterval(-lead), type: event.type, typeFrom: "set",
                    endsAt: event.startsAt.addingTimeInterval(Double(event.durationMinutes) * 60)))
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

/// What PUT /api/alerts/rules carries.
private struct RulesRequest: Decodable {
    var rules: [TypeRule]
}
