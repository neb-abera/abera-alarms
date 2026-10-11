import Foundation
import Testing

@testable import AlarmCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One operation at a time. An actor lets a second call run while the first
/// waits on the network, so a sync that read the server before a change
/// finished after it and wrote the old state back. On 2026-10-11 a routine
/// switched off during the launch sync showed on again (UI test
/// testSwitchingARoutineOffAndOn, Xcode 27).
@Suite struct SerialSyncTests {
    /// Answers through the fake server at once, but holds the first status
    /// answer until the test releases it: a slow response to an old request.
    actor SlowStatus: HTTPTransport {
        let server: FakeAlertsServer
        private var holding = false
        private var waiting: CheckedContinuation<Void, Never>?
        private(set) var held = false

        init(_ server: FakeAlertsServer) { self.server = server }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let answer = try await server.send(request)
            if holding, request.url?.path == "/api/alerts/status" {
                holding = false
                held = true
                await withCheckedContinuation { waiting = $0 }
            }
            return answer
        }

        /// Holds the next status answer.
        func holdNextStatus() {
            holding = true
            held = false
        }

        func release() {
            waiting?.resume()
            waiting = nil
        }
    }

    @Test func aChangeMadeDuringASyncIsNotUndoneByIt() async throws {
        let id = UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000AA")!
        let wake = Routine(id: id, label: "Wake", hour: 5, minute: 30, days: Array(1...7))
        var state = Fixtures.state([])
        state.routines = [wake]
        let server = FakeAlertsServer(state: state, token: Fixtures.token)
        let slow = SlowStatus(server)
        let alarms = MemoryAlarms()
        let racing = AlarmSync(
            credentials: MemoryCredentials(Fixtures.pairing), transport: slow, alarms: alarms,
            documents: MemoryDocuments(), now: { Fixtures.now })
        _ = await racing.sync()
        #expect(await alarms.alarms[id] != nil)
        await slow.holdNextStatus()

        // The launch sync reads the server, and its answer is slow.
        let launch = Task { await racing.sync() }
        while !(await slow.held) { await Task.yield() }

        // The owner switches Wake off meanwhile.
        var off = wake.draft
        off.enabled = false
        let change = Task { await racing.changeRoutine(.update(id: id, draft: off)) }
        // Give an unserialized change time to reach the server first.
        for _ in 0..<200 where await server.routineUpdates.isEmpty {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        await slow.release()
        _ = await launch.value
        let report = await change.value

        #expect(report.state?.routines.first?.enabled == false)
        #expect(await racing.lastState()?.routines.first?.enabled == false)
        #expect(await alarms.alarms[id] == nil)
        #expect(await server.state.routines.first?.enabled == false)
    }
}
