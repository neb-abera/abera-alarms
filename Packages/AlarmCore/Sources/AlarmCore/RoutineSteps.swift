import Foundation

/// A sub-alarm of a routine: "Take medication" 5 minutes after "Wake up".
/// Each step rings as its own alarm, a set number of minutes after the
/// item before it (the routine's own ring for the first step).
public struct RoutineStep: Codable, Equatable, Hashable, Sendable, Identifiable {
    public static let defaultLabel = "Step"
    public static let maxSteps = 20
    public static let maxLabelLength = 60
    /// Each offset, and all of them together, stay within a day.
    public static let maxOffsetMinutes = 1440

    /// A step rings at most this many days apart.
    public static let maxEveryDays = 365

    /// The phone makes the id, so a step added offline keeps it on abera.tech.
    public var id: UUID
    public var label: String
    /// Minutes after the item before it: 0 to 1440.
    public var offsetMinutes: Int
    /// 1 rings at every ring of its alarm. 2 rings every other day from
    /// `startsOn`. Neb asked on 2026-11-26 for one night routine with
    /// tretinoin and night serum on alternate nights.
    public var everyDays: Int
    /// "yyyy-MM-dd", the first day it rings, when `everyDays` is above 1.
    public var startsOn: String?

    public init(id: UUID = UUID(), label: String, offsetMinutes: Int, everyDays: Int = 1, startsOn: String? = nil) {
        self.id = id
        self.label = label
        self.offsetMinutes = offsetMinutes
        self.everyDays = everyDays
        self.startsOn = startsOn
    }

    enum CodingKeys: String, CodingKey { case id, label, offsetMinutes, everyDays, startsOn }

    /// An older server sends no everyDays: every ring.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        offsetMinutes = try container.decode(Int.self, forKey: .offsetMinutes)
        everyDays = try container.decodeIfPresent(Int.self, forKey: .everyDays) ?? 1
        startsOn = try container.decodeIfPresent(String.self, forKey: .startsOn)
    }

    /// True when it rings with its alarm's ring on the local day `date`
    /// falls on: every ring, or a whole number of `everyDays` from
    /// `startsOn`, before or after it.
    public func ringsOn(_ date: Date, calendar: Calendar) -> Bool {
        guard everyDays > 1, let first = startsOn.flatMap({ StepDays.date($0, calendar: calendar) }) else {
            return true
        }
        let days = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: date)).day ?? 0
        return ((days % everyDays) + everyDays) % everyDays == 0
    }

    /// "every 2 days from Fri 27 Nov", or nil for every ring.
    public func everyWords(calendar: Calendar = .current) -> String? {
        guard everyDays > 1, let first = startsOn.flatMap({ StepDays.date($0, calendar: calendar) }) else { return nil }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return "every \(everyDays) days from \(first.formatted(style))"
    }

    /// The label as sent: trimmed, and "Step" when empty.
    public var sentLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel : trimmed
    }

    var sent: RoutineStep {
        RoutineStep(
            id: id, label: sentLabel, offsetMinutes: offsetMinutes, everyDays: everyDays,
            startsOn: everyDays > 1 ? startsOn : nil)
    }

    /// The same bounds abera.tech checks.
    public static func problems(_ steps: [RoutineStep]) -> [String] {
        var problems: [String] = []
        if steps.count > maxSteps { problems.append("At most \(maxSteps) steps.") }
        if steps.contains(where: { $0.sentLabel.count > maxLabelLength }) {
            problems.append("A step's label is longer than \(maxLabelLength) characters.")
        }
        if steps.contains(where: { !(0...maxOffsetMinutes).contains($0.offsetMinutes) }) {
            problems.append("A step's time after the one before must be 0 to 24 hours.")
        } else if steps.reduce(0, { $0 + $1.offsetMinutes }) > maxOffsetMinutes {
            problems.append("The steps must all ring within 24 hours of the alarm.")
        }
        if steps.contains(where: { !(1...maxEveryDays).contains($0.everyDays) }) {
            problems.append("A step rings every 1 to \(maxEveryDays) days.")
        } else if steps.contains(where: { $0.everyDays > 1 && $0.startsOn.flatMap { StepDays.date($0) } == nil }) {
            problems.append("A step every few days needs the first day it rings.")
        }
        if Set(steps.map(\.id)).count != steps.count { problems.append("Two steps have the same id.") }
        return problems
    }

    /// The steps that ring with the ring on `date`, with the minutes from
    /// the ring to each. A step that does not ring that day takes no time:
    /// the next one follows the one before it by its own offset, as on abera.tech.
    public static func ringing(_ steps: [RoutineStep], on date: Date, calendar: Calendar) -> [(RoutineStep, Int)] {
        let kept = steps.filter { $0.ringsOn(date, calendar: calendar) }
        return Array(zip(kept, cumulativeMinutes(kept)))
    }

    /// Minutes from the routine's ring to each step's ring, in order.
    public static func cumulativeMinutes(_ steps: [RoutineStep]) -> [Int] {
        var total = 0
        return steps.map { step in
            total += step.offsetMinutes
            return total
        }
    }
}

