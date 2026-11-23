import Foundation
import Testing

@testable import AlarmCore

/// The Alarms tab in the order the alarms next ring, with each alarm's
/// steps open when its ring is today. Neb asked on 2026-11-21.
@Suite struct AlarmListTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    var calendar: Calendar { Self.calendar }

    /// A local time in November 2026. The 21st is a Saturday.
    func at(_ hour: Int, _ minute: Int, day: Int = 21) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func routine(_ n: Int, _ label: String, _ hour: Int, _ minute: Int, days: [Int], enabled: Bool = true) -> Routine {
        Routine(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!, label: label, hour: hour,
            minute: minute, days: days, enabled: enabled,
            steps: [RoutineStep(label: "Step", offsetMinutes: 5)])
    }

    var morning: Routine { routine(1, "wake up", 7, 0, days: [1, 2, 3, 4, 5, 6, 7]) }
    var night: Routine { routine(2, "night routine", 21, 30, days: [1, 2, 3, 4, 5, 6, 7]) }
    var wednesday: Routine { routine(3, "Weekly review", 9, 0, days: [3]) }
    var off: Routine { routine(4, "Off", 5, 0, days: [1, 2, 3, 4, 5, 6, 7], enabled: false) }

    @Test func alarmsAreInTheOrderTheyNextRing() {
        let state = AlertsState(routines: [morning, night, wednesday, off])
        let ordered = AlarmList.ordered(
            [off, wednesday, morning, night], in: state, now: at(10, 30), calendar: calendar)
        #expect(ordered.map(\.label) == ["night routine", "wake up", "Weekly review", "Off"])
        let early = AlarmList.ordered([night, morning], in: state, now: at(6, 0), calendar: calendar)
        #expect(early.map(\.label) == ["wake up", "night routine"])
    }

    @Test func aRingMarkedDoneOrSkippedDoesNotPlaceTheAlarm() {
        let skipped = RoutineOutcome(
            routineId: morning.id, cycle: "2026-11-21T07:00", status: .skipped, at: at(6, 0))
        let state = AlertsState(routines: [morning, night], routineOutcomes: [skipped])
        let ordered = AlarmList.ordered([morning, night], in: state, now: at(6, 0), calendar: calendar)
        #expect(ordered.map(\.label) == ["night routine", "wake up"])
    }

    @Test func stepsOpenWhenTheRingTheyListIsToday() throws {
        let today = try #require(RoutineCycle.around(night, now: at(10, 0), calendar: calendar).next)
        let tomorrow = try #require(RoutineCycle.around(morning, now: at(10, 0), calendar: calendar).next)
        #expect(AlarmList.openByDefault(night, cycle: today, now: at(10, 0), calendar: calendar))
        #expect(!AlarmList.openByDefault(morning, cycle: tomorrow, now: at(10, 0), calendar: calendar))
        var switchedOff = night
        switchedOff.enabled = false
        #expect(!AlarmList.openByDefault(switchedOff, cycle: today, now: at(10, 0), calendar: calendar))
        #expect(!AlarmList.openByDefault(night, cycle: nil, now: at(10, 0), calendar: calendar))
    }

    @Test func hisChoiceHoldsForThatRingAndTheNextStartsFromTheDefault() throws {
        let tomorrow = try #require(RoutineCycle.around(morning, now: at(10, 0), calendar: calendar).next)
        let opened = [tomorrow.key: true]
        #expect(AlarmList.isOpen(morning, cycle: tomorrow, now: at(10, 0), calendar: calendar, choices: opened))
        let today = try #require(RoutineCycle.around(night, now: at(10, 0), calendar: calendar).next)
        #expect(!AlarmList.isOpen(night, cycle: today, now: at(10, 0), calendar: calendar, choices: [today.key: false]))
        // Sunday's ring is a new ring: the default again.
        #expect(AlarmList.isOpen(morning, cycle: tomorrow, now: at(5, 0, day: 22), calendar: calendar, choices: [:]))
        let pruned = AlarmList.pruned(
            [tomorrow.key: true, "routine:old:2026-11-01T07:00": false], keeping: [tomorrow.key])
        #expect(pruned == [tomorrow.key: true])
    }

    /// Neb's iPhone, 2026-11-22 at 21:31: the 21:30 night routine rang and
    /// he stopped it. The list moved it to Tuesday's ring, below the fold,
    /// while its steps were still to ring, and he could not find it. An
    /// alarm stays on the ring it rang until every step is cleared.
    @Test func aRungAlarmStaysOnTopUntilItsStepsAreCleared() throws {
        let tuesday = routine(5, "night routine, hyaluronic", 21, 30, days: [2, 4, 6, 7])
        let state = AlertsState(routines: [morning, tuesday])
        let now = at(21, 31, day: 22)
        let ordered = AlarmList.ordered([morning, tuesday], in: state, now: now, calendar: calendar)
        #expect(ordered.map(\.label) == ["night routine, hyaluronic", "wake up"])
        let cycle = try #require(AlarmList.underWay(tuesday, in: state, now: now, calendar: calendar))
        #expect(cycle.stamp == "2026-11-22T21:30")
        #expect(AlarmList.openByDefault(tuesday, cycle: cycle, now: now, calendar: calendar))
        #expect(
            RingClock.text(for: tuesday, in: state, at: now, calendar: calendar)
                == "Rang today, Sun 22 Nov at 21:30, 1 step to go")

        // Every step checked off: the alarm counts down to its next ring again.
        let checked = RoutineCompletion(
            routineId: tuesday.id, stepId: tuesday.steps[0].id, cycle: cycle.stamp, completedAt: now)
        let cleared = AlertsState(routines: [morning, tuesday], routineCompletions: [checked])
        #expect(AlarmList.underWay(tuesday, in: cleared, now: now, calendar: calendar) == nil)
        let after = AlarmList.ordered([morning, tuesday], in: cleared, now: now, calendar: calendar)
        #expect(after.map(\.label) == ["wake up", "night routine, hyaluronic"])
        #expect(
            RingClock.text(for: tuesday, in: cleared, at: now, calendar: calendar)
                == "Rings in 1 day 23:59:00, Tue 24 Nov at 21:30")

        // Skipped: nothing is left to do.
        let skipped = RoutineOutcome(routineId: tuesday.id, cycle: cycle.stamp, status: .skipped, at: now)
        let gone = AlertsState(routines: [morning, tuesday], routineOutcomes: [skipped])
        #expect(AlarmList.underWay(tuesday, in: gone, now: now, calendar: calendar) == nil)
    }

    @Test func aRungAlarmWithoutStepsMovesOnAtOnce() {
        var plain = routine(6, "plain", 21, 30, days: [1, 2, 3, 4, 5, 6, 7])
        plain.steps = []
        let state = AlertsState(routines: [plain])
        #expect(AlarmList.underWay(plain, in: state, now: at(21, 31, day: 22), calendar: calendar) == nil)
    }

    @Test func aRingTimeNamesItsDay() {
        let now = at(21, 36, day: 22)
        #expect(RingDay.word(at(21, 31, day: 22), now: now, calendar: calendar) == "today, Sun 22 Nov")
        #expect(RingDay.word(at(7, 5, day: 23), now: now, calendar: calendar) == "tomorrow, Mon 23 Nov")
        #expect(RingDay.word(at(21, 30, day: 21), now: now, calendar: calendar) == "yesterday, Sat 21 Nov")
        #expect(RingDay.word(at(21, 31, day: 24), now: now, calendar: calendar) == "Tue 24 Nov")
        #expect(RingDay.time(at(7, 5, day: 23), now: now, calendar: calendar) == "tomorrow, Mon 23 Nov at 07:05")
    }
}
