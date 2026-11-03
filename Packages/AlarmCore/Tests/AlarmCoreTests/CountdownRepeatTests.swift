import Foundation
import Testing

@testable import AlarmCore

/// A repeating countdown moves to its next date on the phone the moment its
/// time comes, the same dates abera.tech counts to.
@Suite struct CountdownRepeatTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    func at(_ text: String) -> Date { ServerDates.parse(text)! }

    @Test func oneThatDoesNotRepeatOrHasNotComeKeepsItsDate() {
        let start = at("2020-01-01T05:00:00Z")
        #expect(CountdownRepeat.none.next(after: at("2026-11-03T12:00:00Z"), from: start, in: newYork) == start)
        let later = at("2027-01-01T05:00:00Z")
        #expect(CountdownRepeat.yearly.next(after: at("2026-11-03T12:00:00Z"), from: later, in: newYork) == later)
    }

    @Test(arguments: [
        (CountdownRepeat.yearly, "2026-12-30T14:00:00Z"),
        (CountdownRepeat.monthly, "2026-11-30T14:00:00Z"),
        (CountdownRepeat.weekly, "2026-11-09T14:00:00Z"),
    ])
    func eachPeriodStepsToTheFirstDateAfterNow(repeats: CountdownRepeat, expected: String) {
        // 09:00 on Monday 30 December 2019 in New York.
        let start = at("2019-12-30T14:00:00Z")
        #expect(repeats.next(after: at("2026-11-03T17:00:00Z"), from: start, in: newYork) == at(expected))
    }

    @Test func theTimeOnTheClockHoldsAcrossAClockChange() {
        // 09:00 in July is 13:00 UTC. In December it is 14:00 UTC.
        let july = at("2026-07-07T13:00:00Z")
        #expect(
            CountdownRepeat.monthly.next(after: at("2026-11-08T00:00:00Z"), from: july, in: newYork)
                == at("2026-12-07T14:00:00Z"))
    }

    @Test func the29thOfFebruaryAndThe31stAreSkippedWhereTheyAreMissing() {
        let leap = at("2024-02-29T05:00:00Z")
        #expect(
            CountdownRepeat.yearly.next(after: at("2026-11-03T00:00:00Z"), from: leap, in: newYork)
                == at("2028-02-29T05:00:00Z"))
        let end = at("2026-01-31T05:00:00Z")
        #expect(
            CountdownRepeat.monthly.next(after: at("2026-11-03T00:00:00Z"), from: end, in: newYork)
                == at("2026-12-31T05:00:00Z"))
    }

    @Test func aRepeatingCountdownCountsToItsNextDateOnceItsTimeComes() {
        let standup = Countdown(
            id: UUID(), label: "Standup", targetAt: at("2026-10-28T14:00:00Z"), timeZone: "America/New_York",
            repeats: .weekly)
        let after = at("2026-10-28T14:00:30Z")
        #expect(!standup.remaining(at: after).passed)
        #expect(standup.nextAt(after) == at("2026-11-04T15:00:00Z"))
        #expect(standup.targetText(at: after) == "Wed 2026-11-04 10:00 America/New_York")
    }

    @Test func theRepeatIsReadAndSent() throws {
        let json = """
            {"id":"6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11","label":"Birthday","targetAt":"2027-10-07T13:00:00Z",
             "timeZone":"America/New_York","repeat":"yearly"}
            """
        let countdown = try ServerDates.decoder().decode(Countdown.self, from: Data(json.utf8))
        #expect(countdown.repeats == .yearly)
        let sent =
            try JSONSerialization.jsonObject(with: ServerDates.encoder().encode(countdown.draft)) as? [String: Any]
        #expect(sent?["repeat"] as? String == "yearly")
    }

    @Test func aRepeatThisBuildDoesNotKnowReadsAsNever() throws {
        let json =
            #"{"id":"6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11","targetAt":"2027-10-07T13:00:00Z","timeZone":"UTC","repeat":"daily"}"#
        let countdown = try ServerDates.decoder().decode(Countdown.self, from: Data(json.utf8))
        #expect(countdown.repeats == .none)
    }

    @Test func theEditorListsNeverThenYearMonthWeek() {
        #expect(CountdownRepeat.allCases.map(\.label) == ["Never", "Every year", "Every month", "Every week"])
    }
}