/// One ring of a routine and the rings of its steps: a cycle. Checking a
/// step off covers that cycle alone. The next cycle every step is set again.
public struct RoutineCycle: Equatable, Hashable, Sendable, Identifiable {
    public var routineID: UUID
    /// The routine's scheduled local date and time, "yyyy-MM-ddTHH:mm".
    public var stamp: String
    /// When the routine rings, or rang.
    public var at: Date
    public var steps: [StepRing]

    public var id: String { key }
    /// The routine ring's own key: `routine:{id}:{stamp}`.
    public var key: String { RoutineCycle.parentKey(routineID: routineID, stamp: stamp) }

    public struct StepRing: Equatable, Hashable, Sendable, Identifiable {
        public var step: RoutineStep
        public var at: Date
        public var key: String
        public var id: UUID { step.id }
    }

    static func parentKey(routineID: UUID, stamp: String) -> String {
        DesiredAlarm.routinePrefix + routineID.uuidString.lowercased() + ":" + stamp
    }

    /// `routine:{routineId}:{stamp}:step:{stepId}`, as abera.tech names it.
    public static func stepKey(routineID: UUID, stamp: String, stepID: UUID) -> String {
        parentKey(routineID: routineID, stamp: stamp) + ":step:" + stepID.uuidString.lowercased()
    }

    /// The parts of a step ring's key, or nil for any other key.
    public static func parseStepKey(_ key: String) -> (routineID: UUID, stamp: String, stepID: UUID)? {
        guard key.hasPrefix(DesiredAlarm.routinePrefix) else { return nil }
        return parseLoose(key.dropFirst(DesiredAlarm.routinePrefix.count))
    }

    private static func parseLoose(_ rest: Substring) -> (routineID: UUID, stamp: String, stepID: UUID)? {
        guard let marker = rest.range(of: ":step:") else { return nil }
        let head = rest[..<marker.lowerBound]
        let tail = rest[marker.upperBound...]
        guard head.count > 37, let routine = UUID(uuidString: String(head.prefix(36))),
            head[head.index(head.startIndex, offsetBy: 36)] == ":",
            let step = UUID(uuidString: String(tail))
        else { return nil }
        return (routine, String(head.dropFirst(37)), step)
    }

    /// The cycle a routine ring at `at` starts. A ring moved later rings,
    /// with its steps, that many minutes after `at`.
    static func make(_ routine: Routine, at planned: Date, calendar: Calendar) -> RoutineCycle {
        let day = calendar.dateComponents([.year, .month, .day], from: planned)
        let stamp = String(
            format: "%04d-%02d-%02dT%02d:%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0, routine.hour,
            routine.minute)
        let at = planned.addingTimeInterval(TimeInterval((routine.delays[stamp] ?? 0) * 60))
        let steps = RoutineStep.ringing(routine.steps, on: planned, calendar: calendar).map { step, minutes in
            StepRing(
                step: step, at: at.addingTimeInterval(TimeInterval(minutes * 60)),
                key: stepKey(routineID: routine.id, stamp: stamp, stepID: step.id))
        }
        return RoutineCycle(routineID: routine.id, stamp: stamp, at: at, steps: steps)
    }

