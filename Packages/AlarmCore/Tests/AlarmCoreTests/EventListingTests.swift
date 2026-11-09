import Foundation
import Testing

@testable import AlarmCore

/// An event stays in the list from before its start until its end.
@Suite struct EventListingTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func event(endsAt: Date?) -> PlannedAlert {
        PlannedAlert(
            key: "brief", title: "Brief", startsAt: start, alertAt: start.addingTimeInterval(-600), endsAt: endsAt)
    }

    @Test func listedBetweenStartAndEnd() {
        let event = Self.event(endsAt: Self.start.addingTimeInterval(3600))
        #expect(event.isListed(at: Self.start.addingTimeInterval(-60)))
        #expect(event.isListed(at: Self.start))
        #expect(event.isListed(at: Self.start.addingTimeInterval(3599)))
        #expect(!event.isListed(at: Self.start.addingTimeInterval(3600)))
    }

    @Test func withoutAnEndLeavesAtTheStart() {
        let event = Self.event(endsAt: nil)
        #expect(event.isListed(at: Self.start.addingTimeInterval(-1)))
        #expect(!event.isListed(at: Self.start))
    }

    @Test func startedFromItsStart() {
        let event = Self.event(endsAt: Self.start.addingTimeInterval(3600))
        #expect(!event.hasStarted(at: Self.start.addingTimeInterval(-1)))
        #expect(event.hasStarted(at: Self.start))
    }
}
