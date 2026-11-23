import Foundation
import Testing

@testable import AlarmCore

/// A step reads Rang, Coming, or Done. Neb asked on 2026-11-23.
@Suite struct StepStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aStepIsRangComingOrDone() {
        #expect(StepStatus.of(ringAt: now.addingTimeInterval(-60), done: false, now: now) == .rang)
        #expect(StepStatus.of(ringAt: now, done: false, now: now) == .rang)
        #expect(StepStatus.of(ringAt: now.addingTimeInterval(60), done: false, now: now) == .coming)
        #expect(StepStatus.of(ringAt: now.addingTimeInterval(60), done: true, now: now) == .done)
        #expect(StepStatus.of(ringAt: now.addingTimeInterval(-60), done: true, now: now) == .done)
        #expect(StepStatus.rang.rawValue == "Rang")
    }
}