    /// The cycle under way at `now`, whose ring is the latest at or before
    /// `now`, and the next one. A ring-once routine has one cycle: its ring
    /// after its last save, or after `now` when the save time is not known.
    public static func around(_ routine: Routine, now: Date, calendar: Calendar) -> (
        current: RoutineCycle?, next: RoutineCycle?
    ) {
        let schedule = routine.schedule
        if !routine.repeats {
            let from = routine.updatedAt ?? now
            guard let ring = schedule.nextFire(after: from, calendar: calendar) else { return (nil, nil) }
            let cycle = make(routine, at: ring, calendar: calendar)
            return ring <= now ? (cycle, nil) : (nil, cycle)
        }
        let previous = RoutineRing.latestRing(schedule, atOrBefore: now, window: 8 * 86_400, calendar: calendar)
        let next = schedule.nextFire(after: now, calendar: calendar)
        var current = previous.map { make(routine, at: $0, calendar: calendar) }
        var coming = next.map { make(routine, at: $0, calendar: calendar) }
        // A ring delayed past the rings after it is still the one to come,
        // or, once it has rung, the one under way.
        for cycle in moved(routine, before: previous ?? now, now: now, calendar: calendar) {
            if cycle.at > now {
                if coming.map({ cycle.at < $0.at }) ?? true { coming = cycle }
            } else if current.map({ cycle.at > $0.at }) ?? true {
                current = cycle
            }
        }
        return (current, coming)
    }

    /// The cycles planned before `before`, in the last 7 days, that a delay
    /// moved and whose ring or a step's ring is after `now` or came within
    /// a day of it. A delay runs up to 7 days, so one can pass the rings after it.
    static func moved(_ routine: Routine, before: Date, now: Date, calendar: Calendar) -> [RoutineCycle] {
        routine.delays.keys.sorted().compactMap { stamp -> RoutineCycle? in
            guard let planned = plannedDate(stamp, calendar: calendar), planned < before,
                planned >= now.addingTimeInterval(-TimeInterval(RoutineDelay.minutes.upperBound * 60) - 86_400)
            else { return nil }
            let cycle = make(routine, at: planned, calendar: calendar)
            guard cycle.stamp == stamp else { return nil }
            let last = cycle.steps.last?.at ?? cycle.at
            return last.addingTimeInterval(86_400) > now ? cycle : nil
        }
    }

    /// The local time a stamp names, or nil.
    static func plannedDate(_ stamp: String, calendar: Calendar) -> Date? {
        let parts = stamp.split(whereSeparator: { $0 == "-" || $0 == "T" || $0 == ":" }).compactMap { Int($0) }
        guard parts.count == 5 else { return nil }
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))
    }

    /// Every cycle whose step rings may still come: the one under way and
    /// the ones that start within `ahead` of `now`, at least the next one.
    /// The phone holds their step alarms so they ring offline.
    static func upcoming(_ routine: Routine, now: Date, ahead: TimeInterval, calendar: Calendar) -> [RoutineCycle] {
        let (current, next) = around(routine, now: now, calendar: calendar)
        var cycles = [current].compactMap { $0 }
        if routine.repeats {
            // Every other delayed ring that may still ring, with its steps.
            let held = Set(cycles.map(\.stamp) + [next?.stamp].compactMap { $0 })
            cycles += moved(routine, before: now, now: now, calendar: calendar).filter { !held.contains($0.stamp) }
        }
        guard let next else { return cycles }
        cycles.append(next)
        guard routine.repeats else { return cycles }
        // The rings after the next one, by their planned times.
        var planned = next.at.addingTimeInterval(-TimeInterval((next.delay(in: routine) ?? 0) * 60))
        while let after = routine.schedule.nextFire(after: planned, calendar: calendar),
            after <= now.addingTimeInterval(ahead), cycles.count < 16
        {
            planned = after
            let cycle = make(routine, at: after, calendar: calendar)
            if !cycles.contains(where: { $0.stamp == cycle.stamp }) { cycles.append(cycle) }
        }
        return cycles
    }
}

/// A step checked off for one cycle, as the status lists it.
public struct RoutineCompletion: Codable, Equatable, Hashable, Sendable {
    public var routineId: UUID
    public var stepId: UUID
    /// The cycle's stamp, "yyyy-MM-ddTHH:mm".
    public var cycle: String
    public var completedAt: Date
    /// abera.tech's id, for the photo. Nil until abera.tech has it, and from an older server.
    public var id: UUID?
    public var note: String?
    public var hasPhoto: Bool

