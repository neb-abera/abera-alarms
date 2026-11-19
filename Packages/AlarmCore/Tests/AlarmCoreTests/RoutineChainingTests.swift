import Foundation
import Testing

@testable import AlarmCore

/// Existing alarms moved under another as steps, and steps separated back out.
@Suite struct RoutineChainingTests {
    let wakeID = UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!
    let pillsID = UUID(uuidString: "00000000-0000-4000-8000-0000000000C2")!
    let beauty = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000C3")!, label: "Beauty care", offsetMinutes: 10)

    var wake: Routine {
        Routine(
            id: wakeID, label: "Wake up", hour: 6, minute: 0, days: [1, 2, 3, 4, 5], snoozeMinutes: 7, steps: [beauty])
    }

    func alarm(
        _ label: String, _ hour: Int, _ minute: Int, days: [Int] = [1, 2, 3, 4, 5, 6, 7], steps: [RoutineStep] = []
    )
        -> Routine
    {
        Routine(id: pillsID, label: label, hour: hour, minute: minute, days: days, steps: steps)
    }

    func times(_ steps: [RoutineStep]) -> [Int] { RoutineStep.cumulativeMinutes(steps) }

    @Test func anAlarmMovedUnderAnotherKeepsItsTimeAndTheOthersKeepTheirs() throws {
        let draft = try RoutineChaining.subordinate(alarm("Take medication", 6, 5), under: wake).get()
        #expect(draft.steps.map(\.label) == ["Take medication", "Beauty care"])
        #expect(times(draft.steps) == [5, 10])
        #expect(draft.steps[0].id == pillsID)
        #expect(draft.hour == 6 && draft.days == [1, 2, 3, 4, 5] && draft.snoozeMinutes == 7)
    }

    @Test func anAlarmAfterEveryStepGoesLast() throws {
        let draft = try RoutineChaining.subordinate(alarm("Stretch", 6, 30), under: wake).get()
        #expect(draft.steps.map(\.label) == ["Beauty care", "Stretch"])
        #expect(draft.steps.map(\.offsetMinutes) == [10, 20])
    }

    @Test func anAlarmAtAnEarlierClockTimeRingsTheNextTimeThatTimeComes() throws {
        let draft = try RoutineChaining.subordinate(alarm("Night pills", 5, 0), under: wake).get()
        #expect(times(draft.steps) == [10, 23 * 60])
    }

    @Test func anAlarmWithStepsBringsThemAlong() throws {
        let child = alarm(
            "Take medication", 6, 5, steps: [RoutineStep(label: "Log it", offsetMinutes: 2)])
        let draft = try RoutineChaining.subordinate(child, under: wake).get()
        #expect(draft.steps.map(\.label) == ["Take medication", "Log it", "Beauty care"])
        #expect(times(draft.steps) == [5, 7, 10])
    }

    @Test func movingRefusesWhatTheBoundsRefuse() {
        #expect(RoutineChaining.subordinate(wake, under: wake) == .failure(.sameAlarm))
        let late = alarm("Late", 5, 0, steps: [RoutineStep(label: "Later", offsetMinutes: 120)])
        #expect(RoutineChaining.subordinate(late, under: wake) == .failure(.tooLate))
        var full = wake
        full.steps = (0..<RoutineStep.maxSteps).map { RoutineStep(label: "S\($0)", offsetMinutes: 1) }
        #expect(RoutineChaining.subordinate(alarm("One more", 7, 0), under: full) == .failure(.tooManySteps))
        #expect(RoutineChaining.Refusal.tooLate.message.contains("24 hours"))
        #expect(RoutineChaining.Refusal.tooManySteps.message.contains("20"))
        #expect(RoutineChaining.Refusal.sameAlarm.message.contains("itself"))
    }

    @Test func aSeparatedStepBecomesAnAlarmAtItsTime() throws {
        var parent = wake
        parent.steps = [
            RoutineStep(id: pillsID, label: "Take medication", offsetMinutes: 5),
            RoutineStep(id: beauty.id, label: "Beauty care", offsetMinutes: 5),
        ]
        let (remaining, alarm) = try #require(RoutineChaining.separate(pillsID, from: parent))
        #expect(remaining.steps.map(\.label) == ["Beauty care"])
        #expect(times(remaining.steps) == [10])
        #expect(alarm.label == "Take medication")
        #expect(alarm.hour == 6 && alarm.minute == 5)
        #expect(alarm.days == [1, 2, 3, 4, 5])
        #expect(alarm.snoozeMinutes == 7)
        #expect(RoutineChaining.separate(UUID(), from: parent) == nil)
    }

    @Test func aStepAfterMidnightSeparatesOntoTheNextDays() throws {
        var night = wake
        night.hour = 23
        night.minute = 0
        night.days = [5, 7]
        night.steps = [RoutineStep(id: pillsID, label: "Pills", offsetMinutes: 90)]
        let (_, alarm) = try #require(RoutineChaining.separate(pillsID, from: night))
        #expect(alarm.hour == 0 && alarm.minute == 30)
        #expect(alarm.days == [1, 6])
    }

    @Test func movingUnderThenSeparatingGivesTheAlarmBack() throws {
        let child = alarm("Take medication", 6, 5)
        let moved = try RoutineChaining.subordinate(child, under: wake).get()
        var parent = wake
        parent.steps = moved.steps
        let (back, alarm) = try #require(RoutineChaining.separate(pillsID, from: parent))
        #expect(back.steps == wake.steps)
        #expect(alarm.hour == 6 && alarm.minute == 5)
    }

    @Test func theListShowsTheCycleUnderWayUntilItsStepsRingOutThenTheNext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        var daily = wake
        daily.days = [1, 2, 3, 4, 5, 6, 7]
        let window: TimeInterval = 30 * 60
        #expect(RoutineCycle.shown(daily, now: at(19, 6, 20), window: window, calendar: calendar)?.at == at(19, 6, 0))
        #expect(RoutineCycle.shown(daily, now: at(19, 20, 0), window: window, calendar: calendar)?.at == at(20, 6, 0))
        #expect(RoutineCycle.shown(daily, now: at(20, 5, 50), window: window, calendar: calendar)?.at == at(20, 6, 0))
    }
}
