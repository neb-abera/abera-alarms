import Foundation

/// What the phone can read about whether its alarms will ring.
public struct ReadinessInputs: Equatable, Sendable {
    /// The owner let this app ring alarms (AlarmKit).
    public var alarmsAllowed: Bool
    /// Background App Refresh is on for this app.
    public var backgroundRefresh: Bool
    /// iOS gave the app a push token, so abera.tech can wake it.
    public var pushRegistered: Bool
    public var lowPowerMode: Bool
    /// When this phone last read its alarms from abera.tech.
    public var lastSyncedAt: Date?
    /// When the owner said a test alarm rang loud enough on this phone.
    public var testHeardAt: Date?
    /// Alarms iOS refused to set on the last sync.
    public var refused: Int
    /// Pushover, the backup, is on this phone. Nil when it cannot be told.
    public var pushoverInstalled: Bool?

    public init(
        alarmsAllowed: Bool, backgroundRefresh: Bool, pushRegistered: Bool, lowPowerMode: Bool,
        lastSyncedAt: Date?, testHeardAt: Date?, refused: Int, pushoverInstalled: Bool?
    ) {
        self.alarmsAllowed = alarmsAllowed
        self.backgroundRefresh = backgroundRefresh
        self.pushRegistered = pushRegistered
        self.lowPowerMode = lowPowerMode
        self.lastSyncedAt = lastSyncedAt
        self.testHeardAt = testHeardAt
        self.refused = refused
        self.pushoverInstalled = pushoverInstalled
    }
}

/// One thing that can stop an alarm from ringing, and what fixes it.
public struct ReadinessCheck: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case alarms, backgroundRefresh, test, synced, refused, push, lowPower, pushover
    }

    /// Blocking checks hold the app on the setup screen until they pass.
    public enum Severity: Int, Sendable, Comparable {
        case blocking, warning

        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// What the button beside the check does.
    public enum Fix: Sendable {
        case allowAlarms, openSettings, testAlarm, sync, none
    }

    public var kind: Kind
    public var severity: Severity
    public var title: String
    public var detail: String
    public var fix: Fix
    public var id: Kind { kind }
}

/// Every check that fails, blocking ones first. Empty when nothing the
/// phone can read stops an alarm from ringing.
public enum Readiness {
    /// A phone that has not synced for this long may be missing new or moved alarms.
    public static let staleAfter: TimeInterval = 12 * 3600

    public static func failing(_ inputs: ReadinessInputs, now: Date) -> [ReadinessCheck] {
        var checks: [ReadinessCheck] = []
        if !inputs.alarmsAllowed {
            checks.append(
                .init(
                    kind: .alarms, severity: .blocking, title: "Alarms are off for this app",
                    detail: "Nothing rings on this phone. Settings > Apps > Alarms > Alarms, on.",
                    fix: .allowAlarms))
        }
        if !inputs.backgroundRefresh {
            checks.append(
                .init(
                    kind: .backgroundRefresh, severity: .blocking, title: "Background App Refresh is off",
                    detail:
                        "The phone gets new and moved alarms only while the app is open. Settings > Apps > Alarms > Background App Refresh, on.",
                    fix: .openSettings))
        }
        if inputs.testHeardAt == nil {
            checks.append(
                .init(
                    kind: .test, severity: .blocking, title: "Ring a test alarm",
                    detail:
                        "It rings in 10 seconds at the volume your alarms use. Settings > Sounds & Haptics > Ringtone and Alert Volume sets it. Turn Change with Buttons off so music volume never lowers it.",
                    fix: .testAlarm))
        }
        if inputs.refused > 0 {
            checks.append(
                .init(
                    kind: .refused, severity: .warning, title: "\(inputs.refused) alarm(s) could not be set",
                    detail: "iOS refused them. Sync again. If it repeats, those alarms ring only through Pushover.",
                    fix: .sync))
        }
        if let synced = inputs.lastSyncedAt, now.timeIntervalSince(synced) > staleAfter {
            let hours = Int(now.timeIntervalSince(synced) / 3600)
            checks.append(
                .init(
                    kind: .synced, severity: .warning, title: "Last synced \(hours) hours ago",
                    detail:
                        "Alarms set before then still ring. Events added or moved since then are not on this phone. Connect and sync.",
                    fix: .sync))
        }
        if !inputs.pushRegistered {
            checks.append(
                .init(
                    kind: .push, severity: .warning, title: "abera.tech cannot wake this phone",
                    detail:
                        "iOS has not given the app a push token. Changes reach the phone at the next open or refresh.",
                    fix: .none))
        }
        if inputs.lowPowerMode {
            checks.append(
                .init(
                    kind: .lowPower, severity: .warning, title: "Low Power Mode is on",
                    detail:
                        "iOS delays background refresh and pushes, so new alarms reach the phone later. Alarms already set ring.",
                    fix: .none))
        }
        if inputs.pushoverInstalled == false {
            checks.append(
                .init(
                    kind: .pushover, severity: .warning, title: "Pushover is not on this phone",
                    detail:
                        "Pushover is the backup that rings if this app cannot. Install it and turn on its Critical Alerts.",
                    fix: .none))
        }
        return checks.sorted { $0.severity < $1.severity }
    }

    /// True while a check holds the app on the setup screen.
    public static func blocked(_ inputs: ReadinessInputs, now: Date) -> Bool {
        failing(inputs, now: now).contains { $0.severity == .blocking }
    }
}
