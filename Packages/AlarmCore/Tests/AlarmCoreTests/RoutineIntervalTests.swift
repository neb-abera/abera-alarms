import Foundation
import Testing

@testable import AlarmCore

/// A routine that repeats every N weeks on its days, or every N minutes,
/// hours, days, weeks, months, or years from a start date. Neb asked on
/// 2026-11-25: he could not set an alarm for every 97 minutes, or every
/// other week.
@Suite struct RoutineIntervalTests {
    static let id = UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000ABCD")!
    static let key = "routine:0a1b2c3d-0000-4000-8000-00000000abcd:"
    static let newYork = RoutineRingTests.newYork

    func at(_ text: String) -> Date { ServerDates.parse(text)! }

    func interval(_ hour: Int, _ minute: Int, every: Int, _ unit: RoutineUnit, from start: String?)
        -> RoutineSchedule
    {
        RoutineSchedule(
            hour: hour, minute: minute, days: [], snoozeMinutes: 9, repeatMode: .interval, every: every, unit: unit,
            startsOn: start)
    }

    func weeks(_ hour: Int, _ minute: Int, days: [Int], every: Int, from start: String?) -> RoutineSchedule {
        RoutineSchedule(
            hour: hour, minute: minute, days: days, snoozeMinutes: 9, repeatMode: .weekdays, every: every,
            unit: .weeks, startsOn: start)
    }

    /// The next `count` rings after `now`.
    func rings(_ schedule: RoutineSchedule, after now: Date, _ count: Int) -> [Date] {
        var out: [Date] = []
        var after = now
        while out.count < count, let next = schedule.nextFire(after: after, calendar: Self.newYork) {
            out.append(next)
            after = next
        }
        return out
    }

    func stamps(_ schedule: RoutineSchedule, _ rings: [Date]) -> [String] {
        rings.map { schedule.stamp(of: $0, calendar: Self.newYork) }
    }

    // MARK: Every N minutes and hours

