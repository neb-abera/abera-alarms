import Foundation
import Testing

@testable import AlarmCore

/// Every way into the sync: pairing, launch and refresh, the Stop button,
/// the action buttons, and unpairing.
@Suite struct AlarmSyncTests {
    func heldKeys(_ rig: Fixtures.Rig) async -> Set<String> {
        Set(await rig.alarms.alarms.values.map(\.key))
    }

    // MARK: Pairing

    @Test func pairingStoresTheTokenAndSchedules() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)], paired: false)
        let report = await rig.sync.pair(Fixtures.pairing)
        #expect(report.error == nil)
        #expect(report.scheduled == 1)
        #expect(await rig.credentials.load() == Fixtures.pairing)
        #expect(await heldKeys(rig) == ["a"])
    }

    @Test func aRefusedTokenIsNotStored() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)], paired: false)
        await rig.server.revoke()
        let report = await rig.sync.pair(Fixtures.pairing)
        #expect(report.error == .unpaired)
        #expect(await rig.credentials.load() == nil)
        #expect(await heldKeys(rig).isEmpty)
    }

    @Test func pairingOfflineStoresNothing() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)], paired: false)
        await rig.server.setOffline(true)
        #expect(await rig.sync.pair(Fixtures.pairing).error == .offline)
        #expect(await rig.credentials.load() == nil)
    }

    // MARK: Sync

    @Test func syncHoldsTheServersAlarms() async {
        let rig = Fixtures.rig([
            Fixtures.alert("a", inMinutes: 30), Fixtures.alert("b", inMinutes: 60),
            Fixtures.alert("n", inMinutes: 60, type: AlertType.notification),
        ])
        let report = await rig.sync.sync()
        #expect(report.error == nil)
        #expect(report.held.map(\.key) == ["a", "b"])
        #expect(await heldKeys(rig) == ["a", "b"])
        #expect(await rig.server.requests == ["GET /api/alerts/status"])
    }

    @Test func aSecondSyncChangesNothing() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        let second = await rig.sync.sync()
        #expect(second.scheduled == 0)
        #expect(second.cancelled == 0)
        #expect(second.held.map(\.key) == ["a"])
    }

    @Test func offlineTheAlarmsStay() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        let report = await rig.sync.sync()
        #expect(report.error == .offline)
        #expect(report.state?.alerts.map(\.key) == ["a"])
        #expect(await heldKeys(rig) == ["a"])
    }

    @Test func anEventRemovedOnTheServerIsCancelled() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30), Fixtures.alert("b", inMinutes: 40)])
        _ = await rig.sync.sync()
        await rig.server.setState(Fixtures.state([Fixtures.alert("b", inMinutes: 40)]))
        let report = await rig.sync.sync()
        #expect(report.cancelled == 1)
        #expect(await heldKeys(rig) == ["b"])
    }

    @Test func anAcknowledgementElsewhereCancelsThePhonesAlarm() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setState(Fixtures.state([Fixtures.alert("a", inMinutes: 30, acknowledged: true)]))
        _ = await rig.sync.sync()
        #expect(await heldKeys(rig).isEmpty)
    }

    @Test func aRevokedTokenKeepsTheAlarmsAndSaysSo() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.revoke()
        let report = await rig.sync.sync()
        #expect(report.error == .unpaired)
        #expect(await heldKeys(rig) == ["a"])
    }

    @Test func anAlarmTheSystemRefusesIsReported() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30), Fixtures.alert("b", inMinutes: 40)])
        await rig.alarms.refuse("b")
        let report = await rig.sync.sync()
        #expect(report.refused == ["b"])
        #expect(report.held.map(\.key) == ["a"])
    }

    @Test func unpairedSyncDoesNothing() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)], paired: false)
        #expect(await rig.sync.sync().error == .unpaired)
        #expect(await rig.server.requests.isEmpty)
    }

    // MARK: The Stop button

    @Test func stoppingTheAlarmAcknowledgesOnTheServer() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.alarms.ring(AlarmID.of(key: "a"))
        let report = await rig.sync.acknowledge(key: "a")
        #expect(report.error == nil)
        #expect(report.waitingAcknowledgements == 0)
        #expect(await rig.server.acknowledgements == ["a"])
        #expect(await heldKeys(rig).isEmpty)
    }

    @Test func stoppingOfflineWaitsAndDoesNotRingAgain() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30), Fixtures.alert("b", inMinutes: 40)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        await rig.alarms.ring(AlarmID.of(key: "a"))

        let offline = await rig.sync.acknowledge(key: "a")
        #expect(offline.error == .offline)
        #expect(await rig.sync.pending() == ["a"])

        // Back online, before the server has heard: the acknowledgement goes
        // first, and "a" is not scheduled again from the stale list.
        await rig.server.setOffline(false)
        let online = await rig.sync.sync()
        #expect(online.error == nil)
        #expect(await rig.server.acknowledgements == ["a"])
        #expect(await rig.sync.pending().isEmpty)
        #expect(await heldKeys(rig) == ["b"])
    }

    @Test func anAcknowledgementTheServerNoLongerListsIsDropped() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        _ = await rig.sync.acknowledge(key: "a")
        await rig.server.setState(Fixtures.state([]))
        await rig.server.setOffline(false)
        let report = await rig.sync.sync()
        #expect(report.error == nil)
        #expect(await rig.sync.pending().isEmpty)
    }

    // MARK: Action buttons

    @Test func skipCancelsAndUnskipRestores() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        _ = await rig.sync.perform { client throws(APIError) in try await client.skip(key: "a") }
        #expect(await heldKeys(rig).isEmpty)
        _ = await rig.sync.perform { client throws(APIError) in try await client.unskip(key: "a") }
        #expect(await heldKeys(rig) == ["a"])
    }

    @Test func muteCancelsAndUnmuteRestores() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        let muted = await rig.sync.perform { client throws(APIError) in try await client.mute(.hour) }
        #expect(muted.state?.mutedUntil != nil)
        #expect(await heldKeys(rig).isEmpty)
        _ = await rig.sync.perform { client throws(APIError) in try await client.unmute() }
        #expect(await heldKeys(rig) == ["a"])
    }

    @Test func anActionOfflineChangesNothing() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        let report = await rig.sync.perform { client throws(APIError) in try await client.skip(key: "a") }
        #expect(report.error == .offline)
        #expect(await heldKeys(rig) == ["a"])
    }

    // MARK: Unpairing

    @Test func unpairingRemovesEveryAlarmAndTheToken() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.sync.unpair()
        #expect(await rig.credentials.load() == nil)
        #expect(await heldKeys(rig).isEmpty)
        #expect(await rig.sync.lastState() == nil)
    }
}
