import Foundation
import Testing

@testable import AlarmCore

/// Editing and deleting calendar events from the phone.
@Suite struct EventEditTests {
    func heldKeys(_ rig: Fixtures.Rig) async -> Set<String> {
        Set(await rig.alarms.alarms.values.map(\.key))
    }

    func daily(_ day: Int) -> PlannedAlert {
        var alert = Fixtures.alert("standup|day\(day)", inMinutes: Double(60 + day * 1440))
        alert.recurring = true
        alert.endsAt = alert.startsAt.addingTimeInterval(30 * 60)
        return alert
    }

    @Test func lengthAndLeadComeFromTheTimes() {
        let alert = daily(0)
        #expect(alert.durationMinutes == 30)
        #expect(alert.leadMinutes == 10)
        var open = alert
        open.endsAt = nil
        #expect(open.durationMinutes == nil)
    }

    func edit(_ alert: PlannedAlert, scope: EditScope, minutes: Double) -> EventEdit {
        EventEdit(
            key: alert.key, scope: scope, title: "Stand-up", startsAt: alert.startsAt.addingTimeInterval(minutes * 60),
            durationMinutes: nil, location: "Room 5", leadMinutes: 5)
    }

    @Test func editingOneOccurrenceMovesOnlyThatAlarm() async {
        let rig = Fixtures.rig([daily(0), daily(1)])
        _ = await rig.sync.sync()
        let before = await rig.alarms.alarms
        let change = edit(daily(0), scope: .occurrence, minutes: 30)
        let report = await rig.sync.perform { client throws(APIError) in try await client.updateEvent(change) }
        #expect(report.error == nil)
        #expect(await rig.server.edits == [change])
        let after = await rig.alarms.alarms
        let day0 = AlarmID.of(key: "standup|day0")
        let day1 = AlarmID.of(key: "standup|day1")
        #expect(after[day0]?.title == "Stand-up")
        #expect(after[day0]?.fireAt == change.startsAt.addingTimeInterval(-5 * 60))
        #expect(after[day1] == before[day1])
    }

    @Test func editingTheSeriesMovesEveryAlarm() async {
        let rig = Fixtures.rig([daily(0), daily(1)])
        _ = await rig.sync.sync()
        let change = edit(daily(1), scope: .series, minutes: 15)
        _ = await rig.sync.perform { client throws(APIError) in try await client.updateEvent(change) }
        let titles = Set(await rig.alarms.alarms.values.map(\.title))
        #expect(titles == ["Stand-up"])
    }

    @Test(arguments: [(EditScope.occurrence, ["standup|day1"]), (EditScope.series, [String]())])
    func deletingTakesTheAlarmsOffThePhone(scope: EditScope, left: [String]) async {
        let rig = Fixtures.rig([daily(0), daily(1)])
        _ = await rig.sync.sync()
        let report = await rig.sync.perform { client throws(APIError) in
            try await client.deleteEvent(key: "standup|day0", scope: scope)
        }
        #expect(report.error == nil)
        #expect(await heldKeys(rig) == Set(left))
        #expect(await rig.server.deletions == ["standup|day0 \(scope.rawValue)"])
    }

    @Test func anInvitationSomeoneElseOrganizesIsRefusedWithTheReason() async {
        let rig = Fixtures.rig([daily(0)])
        _ = await rig.sync.sync()
        await rig.server.refuseNewEvents("Only the organizer can change this event.")
        let report = await rig.sync.perform { client throws(APIError) in
            try await client.deleteEvent(key: "standup|day0", scope: .occurrence)
        }
        #expect(report.error == .refused("Only the organizer can change this event."))
        #expect(await heldKeys(rig) == ["standup|day0"])
    }

    @Test func anEventNoLongerListedIsNotFound() async {
        let rig = Fixtures.rig([daily(0)])
        let report = await rig.sync.perform { client throws(APIError) in
            try await client.deleteEvent(key: "gone|x", scope: .occurrence)
        }
        #expect(report.error == .notFound)
    }

    @Test func theKeyTravelsInTheBodyNeverThePath() async throws {
        let transport = ScriptedTransport(body: Data(#"{"configured":true,"alerts":[]}"#.utf8))
        let client = AlertsClient(pairing: Fixtures.pairing, transport: transport)
        _ = try await client.deleteEvent(key: "uid@google.com|2026", scope: .series)
        var request = try #require(await transport.last)
        #expect(request.url?.path == "/api/alerts/events/delete")
        #expect(request.url?.query == nil)
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["key": "uid@google.com|2026", "scope": "series"])

        _ = try await client.updateEvent(edit(daily(0), scope: .occurrence, minutes: 0))
        request = try #require(await transport.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/alerts/events")
        let json = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(json.contains(#""key":"standup|day0""#))
        #expect(json.contains(#""scope":"occurrence""#))
    }

    @Test func theEditorCatchesWhatTheServerWouldRefuse() {
        let now = Date()
        let bad = EventEdit(
            key: "k", scope: .occurrence, title: " ", startsAt: now.addingTimeInterval(-60), durationMinutes: 2,
            location: nil, leadMinutes: 2000)
        #expect(bad.problems(now: now).count == 4)
    }

    @Test func recurringAndEndsAtDecodeAndDefault() throws {
        let json = #"""
            {"configured":true,"alerts":[
             {"key":"a","title":"A","startsAt":"2026-09-21T15:00:00+00:00","alertAt":"2026-09-21T14:50:00+00:00",
              "recurring":true,"endsAt":"2026-09-21T15:45:00+00:00"},
             {"key":"b","title":"B","startsAt":"2026-09-21T16:00:00+00:00","alertAt":"2026-09-21T15:50:00+00:00"}]}
            """#
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(state.alerts[0].recurring)
        #expect(state.alerts[0].durationMinutes == 45)
        #expect(!state.alerts[1].recurring)
        #expect(state.alerts[1].endsAt == nil)
    }
}