    @Test func every97MinutesCrossesMidnightAndEachRingCarriesItsOwnTime() {
        let schedule = interval(21, 0, every: 97, .minutes, from: "2026-11-25")
        let found = rings(schedule, after: at("2026-11-25T20:00:00-05:00"), 5)
        #expect(
            found == [
                at("2026-11-25T21:00:00-05:00"), at("2026-11-25T22:37:00-05:00"), at("2026-11-26T00:14:00-05:00"),
                at("2026-11-26T01:51:00-05:00"), at("2026-11-26T03:28:00-05:00"),
            ])
        let named = stamps(schedule, found)
        #expect(
            named == [
                "2026-11-25T21:00", "2026-11-25T22:37", "2026-11-26T00:14", "2026-11-26T01:51", "2026-11-26T03:28",
            ])
        #expect(Set(named).count == named.count)
    }

    @Test func theFirstRingIsTheStartAndNothingRingsBeforeIt() {
        let schedule = interval(21, 0, every: 97, .minutes, from: "2026-11-25")
        #expect(
            schedule.nextFire(after: at("2026-11-20T09:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-25T21:00:00-05:00"))
        #expect(schedule.lastFire(atOrBefore: at("2026-11-25T20:59:59-05:00"), calendar: Self.newYork) == nil)
        #expect(
            schedule.lastFire(atOrBefore: at("2026-11-25T21:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-25T21:00:00-05:00"))
        // A ring is never its own next ring.
        #expect(
            schedule.nextFire(after: at("2026-11-25T21:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-25T22:37:00-05:00"))
    }

    @Test func everyTwoHoursIsElapsedTimeWhenTheClocksGoForward() {
        // 14 March 2027: 02:00 becomes 03:00 in New York.
        let schedule = interval(23, 30, every: 2, .hours, from: "2027-03-13")
        let found = rings(schedule, after: at("2027-03-13T23:00:00-05:00"), 4)
        #expect(
            found == [
                at("2027-03-13T23:30:00-05:00"), at("2027-03-14T01:30:00-05:00"), at("2027-03-14T04:30:00-04:00"),
                at("2027-03-14T06:30:00-04:00"),
            ])
        #expect(
            stamps(schedule, found) == ["2027-03-13T23:30", "2027-03-14T01:30", "2027-03-14T04:30", "2027-03-14T06:30"])
    }

    @Test func everyTwoHoursIsElapsedTimeWhenTheClocksGoBack() {
        // 1 November 2026: 02:00 becomes 01:00 in New York.
        let schedule = interval(23, 30, every: 2, .hours, from: "2026-10-31")
        let found = rings(schedule, after: at("2026-10-31T23:00:00-04:00"), 4)
        #expect(
            found == [
                at("2026-10-31T23:30:00-04:00"), at("2026-11-01T01:30:00-04:00"), at("2026-11-01T02:30:00-05:00"),
                at("2026-11-01T04:30:00-05:00"),
            ])
        #expect(
            stamps(schedule, found) == ["2026-10-31T23:30", "2026-11-01T01:30", "2026-11-01T02:30", "2026-11-01T04:30"])
    }

    @Test func aRingInTheSecondPassStaysWhenNoEarlierRingReadTheSameTime() {
        // 00:30, then two hours on is 01:30 for the second time. 01:30 the
        // first time was not a ring, so nothing is dropped.
        let schedule = interval(0, 30, every: 2, .hours, from: "2026-11-01")
        let found = rings(schedule, after: at("2026-11-01T00:00:00-04:00"), 3)
        #expect(
            found == [
                at("2026-11-01T00:30:00-04:00"), at("2026-11-01T01:30:00-05:00"), at("2026-11-01T03:30:00-05:00"),
            ])
        #expect(stamps(schedule, found) == ["2026-11-01T00:30", "2026-11-01T01:30", "2026-11-01T03:30"])
    }

    @Test func everyThirtyMinutesDropsTheRingsThatWouldRepeatAStampWhenTheClocksGoBack() {
        let schedule = interval(0, 0, every: 30, .minutes, from: "2026-11-01")
        let found = rings(schedule, after: at("2026-10-31T23:59:00-04:00"), 6)
        // 01:00 and 01:30 come twice. The second pass is dropped.
        #expect(
            found == [
                at("2026-11-01T00:00:00-04:00"), at("2026-11-01T00:30:00-04:00"), at("2026-11-01T01:00:00-04:00"),
                at("2026-11-01T01:30:00-04:00"), at("2026-11-01T02:00:00-05:00"), at("2026-11-01T02:30:00-05:00"),
            ])
        let named = stamps(schedule, found)
        #expect(Set(named).count == 6)
        #expect(named[3] == "2026-11-01T01:30" && named[4] == "2026-11-01T02:00")
        // Looking back from the dropped rings finds the last one that rang.
        #expect(
            schedule.lastFire(atOrBefore: at("2026-11-01T01:45:00-05:00"), calendar: Self.newYork)
                == at("2026-11-01T01:30:00-04:00"))
    }

    @Test func aStartFarInThePastWithAOneMinuteStepAnswersFast() {
        let schedule = interval(0, 0, every: 1, .minutes, from: "1990-01-01")
        let now = at("2026-11-25T08:00:30-05:00")
        let clock = ContinuousClock()
        var next: Date?
        var last: Date?
        let took = clock.measure {
            for _ in 0..<200 {
                next = schedule.nextFire(after: now, calendar: Self.newYork)
                last = schedule.lastFire(atOrBefore: now, calendar: Self.newYork)
            }
        }
        #expect(next == at("2026-11-25T08:01:00-05:00"))
        #expect(last == at("2026-11-25T08:00:00-05:00"))
        // 19 million rings lie between the start and now. A walk would take minutes.
        #expect(took < .seconds(2), "\(took)")

        let routine = Routine(
            id: Self.id, label: "Sip", hour: 0, minute: 0, days: [], repeatMode: .interval, every: 1, unit: .minutes,
            startsOn: "1990-01-01")
        var cycles: [RoutineCycle] = []
        let listing = clock.measure {
            for _ in 0..<50 {
                cycles = RoutineCycle.upcoming(routine, now: now, ahead: 7 * 86_400, calendar: Self.newYork)
            }
        }
        #expect(cycles.count == 16)
        #expect(cycles.first?.stamp == "2026-11-25T08:00" && cycles.last?.stamp == "2026-11-25T08:15")
        #expect(listing < .seconds(2), "\(listing)")
    }

    // MARK: Every N days, weeks, months, and years

    @Test func everyThreeDaysKeepsTheTimeOnTheClock() {
        let schedule = interval(7, 0, every: 3, .days, from: "2026-11-25")
        let found = rings(schedule, after: at("2026-11-25T07:00:00-05:00"), 3)
        #expect(
            found == [
                at("2026-11-28T07:00:00-05:00"), at("2026-12-01T07:00:00-05:00"), at("2026-12-04T07:00:00-05:00"),
            ])
        #expect(stamps(schedule, found) == ["2026-11-28T07:00", "2026-12-01T07:00", "2026-12-04T07:00"])
        #expect(
            schedule.lastFire(atOrBefore: at("2026-11-30T12:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-28T07:00:00-05:00"))
        // On a ring day before the time, the last ring is the one before.
        #expect(
            schedule.lastFire(atOrBefore: at("2026-11-28T06:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-25T07:00:00-05:00"))
    }

    @Test func everyDayKeepsItsTimeAcrossTheClockChange() {
        let schedule = interval(7, 0, every: 1, .days, from: "2026-10-31")
        #expect(
            rings(schedule, after: at("2026-10-31T06:00:00-04:00"), 3) == [
                at("2026-10-31T07:00:00-04:00"), at("2026-11-01T07:00:00-05:00"), at("2026-11-02T07:00:00-05:00"),
            ])
    }

    @Test func aDayRingTheClocksSkipRingsAtTheNextTimeAndKeepsItsStamp() {
        // 02:30 does not exist on 14 March 2027.
        let schedule = interval(2, 30, every: 1, .days, from: "2027-03-13")
        let found = rings(schedule, after: at("2027-03-13T12:00:00-05:00"), 1)
        #expect(found == [at("2027-03-14T03:00:00-04:00")])
        #expect(stamps(schedule, found) == ["2027-03-14T02:30"])
    }

    @Test func everyTwoWeeksRingsOnTheStartsWeekday() {
        let schedule = interval(7, 0, every: 2, .weeks, from: "2026-11-25")
        #expect(
            rings(schedule, after: at("2026-11-24T00:00:00-05:00"), 3) == [
                at("2026-11-25T07:00:00-05:00"), at("2026-12-09T07:00:00-05:00"), at("2026-12-23T07:00:00-05:00"),
            ])
        #expect(
            schedule.lastFire(atOrBefore: at("2026-12-22T00:00:00-05:00"), calendar: Self.newYork)
                == at("2026-12-09T07:00:00-05:00"))
    }

    @Test func everyMonthFromThe31stSkipsTheMonthsWithoutOne() {
        let schedule = interval(8, 0, every: 1, .months, from: "2027-01-31")
        let found = rings(schedule, after: at("2027-01-01T00:00:00-05:00"), 5)
        #expect(
            found == [
                at("2027-01-31T08:00:00-05:00"), at("2027-03-31T08:00:00-04:00"), at("2027-05-31T08:00:00-04:00"),
                at("2027-07-31T08:00:00-04:00"), at("2027-08-31T08:00:00-04:00"),
            ])
        #expect(stamps(schedule, found).first == "2027-01-31T08:00")
        // In April the last ring is March's: February and April have no 31st.
        #expect(
            schedule.lastFire(atOrBefore: at("2027-04-30T23:00:00-04:00"), calendar: Self.newYork)
                == at("2027-03-31T08:00:00-04:00"))
    }

    @Test func everyYearFrom29FebruaryRingsInLeapYearsOnly() {
        let schedule = interval(8, 0, every: 1, .years, from: "2028-02-29")
        #expect(
            rings(schedule, after: at("2028-01-01T00:00:00-05:00"), 3) == [
                at("2028-02-29T08:00:00-05:00"), at("2032-02-29T08:00:00-05:00"), at("2036-02-29T08:00:00-05:00"),
            ])
        #expect(
            schedule.lastFire(atOrBefore: at("2031-06-01T00:00:00-04:00"), calendar: Self.newYork)
                == at("2028-02-29T08:00:00-05:00"))
    }

    @Test func everyTwoYearsCountsYears() {
        let schedule = interval(8, 0, every: 2, .years, from: "2026-11-25")
        #expect(
            rings(schedule, after: at("2026-11-25T08:00:00-05:00"), 2) == [
                at("2028-11-25T08:00:00-05:00"), at("2030-11-25T08:00:00-05:00"),
            ])
    }

    @Test func aSeriesPastTheCalendarsEndHasNoNextRing() {
        let schedule = interval(8, 0, every: 999, .years, from: "9500-01-01")
        #expect(schedule.nextFire(after: at("2026-11-25T08:00:00-05:00"), calendar: Self.newYork) != nil)
        let late = Self.newYork.date(from: DateComponents(year: 9500, month: 6, day: 1))!
        #expect(schedule.nextFire(after: late, calendar: Self.newYork) == nil)
    }

    // MARK: Weekdays every N weeks

    @Test func everyTwoWeeksOnMonWedFriStartsOnItsDateAndSkipsTheOffWeek() {
        // Wednesday 25 November 2026. That week's Monday is before the start.
        let schedule = weeks(6, 30, days: [1, 3, 5], every: 2, from: "2026-11-25")
        let found = rings(schedule, after: at("2026-11-23T00:00:00-05:00"), 6)
        #expect(
            found == [
                at("2026-11-25T06:30:00-05:00"), at("2026-11-27T06:30:00-05:00"), at("2026-12-07T06:30:00-05:00"),
                at("2026-12-09T06:30:00-05:00"), at("2026-12-11T06:30:00-05:00"), at("2026-12-21T06:30:00-05:00"),
            ])
        #expect(stamps(schedule, found).prefix(3) == ["2026-11-25T06:30", "2026-11-27T06:30", "2026-12-07T06:30"])
        // In the off week the last ring is the Friday before it.
        #expect(
            schedule.lastFire(atOrBefore: at("2026-12-03T12:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-27T06:30:00-05:00"))
        // On the start's own Monday nothing has rung.
        #expect(schedule.lastFire(atOrBefore: at("2026-11-24T12:00:00-05:00"), calendar: Self.newYork) == nil)
        #expect(
            schedule.lastFire(atOrBefore: at("2026-12-07T06:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-27T06:30:00-05:00"))
    }

    @Test func aSundayStartCountsItsWeekFromTheMondayBefore() {
        // Sunday 29 November 2026 is in the week of Monday 23 November.
        let schedule = weeks(9, 0, days: [1, 7], every: 3, from: "2026-11-29")
        #expect(
            rings(schedule, after: at("2026-11-23T00:00:00-05:00"), 3) == [
                at("2026-11-29T09:00:00-05:00"), at("2026-12-14T09:00:00-05:00"), at("2026-12-20T09:00:00-05:00"),
            ])
    }

    @Test func weekdaysEveryWeekRingAsBefore() {
        let old = RoutineSchedule(hour: 5, minute: 30, days: [1, 2, 3, 4, 5], snoozeMinutes: 9)
        #expect(old.fitsSystemRepeat && !old.ringsOnce)
        #expect(
            old.nextFire(after: at("2026-11-27T07:00:00-05:00"), calendar: Self.newYork)
                == at("2026-11-30T05:30:00-05:00"))
        #expect(old.stamp(of: at("2026-11-30T05:30:00-05:00"), calendar: Self.newYork) == "2026-11-30T05:30")
        #expect(old.lastFire(atOrBefore: at("2026-11-30T06:00:00-05:00"), calendar: Self.newYork) == nil)
    }

    @Test func aRepeatThatNeedsAStartDateAndHasNoneNeverRings() {
        let now = at("2026-11-25T08:00:00-05:00")
        #expect(interval(8, 0, every: 2, .hours, from: nil).nextFire(after: now, calendar: Self.newYork) == nil)
        #expect(interval(8, 0, every: 2, .days, from: "soon").nextFire(after: now, calendar: Self.newYork) == nil)
        #expect(
            weeks(8, 0, days: [1], every: 2, from: nil).lastFire(atOrBefore: now, calendar: Self.newYork) == nil)
        // An N outside 1 to 999 is held to it.
        #expect(
            interval(8, 0, every: 0, .hours, from: "2026-11-25").nextFire(after: now, calendar: Self.newYork)
                == at("2026-11-25T09:00:00-05:00"))
    }

    // MARK: Which routines the alarm system repeats

    @Test func onlyWeekdaysEveryWeekAndRingOnceFitTheAlarmSystem() {
        #expect(weeks(6, 0, days: [1], every: 1, from: nil).fitsSystemRepeat)
        #expect(weeks(6, 0, days: [], every: 1, from: nil).fitsSystemRepeat)
        #expect(weeks(6, 0, days: [], every: 1, from: nil).ringsOnce)
        #expect(!weeks(6, 0, days: [1], every: 2, from: "2026-11-25").fitsSystemRepeat)
        #expect(!interval(6, 0, every: 1, .days, from: "2026-11-25").fitsSystemRepeat)
        // An interval has no days and still repeats.
        #expect(!interval(6, 0, every: 1, .days, from: "2026-11-25").ringsOnce)
        let water = Routine(
            id: Self.id, label: "Water", hour: 6, minute: 0, days: [], repeatMode: .interval, every: 97,
            unit: .minutes, startsOn: "2026-11-25")
        #expect(water.repeats)
        #expect(!Routine(id: Self.id, label: "Once", hour: 6, minute: 0, days: []).repeats)
    }

    // MARK: Stamps and keys

    @Test func anIntervalRingsKeyCarriesTheTimeItRingsAt() {
        let schedule = interval(21, 0, every: 97, .minutes, from: "2026-11-25")
        let ring = at("2026-11-26T00:14:00-05:00")
        #expect(
            RoutineRing.key(routineID: Self.id, schedule: schedule, ring: ring, calendar: Self.newYork)
                == Self.key + "2026-11-26T00:14")
        // Stop within the window names the latest ring.
        #expect(
            RoutineRing.key(
                routineID: Self.id, schedule: schedule, stoppedAt: at("2026-11-26T00:20:00-05:00"),
                window: 60 * 60, calendar: Self.newYork) == Self.key + "2026-11-26T00:14")
        // A ring longer ago than the window names none.
        let monthly = interval(8, 0, every: 1, .months, from: "2026-11-25")
        #expect(
            RoutineRing.key(
                routineID: Self.id, schedule: monthly, stoppedAt: at("2026-11-26T08:00:00-05:00"),
                window: 60 * 60, calendar: Self.newYork) == nil)
    }

    @Test func aCycleAndItsStepsAreNamedByTheRingsOwnStamp() {
        let step = RoutineStep(
            id: UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000051")!, label: "Stretch", offsetMinutes: 5)
        var routine = Routine(
            id: Self.id, label: "Water", hour: 21, minute: 0, days: [], steps: [step], repeatMode: .interval,
            every: 97, unit: .minutes, startsOn: "2026-11-25")
        let cycle = RoutineCycle.make(routine, at: at("2026-11-26T00:14:00-05:00"), calendar: Self.newYork)
        #expect(cycle.stamp == "2026-11-26T00:14")
        #expect(cycle.key == Self.key + "2026-11-26T00:14")
        #expect(cycle.steps.first?.key == Self.key + "2026-11-26T00:14:step:0a1b2c3d-0000-4000-8000-000000000051")
        #expect(cycle.steps.first?.at == at("2026-11-26T00:19:00-05:00"))
        // A delay moves the ring and its step. The stamp stays.
        routine.delays = ["2026-11-26T00:14": 30]
        let moved = RoutineCycle.make(routine, at: at("2026-11-26T00:14:00-05:00"), calendar: Self.newYork)
        #expect(moved.stamp == "2026-11-26T00:14")
        #expect(moved.at == at("2026-11-26T00:44:00-05:00"))
        #expect(moved.steps.first?.at == at("2026-11-26T00:49:00-05:00"))
    }

    // MARK: Cycles

    @Test func aRingAtOrBeforeTheLastSaveDidNotRing() {
        var routine = Routine(
            id: Self.id, label: "Water", hour: 9, minute: 0, days: [], repeatMode: .interval, every: 1,
            unit: .hours, startsOn: "2026-11-20")
        let now = at("2026-11-25T08:45:00-05:00")
        // Saved at 08:30: the 08:00 ring was before it.
        routine.updatedAt = at("2026-11-25T08:30:00-05:00")
        var around = RoutineCycle.around(routine, now: now, calendar: Self.newYork)
        #expect(around.current == nil)
        #expect(around.next?.stamp == "2026-11-25T09:00")
        // Saved at 08:00 exactly: still not rung.
        routine.updatedAt = at("2026-11-25T08:00:00-05:00")
        #expect(RoutineCycle.around(routine, now: now, calendar: Self.newYork).current == nil)
        // Saved the day before, or at a time not known: 08:00 rang.
        routine.updatedAt = at("2026-11-24T08:30:00-05:00")
        around = RoutineCycle.around(routine, now: now, calendar: Self.newYork)
        #expect(around.current?.stamp == "2026-11-25T08:00")
        routine.updatedAt = nil
        #expect(RoutineCycle.around(routine, now: now, calendar: Self.newYork).current?.stamp == "2026-11-25T08:00")
    }

    @Test func aMonthlyAlarmFindsItsLastRingWeeksBack() {
        let routine = Routine(
            id: Self.id, label: "Rent", hour: 8, minute: 0, days: [], repeatMode: .interval, every: 1,
            unit: .months, startsOn: "2026-10-01")
        let around = RoutineCycle.around(routine, now: at("2026-11-25T12:00:00-05:00"), calendar: Self.newYork)
        #expect(around.current?.stamp == "2026-11-01T08:00")
        #expect(around.next?.stamp == "2026-12-01T08:00")
        // The next ring is listed however far off it is.
        let ahead = RoutineCycle.upcoming(
            routine, now: at("2026-11-25T12:00:00-05:00"), ahead: 7 * 86_400, calendar: Self.newYork)
        #expect(ahead.map(\.stamp) == ["2026-11-01T08:00", "2026-12-01T08:00"])
    }

    // MARK: The words

    @Test(arguments: [
        (RoutineRepeat.weekdays, 1, RoutineUnit.weeks, [Int](), "No repeat"),
        (.weekdays, 1, .weeks, Array(1...7), "Every day"),
        (.weekdays, 1, .weeks, [1, 2, 3, 4, 5], "Weekdays"),
        (.weekdays, 1, .weeks, [6, 7], "Weekends"),
        (.weekdays, 1, .weeks, [5, 1, 3], "Mon Wed Fri"),
        (.weekdays, 2, .weeks, [5, 1, 3], "Every 2 weeks on Mon Wed Fri"),
        (.weekdays, 3, .weeks, [1, 2, 3, 4, 5], "Every 3 weeks on Mon Tue Wed Thu Fri"),
        (.weekdays, 2, .weeks, [Int](), "No repeat"),
        (.interval, 97, .minutes, [Int](), "Every 97 minutes"),
        (.interval, 1, .minutes, [Int](), "Every minute"),
        (.interval, 1, .hours, [Int](), "Every hour"),
        (.interval, 3, .days, [Int](), "Every 3 days"),
        (.interval, 2, .weeks, [Int](), "Every 2 weeks"),
        (.interval, 1, .months, [Int](), "Every month"),
        (.interval, 1, .years, [Int](), "Every year"),
        (.interval, 999, .years, [Int](), "Every 999 years"),
    ])
    func theRepeatReadsAsAberaTechWritesIt(
        mode: RoutineRepeat, every: Int, unit: RoutineUnit, days: [Int], text: String
    ) {
        #expect(Routine.repeatText(repeatMode: mode, every: every, unit: unit, days: days) == text)
        let routine = Routine(
            id: Self.id, label: "A", hour: 6, minute: 0, days: days, repeatMode: mode, every: every, unit: unit,
            startsOn: "2026-11-25")
        #expect(routine.repeatText == text)
        // A routine on weekdays every week reads as it always has.
        if mode == .weekdays, every == 1 { #expect(routine.repeatText == routine.daysText) }
    }

    @Test func theEditorsNoteSaysWhatTheAlarmWillDo() {
        let today = CivilDate(year: 2026, month: 11, day: 25)!
        #expect(
            RoutineDraft(hour: 6, minute: 0).repeatNote(today: today)
                == "No repeat. It rings on the next day at this time until you stop it, then switches off.")
        #expect(
            RoutineDraft(hour: 6, minute: 0, days: [2, 4]).repeatNote(today: today)
                == "Repeats: Tue Thu. It rings until you stop it.")
        #expect(
            RoutineDraft(
                hour: 6, minute: 0, repeatMode: .interval, every: 97, unit: .minutes, startsOn: "2026-11-25"
            ).repeatNote(today: today)
                == "Repeats: Every 97 minutes, from Wed 25 Nov. It rings until you stop it. The phone sets the next rings each time it syncs."
        )
        #expect(
            RoutineDraft(
                hour: 6, minute: 0, days: [2, 4], repeatMode: .weekdays, every: 2, unit: .weeks,
                startsOn: "2027-01-05"
            ).repeatNote(today: today)
                == "Repeats: Every 2 weeks on Tue Thu, from Tue 5 Jan 2027. It rings until you stop it. The phone sets the next rings each time it syncs."
        )
        #expect(
            RoutineDraft(hour: 6, minute: 0, repeatMode: .weekdays, every: 2, unit: .weeks, startsOn: "2026-11-25")
                .repeatNote(today: today) == "Choose the days it rings on.")
        // With no start date the note leaves it out.
        #expect(
            RoutineDraft(hour: 6, minute: 0, repeatMode: .interval, every: 1, unit: .hours).repeatNote(today: today)
                .hasPrefix("Repeats: Every hour. It rings"))
    }

    @Test func aUnitNamesItselfForOneAndForMore() {
        #expect(RoutineUnit.allCases.map { $0.name(1) } == ["minute", "hour", "day", "week", "month", "year"])
        #expect(RoutineUnit.allCases.map { $0.name(2) } == ["minutes", "hours", "days", "weeks", "months", "years"])
    }

    // MARK: Drafts

    func draft(
        days: [Int] = [], _ mode: RoutineRepeat, every: Int = 1, _ unit: RoutineUnit = .weeks, from start: String? = nil
    ) -> RoutineDraft {
        RoutineDraft(hour: 6, minute: 0, days: days, repeatMode: mode, every: every, unit: unit, startsOn: start)
    }

    @Test func aDraftIsCheckedByTheRulesAberaTechChecks() {
        // Weekdays every week: as before. The start date is ignored.
        #expect(draft(days: [1, 3], .weekdays).problems.isEmpty)
        #expect(draft(.weekdays).problems.isEmpty)
        #expect(draft(days: [1], .weekdays, from: "not a date").problems.isEmpty)
        // Weekdays count in weeks.
        #expect(
            draft(days: [1], .weekdays, every: 1, .days).problems == ["An alarm on days of the week repeats in weeks."])
        // Every N weeks needs days and a start date.
        #expect(draft(days: [1, 3], .weekdays, every: 2, from: "2026-11-25").problems.isEmpty)
        #expect(draft(.weekdays, every: 2, from: "2026-11-25").problems == ["Choose the days it rings on."])
        #expect(draft(days: [1], .weekdays, every: 2).problems == ["Choose the date it starts on."])
        // An interval has no days and needs a start date.
        for unit in RoutineUnit.allCases {
            #expect(draft(.interval, every: 97, unit, from: "2026-11-25").problems.isEmpty)
        }
        #expect(
            draft(days: [1], .interval, every: 2, .hours, from: "2026-11-25").problems
                == ["An alarm that repeats by interval has no days of the week."])
        #expect(draft(.interval, every: 2, .hours).problems == ["Choose the date it starts on."])
        #expect(draft(.interval, every: 2, .hours, from: "2026-02-30").problems == ["Choose the date it starts on."])
        #expect(draft(.interval, every: 2, .hours, from: "25 Nov").problems == ["Choose the date it starts on."])
        // N is 1 to 999.
        #expect(draft(.interval, every: 0, .hours, from: "2026-11-25").problems == ["Repeat every 1 to 999."])
        #expect(draft(.interval, every: 1000, .hours, from: "2026-11-25").problems == ["Repeat every 1 to 999."])
        #expect(draft(.interval, every: 999, .hours, from: "2026-11-25").problems.isEmpty)
        #expect(draft(.interval, every: 1, .hours, from: "2026-11-25").repeatProblems.isEmpty)
    }

    @Test func theBodyCarriesTheRepeatAndDropsAStartDateWeekdaysDoNotUse() throws {
        let water = draft(.interval, every: 97, .minutes, from: "2026-11-25")
        let sent = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(water.body)) as? [String: Any])
        #expect(sent["repeat"] as? String == "interval")
        #expect(sent["every"] as? Int == 97)
        #expect(sent["unit"] as? String == "minutes")
        #expect(sent["startsOn"] as? String == "2026-11-25")
        #expect(sent["days"] as? [Int] == [])

        let plain = draft(days: [3, 1], .weekdays, from: "2026-11-25")
        let body = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(plain.body)) as? [String: Any])
        #expect(body["repeat"] as? String == "weekdays")
        #expect(body["every"] as? Int == 1)
        #expect(body["unit"] as? String == "weeks")
        #expect(body["startsOn"] == nil)
        #expect(body["days"] as? [Int] == [1, 3])

        let fortnight = draft(days: [1], .weekdays, every: 2, from: "2026-11-25").body
        #expect(fortnight.startsOn == "2026-11-25")
    }

    @Test func theClientSendsTheRepeatOnCreateAndUpdate() async throws {
        let transport = ScriptedTransport(body: Data(#"{"configured":true,"alerts":[]}"#.utf8))
        let client = AlertsClient(pairing: Fixtures.pairing, transport: transport)
        _ = try await client.createRoutine(draft(.interval, every: 97, .minutes, from: "2026-11-25"))
        var body = try #require(await transport.last?.httpBody)
        var sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["repeat"] as? String == "interval" && sent["every"] as? Int == 97)
        #expect(sent["unit"] as? String == "minutes" && sent["startsOn"] as? String == "2026-11-25")

        _ = try await client.updateRoutine(id: Self.id, draft(days: [2, 4], .weekdays, every: 2, from: "2026-11-24"))
        body = try #require(await transport.last?.httpBody)
        sent = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["repeat"] as? String == "weekdays" && sent["every"] as? Int == 2)
        #expect(sent["unit"] as? String == "weeks" && sent["startsOn"] as? String == "2026-11-24")
    }

    @Test func aRoutinesDraftAndScheduleCarryItsRepeat() {
        let water = Routine(
            id: Self.id, label: "Water", hour: 21, minute: 0, days: [], repeatMode: .interval, every: 97,
            unit: .minutes, startsOn: "2026-11-25")
        #expect(
            water.draft
                == RoutineDraft(
                    label: "Water", hour: 21, minute: 0, repeatMode: .interval, every: 97, unit: .minutes,
                    startsOn: "2026-11-25"))
        #expect(water.schedule == interval(21, 0, every: 97, .minutes, from: "2026-11-25"))
        // Weekdays every week carries no start date, whatever was stored.
        let wake = Routine(
            id: Self.id, label: "Wake", hour: 5, minute: 30, days: [3, 1], repeatMode: .weekdays, every: 1,
            unit: .weeks, startsOn: "2026-11-25")
        #expect(wake.schedule == RoutineSchedule(hour: 5, minute: 30, days: [1, 3], snoozeMinutes: 9))
    }

    @Test func aChangeMadeOnThePhoneShowsItsRepeatBeforeAberaTechHasIt() {
        let water = draft(.interval, every: 97, .minutes, from: "2026-11-25")
        let local = UUID()
        var state = RoutineChange.overlay(AlertsState(configured: true), [.create(local: local, draft: water)])
        #expect(state.routines.first?.repeatMode == .interval)
        #expect(state.routines.first?.every == 97 && state.routines.first?.unit == .minutes)
        #expect(state.routines.first?.startsOn == "2026-11-25")
        state = RoutineChange.overlay(
            state, [.update(id: local, draft: draft(days: [1], .weekdays, every: 2, from: "2026-11-23"))])
        #expect(state.routines.first?.repeatText == "Every 2 weeks on Mon")
        #expect(state.routines.first?.startsOn == "2026-11-23")
    }

    // MARK: Reading what an older build or server wrote

    @Test func aRoutineFromAnOlderServerReadsAsWeekdaysEveryWeek() throws {
        let json = #"{"id":"0A1B2C3D-0000-4000-8000-00000000ABCD","label":"Wake","hour":5,"minute":30,"days":[1,2]}"#
        let routine = try ServerDates.decoder().decode(Routine.self, from: Data(json.utf8))
        #expect(routine.repeatMode == .weekdays && routine.every == 1 && routine.unit == .weeks)
        #expect(routine.startsOn == nil)
        #expect(routine.repeatText == "Mon Tue")
        #expect(routine.schedule.fitsSystemRepeat)
    }

    @Test func aRoutineReadsItsRepeatAndWritesItBack() throws {
        let json =
            #"{"id":"0A1B2C3D-0000-4000-8000-00000000ABCD","label":"Water","hour":21,"minute":0,"days":[],"repeat":"interval","every":97,"unit":"minutes","startsOn":"2026-11-25"}"#
        let routine = try ServerDates.decoder().decode(Routine.self, from: Data(json.utf8))
        #expect(routine.repeatMode == .interval && routine.every == 97 && routine.unit == .minutes)
        #expect(routine.startsOn == "2026-11-25")
        let again = try ServerDates.decoder().decode(Routine.self, from: ServerDates.encoder().encode(routine))
        #expect(again == routine)
        let written = try #require(
            JSONSerialization.jsonObject(with: ServerDates.encoder().encode(routine)) as? [String: Any])
        #expect(written["repeat"] as? String == "interval")
    }

    @Test func anUnknownRepeatOrUnitReadsAsTheDefault() throws {
        let json =
            #"{"id":"0A1B2C3D-0000-4000-8000-00000000ABCD","hour":5,"minute":30,"days":[1],"repeat":"lunar","every":"often","unit":"fortnights","startsOn":20261125}"#
        let routine = try ServerDates.decoder().decode(Routine.self, from: Data(json.utf8))
        #expect(routine.repeatMode == .weekdays && routine.every == 1 && routine.unit == .weeks)
        #expect(routine.startsOn == nil)
        let schedule = try JSONDecoder().decode(
            RoutineSchedule.self,
            from: Data(#"{"hour":5,"minute":30,"days":[1],"snoozeMinutes":9,"repeat":"lunar","unit":"eons"}"#.utf8))
        #expect(schedule == RoutineSchedule(hour: 5, minute: 30, days: [1], snoozeMinutes: 9))
        let draft = try JSONDecoder().decode(
            RoutineDraft.self, from: Data(#"{"label":"A","hour":5,"minute":30,"repeat":7,"unit":null}"#.utf8))
        #expect(draft.repeatMode == .weekdays && draft.unit == .weeks && draft.every == 1)
    }

    @Test func aScheduleAndADraftStoredByAnOlderBuildStillRead() throws {
        let schedule = try JSONDecoder().decode(
            RoutineSchedule.self, from: Data(#"{"hour":5,"minute":30,"days":[1,2],"snoozeMinutes":9}"#.utf8))
        #expect(schedule == RoutineSchedule(hour: 5, minute: 30, days: [1, 2], snoozeMinutes: 9))
        #expect(schedule.fitsSystemRepeat)

        // A change queued offline by the build before intervals.
        let queued =
            #"[{"update":{"id":"0A1B2C3D-0000-4000-8000-00000000ABCD","draft":{"label":"Wake","hour":5,"minute":30,"days":[1],"enabled":true,"snoozeMinutes":9,"steps":[]}}}]"#
        let changes = try JSONDecoder().decode([RoutineChange].self, from: Data(queued.utf8))
        guard case .update(_, let draft)? = changes.first else {
            Issue.record("not an update")
            return
        }
        #expect(draft.repeatMode == .weekdays && draft.every == 1 && draft.unit == .weeks && draft.startsOn == nil)

        // The ledger's alarm for a routine, as the build before intervals wrote it.
        let held =
            #"[{"id":"0A1B2C3D-0000-4000-8000-00000000ABCD","key":"routine:0a1b2c3d-0000-4000-8000-00000000abcd","title":"Wake","fireAt":"2026-11-26T10:30:00Z","startsAt":"2026-11-26T10:30:00Z","routine":{"hour":5,"minute":30,"days":[1,2],"snoozeMinutes":9},"sound":"default","setup":2}]"#
        let ledger = try ServerDates.decoder().decode([DesiredAlarm].self, from: Data(held.utf8))
        let wake = Routine(id: Self.id, label: "Wake", hour: 5, minute: 30, days: [1, 2])
        let now = DesiredAlarm(
            id: Self.id, key: "routine:0a1b2c3d-0000-4000-8000-00000000abcd", title: "Wake", location: nil,
            fireAt: Date(), startsAt: Date(), routine: wake.schedule)
        // The alarm the phone holds still matches, so an update schedules nothing again.
        #expect(try #require(ledger.first).sameAlarm(as: now))
    }
}
