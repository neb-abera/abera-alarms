import Foundation
import Testing

@testable import AlarmCore

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// The rings of routine alarms against the golden vectors abera.tech tests
/// too. Resources/routine-ring-vectors.json is the same file, byte for byte,
/// as aberaTech.Server.Tests/Alerts/Golden/routine-ring-vectors.json in
/// aberaTech. Each vector was worked out from the written contract, by
/// neither side's code.
@Suite struct RoutineRingVectorsTests {
    /// The SHA-256 of the file. The server's test holds the same value.
    /// Change the file in both repositories and this with it.
    static let sha256 = "2e8564b13518f7d131cc051fdc0e097fc180a08a398985e08c17fe3dd8d48c88"

    static let id = UUID(uuidString: "0D8C6F1E-3F6E-4A53-9D53-8F1B2A7C4D10")!

    /// Vectors the phone does not meet, found on 2026-11-26. All five are
    /// a time the clocks skip where the gap does not run from one whole
    /// hour to the next inside one day: 23:00 to 00:00 in Nuuk, 02:00 to
    /// 02:30 on Lord Howe Island, and 02:45 to 03:45 on the Chatham
    /// Islands. The contract rings at the next time that exists, and
    /// abera.tech does. `clockFire` asks `Calendar.nextDate`. In Nuuk and
    /// on Lord Howe Island it gives no ring for that day. On the Chatham
    /// Islands it gives 04:00, 15 minutes late. Linux and macOS 26 agree.
    /// A vector leaves this list when the phone rings it.
    static let knownDifferences: Set<String> = [
        "every day at 23:30 in Nuuk, where the clocks skip 23:00 to 00:00: "
            + "the ring is at 00:00 the next day under the 23:30 stamp of its own day",
        "weekdays every day at 23:30 in Nuuk across the same night",
        "every day at 02:07 on Lord Howe Island, where the clocks skip 02:00 to 02:30: the ring is at 02:30",
        "weekdays every 3 weeks at 02:07 on Lord Howe Island: "
            + "the skipped Sunday rings at 02:30 and the Monday of the off week does not ring",
        "every day at 03:15 on the Chatham Islands, where the clocks skip 02:45 to 03:45: the ring is at 03:45",
    ]

    struct VectorFile: Decodable {
        var vectors: [Vector]
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        var name: String
        var zone: String
        var routine: Given
        var from: Date
        var until: Date
        var summary: String
        var rings: [Ring]

        var testDescription: String { name }
    }

    /// The fields of a routine a vector gives. `updatedAt` is left out of
    /// one saved long before its window.
    struct Given: Decodable, Sendable {
        var hour: Int
        var minute: Int
        var days: [Int]
        var `repeat`: RoutineRepeat
        var every: Int
        var unit: RoutineUnit
        var startsOn: String?
        var updatedAt: Date?
    }

    struct Ring: Decodable, Equatable, Sendable {
        var stamp: String
        var at: Date
    }

    static func bytes() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "routine-ring-vectors", withExtension: "json", subdirectory: "Resources")
                ?? Bundle.module.url(forResource: "routine-ring-vectors", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    static let vectors: [Vector] = {
        guard let data = try? bytes(), let file = try? ServerDates.decoder().decode(VectorFile.self, from: data)
        else { return [] }
        return file.vectors
    }()

    /// Every ring from `from` to `until`, both ends included, and after the
    /// save. `nextFire` gives the first ring strictly after a time, so the
    /// walk starts a second before `from`, or at the save when that is
    /// later. Every ring is on a whole minute. A ring-once routine has one
    /// ring: the first after its save.
    static func rings(_ vector: Vector) throws -> [Ring] {
        let given = vector.routine
        let routine = Routine(
            id: id, label: "Alarm", hour: given.hour, minute: given.minute, days: given.days,
            updatedAt: given.updatedAt, repeatMode: given.repeat, every: given.every, unit: given.unit,
            startsOn: given.startsOn)
        let calendar = RoutineRingTests.calendar(vector.zone)
        let schedule = routine.schedule

        func ring(_ at: Date) -> Ring {
            let key = RoutineRing.key(routineID: id, schedule: schedule, ring: at, calendar: calendar)
            let cycle = RoutineCycle.make(routine, at: at, calendar: calendar)
            #expect(cycle.key == key)
            #expect(key.hasPrefix("routine:\(id.uuidString.lowercased()):"))
            return Ring(stamp: schedule.stamp(of: at, calendar: calendar), at: at)
        }

        if !routine.repeats {
            let saved = try #require(given.updatedAt)
            guard let at = routine.nextFire(after: saved, calendar: calendar), at >= vector.from, at <= vector.until
            else { return [] }
            return [ring(at)]
        }
        var found: [Ring] = []
        var after = vector.from.addingTimeInterval(-1)
        if let saved = given.updatedAt, saved > after { after = saved }
        while let at = routine.nextFire(after: after, calendar: calendar), at <= vector.until {
            try #require(at > after)
            found.append(ring(at))
            after = at
        }
        return found
    }

    func text(_ rings: [Ring]) -> [String] {
        rings.map { "\($0.stamp) \(Self.utc($0.at))" }
    }

    /// "2026-11-01T04:30:00Z", as the file writes an instant.
    static func utc(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    @Test func theFileIsTheOneTheServerTests() throws {
        let digest = SHA256.hash(data: try Self.bytes()).map { String(format: "%02x", $0) }.joined()
        #expect(digest == Self.sha256)
        #expect(Self.vectors.count >= 50)
        #expect(Set(Self.vectors.map(\.name)).count == Self.vectors.count)
    }

    @Test(arguments: vectors)
    func nextFireListsExactlyTheRingsOfTheVector(_ vector: Vector) throws {
        let found = text(try Self.rings(vector))
        let listed = text(vector.rings)
        if Self.knownDifferences.contains(vector.name) {
            withKnownIssue("Calendar.nextDate does not ring at the next time that exists after this gap.") {
                #expect(found == listed)
            }
        } else {
            #expect(found == listed)
        }
    }

    @Test(arguments: vectors)
    func theSummaryIsTheTextOfTheVector(_ vector: Vector) {
        let given = vector.routine
        let text = Routine.repeatText(
            repeatMode: given.repeat, every: given.every, unit: given.unit, days: given.days)
        #expect(text == vector.summary)
    }
}
