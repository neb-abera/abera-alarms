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

    /// The phone makes the id, so a step added offline keeps it on abera.tech.
    public var id: UUID
    public var label: String
    /// Minutes after the item before it: 0 to 1440.
    public var offsetMinutes: Int

    public init(id: UUID = UUID(), label: String, offsetMinutes: Int) {
        self.id = id
        self.label = label
        self.offsetMinutes = offsetMinutes
    }

    /// The label as sent: trimmed, and "Step" when empty.
    public var sentLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultLabel : trimmed
    }

    var sent: RoutineStep {
        RoutineStep(id: id, label: sentLabel, offsetMinutes: offsetMinutes)
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
        if Set(steps.map(\.id)).count != steps.count { problems.append("Two steps have the same id.") }
        return problems
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

    /// The cycle a routine ring at `at` starts.
    static func make(_ routine: Routine, at: Date, calendar: Calendar) -> RoutineCycle {
        let day = calendar.dateComponents([.year, .month, .day], from: at)
        let stamp = String(
            format: "%04d-%02d-%02dT%02d:%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0, routine.hour,
            routine.minute)
        let offsets = RoutineStep.cumulativeMinutes(routine.steps)
        let steps = zip(routine.steps, offsets).map { step, minutes in
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
        return (
            previous.map { make(routine, at: $0, calendar: calendar) },
            next.map { make(routine, at: $0, calendar: calendar) }
        )
    }

    /// Every cycle whose step rings may still come: the one under way and
    /// the ones that start within `ahead` of `now`, at least the next one.
    /// The phone holds their step alarms so they ring offline.
    static func upcoming(_ routine: Routine, now: Date, ahead: TimeInterval, calendar: Calendar) -> [RoutineCycle] {
        let (current, next) = around(routine, now: now, calendar: calendar)
        var cycles = [current].compactMap { $0 }
        guard var cycle = next else { return cycles }
        cycles.append(cycle)
        guard routine.repeats else { return cycles }
        while let after = routine.schedule.nextFire(after: cycle.at, calendar: calendar),
            after <= now.addingTimeInterval(ahead), cycles.count < 16
        {
            cycle = make(routine, at: after, calendar: calendar)
            cycles.append(cycle)
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

    public var routineId: UUID {
        switch self {
        case .complete(let draft): draft.routineId
        case .undo(let routineId, _, _): routineId
        }
    }

    public var stepKey: String {
        switch self {
        case .complete(let draft):
            RoutineCycle.stepKey(routineID: draft.routineId, stamp: draft.cycle, stepID: draft.stepId)
        case .undo(let routineId, let stepId, let cycle):
            RoutineCycle.stepKey(routineID: routineId, stamp: cycle, stepID: stepId)
        }
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

        public var id: String { routineId.uuidString + cycle }

        public init(
            routineId: UUID, label: String, cycle: String, at: Date, acknowledgedAt: Date? = nil,
            acknowledgedVia: String? = nil, steps: [Step]
        ) {
            self.routineId = routineId
            self.label = label
            self.cycle = cycle
            self.at = at
            self.acknowledgedAt = acknowledgedAt
            self.acknowledgedVia = acknowledgedVia
            self.steps = steps
        }

        /// "2 of 3 done". A step still to ring counts once it is checked off.
        public func doneText(now: Date) -> String {
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
        for cycle in cycles {
            for step in cycle.steps where step.completion != nil || step.at <= now {
                let (done, of) = counts[step.label] ?? (0, 0)
                counts[step.label] = (done + (step.completion == nil ? 0 : 1), of + 1)
            }
        }
        return counts.keys.sorted().map { Tally(label: $0, done: counts[$0]!.0, of: counts[$0]!.1) }
    }
}
