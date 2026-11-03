import Foundation
import Testing

@testable import AlarmCore

/// The zone pickers' order and the zone a new countdown starts in.
@Suite struct ZonesTests {
    @Test func theUnitedStatesComeFirstEastToWest() {
        let zones = Zones.matching("")
        #expect(
            Array(zones.prefix(7)) == [
                "America/New_York", "America/Chicago", "America/Denver", "America/Phoenix",
                "America/Los_Angeles", "America/Anchorage", "Pacific/Honolulu",
            ])
        #expect(Array(zones.prefix(Zones.unitedStates.count)) == Zones.unitedStates)
        #expect(zones.filter { $0 == "America/Chicago" }.count == 1)
        #expect(zones.contains("Asia/Amman"))
        #expect(zones.count == Set(zones).count)
    }

    @Test func theRestKeepTheirOrder() {
        #expect(
            Zones.usFirst(["Asia/Amman", "America/Chicago", "Europe/Berlin"])
                == Zones.unitedStates + ["Asia/Amman", "Europe/Berlin"])
    }

    @Test func aSearchKeepsTheUnitedStatesFirst() {
        #expect(Zones.matching("new york") == ["America/New_York"])
        let america = Zones.matching("America/")
        #expect(america.first == "America/New_York")
        #expect(america.firstIndex(of: "America/Los_Angeles")! < america.firstIndex(of: "America/Adak")!)
        #expect(!america.contains("Pacific/Guam"))
    }

    @Test func aNewCountdownStartsInThePhonesZone() {
        #expect(Zones.phone(TimeZone(identifier: "Asia/Amman")!) == "Asia/Amman")
    }

    @Test func aZoneTheDatabaseDoesNotKnowFallsBackToNewYork() {
        // A fixed offset has no tz database name: "GMT+0300".
        #expect(Zones.phone(TimeZone(secondsFromGMT: 3 * 3600)!) == "America/New_York")
    }
}
