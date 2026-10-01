import Foundation
import Testing

@testable import AlarmCore

/// The sound every alarm plays, and Snooze on calendar alarms.
@Suite struct PhoneSettingsTests {
    @Test func readsTheServersSettings() throws {
        let json = #"{"configured":true,"settings":{"priority":2,"phoneSound":"chime","phoneSnoozeMinutes":5}}"#
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(state.phone == PhoneSettings(sound: "chime", snoozeMinutes: 5))
    }

    @Test func aServerWithoutThemGivesTheDefaults() throws {
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(state.phone == PhoneSettings(sound: "default", snoozeMinutes: 9))
    }

    @Test func anUnknownSoundPlaysTheDefaultAndSnoozeStaysInBounds() throws {
        let json = #"{"configured":true,"settings":{"phoneSound":"foghorn","phoneSnoozeMinutes":90}}"#
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(state.phone == PhoneSettings(sound: "default", snoozeMinutes: 30))
    }

    @Test func thePhonesOwnCopyRoundTrips() throws {
        var state = Fixtures.state([])
        state.phone = PhoneSettings(sound: "siren", snoozeMinutes: 3)
        let back = try ServerDates.decoder().decode(AlertsState.self, from: ServerDates.encoder().encode(state))
        #expect(back.phone == state.phone)
    }

    @Test func everyAlarmPlaysTheSoundAndOnlyCalendarAlarmsTakeTheSnooze() {
        var state = Fixtures.state([Fixtures.alert("a", inMinutes: 30)])
        state.routines = [Routine(id: UUID(), label: "Wake", hour: 6, minute: 0, days: [1], snoozeMinutes: 4)]
        state.phone = PhoneSettings(sound: "pulse", snoozeMinutes: 7)
        let desired = Reconciler.desired(from: state, now: Fixtures.now, acknowledgedHere: [])
        #expect(desired.allSatisfy { $0.sound == "pulse" })
        #expect(desired.first { !$0.isRoutine }?.snoozeMinutes == 7)
        #expect(desired.first { $0.isRoutine }?.snoozeMinutes == nil)
        #expect(desired.first { $0.isRoutine }?.routine?.snoozeMinutes == 4)
    }

    @Test func aNewSoundSetsEveryAlarmAgain() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        await rig.server.setRoutines([Routine(id: UUID(), label: "Wake", hour: 6, minute: 0, days: [1])])
        _ = await rig.sync.sync()
        let report = await rig.sync.perform { client throws(APIError) in
            try await client.updatePhoneSettings(PhoneSettings(sound: "beacon", snoozeMinutes: 9))
        }
        #expect(report.error == nil)
        #expect(report.cancelled == 2)
        #expect(report.scheduled == 2)
        #expect(await rig.alarms.alarms.values.allSatisfy { $0.sound == "beacon" })
    }

    @Test func theSettingsTravelAsTheServerNamesThem() async throws {
        let transport = ScriptedTransport(body: Data(#"{"configured":true}"#.utf8))
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport)
            .updatePhoneSettings(PhoneSettings(sound: "rise", snoozeMinutes: 12))
        let request = try #require(await transport.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/alerts/phone-settings")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["sound"] as? String == "rise")
        #expect(body["snoozeMinutes"] as? Int == 12)
    }

    @Test func aLedgerFromAnOlderBuildReadsAsTheDefaultSound() throws {
        let json =
            #"[{"id":"00000000-0000-4000-8000-000000000009","key":"k","title":"T","fireAt":"2026-09-21T15:00:00Z","startsAt":"2026-09-21T15:00:00Z"}]"#
        let ledger = try ServerDates.decoder().decode([DesiredAlarm].self, from: Data(json.utf8))
        #expect(ledger.first?.sound == "default")
    }
}
