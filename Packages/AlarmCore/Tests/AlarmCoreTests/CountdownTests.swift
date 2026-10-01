import Foundation
import Testing

@testable import AlarmCore

/// Countdowns: kept on abera.tech, shown ticking on the phone.
@Suite struct CountdownTests {
    func at(_ text: String) -> Date { ServerDates.parse(text)! }

    // MARK: The state

    @Test func decodesTheCountdownsInTheState() throws {
        let json = """
            {"configured":true,"alerts":[],"countdowns":[
             {"id":"6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11","label":"Home","targetAt":"2026-11-13T17:00:00+03:00",
              "timeZone":"Asia/Amman","updatedAt":"2026-10-01T12:00:00.1234567+00:00"}]}
            """
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        let home = try #require(state.countdowns.first)
        #expect(home.id == UUID(uuidString: "6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11"))
        #expect(home.label == "Home")
        #expect(home.targetAt == at("2026-11-13T14:00:00Z"))
        #expect(home.timeZone == "Asia/Amman")
        #expect(home.updatedAt != nil)
    }

    @Test func anOlderServerHasNoCountdowns() throws {
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(state.countdowns.isEmpty)
    }

    @Test func theStateKeepsItsCountdownsThroughTheCache() throws {
        var state = AlertsState()
        state.countdowns = [
            Countdown(id: UUID(), label: "Home", targetAt: at("2026-11-13T14:00:00Z"), timeZone: "Asia/Amman")
        ]
        let data = try ServerDates.encoder().encode(state)
        #expect(try ServerDates.decoder().decode(AlertsState.self, from: data) == state)
    }

    @Test func aCountdownWithoutLabelOrUpdateStillReads() throws {
        let json = #"{"id":"6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11","targetAt":"2026-11-13T14:00:00Z","timeZone":"UTC"}"#
        let countdown = try ServerDates.decoder().decode(Countdown.self, from: Data(json.utf8))
        #expect(countdown.label == "Countdown")
        #expect(countdown.updatedAt == nil)
    }

    // MARK: Remaining time

    /// Seconds from now to the target, passed, the clock, the text.
    static let remainingCases: [(Double, Bool, String, String)] = [
        (3_561_153, false, "41 days 05:12:33", "41 days 05:12:33"),
        (86_401, false, "1 day 00:00:01", "1 day 00:00:01"),
        (59.9, false, "0 days 00:00:59", "0 days 00:00:59"),
        (0, true, "0 days 00:00:00", "Passed 0 days 00:00:00 ago"),
        (-183_845, true, "2 days 03:04:05", "Passed 2 days 03:04:05 ago"),
        (-86_400, true, "1 day 00:00:00", "Passed 1 day 00:00:00 ago"),
    ]

    @Test(arguments: remainingCases)
    func remainingTime(seconds: Double, passed: Bool, clock: String, text: String) {
        let now = at("2026-10-01T12:00:00Z")
        let remaining = Remaining(from: now, to: now.addingTimeInterval(seconds))
        #expect(remaining.passed == passed)
        #expect(remaining.clock == clock)
        #expect(remaining.text == text)
    }