    public init(
        routineId: UUID, stepId: UUID, cycle: String, completedAt: Date, id: UUID? = nil, note: String? = nil,
        hasPhoto: Bool = false
    ) {
        self.routineId = routineId
        self.stepId = stepId
        self.cycle = cycle
        self.completedAt = completedAt
        self.id = id
        self.note = note
        self.hasPhoto = hasPhoto
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routineId = try container.decode(UUID.self, forKey: .routineId)
        stepId = try container.decode(UUID.self, forKey: .stepId)
        cycle = try container.decode(String.self, forKey: .cycle)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        hasPhoto = try container.decodeIfPresent(Bool.self, forKey: .hasPhoto) ?? false
    }

    /// The step ring it answers.
    public var stepKey: String { RoutineCycle.stepKey(routineID: routineId, stamp: cycle, stepID: stepId) }
}

/// A step checked off, or the check taken back, that abera.tech has not
/// taken yet. The photo waits on the phone under `photoName`.
public enum CompletionChange: Codable, Equatable, Sendable {
    case complete(CompletionDraft)
    case undo(routineId: UUID, stepId: UUID, cycle: String)
    /// A ring of the alarm itself marked Done or Skipped.
    case outcome(OutcomeDraft)
    /// The mark taken off.
    case clearOutcome(routineId: UUID, cycle: String)
    /// A ring and its steps moved later.
    case delay(RoutineDelay)
    /// The ring back at its planned time.
    case clearDelay(routineId: UUID, cycle: String)

    public var routineId: UUID {
        switch self {
        case .complete(let draft): draft.routineId
        case .undo(let routineId, _, _): routineId
        case .outcome(let draft): draft.routineId
        case .clearOutcome(let routineId, _): routineId
        case .delay(let delay): delay.routineId
        case .clearDelay(let routineId, _): routineId
        }
    }

    /// What the change is about: a step's ring, or the alarm's own ring
    /// with ":outcome" after it. A later change to the same key replaces it.
    public var stepKey: String {
        switch self {
        case .complete(let draft):
            RoutineCycle.stepKey(routineID: draft.routineId, stamp: draft.cycle, stepID: draft.stepId)
        case .undo(let routineId, let stepId, let cycle):
            RoutineCycle.stepKey(routineID: routineId, stamp: cycle, stepID: stepId)
        case .outcome(let draft):
            RoutineCycle.parentKey(routineID: draft.routineId, stamp: draft.cycle) + ":outcome"
        case .clearOutcome(let routineId, let cycle):
            RoutineCycle.parentKey(routineID: routineId, stamp: cycle) + ":outcome"
        case .delay(let delay):
            RoutineCycle.parentKey(routineID: delay.routineId, stamp: delay.cycle) + ":delay"
        case .clearDelay(let routineId, let cycle):
            RoutineCycle.parentKey(routineID: routineId, stamp: cycle) + ":delay"
        }
    }

    /// The outcomes as they will be once abera.tech has these changes.
    public static func overlayOutcomes(_ outcomes: [RoutineOutcome], _ changes: [CompletionChange])
        -> [RoutineOutcome]
    {
        var out = outcomes
        for change in changes {
            switch change {
            case .outcome(let draft):
                out.removeAll { $0.routineId == draft.routineId && $0.cycle == draft.cycle }
                out.append(
                    RoutineOutcome(
                        routineId: draft.routineId, cycle: draft.cycle, status: draft.status, at: draft.at,
                        note: draft.body.note))
            case .clearOutcome(let routineId, let cycle):
                out.removeAll { $0.routineId == routineId && $0.cycle == cycle }
            case .complete, .undo, .delay, .clearDelay:
                continue
            }
        }
        return out
    }

    /// The delays as they will be once abera.tech has these changes.
    public static func overlayDelays(_ delays: [RoutineDelay], _ changes: [CompletionChange]) -> [RoutineDelay] {
        var out = delays
        for change in changes {
            switch change {
            case .delay(let delay):
                out.removeAll { $0.routineId == delay.routineId && $0.cycle == delay.cycle }
                out.append(delay)
            case .clearDelay(let routineId, let cycle):
                out.removeAll { $0.routineId == routineId && $0.cycle == cycle }
            case .complete, .undo, .outcome, .clearOutcome:
                continue
            }
        }
        return out
    }

