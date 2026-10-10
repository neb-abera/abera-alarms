import Foundation
import Testing

@testable import AlarmCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Stop hands its acknowledgement to the system as well as sending it, so
/// it reaches abera.tech when iOS suspends the app before the request ends.
/// On 2026-10-10 a Stop on the phone never arrived and Pushover rang.
@Suite struct BackgroundAcknowledgementTests {
    struct Rig {
        let server: FakeAlertsServer
        let alarms: MemoryAlarms
        let uploads: MemoryUploads
        let credentials: MemoryCredentials
        let sync: AlarmSync
    }

    func rig(_ alerts: [PlannedAlert], paired: Bool = true) -> Rig {
        let server = FakeAlertsServer(state: Fixtures.state(alerts), token: Fixtures.token)
        let alarms = MemoryAlarms()
        let uploads = MemoryUploads()
        let credentials = MemoryCredentials(paired ? Fixtures.pairing : nil)
        let sync = AlarmSync(
            credentials: credentials, transport: server, alarms: alarms, documents: MemoryDocuments(),
            uploads: uploads, now: { Fixtures.now })
        return Rig(server: server, alarms: alarms, uploads: uploads, credentials: credentials, sync: sync)
    }

    @Test func stopHandsTheAcknowledgementToTheSystemBeforeTheNetwork() async throws {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        let before = await rig.server.requests.count

        _ = await rig.sync.acknowledge(key: "a")

        let upload = try #require(await rig.uploads.waiting.first)
        #expect(await rig.uploads.waiting.count == 1)
        #expect(upload.label == "a")
        #expect(upload.request.httpMethod == "POST")
        #expect(upload.request.url?.path == "/api/alerts/ack")
        #expect(upload.request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)")
        #expect(upload.request.value(forHTTPHeaderField: "X-Time-Zone") != nil)
        let body = try JSONDecoder().decode([String: String].self, from: try #require(upload.request.httpBody))
        #expect(body == ["key": "a", "via": "phone"])
        // The foreground request still goes too: it is the fast path.
        #expect(await rig.server.requests[before] == "POST /api/alerts/ack")
    }

    @Test func aStopTheAppCouldNotSendReachesTheServerFromTheSystem() async {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        await rig.alarms.ring(AlarmID.of(key: "a"))

        let report = await rig.sync.acknowledge(key: "a")
        #expect(report.error == .offline)
        #expect(await rig.sync.pending() == ["a"])
        #expect(await rig.server.acknowledgements.isEmpty)

        // The app is suspended. The connection comes back and iOS sends it.
        await rig.server.setOffline(false)
        let results = await rig.uploads.deliver(to: rig.server)
        #expect(results.map(\.label) == ["a"])
        #expect(results.map(\.status) == [200])
        #expect(await rig.server.acknowledgements == ["a"])
        #expect(await rig.server.state.alerts.first?.acknowledgedVia == "phone")

        // The app is woken with the result and stops waiting.
        for result in results { await rig.sync.uploadFinished(label: result.label, status: result.status) }
        #expect(await rig.sync.pending().isEmpty)
        let before = await rig.server.requests
        _ = await rig.sync.sync()
        let after = await rig.server.requests
        #expect(!after.dropFirst(before.count).contains("POST /api/alerts/ack"))
    }

    @Test func anUploadTheServerNoLongerListsEndsTheWait() async {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        _ = await rig.sync.acknowledge(key: "a")
        await rig.server.setOffline(false)
        await rig.server.setState(Fixtures.state([]))

        let results = await rig.uploads.deliver(to: rig.server)
        #expect(results.map(\.status) == [404])
        await rig.sync.uploadFinished(label: "a", status: 404)
        #expect(await rig.sync.pending().isEmpty)
    }

    @Test func anUploadThatFailedKeepsTheKeyForTheNextSync() async {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        _ = await rig.sync.acknowledge(key: "a")

        let results = await rig.uploads.deliver(to: rig.server)
        #expect(results.map(\.status) == [nil])
        for status in [nil, 401, 429, 500] { await rig.sync.uploadFinished(label: "a", status: status) }
        #expect(await rig.sync.pending() == ["a"])

        await rig.server.setOffline(false)
        _ = await rig.sync.sync()
        #expect(await rig.server.acknowledgements == ["a"])
        #expect(await rig.sync.pending().isEmpty)
    }

    @Test func aSystemThatRefusesTheUploadStillSendsInTheForeground() async {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.uploads.refuse()

        let report = await rig.sync.acknowledge(key: "a")
        #expect(report.error == nil)
        #expect(await rig.uploads.waiting.isEmpty)
        #expect(await rig.server.acknowledgements == ["a"])
        #expect(await rig.sync.pending().isEmpty)
    }

    @Test func anUnpairedPhoneUploadsNothing() async {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)], paired: false)
        _ = await rig.sync.acknowledge(key: "a")
        #expect(await rig.uploads.waiting.isEmpty)
    }

    @Test func aKeyTooLongToKeepIsNotUploaded() async {
        let rig = rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.acknowledge(key: String(repeating: "k", count: 201))
        #expect(await rig.uploads.waiting.isEmpty)
    }

    @Test func aRoutineStopUploadsItsRingKey() async throws {
        let id = RoutineStopTests.wakeID
        let start = RoutineStopTests.start
        let key = RoutineStopTests.todaysKey
        var state = Fixtures.state([])
        state.routines = [Routine(id: id, label: "Wake", hour: 5, minute: 30, days: Array(1...7))]
        let alertAt = ServerDates.parse("2026-10-05T05:30:00-04:00")!
        state.routineRings = [
            RoutineRing(
                key: key, routineId: id, label: "Wake", alertAt: alertAt, startsAt: alertAt.addingTimeInterval(3 * 3600)
            )
        ]
        let server = FakeAlertsServer(state: state, token: Fixtures.token)
        let uploads = MemoryUploads()
        let clock = Fixtures.TestClock(start)
        let sync = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: server, alarms: MemoryAlarms(),
            documents: MemoryDocuments(), uploads: uploads, now: { clock.now }, calendar: RoutineStopTests.newYork)
        _ = await sync.sync()
        await server.setOffline(true)
        clock.advance(minutes: 31)

        _ = await sync.acknowledgeRoutine(id: id)

        let upload = try #require(await uploads.waiting.first)
        #expect(upload.label == key)
        await server.setOffline(false)
        let results = await uploads.deliver(to: server)
        #expect(results.map(\.status) == [200])
        let ring = try #require(await server.state.routineRings.first)
        #expect(ring.acknowledged)
        #expect(ring.acknowledgedVia == "phone")
    }
}
