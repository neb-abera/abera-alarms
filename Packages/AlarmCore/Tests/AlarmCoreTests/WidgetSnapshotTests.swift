import Foundation
import Testing

@testable import AlarmCore

/// What the widgets show: the next ring on this phone, the next event, and
/// a countdown. The snapshot is built from what the alarm system holds, so
/// it matches the Calendar tab's Set on this phone.
@Suite struct WidgetSnapshotTests {
    let now = Fixtures.now
    static let newYork = RingClockTests.newYork

    func minutes(_ value: Double) -> Date { now.addingTimeInterval(value * 60) }

    func held(_ key: String, inMinutes value: Double) -> DesiredAlarm {
        DesiredAlarm(
            id: AlarmID.of(key: key), key: key, title: "Event \(key)", location: nil, fireAt: minutes(value),
            startsAt: minutes(value + 10))
    }

    func routine(_ label: String, _ hour: Int, _ minute: Int, days: [Int], fireAt: Date) -> DesiredAlarm {
        DesiredAlarm(
            id: UUID(), key: DesiredAlarm.routinePrefix + label, title: label, location: nil, fireAt: fireAt,
            startsAt: fireAt, routine: RoutineSchedule(hour: hour, minute: minute, days: days, snoozeMinutes: 9))
    }

    func snapshot(_ held: [DesiredAlarm], timer: WidgetSnapshot.OneTime? = nil, state: AlertsState? = nil)
        -> WidgetSnapshot
    {
        WidgetSnapshot.make(state: state, held: held, timer: timer, paired: true, now: now)
    }

    // MARK: The next ring

    @Test func theNextRingIsTheEarliestCalendarAlarmHeld() {
        let next = snapshot([held("later", inMinutes: 90), held("sooner", inMinutes: 30)]).nextRing(after: now)
        #expect(next == WidgetSnapshot.Ring(title: "Event sooner", at: minutes(30), kind: .calendar))
    }

    @Test func nothingSetSaysNothing() {
        #expect(snapshot([]).nextRing(after: now) == nil)
    }

    @Test func aRingThatPassedIsNotNext() {
        let shot = snapshot([held("a", inMinutes: 30), held("b", inMinutes: 60)])
        #expect(shot.nextRing(after: minutes(30))?.title == "Event b")
        #expect(shot.nextRing(after: minutes(61)) == nil)
    }

    @Test func aRunningTimerSoonerThanTheAlarmsIsNext() {
        let timer = WidgetSnapshot.OneTime(title: "Tea", at: minutes(5))
        let next = snapshot([held("a", inMinutes: 30)], timer: timer).nextRing(after: now)
        #expect(next == WidgetSnapshot.Ring(title: "Tea", at: minutes(5), kind: .timer))
    }

    @Test func aTimerThatRangIsLeftOut() {
        let timer = WidgetSnapshot.OneTime(title: "Tea", at: minutes(-1))
        #expect(snapshot([], timer: timer).timer == nil)
    }