    /// The last change for each step and cycle. A second check-off with no
    /// new photo keeps the photo of the first.
    public static func coalesce(_ changes: [CompletionChange]) -> [CompletionChange] {
        var out: [CompletionChange] = []
        for change in changes {
            let earlier = out.firstIndex { $0.stepKey == change.stepKey }
            if let earlier {
                if case .complete(var draft) = change, case .complete(let before) = out[earlier],
                    draft.photoName == nil, !draft.removePhoto
                {
                    draft.photoName = before.photoName
                    out.remove(at: earlier)
                    out.append(.complete(draft))
                    continue
                }
                out.remove(at: earlier)
            }
            out.append(change)
        }
        return out
    }

    /// The completions as they will be once abera.tech has these changes.
    public static func overlay(_ completions: [RoutineCompletion], _ changes: [CompletionChange])
        -> [RoutineCompletion]
    {
        var out = completions
        for change in changes {
            let before = out.first { $0.stepKey == change.stepKey }
            out.removeAll { $0.stepKey == change.stepKey }
            if case .complete(let draft) = change {
                // A photo waiting on the phone shows from there. One abera.tech holds stays unless removed.
                out.append(
                    RoutineCompletion(
                        routineId: draft.routineId, stepId: draft.stepId, cycle: draft.cycle,
                        completedAt: draft.completedAt, id: before?.id, note: draft.sentNote,
                        hasPhoto: !draft.removePhoto && (draft.photoName != nil || before?.hasPhoto == true)))
            }
        }
        return out
    }

    /// The same changes naming a routine made offline by abera.tech's id.
    func renaming(_ ids: [UUID: UUID]) -> CompletionChange {
        switch self {
        case .complete(var draft):
            draft.routineId = ids[draft.routineId] ?? draft.routineId
            return .complete(draft)
        case .undo(let routineId, let stepId, let cycle):
            return .undo(routineId: ids[routineId] ?? routineId, stepId: stepId, cycle: cycle)
        case .outcome(var draft):
            draft.routineId = ids[draft.routineId] ?? draft.routineId
            return .outcome(draft)
        case .clearOutcome(let routineId, let cycle):
            return .clearOutcome(routineId: ids[routineId] ?? routineId, cycle: cycle)
        case .delay(var delay):
            delay.routineId = ids[delay.routineId] ?? delay.routineId
            return .delay(delay)
        case .clearDelay(let routineId, let cycle):
            return .clearDelay(routineId: ids[routineId] ?? routineId, cycle: cycle)
        }
    }
}

/// What the phone sends to check a step off.
public struct CompletionDraft: Codable, Equatable, Sendable {
    public static let maxNoteLength = 2000
    /// abera.tech refuses a larger photo.
    public static let maxPhotoBytes = 2_000_000

    public var routineId: UUID
    public var stepId: UUID
    public var cycle: String
    public var note: String?
    /// The document holding the JPEG until it is sent. Nil keeps the photo
    /// abera.tech has.
    public var photoName: String?
    /// True takes the stored photo off.
    public var removePhoto: Bool
    public var completedAt: Date

    public init(
        routineId: UUID, stepId: UUID, cycle: String, note: String? = nil, photoName: String? = nil,
        removePhoto: Bool = false, completedAt: Date
    ) {
        self.routineId = routineId
        self.stepId = stepId
        self.cycle = cycle
        self.note = note
        self.photoName = photoName
        self.removePhoto = removePhoto
        self.completedAt = completedAt
    }

    /// The note trimmed, nil when empty.
    public var sentNote: String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var problems: [String] {
        (sentNote?.count ?? 0) > Self.maxNoteLength ? ["The note is longer than \(Self.maxNoteLength) characters."] : []
    }

    /// A JPEG starts FF D8 FF. abera.tech checks the same.
    public static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF])
    }
}

/// What PUT .../completion carries. `photo` is base64, "" to remove it, or
/// absent to keep the one stored.
struct CompletionBody: Encodable {
    var note: String?
    var photo: String?
    var completedAt: Date

    enum CodingKeys: String, CodingKey { case note, photo, completedAt }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(note, forKey: .note)
        try container.encode(photo, forKey: .photo)
        try container.encode(completedAt, forKey: .completedAt)
    }
}

