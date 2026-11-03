import Foundation

/// The zones a zone picker offers, United States first, and the zone a new
/// countdown starts in.
public enum Zones {
    /// Where a zone falls back to when the phone names none it knows. Neb
    /// lives in Washington, DC.
    public static let home = "America/New_York"

    /// The United States zones, east to west, then Puerto Rico and Guam.
    /// Every zone list starts with these, in this order. Neb asked for
    /// options to put the United States first on 2026-11-03.
    public static let unitedStates = [
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Phoenix",
        "America/Los_Angeles",
        "America/Anchorage",
        "Pacific/Honolulu",
        "America/Puerto_Rico",
        "Pacific/Guam",
    ]

    /// The phone's own zone, or New York when the phone's zone is not one
    /// the tz database knows, such as a bare offset ("GMT+0300"), which
    /// abera.tech refuses.
    public static func phone(_ current: TimeZone = .current) -> String {
        TimeZone.knownTimeZoneIdentifiers.contains(current.identifier) ? current.identifier : home
    }

    /// The United States zones first, in their order, then the rest in the
    /// order given.
    public static func usFirst(_ zones: [String]) -> [String] {
        let us = Set(unitedStates)
        return unitedStates + zones.filter { !us.contains($0) }
    }

    /// The zones whose name holds the search, spaces read as underscores,
    /// United States first. Every zone when the search is empty.
    public static func matching(_ search: String, in zones: [String] = TimeZone.knownTimeZoneIdentifiers) -> [String] {
        let ordered = usFirst(zones)
        guard !search.isEmpty else { return ordered }
        let words = search.replacingOccurrences(of: " ", with: "_")
        return ordered.filter { $0.localizedCaseInsensitiveContains(words) }
    }
}
