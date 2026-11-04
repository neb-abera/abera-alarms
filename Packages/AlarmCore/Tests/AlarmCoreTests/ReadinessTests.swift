import Foundation
import Testing

@testable import AlarmCore

/// The checks that hold the app on its setup screen until the phone can ring.
@Suite struct ReadinessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func ready() -> ReadinessInputs {
        ReadinessInputs(
            alarmsAllowed: true, backgroundRefresh: true, pushRegistered: true, lowPowerMode: false,
            lastSyncedAt: now.addingTimeInterval(-60), testHeardAt: now.addingTimeInterval(-86_400), refused: 0,
            pushoverInstalled: true)
    }

    @Test func aReadyPhoneFailsNothing() {
        #expect(Readiness.failing(ready(), now: now).isEmpty)
        #expect(!Readiness.blocked(ready(), now: now))
    }

    @Test func alarmsOffRefreshOffAndNoTestHeardEachBlock() {
        for change in [
            { (i: inout ReadinessInputs) in i.alarmsAllowed = false },
            { (i: inout ReadinessInputs) in i.backgroundRefresh = false },
            { (i: inout ReadinessInputs) in i.testHeardAt = nil },
        ] {
            var inputs = ready()
            change(&inputs)
            #expect(Readiness.blocked(inputs, now: now))
        }
    }

    @Test func whatTheOwnerCannotFixInSettingsOnlyWarns() {
        var inputs = ready()
        inputs.pushRegistered = false
        inputs.lowPowerMode = true
        inputs.pushoverInstalled = false
        inputs.refused = 2
        inputs.lastSyncedAt = now.addingTimeInterval(-13 * 3600)
        let kinds = Readiness.failing(inputs, now: now).map(\.kind)
        #expect(Set(kinds) == [.push, .lowPower, .pushover, .refused, .synced])
        #expect(!Readiness.blocked(inputs, now: now))
    }

    @Test func aSyncTwelveHoursOldIsNotYetStale() {
        var inputs = ready()
        inputs.lastSyncedAt = now.addingTimeInterval(-Readiness.staleAfter)
        #expect(Readiness.failing(inputs, now: now).isEmpty)
        inputs.lastSyncedAt = now.addingTimeInterval(-Readiness.staleAfter - 3600)
        #expect(Readiness.failing(inputs, now: now).first?.title == "Last synced 13 hours ago")
    }

    @Test func blockingChecksComeFirst() {
        var inputs = ready()
        inputs.lowPowerMode = true
        inputs.alarmsAllowed = false
        let checks = Readiness.failing(inputs, now: now)
        #expect(checks.map(\.kind) == [.alarms, .lowPower])
    }

    @Test func pushoverUnknownIsNotAWarning() {
        var inputs = ready()
        inputs.pushoverInstalled = nil
        #expect(Readiness.failing(inputs, now: now).isEmpty)
    }
}