/// Two weeks of cycles, from `GET /api/alerts/history`, newest first.
public struct RoutineHistory: Codable, Equatable, Sendable {
    public static let days = 14

    public var days: Int
    public var cycles: [Cycle]

    public init(days: Int = RoutineHistory.days, cycles: [Cycle]) {
        self.days = days
        self.cycles = cycles
    }

    public struct Cycle: Codable, Equatable, Sendable, Identifiable {
        public var routineId: UUID
        public var label: String
        public var cycle: String
        public var at: Date
        public var acknowledgedAt: Date?
        public var acknowledgedVia: String?
        public var steps: [Step]
        /// The ring marked Done or Skipped. Nil from an older server.
        public var outcome: Outcome?

        public var id: String { routineId.uuidString + cycle }

        public init(
            routineId: UUID, label: String, cycle: String, at: Date, acknowledgedAt: Date? = nil,
            acknowledgedVia: String? = nil, steps: [Step], outcome: Outcome? = nil
        ) {
            self.routineId = routineId
            self.label = label
            self.cycle = cycle
            self.at = at
            self.acknowledgedAt = acknowledgedAt
            self.acknowledgedVia = acknowledgedVia
            self.steps = steps
            self.outcome = outcome
        }

        public var skipped: Bool { outcome?.status == .skipped }

        /// "2 of 3 done". A step still to ring counts once it is checked off.
        public func doneText(now: Date) -> String {
            if skipped { return "Skipped" }
            // abera.tech lists a marked ring of an alarm with no steps too.
            if steps.isEmpty { return outcome?.status == .done ? "Done" : "" }
            let counted = steps.filter { $0.completion != nil || $0.at <= now }
            return "\(counted.filter { $0.completion != nil }.count) of \(counted.count) done"
        }
    }

    public struct Step: Codable, Equatable, Sendable, Identifiable {
        public var stepId: UUID
        public var label: String
        public var at: Date
        public var acknowledgedAt: Date?
        public var completion: Completion?

        public var id: UUID { stepId }

        public init(stepId: UUID, label: String, at: Date, acknowledgedAt: Date? = nil, completion: Completion? = nil) {
            self.stepId = stepId
            self.label = label
            self.at = at
            self.acknowledgedAt = acknowledgedAt
            self.completion = completion
        }
    }

    public struct Outcome: Codable, Equatable, Sendable {
        public var status: RoutineOutcome.Status
        public var at: Date
        public var note: String?

        public init(status: RoutineOutcome.Status, at: Date, note: String? = nil) {
            self.status = status
            self.at = at
            self.note = note
        }
    }

    public struct Completion: Codable, Equatable, Sendable {
        public var id: UUID
        public var completedAt: Date
        public var note: String?
        public var hasPhoto: Bool

        public init(id: UUID, completedAt: Date, note: String? = nil, hasPhoto: Bool = false) {
            self.id = id
            self.completedAt = completedAt
            self.note = note
            self.hasPhoto = hasPhoto
        }
    }

    /// One step's count over the two weeks.
    public struct Tally: Equatable, Sendable, Identifiable {
        public var label: String
        public var done: Int
        public var of: Int
        public var id: String { label }
    }

    /// Per step label, how many of its rings were checked off: the
    /// weekend's compliance check. A step still to ring counts only once it
    /// is checked off. Steps in label order.
    public func tally(now: Date) -> [Tally] {
        var counts: [String: (Int, Int)] = [:]
        // A skipped ring was not due, so it counts neither way.
        for cycle in cycles where !cycle.skipped {
            for step in cycle.steps where step.completion != nil || step.at <= now {
                let (done, of) = counts[step.label] ?? (0, 0)
                counts[step.label] = (done + (step.completion == nil ? 0 : 1), of + 1)
            }
        }
        return counts.keys.sorted().map { Tally(label: $0, done: counts[$0]!.0, of: counts[$0]!.1) }
    }
}

/// A step's first day, "yyyy-MM-dd", as a local date.
public enum StepDays {
    /// Midnight of that day in the calendar's zone, or nil when it is not a date.
    public static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == parts[2]
        else { return nil }
        return date
    }

    /// "2026-11-27" for the local day `date` falls on.
    public static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}
