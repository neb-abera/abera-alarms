import Foundation
import Testing

@testable import AlarmCore

@Suite struct ServerDatesTests {
    static let reference = Date(timeIntervalSince1970: 1_790_000_000)

    @Test(arguments: [
        ("2026-09-21T14:13:20+00:00", 0.0),
        ("2026-09-21T14:13:20Z", 0.0),
        ("2026-09-21T14:13:20.5+00:00", 0.5),
        ("2026-09-21T14:13:20.1234567+00:00", 0.123),
        ("2026-09-21T17:13:20+03:00", 0.0),
        ("2026-09-21T10:13:20.250-04:00", 0.25),
    ])
    func parsesWhatDotNetWrites(text: String, fraction: Double) throws {
        let date = try #require(ServerDates.parse(text))
        #expect(abs(date.timeIntervalSince(Self.reference) - fraction) < 0.001)
    }

    @Test(arguments: [
        "", "yesterday", "2026-09-21", "2026-09-21T14:13:20.+00:00",
        "2026-09-21T14:13:20." + String(repeating: "9", count: 40) + "+00:00",
    ])
    func refusesWhatIsNotADate(text: String) {
        #expect(ServerDates.parse(text) == nil)
    }

    @Test func roundTrips() throws {
        let data = try ServerDates.encoder().encode(["at": Self.reference])
        let back = try ServerDates.decoder().decode([String: Date].self, from: data)
        #expect(back["at"] == Self.reference)
    }

    /// The shape /api/alerts/status answers today, with fields the phone
    /// does not read and without the ones the server has not shipped yet.
    @Test func decodesTheServersState() throws {
        let json = """
            {"configured":true,"timeZone":"America/New_York","pollMinutes":5,"defaultLeadMinutes":10,
             "settings":{"priority":2},"bounds":{},"mutedUntil":null,
             "lastFetchAt":"2026-09-21T14:10:00.1234567+00:00","lastFetchError":null,
             "lastSuccessAt":"2026-09-21T14:10:00+00:00","lastSend":null,
             "alerts":[
              {"key":"uid-1|2026-09-21T15:00:00Z","title":"Standup","location":"Room 4",
               "startsAt":"2026-09-21T15:00:00+00:00","alertAt":"2026-09-21T14:50:00+00:00",
               "source":"reminder","skipped":false,"muted":false},
              {"key":"uid-2","title":"Lunch","location":null,
               "startsAt":"2026-09-21T16:00:00+00:00","alertAt":"2026-09-21T15:50:00+00:00",
               "source":"default","skipped":true,"muted":false,"critical":false,"type":"notification",
               "typeFrom":"default","acknowledged":true,"acknowledgedAt":"2026-09-21T15:51:00+00:00",
               "acknowledgedVia":"browser"}
             ]}
            """
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(state.configured)
        #expect(state.alerts.count == 2)
        #expect(state.alerts[0].type == AlertType.alarm)
        #expect(state.alerts[0].location == "Room 4")
        #expect(!state.alerts[0].acknowledged)
        #expect(state.alerts[1].type == AlertType.notification)
        #expect(state.alerts[1].acknowledgedVia == "browser")
        #expect(state.alerts[1].skipped)
    }

    @Test func decodesAnUnconfiguredServer() throws {
        let json = #"{"configured":false,"missing":["Alerts__PushoverUserKey"]}"#
        let state = try ServerDates.decoder().decode(AlertsState.self, from: Data(json.utf8))
        #expect(!state.configured)
        #expect(state.alerts.isEmpty)
    }

    /// Any bytes: the decoder answers or throws, and never traps.
    @Test func survivesArbitraryBytes() {
        var generator = SeededGenerator(seed: 0xA1A2)
        let samples = [
            #"{"configured":true,"alerts":[{"key":1}]}"#, #"{"configured":"yes"}"#, "[]", "null",
            #"{"configured":true,"alerts":[{"key":"k","title":"t","startsAt":"x","alertAt":"y"}]}"#,
        ]
        for sample in samples {
            _ = try? ServerDates.decoder().decode(AlertsState.self, from: Data(sample.utf8))
        }
        for _ in 0..<2000 {
            let length = Int.random(in: 0..<200, using: &generator)
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
            _ = try? ServerDates.decoder().decode(AlertsState.self, from: Data(bytes))
        }
    }
}

/// SplitMix64: the same sequence on every platform, so a failing seed
/// reproduces anywhere.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