    @Test func remainingSplitsIntoUnits() {
        let now = at("2026-10-01T12:00:00Z")
        let remaining = Remaining(from: now, to: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 5 * 60 + 6))
        let units: [Int] = [remaining.days, remaining.hours, remaining.minutes, remaining.seconds]
        #expect(units == [3, 4, 5, 6])
    }

    @Test func aCountdownSaysWhatRemains() {
        let home = Countdown(id: UUID(), label: "Home", targetAt: at("2026-10-02T12:00:00Z"), timeZone: "UTC")
        #expect(home.remaining(at: at("2026-10-01T12:00:00Z")).text == "1 day 00:00:00")
    }

    @Test func theClockTicksOncePerSecond() {
        let now = at("2026-10-01T12:00:00Z")
        let target = now.addingTimeInterval(100)
        #expect(Remaining(from: now, to: target).clock != Remaining(from: now.addingTimeInterval(1), to: target).clock)
    }

    // MARK: The target, in its own zone

    @Test func theTargetIsWrittenInItsOwnZone() {
        let home = Countdown(id: UUID(), label: "Home", targetAt: at("2026-11-13T14:00:00Z"), timeZone: "Asia/Amman")
        #expect(home.targetText == "Fri 2026-11-13 17:00 Asia/Amman")
        var newYork = home
        newYork.timeZone = "America/New_York"
        #expect(newYork.targetText == "Fri 2026-11-13 09:00 America/New_York")
    }

    @Test func anUnknownZoneIsWrittenInUTC() {
        let odd = Countdown(id: UUID(), label: "X", targetAt: at("2026-11-13T14:00:00Z"), timeZone: "Mars/Olympus")
        #expect(odd.targetText == "Fri 2026-11-13 14:00 UTC")
    }

    @Test func aCountdownGivesTheDraftThatRecreatesIt() {
        let home = Countdown(id: UUID(), label: "Home", targetAt: at("2026-11-13T14:00:00Z"), timeZone: "Asia/Amman")
        #expect(home.draft == CountdownDraft(label: "Home", targetAt: home.targetAt, timeZone: "Asia/Amman"))
    }

    // MARK: Drafts

    @Test func aBlankLabelIsSentAsCountdown() {
        let draft = CountdownDraft(label: "  ", targetAt: at("2026-11-13T14:00:00Z"), timeZone: "Asia/Amman")
        #expect(draft.sentLabel == "Countdown")
        #expect(draft.problems.isEmpty)
    }

    @Test func aDraftOutsideTheBoundsSaysWhy() {
        let bad = CountdownDraft(
            label: String(repeating: "x", count: 61), targetAt: at("1899-12-31T23:59:59Z"), timeZone: "Mars/Olympus")
        #expect(bad.problems.count == 3)
        let late = CountdownDraft(label: "Late", targetAt: at("2200-01-01T00:00:00Z"), timeZone: "UTC")
        #expect(late.problems == ["The date must be between 1900 and 2199."])
        let control = CountdownDraft(label: "Bell\u{7}", targetAt: at("2026-11-13T14:00:00Z"), timeZone: "UTC")
        #expect(control.problems == ["The label cannot hold control characters."])
        let first = CountdownDraft(label: "Start", targetAt: at("1900-01-01T00:00:00Z"), timeZone: "UTC")
        #expect(first.problems.isEmpty)
    }

    @Test func changingTheZoneKeepsTheTimeOnTheClock() {
        let amman = at("2026-11-13T14:00:00Z")  // 17:00 in Amman
        #expect(
            CountdownDraft.sameWallClock(amman, from: "Asia/Amman", to: "America/New_York")
                == at("2026-11-13T22:00:00Z"))
        #expect(CountdownDraft.sameWallClock(amman, from: "Asia/Amman", to: "Mars/Olympus") == amman)
    }

    // MARK: The client

    let okBody = Data(#"{"configured":true,"alerts":[],"countdowns":[]}"#.utf8)
    let draft = CountdownDraft(
        label: " Home ", targetAt: Date(timeIntervalSince1970: 1_794_578_400), timeZone: "Asia/Amman")
    let id = UUID(uuidString: "6F1C2C1E-3B52-4A52-9A0E-2B8F2F6B0A11")!

    func body(_ request: URLRequest) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
    }

    @Test func createPostsTheDraft() async throws {
        let transport = ScriptedTransport(status: 201, body: okBody)
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport).createCountdown(draft)
        let request = try #require(await transport.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://abera.tech/api/alerts/countdowns")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(
            try body(request)
                == ["label": "Home", "targetAt": "2026-11-13T14:00:00.000Z", "timeZone": "Asia/Amman"])
    }

    @Test func updatePutsAllThreeFieldsToTheId() async throws {
        let transport = ScriptedTransport(body: okBody)
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport).updateCountdown(id: id, draft)
        let request = try #require(await transport.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/alerts/countdowns/6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)")
        #expect(try body(request).keys.sorted() == ["label", "targetAt", "timeZone"])
    }

    @Test func deleteSendsNoBody() async throws {
        let transport = ScriptedTransport(body: okBody)
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport).deleteCountdown(id: id)
        let request = try #require(await transport.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/alerts/countdowns/6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)")
        #expect(request.httpBody == nil)
    }

    @Test(arguments: [
        (400, #"{"errors":{"timeZone":["Not a time zone."]}}"#, APIError.refused("Not a time zone.")),
        (400, #"{"errors":{"label":["Too long."],"targetAt":["Out of range."]}}"#, APIError.refused("Too long.")),
        (409, #"{"detail":"At most 50 countdowns."}"#, APIError.refused("At most 50 countdowns.")),
        (401, "", APIError.unpaired), (404, "", APIError.notFound), (429, "", APIError.rateLimited),
        (500, "", APIError.status(500)),
    ])
    func everyRefusalIsNamed(status: Int, body: String, expected: APIError) async {
        let client = AlertsClient(
            pairing: Fixtures.pairing, transport: ScriptedTransport(status: status, body: Data(body.utf8)))
        await #expect(throws: expected) { try await client.createCountdown(draft) }
        await #expect(throws: expected) { try await client.updateCountdown(id: id, draft) }
        await #expect(throws: expected) { try await client.deleteCountdown(id: id) }
    }

    @Test func noConnectionIsOffline() async {
        let client = AlertsClient(
            pairing: Fixtures.pairing, transport: ScriptedTransport(failure: URLError(.notConnectedToInternet)))
        await #expect(throws: APIError.offline) { try await client.createCountdown(draft) }
    }

    // MARK: Through the sync, as the buttons call it

    @Test func addingEditingAndDeleting() async throws {
        let rig = Fixtures.rig([], routines: [], clock: Fixtures.TestClock())
        let later = CountdownDraft(label: "Later", targetAt: at("2027-01-01T00:00:00Z"), timeZone: "UTC")

        var report = await rig.sync.perform { client throws(APIError) in try await client.createCountdown(later) }
        report = await rig.sync.perform { [draft] client throws(APIError) in try await client.createCountdown(draft) }
        #expect(report.error == nil)
        // Sorted by target, then label.
        #expect(report.state?.countdowns.map(\.label) == ["Home", "Later"])
        let home = try #require(report.state?.countdowns.first)
        #expect(await rig.sync.lastState()?.countdowns.count == 2)

        var draft = home.draft
        draft.targetAt = at("2028-01-01T00:00:00Z")
        let moved = draft
        report = await rig.sync.perform { client throws(APIError) in
            try await client.updateCountdown(id: home.id, moved)
        }
        #expect(report.state?.countdowns.map(\.label) == ["Later", "Home"])
        #expect(report.state?.countdowns.last?.timeZone == "Asia/Amman")

        report = await rig.sync.perform { client throws(APIError) in try await client.deleteCountdown(id: home.id) }
        #expect(report.state?.countdowns.map(\.label) == ["Later"])

        report = await rig.sync.perform { client throws(APIError) in try await client.deleteCountdown(id: home.id) }
        #expect(report.error == .notFound)
        #expect(report.state?.countdowns.map(\.label) == ["Later"])
    }

    @Test func theFiftyFirstIsRefused() async {
        let rig = Fixtures.rig([], routines: [], clock: Fixtures.TestClock())
        var state = Fixtures.state([])
        state.countdowns = (0..<CountdownDraft.maxCountdowns).map {
            Countdown(id: UUID(), label: "C\($0)", targetAt: at("2027-01-01T00:00:00Z"), timeZone: "UTC")
        }
        await rig.server.setState(state)
        let report = await rig.sync.perform { [draft] client throws(APIError) in
            try await client.createCountdown(draft)
        }
        #expect(report.error == .refused("At most 50 countdowns."))
    }

    @Test func theServerRefusesWhatTheDraftRefuses() async {
        let rig = Fixtures.rig([], routines: [], clock: Fixtures.TestClock())
        let bad = CountdownDraft(label: "Mars", targetAt: at("2027-01-01T00:00:00Z"), timeZone: "Mars/Olympus")
        let report = await rig.sync.perform { client throws(APIError) in try await client.createCountdown(bad) }
        #expect(report.error == .refused("Choose a time zone the tz database knows."))
    }

    @Test func offlineTheChangeIsNotMadeAndTheListStays() async {
        let rig = Fixtures.rig([], routines: [], clock: Fixtures.TestClock())
        _ = await rig.sync.perform { [draft] client throws(APIError) in try await client.createCountdown(draft) }
        await rig.server.setOffline(true)
        let report = await rig.sync.perform { [draft] client throws(APIError) in
            try await client.createCountdown(draft)
        }
        #expect(report.error == .offline)
        #expect(report.state?.countdowns.count == 1)
    }
}
