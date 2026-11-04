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

    @Test(arguments: [
        (CountdownRepeat.hourly, 2, "2026-11-03T14:00:00Z"),
        (CountdownRepeat.daily, 3, "2026-11-05T14:00:00Z"),
        (CountdownRepeat.weekly, 2, "2026-11-09T14:00:00Z"),
        (CountdownRepeat.monthly, 3, "2026-12-30T14:00:00Z"),
        (CountdownRepeat.yearly, 2, "2027-12-30T14:00:00Z"),
    ])
    func everyNUnitsCountsWholeStepsOfNFromTheFirstDate(repeats: CountdownRepeat, every: Int, expected: String) {
        // The same cases abera.tech's CountdownRepeatsTests hold: 09:00 on
        // Monday 30 December 2019 in New York, asked at 12:00 UTC on 3 November 2026.
        let start = at("2019-12-30T14:00:00Z")
        #expect(repeats.next(after: at("2026-11-03T12:00:00Z"), from: start, every: every, in: newYork) == at(expected))
    }

    @Test func theListSaysHowOften() {
        #expect(CountdownRepeat.yearly.describe(every: 1) == "Every year")
        #expect(CountdownRepeat.hourly.describe(every: 2) == "Every 2 hours")
        #expect(CountdownRepeat.none.describe(every: 3) == nil)
    }

    @Test func anIntervalOutside1To999IsNotSent() {
        var draft = CountdownDraft(
            targetAt: at("2027-01-01T00:00:00Z"), timeZone: "UTC", repeats: .daily, repeatEvery: 0)
        #expect(draft.problems == ["Repeat every 1 to 999."])
        draft.repeatEvery = 999
        #expect(draft.problems.isEmpty)
        draft.repeats = .none
        draft.repeatEvery = 0
        #expect(draft.problems.isEmpty)
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
             "timeZone":"America/New_York","repeat":"weekly","repeatEvery":2}
            """
        let countdown = try ServerDates.decoder().decode(Countdown.self, from: Data(json.utf8))
        #expect(countdown.repeats == .weekly)
        #expect(countdown.repeatEvery == 2)
        let sent =
            try JSONSerialization.jsonObject(with: ServerDates.encoder().encode(countdown.draft)) as? [String: Any]
        #expect(sent?["repeat"] as? String == "weekly")
        #expect(sent?["repeatEvery"] as? Int == 2)
    }

    @Test func aRepeatThisBuildDoesNotKnowReadsAsNever() throws {
        let json =
            #"{"id":"6f1c2c1e-3b52-4a52-9a0e-2b8f2f6b0a11","targetAt":"2027-10-07T13:00:00Z","timeZone":"UTC","repeat":"fortnightly"}"#
        let countdown = try ServerDates.decoder().decode(Countdown.self, from: Data(json.utf8))
        #expect(countdown.repeats == .none)
    }

    @Test func theEditorListsNeverThenHoursToYears() {
        #expect(CountdownRepeat.allCases.map { $0.unit(2) } == ["Never", "hours", "days", "weeks", "months", "years"])
        #expect(CountdownRepeat.allCases.map { $0.unit(1) } == ["Never", "hour", "day", "week", "month", "year"])
    }
}
