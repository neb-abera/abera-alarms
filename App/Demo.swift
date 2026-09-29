#if DEBUG
    import AlarmCore
    import Foundation

    /// The app with abera.tech and AlarmKit in memory, for the UI tests and
    /// for trying the screens in the simulator. Debug builds only.
    ///
    /// `-demo` starts paired with four events. `-demo-unpaired` starts on
    /// the pairing screen. `-demo-offline` starts with the server unreachable.
    enum Demo {
        static let token = "aat_" + String(repeating: "D", count: 43)
        static let link = "aberaalarms://pair#token=\(token)"

        static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Dependencies? {
            guard arguments.contains("-demo") else { return nil }
            let server = FakeAlertsServer(
                state: state(now: Date()), token: token, offline: arguments.contains("-demo-offline"))
            let pairing = Pairing(server: Pairing.production, token: token)
            return Dependencies(
                sync: AlarmSync(
                    credentials: MemoryCredentials(arguments.contains("-demo-unpaired") ? nil : pairing),
                    transport: server,
                    alarms: MemoryAlarms(),
                    documents: MemoryDocuments()),
                permissions: DemoPermissions(),
                allowedServers: [Pairing.production])
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
                        key: "standup", title: "Standup", location: "Room 4", startsAt: at(70), alertAt: at(60)),
                    PlannedAlert(
                        key: "lunch", title: "Lunch", startsAt: at(130), alertAt: at(120),
                        type: AlertType.notification),
                    PlannedAlert(
                        key: "brief", title: "Commander's brief", startsAt: at(190), alertAt: at(180),
                        acknowledged: true, acknowledgedAt: now, acknowledgedVia: "browser"),
                    PlannedAlert(key: "pt", title: "PT test", location: "Track", startsAt: at(300), alertAt: at(290)),
                    PlannedAlert(
                        key: "dinner", title: "Dinner", startsAt: at(400), alertAt: at(390), type: AlertType.none,
                        typeFrom: "default"),
                ])
        }
    }

    struct DemoPermissions: AlarmPermissions {
        func current() async -> AlarmPermission { .allowed }
        func request() async -> AlarmPermission { .allowed }
    }
#endif
