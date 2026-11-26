import Foundation
import Testing

@testable import AlarmCore

/// A step that rings every few days. Neb asked on 2026-11-26 for his four
/// beauty care alarms to be two: a night routine with tretinoin one night
/// and night serum the next, and a morning one with vitamin C every other
/// morning. A night it does not ring takes no time.
@Suite struct RoutineStepDaysTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    var calendar: Calendar { Self.calendar }

    let routineID = UUID(uuidString: "00000000-0000-4000-8000-0000000000F1")!
    let wash = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000F2")!, label: "Wash face", offsetMinutes: 1)
    let tretinoin = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000F3")!, label: "Tretinoin", offsetMinutes: 24,
        everyDays: 2, startsOn: "2026-11-27")
    let serum = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000F4")!, label: "Night serum", offsetMinutes: 3,
        everyDays: 2, startsOn: "2026-11-28")
    let moisturizer = RoutineStep(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000F5")!, label: "Moisturizer", offsetMinutes: 3)

    var night: Routine {
        Routine(
            id: routineID, label: "night routine", hour: 21, minute: 30, days: [1, 2, 3, 4, 5, 6, 7],
            steps: [wash, tretinoin, serum, moisturizer])
    }

    func at(_ hour: Int, _ minute: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func steps(on day: Int) -> [String] {
        let cycle = RoutineCycle.make(night, at: at(21, 30, day: day), calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return cycle.steps.map { "\($0.step.label) \(formatter.string(from: $0.at))" }
    }

    @Test func tretinoinAndSerumAlternateAndASkippedStepTakesNoTime() {
        #expect(steps(on: 27) == ["Wash face 21:31", "Tretinoin 21:55", "Moisturizer 21:58"])
        #expect(steps(on: 28) == ["Wash face 21:31", "Night serum 21:34", "Moisturizer 21:37"])
        #expect(steps(on: 29) == steps(on: 27))
        // Before its first day it keeps the same rhythm.
        #expect(steps(on: 25) == steps(on: 27))
        #expect(steps(on: 26) == steps(on: 28))
    }

    @Test func theStepsTheAlarmsTabHoldsRingOnTheirOwnNights() {
        let state = AlertsState(configured: true, routines: [night], stopAfterMinutes: 180)
        let held = Reconciler.desired(from: state, now: at(21, 0, day: 27), acknowledgedHere: [], calendar: calendar)
            .filter { $0.fireAt < at(23, 59, day: 28) && $0.title != "night routine" }
        #expect(
            held.map(\.title) == ["Wash face", "Tretinoin", "Moisturizer", "Wash face", "Night serum", "Moisturizer"])
        #expect(held[1].fireAt == at(21, 55, day: 27))
        #expect(held[4].fireAt == at(21, 34, day: 28))
    }

    @Test func aStepFromAnOlderServerRingsEveryTime() throws {
        let json = #"{"id":"00000000-0000-4000-8000-0000000000F2","label":"Wash face","offsetMinutes":1}"#
        let step = try JSONDecoder().decode(RoutineStep.self, from: Data(json.utf8))
        #expect(step.everyDays == 1)
        #expect(step.startsOn == nil)
        #expect(step.ringsOn(at(21, 30, day: 28), calendar: calendar))
    }

    @Test func aStepSendsItsDaysAndFirstDayAndNoneForEveryRing() throws {
        let body = try JSONEncoder().encode([tretinoin.sent, wash.sent])
        let decoded = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
        #expect(decoded?[0]["everyDays"] as? Int == 2)
        #expect(decoded?[0]["startsOn"] as? String == "2026-11-27")
        #expect(decoded?[1]["everyDays"] as? Int == 1)
        #expect(decoded?[1]["startsOn"] == nil)
    }

    @Test func theEditorsBoundsMatchAbearaTech() {
        var bad = tretinoin
        bad.everyDays = 0
        #expect(RoutineStep.problems([bad]) == ["A step rings every 1 to 365 days."])
        bad.everyDays = 366
        #expect(RoutineStep.problems([bad]) == ["A step rings every 1 to 365 days."])
        bad.everyDays = 2
        bad.startsOn = "27 Nov"
        #expect(RoutineStep.problems([bad]) == ["A step every few days needs the first day it rings."])
        #expect(RoutineStep.problems([tretinoin, serum, wash]).isEmpty)
    }

    @Test func theWordsBesideAStepNameItsFirstDay() {
        let words = tretinoin.everyWords(calendar: calendar) ?? ""
        #expect(words.hasPrefix("every 2 days from "))
        #expect(words.contains("27") && words.contains("Fri"))
        #expect(wash.everyWords(calendar: calendar) == nil)
    }

    @Test func aFirstDayIsReadAndWrittenAsALocalDate() {
        #expect(StepDays.date("2026-02-30", calendar: calendar) == nil)
        #expect(StepDays.date("2026-11-27", calendar: calendar) == at(0, 0, day: 27))
        #expect(StepDays.text(at(23, 59, day: 27), calendar: calendar) == "2026-11-27")
    }
}
