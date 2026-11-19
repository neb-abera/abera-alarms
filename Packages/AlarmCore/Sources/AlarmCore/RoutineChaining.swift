import Foundation

/// Moving alarms under one another and back out. An alarm moved under
/// another becomes one of its steps, at the time it rang on its own. A step
/// separated becomes an alarm of its own, at the time it rang as a step.
/// The other steps keep their times either way.
public enum RoutineChaining {
    public enum Refusal: Error, Equatable, Sendable {
        /// The chain would hold more than 20 steps.
        case tooManySteps
        /// A step would ring more than 24 hours after the alarm.
        case tooLate
        /// An alarm cannot be moved under itself.
        case sameAlarm

        public var message: String {
            switch self {
            case .tooManySteps: "An alarm holds at most \(RoutineStep.maxSteps) steps."
            case .tooLate: "Every step must ring within 24 hours of its alarm."
            case .sameAlarm: "An alarm cannot be moved under itself."
            }
        }
    }

    /// The steps with one more, at `delta` minutes after the alarm. It goes
    /// before the first step that rings later, and that step's offset
    /// shrinks so its own time stays.
    public static func insert(_ step: RoutineStep, atDelta delta: Int, into steps: [RoutineStep]) -> [RoutineStep] {
        var steps = steps
        let times = RoutineStep.cumulativeMinutes(steps)
        let index = times.firstIndex { $0 > delta } ?? steps.count
        let before = index == 0 ? 0 : times[index - 1]
        var added = step
        added.offsetMinutes = delta - before
        if index < steps.count { steps[index].offsetMinutes = times[index] - delta }
        steps.insert(added, at: index)
        return steps
    }

    /// The steps with one taken out. The step after it keeps its time.
    public static func remove(_ id: UUID, from steps: [RoutineStep]) -> [RoutineStep] {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return steps }
        var steps = steps
        let removed = steps.remove(at: index)
        if index < steps.count { steps[index].offsetMinutes += removed.offsetMinutes }
        return steps
    }

    /// Minutes from `parent`'s ring to the next time `hour:minute` comes, 0 to 1439.
    static func delta(from parent: (hour: Int, minute: Int), to hour: Int, _ minute: Int) -> Int {
        ((hour * 60 + minute) - (parent.hour * 60 + parent.minute) + 1440) % 1440
    }

    /// `parent`'s draft with `child` as a step at the time `child` rings,
    /// and `child`'s own steps after it at their times. The step rings on
    /// the parent's days. The caller deletes `child`.
    public static func subordinate(_ child: Routine, under parent: Routine) -> Result<RoutineDraft, Refusal> {
        guard child.id != parent.id else { return .failure(.sameAlarm) }
        let start = delta(from: (parent.hour, parent.minute), to: child.hour, child.minute)
        var steps = insert(
            RoutineStep(id: child.id, label: child.label, offsetMinutes: 0), atDelta: start, into: parent.steps)
        for (step, minutes) in zip(child.steps, RoutineStep.cumulativeMinutes(child.steps)) {
            guard start + minutes <= RoutineStep.maxOffsetMinutes else { return .failure(.tooLate) }
            steps = insert(step, atDelta: start + minutes, into: steps)
        }
        if steps.count > RoutineStep.maxSteps { return .failure(.tooManySteps) }
        if !RoutineStep.problems(steps).isEmpty { return .failure(.tooLate) }
        var draft = parent.draft
        draft.steps = steps
        return .success(draft)
    }

    /// `parent`'s draft without the step, and a new alarm at the time the
    /// step rang, on the parent's days, moved a day on when the step rang
    /// after midnight. Nil when the parent has no such step.
    public static func separate(_ stepID: UUID, from parent: Routine) -> (parent: RoutineDraft, alarm: RoutineDraft)? {
        guard let index = parent.steps.firstIndex(where: { $0.id == stepID }) else { return nil }
        let step = parent.steps[index]
        let at = parent.hour * 60 + parent.minute + RoutineStep.cumulativeMinutes(parent.steps)[index]
        let days = at >= 1440 ? parent.days.map { $0 % 7 + 1 } : parent.days
        var remaining = parent.draft
        remaining.steps = remove(stepID, from: parent.steps)
        let alarm = RoutineDraft(
            label: step.sentLabel, hour: (at / 60) % 24, minute: at % 60, days: days.sorted(),
            enabled: parent.enabled, snoozeMinutes: parent.snoozeMinutes)
        return (remaining, alarm)
    }
}

extension RoutineCycle {
    /// The cycle a list shows under the alarm: the one under way until its
    /// last step has rung out `window`, then the next. At 05:50 before a
    /// 06:00 alarm that is the 06:00 cycle, so its steps can be checked off
    /// ahead.
    public static func shown(_ routine: Routine, now: Date, window: TimeInterval, calendar: Calendar)
        -> RoutineCycle?
    {
        let (current, next) = around(routine, now: now, calendar: calendar)
        if let current, (current.steps.last?.at ?? current.at).addingTimeInterval(window) > now {
            return current
        }
        return next ?? current
    }
}
