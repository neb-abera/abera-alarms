import Foundation
import Testing

@testable import AlarmCore

/// Apple Health's weigh-ins reach abera.tech/fitness: one a day, the last of
/// the day, sent with the paired token, and not sent twice.
struct WeightSyncTests {
    static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// 21 November 2026, 12:00 in New York.
    static let noon = newYork.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!

    static func at(day: Int, hour: Int, month: Int = 11) -> Date {
        newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    struct Rig {
        let server: FakeAlertsServer
        let health: MemoryWeights
        let documents: MemoryDocuments
        let sync: WeightSync
    }

    static func rig(_ samples: [WeightSample], paired: Bool = true) async -> Rig {
        let server = FakeAlertsServer(state: Fixtures.state([]), token: Fixtures.token)
        let credentials = MemoryCredentials()
        if paired { await credentials.save(Fixtures.pairing) }
        let health = MemoryWeights(samples)
        let documents = MemoryDocuments()
        let sync = WeightSync(
            credentials: credentials, transport: server, reader: health, documents: documents,
            now: { noon }, calendar: newYork)
        return Rig(server: server, health: health, documents: documents, sync: sync)
    }

    @Test func lose_it_weigh_ins_reach_abera_tech_once_a_day_with_the_last_of_each_day() async {
        // 170.6 lb on 19 November and 170.0 lb on 21 November, as Lose It
        // wrote them. The 21st also has an earlier 171.2 lb.
        let rig = await Self.rig([
            WeightSample(date: Self.at(day: 19, hour: 15), kilograms: 77.383),
            WeightSample(date: Self.at(day: 21, hour: 7), kilograms: 77.656),
            WeightSample(date: Self.at(day: 21, hour: 7).addingTimeInterval(600), kilograms: 77.111),
        ])

        let outcome = await rig.sync.run()

        #expect(outcome == .sent(WeightUploadResult(saved: 2, unchanged: 0)))
        #expect(await rig.server.weights == ["2026-11-19": 77.383, "2026-11-21": 77.111])
        #expect(await rig.server.requests == ["POST /api/alerts/health/weights"])
    }

    @Test func the_same_weigh_ins_are_not_sent_again_and_a_new_one_is() async {
        let rig = await Self.rig([WeightSample(date: Self.at(day: 19, hour: 15), kilograms: 77.383)])
        _ = await rig.sync.run()

        #expect(await rig.sync.run() == .alreadySent)
        #expect(await rig.server.requests.count == 1)

        await rig.health.add(WeightSample(date: Self.at(day: 21, hour: 7), kilograms: 77.111))
        #expect(await rig.sync.run() == .sent(WeightUploadResult(saved: 1, unchanged: 1)))
    }

    @Test func a_weigh_in_older_than_thirty_days_or_implausible_is_left_out() async {
        let rig = await Self.rig([
            WeightSample(date: Self.at(day: 20, hour: 7, month: 10), kilograms: 78.0),
            WeightSample(date: Self.at(day: 20, hour: 7), kilograms: 7.7),
            WeightSample(date: Self.at(day: 21, hour: 7), kilograms: 77.111),
        ])

        _ = await rig.sync.run()

        #expect(await rig.server.weights == ["2026-11-21": 77.111])
    }

    @Test func a_day_is_the_phones_day_and_not_utcs() {
        // 22:30 in New York on the 20th is 03:30 UTC on the 21st.
        let late = Self.newYork.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30))!
        let daily = WeightSync.daily([WeightSample(date: late, kilograms: 77.0)], calendar: Self.newYork)
        #expect(daily == [DailyWeight(date: "2026-11-20", weightKg: 77.0)])
    }

    @Test func nothing_is_sent_without_a_pairing_or_without_weigh_ins() async {
        let unpaired = await Self.rig([WeightSample(date: Self.at(day: 21, hour: 7), kilograms: 77.1)], paired: false)
        #expect(await unpaired.sync.run() == .notPaired)
        #expect(await unpaired.server.requests.isEmpty)

        let denied = await Self.rig([WeightSample(date: Self.at(day: 21, hour: 7), kilograms: 77.1)])
        await denied.health.deny()
        #expect(await denied.sync.run() == .nothingToSend)
        #expect(await denied.server.requests.isEmpty)
    }

    @Test func a_failed_upload_is_tried_again_on_the_next_run() async {
        let rig = await Self.rig([WeightSample(date: Self.at(day: 21, hour: 7), kilograms: 77.111)])
        await rig.server.setOffline(true)
        #expect(await rig.sync.run() == .failed(.offline))

        await rig.server.setOffline(false)
        #expect(await rig.sync.run() == .sent(WeightUploadResult(saved: 1, unchanged: 0)))

        await rig.server.revoke()
        await rig.health.add(WeightSample(date: Self.at(day: 20, hour: 7), kilograms: 77.3))
        #expect(await rig.sync.run() == .failed(.unpaired))
    }
}