    /// Monday 2026-10-05 12:00 in New York: a weekday 06:00 alarm rings next
    /// on Tuesday, and on each day after that in turn.
    @Test func aRepeatingRoutineRingsAtEachOfItsDays() {
        let monday = ServerDates.parse("2026-10-05T12:00:00-04:00")!
        let wake = routine("Wake", 6, 0, days: [1, 2, 3, 4, 5], fireAt: monday)
        let shot = WidgetSnapshot.make(state: nil, held: [wake], timer: nil, paired: true, now: monday)
        #expect(
            shot.nextRing(after: monday, calendar: Self.newYork)?.at == ServerDates.parse("2026-10-06T06:00:00-04:00"))
        let week = shot.rings(after: monday, through: monday.addingTimeInterval(7 * 86_400), calendar: Self.newYork)
        #expect(
            week.map(\.at)
                == [
                    "2026-10-06T06:00:00-04:00", "2026-10-07T06:00:00-04:00", "2026-10-08T06:00:00-04:00",
                    "2026-10-09T06:00:00-04:00", "2026-10-12T06:00:00-04:00",
                ].map { ServerDates.parse($0)! })
        #expect(week.allSatisfy { $0.kind == .routine && $0.title == "Wake" })
    }

    @Test func aRingOnceRoutineRingsOnceAtItsTime() {
        let once = routine("Nap", 13, 0, days: [], fireAt: minutes(45))
        let shot = snapshot([once])
        #expect(shot.nextRing(after: now)?.at == minutes(45))
        #expect(shot.nextRing(after: minutes(46)) == nil)
    }

    @Test func aRoutineSoonerThanTheCalendarAlarmIsNext() {
        let monday = ServerDates.parse("2026-10-05T05:00:00-04:00")!
        let wake = routine("Wake", 5, 30, days: [1], fireAt: monday)
        let standup = DesiredAlarm(
            id: UUID(), key: "standup", title: "Standup", location: nil, fireAt: monday.addingTimeInterval(3600),
            startsAt: monday.addingTimeInterval(4200))
        let shot = WidgetSnapshot.make(state: nil, held: [standup, wake], timer: nil, paired: true, now: monday)
        #expect(shot.nextRing(after: monday, calendar: Self.newYork)?.title == "Wake")
        #expect(shot.nextRing(after: monday.addingTimeInterval(1900), calendar: Self.newYork)?.title == "Standup")
    }

    /// A calendar alarm days out is still found though routines are looked
    /// for a week ahead.
    @Test func aCalendarAlarmTwoWeeksOutIsNext() {
        #expect(snapshot([held("far", inMinutes: 14 * 1440)]).nextRing(after: now)?.at == minutes(14 * 1440))
    }

    @Test func theTimelineListsEveryRingInOrderUpToItsLimit() {
        let shot = snapshot([held("c", inMinutes: 30), held("a", inMinutes: 10), held("b", inMinutes: 20)])
        #expect(shot.rings(after: now, through: minutes(25)).map(\.title) == ["Event a", "Event b"])
        #expect(shot.rings(after: now, through: minutes(60), limit: 1).map(\.title) == ["Event a"])
    }

    // MARK: The next event

    @Test func theNextEventSkipsTheAlarmShown() {
        let state = Fixtures.state([
            Fixtures.alert("a", inMinutes: 30), Fixtures.alert("b", inMinutes: 40, type: AlertType.notification),
            Fixtures.alert("skipped", inMinutes: 35, skipped: true), Fixtures.alert("past", inMinutes: -30),
        ])
        let shot = snapshot([held("a", inMinutes: 30)], state: state)
        #expect(shot.events.map(\.title) == ["Event a", "Event b"])
        let ring = shot.nextRing(after: now)
        #expect(shot.nextEvent(after: now, besides: ring)?.title == "Event b")
        #expect(shot.nextEvent(after: now, besides: nil)?.title == "Event a")
    }

    /// A timer named like the event leaves the event in view: only a
    /// calendar alarm shown stands for its event.
    @Test func aTimerShownLeavesTheNextEventAsItIs() {
        let state = Fixtures.state([Fixtures.alert("a", inMinutes: 30)])
        let shot = snapshot([], timer: .init(title: "Event a", at: minutes(5)), state: state)
        #expect(shot.nextEvent(after: now, besides: shot.nextRing(after: now))?.title == "Event a")
    }

    // MARK: Countdowns

    func countdown(_ label: String, inDays days: Double, id: UUID = UUID()) -> Countdown {
        Countdown(id: id, label: label, targetAt: now.addingTimeInterval(days * 86_400), timeZone: "Asia/Amman")
    }

    @Test func aCountdownChosenIsShownWhileItExists() {
        let chosen = UUID()
        var state = Fixtures.state([])
        state.countdowns = [countdown("Home", inDays: 41), countdown("Arrived", inDays: -3, id: chosen)]
        let shot = snapshot([], state: state)
        #expect(shot.countdown(chosen, at: now)?.label == "Arrived")
        #expect(shot.countdown(UUID(), at: now)?.label == "Home")
    }

    @Test func noChoiceShowsTheNextCountdownToCome() {
        var state = Fixtures.state([])
        state.countdowns = [
            countdown("Arrived", inDays: -3), countdown("Anniversary", inDays: 100), countdown("Home", inDays: 41),
        ]
        #expect(snapshot([], state: state).countdown(nil, at: now)?.label == "Home")
    }

    @Test func withEveryCountdownPassedTheLatestShows() {
        var state = Fixtures.state([])
        state.countdowns = [countdown("Old", inDays: -30), countdown("Arrived", inDays: -3)]
        #expect(snapshot([], state: state).countdown(nil, at: now)?.label == "Arrived")
        #expect(snapshot([]).countdown(nil, at: now) == nil)
    }

    @Test func theMinuteClockReadsLikeTheCountdownsTab() {
        let target = now.addingTimeInterval(41 * 86_400 + 5 * 3600 + 12 * 60 + 33)
        #expect(Remaining(from: now, to: target).minuteText == "41 days 05:12")
        #expect(Remaining(from: now, to: now.addingTimeInterval(86_400 + 60)).minuteText == "1 day 00:01")
        #expect(Remaining(from: target, to: now).minuteText == "Passed 41 days 05:12 ago")
    }

    // MARK: Storage

    @Test func itRoundTripsAndHoldsNoToken() throws {
        var state = Fixtures.state([Fixtures.alert("a", inMinutes: 30)])
        state.countdowns = [countdown("Home", inDays: 41)]
        let shot = snapshot(
            [held("a", inMinutes: 30), routine("Wake", 6, 0, days: [1], fireAt: minutes(60))],
            timer: .init(title: "Tea", at: minutes(5)), state: state)
        let data = try shot.encoded()
        #expect(try WidgetSnapshot.decode(data) == shot)
        #expect(!String(decoding: data, as: UTF8.self).contains(Fixtures.token))
    }

    // MARK: From the sync

    /// The sync's own alarms: what it scheduled and the system still holds.
    /// An alarm that rang leaves the system and leaves the widget.
    @Test func theSnapshotFollowsWhatTheSyncHolds() async {
        let clock = Fixtures.TestClock()
        let wake = Routine(id: UUID(), label: "Wake", hour: 5, minute: 30, days: [1, 2, 3, 4, 5])
        let off = Routine(id: UUID(), label: "Weekend", hour: 8, minute: 0, days: [6, 7], enabled: false)
        let rig = Fixtures.rig(
            [Fixtures.alert("a", inMinutes: 30), Fixtures.alert("n", inMinutes: 20, type: AlertType.notification)],
            routines: [wake, off], clock: clock)
        let report = await rig.sync.sync()
        #expect(report.error == nil)
        let held = await rig.sync.heldAlarms()
        #expect(Set(held.map(\.title)) == ["Event a", "Wake"])
        let shot = WidgetSnapshot.make(state: report.state, held: held, timer: nil, paired: true, now: clock.now)
        #expect(shot.alarms.map(\.title) == ["Event a"])
        #expect(shot.routines.map(\.label) == ["Wake"])

        await rig.alarms.ring(AlarmID.of(key: "a"))
        let after = await rig.sync.heldAlarms()
        #expect(after.map(\.title) == ["Wake"])
    }

    @Test func aPhoneThatCannotReadItsAlarmsHoldsNone() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.alarms.failSystemReads()
        #expect(await rig.sync.heldAlarms().isEmpty)
    }
}
