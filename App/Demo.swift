#if DEBUG
    import AlarmCore
    import Foundation
    import Synchronization

    /// The app with abera.tech and AlarmKit in memory, for the UI tests and
    /// for trying the screens in the simulator. Debug builds only.
    ///
    /// `-demo` starts paired with six events, two routines and two
    /// countdowns, one passed. `-demo-unpaired` starts on
    /// the pairing screen. `-demo-offline` starts with the server unreachable.
    /// `-demo-slow` answers every request after 8 s, as a weak signal does.
    enum Demo {
        static let token = "aat_" + String(repeating: "D", count: 43)
        static let link = "aberaalarms://pair#token=\(token)"

        static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Dependencies? {
            guard arguments.contains("-demo") else { return nil }
            let server = FakeAlertsServer(
                state: state(now: Date()), token: token, offline: arguments.contains("-demo-offline"),
                latency: arguments.contains("-demo-slow") ? .seconds(8) : .zero)
            let pairing = Pairing(server: Pairing.production, token: token)
            return Dependencies(
                sync: AlarmSync(
                    credentials: MemoryCredentials(arguments.contains("-demo-unpaired") ? nil : pairing),
                    transport: server,
                    alarms: MemoryAlarms(),
                    documents: MemoryDocuments()),
                permissions: DemoPermissions(),
                allowedServers: [Pairing.production],
                device: DemoDevice(arguments))
        }

        static func state(now: Date) -> AlertsState {
            func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
            return AlertsState(
                configured: true,
                timeZone: TimeZone.current.identifier,
                lastFetchAt: now,
                lastSuccessAt: now,
                alerts: [
                    PlannedAlert(
                        key: "drill", title: "Fire drill", startsAt: at(-10), alertAt: at(-20), endsAt: at(20)),
                    PlannedAlert(
                        key: "standup", title: "Standup", location: "Room 4", startsAt: at(70), alertAt: at(60),
                        endsAt: at(85)),
                    PlannedAlert(
                        key: "lunch", title: "Lunch", startsAt: at(130), alertAt: at(120),
                        type: AlertType.notification),
                    PlannedAlert(
                        key: "brief", title: "Commander's brief", startsAt: at(190), alertAt: at(180),
                        acknowledged: true, acknowledgedAt: now, acknowledgedVia: "browser"),
                    PlannedAlert(
                        key: "formation", title: "Formation", startsAt: at(250), alertAt: at(240),
                        acknowledged: true, acknowledgedAt: now, acknowledgedVia: "pushover"),
                    PlannedAlert(
                        key: "pt|1", title: "PT test", location: "Track", startsAt: at(300), alertAt: at(290),
                        recurring: true, endsAt: at(360)),
                    PlannedAlert(
                        key: "dinner", title: "Dinner", startsAt: at(400), alertAt: at(390), type: AlertType.none,
                        typeFrom: "default"),
                ],
                routines: [
                    Routine(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, label: "Wake", hour: 5,
                        minute: 30, days: [1, 2, 3, 4, 5]),
                    Routine(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, label: "Weekend", hour: 8,
                        minute: 0, days: [6, 7], enabled: false),
                ],
                countdowns: [
                    Countdown(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000011")!, label: "Arrived",
                        targetAt: now.addingTimeInterval(-3 * 86_400), timeZone: "America/New_York"),
                    Countdown(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000012")!, label: "Home",
                        targetAt: now.addingTimeInterval(41 * 86_400 + 5 * 3600), timeZone: "Asia/Amman",
                        alarm: true, onCalendar: true),
                    Countdown(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000013")!, label: "Anniversary",
                        targetAt: now.addingTimeInterval(100 * 86_400), timeZone: "America/New_York",
                        onCalendar: true, repeats: .yearly),
                ])
        }
    }

    /// A phone that passes every check, unless `-demo-unready` (no test
    /// alarm heard yet) or `-demo-refresh-off` (Background App Refresh off).
    final class DemoDevice: DeviceChecks {
        private let heard: Mutex<Date?>
        private let refresh: Bool

        init(_ arguments: [String]) {
            heard = Mutex(arguments.contains("-demo-unready") ? nil : Date(timeIntervalSinceNow: -86_400))
            refresh = !arguments.contains("-demo-refresh-off")
        }

        @MainActor func read() -> DeviceReading {
            DeviceReading(backgroundRefresh: refresh, pushRegistered: true, lowPower: false, pushover: true)
        }

        var testHeardAt: Date? { heard.withLock { $0 } }
        func markTestHeard(_ at: Date) { heard.withLock { $0 = at } }
        func ringTest(sound: String) async -> Bool { true }

        private let timer = Mutex<Date?>(nil)
        func startTimer(seconds: Int, label: String, sound: String) async -> Date? {
            let endsAt = Date().addingTimeInterval(TimeInterval(seconds))
            timer.withLock { $0 = endsAt }
            return endsAt
        }
        func cancelTimer() async { timer.withLock { $0 = nil } }
        func timerEndsAt() async -> Date? { timer.withLock { $0 } }
    }

    struct DemoPermissions: AlarmPermissions {
        func current() async -> AlarmPermission { .allowed }
        func request() async -> AlarmPermission { .allowed }
    }
#endif
