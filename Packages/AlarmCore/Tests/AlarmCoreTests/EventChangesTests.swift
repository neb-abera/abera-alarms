import Foundation
import Testing

@testable import AlarmCore

/// Setting an event's type and making a new event, from the phone.
@Suite struct EventChangesTests {
    func heldKeys(_ rig: Fixtures.Rig) async -> Set<String> {
        Set(await rig.alarms.alarms.values.map(\.key))
    }

    func daily(_ day: Int, type: String = AlertType.none) -> PlannedAlert {
        Fixtures.alert("standup|day\(day)", inMinutes: Double(60 + day * 1440), type: type)
    }

    @Test func settingAlarmRingsEveryOccurrence() async {
        let rig = Fixtures.rig([daily(0), daily(1), Fixtures.alert("other", inMinutes: 30, type: AlertType.none)])
        _ = await rig.sync.sync()
        #expect(await heldKeys(rig).isEmpty)

        let report = await rig.sync.perform { client throws(APIError) in
            try await client.setType(key: "standup|day0", type: AlertType.alarm)
        }
        #expect(report.error == nil)
        #expect(await heldKeys(rig) == ["standup|day0", "standup|day1"])
        #expect(await rig.server.typeChanges == ["standup alarm"])
    }

    @Test(arguments: [AlertType.none, AlertType.notification, AlertType.default])
    func anyOtherTypeCancelsTheAlarms(type: String) async {
        let rig = Fixtures.rig([daily(0, type: AlertType.alarm), daily(1, type: AlertType.alarm)])
        _ = await rig.sync.sync()
        #expect(await heldKeys(rig).count == 2)
        _ = await rig.sync.perform { client throws(APIError) in
            try await client.setType(key: "standup|day1", type: type)
        }
        #expect(await heldKeys(rig).isEmpty)
    }

    @Test func aGoogleWriteFailureIsShownAndTheChoiceHolds() async {
        let rig = Fixtures.rig([daily(0)])
        await rig.server.failCalendarWrites("Google Calendar is not connected with edit access.")
        let report = await rig.sync.perform { client throws(APIError) in
            try await client.setType(key: "standup|day0", type: AlertType.alarm)
        }
        #expect(report.error == nil)
        #expect(report.state?.calendarWrite == "Google Calendar is not connected with edit access.")
        #expect(await heldKeys(rig) == ["standup|day0"])
    }

    @Test func settingTheTypeOfAnEventNoLongerListedIsNotFound() async {
        let rig = Fixtures.rig([daily(0)])
        let report = await rig.sync.perform { client throws(APIError) in
            try await client.setType(key: "gone|x", type: AlertType.alarm)
        }
        #expect(report.error == .notFound)
    }

    func event(_ type: String = AlertType.alarm, inMinutes minutes: Double = 120) -> NewEvent {
        NewEvent(
            title: "Dentist",
            startsAt: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + minutes * 60).rounded()),
            durationMinutes: 30,
            location: "Clinic", type: type, leadMinutes: 15)
    }

    @Test func aNewAlarmRingsAtOnce() async {
        let rig = Fixtures.rig([])
        let made = event()
        let report = await rig.sync.perform { client throws(APIError) in try await client.createEvent(made) }
        #expect(report.error == nil)
        #expect(await rig.server.created == [made])
        let held = await rig.alarms.alarms.values.first
        #expect(held?.title == "Dentist")
        #expect(held.map { abs($0.fireAt.timeIntervalSince(made.startsAt) + 15 * 60) < 1 } == true)
    }

    @Test func aNewNotificationSetsNoAlarm() async {
        let rig = Fixtures.rig([])
        let made = event(AlertType.notification)
        let report = await rig.sync.perform { client throws(APIError) in try await client.createEvent(made) }
        #expect(report.error == nil)
        #expect(report.state?.alerts.map(\.title) == ["Dentist"])
        #expect(await heldKeys(rig).isEmpty)
    }

    @Test func aRefusedEventCarriesTheServersReason() async {
        let rig = Fixtures.rig([])
        await rig.server.refuseNewEvents("No calendar with edit access is connected.")
        let made = event()
        let report = await rig.sync.perform { client throws(APIError) in try await client.createEvent(made) }
        #expect(report.error == .refused("No calendar with edit access is connected."))
        #expect(await heldKeys(rig).isEmpty)
    }

    @Test func theFormCatchesWhatTheServerWouldRefuse() {
        let now = Date()
        var bad = NewEvent(
            title: "  ", startsAt: now.addingTimeInterval(-60), durationMinutes: 2, location: nil,
            type: "loud", leadMinutes: 2000)
        #expect(bad.problems(now: now).count == 5)
        bad = NewEvent(
            title: "PT", startsAt: now.addingTimeInterval(400 * 86_400), durationMinutes: 60, location: nil,
            type: AlertType.alarm, leadMinutes: nil)
        #expect(bad.problems(now: now) == ["The start is more than a year away."])
        #expect(event().problems(now: now).isEmpty)
    }
}
