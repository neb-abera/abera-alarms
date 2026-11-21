#if DEBUG
    import AlarmCore
    import AlarmKit
    import Foundation
    import Synchronization
    import UIKit

    /// The app with abera.tech and AlarmKit in memory, for the UI tests and
    /// for trying the screens in the simulator. Debug builds only.
    ///
    /// `-demo` starts paired with six events, two routines and two
    /// countdowns, one passed. `-demo-unpaired` starts on
    /// the pairing screen. `-demo-offline` starts with the server unreachable.
    /// `-demo-slow` answers every request after 8 s, as a weak signal does.
    /// `-demo-real-timer` gives the timer to AlarmKit, so a UI test hears
    /// it ring through iOS and stops it there.
    /// `-demo-started` adds an event that started 10 minutes ago and ends in 20.
    /// `-demo-invited` refuses every event edit as Google refuses one of an
    /// event someone else organized.
    /// `-demo-steps` adds Morning at 06:00 every day with two steps, and a
    /// check-off yesterday with a note and a photo.
    /// `-demo-step-soon` adds Pills at the current minute with two steps that
    /// ring 2 minutes later. `-demo-real-alarms` gives every alarm to
    /// AlarmKit, so a UI test hears a step ring through iOS.
    /// `-demo-ring-soon` adds Gym, every day, ringing 2 to 3 minutes after
    /// launch, with its step Stretch at the same minute.
    /// `-demo-health` sends Apple Health weigh-ins to the demo server, and
    /// puts one weigh-in of 77.111 kg in the simulator's Health first.
    /// `-demo-clear-alarms` stops and cancels every alarm the app holds in
    /// AlarmKit, so a test that rang real alarms leaves none ringing for the
    /// tests after it.
    /// The simulator's Health with one weigh-in put there before the first read.
    actor SeededHealth: WeightReading {
        let health: HealthKitWeights
        private var seeded = false

        init(health: HealthKitWeights) { self.health = health }

        func samples(since: Date) async throws -> [WeightSample] {
            if !seeded {
                seeded = true
                try? await health.add(kilograms: 77.111)
            }
            return try await health.samples(since: since)
        }
    }

    enum Demo {
        static let token = "aat_" + String(repeating: "D", count: 43)
        static let link = "aberaalarms://pair#token=\(token)"

        static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Dependencies? {
            guard arguments.contains("-demo") else { return nil }
            var initial = state(now: Date(), started: arguments.contains("-demo-started"))
            if arguments.contains("-demo-steps") { initial.routines.append(morning) }
            if arguments.contains("-demo-step-soon") { initial.routines.append(pills(now: Date())) }
            if arguments.contains("-demo-ring-soon") { initial.routines.append(gym(now: Date())) }
            let server = FakeAlertsServer(
                state: initial, token: token,
                offline: arguments.contains("-demo-offline"),
                latency: arguments.contains("-demo-slow") ? .seconds(8) : .zero)
            if arguments.contains("-demo-invited") {
                Task { await server.refuseNewEvents("Only the organizer can change this event.") }
            }
            if arguments.contains("-demo-steps") {
                Task { @MainActor in
                    let seed = yesterdaysPills()
                    await server.setCompletions([seed])
                }
            }
            let pairing = Pairing(server: Pairing.production, token: token)
            if arguments.contains("-demo-clear-alarms") {
                Task {
                    for alarm in (try? AlarmManager.shared.alarms) ?? [] {
                        try? AlarmManager.shared.stop(id: alarm.id)
                        try? AlarmManager.shared.cancel(id: alarm.id)
                    }
                }
            }
            let alarms: any AlarmScheduling =
                arguments.contains("-demo-real-alarms") ? AuthorizingScheduler() : MemoryAlarms()
            let credentials = MemoryCredentials(arguments.contains("-demo-unpaired") ? nil : pairing)
            let health = arguments.contains("-demo-health") ? HealthKitWeights(writes: true) : nil
            return Dependencies(
                sync: AlarmSync(
                    credentials: credentials,
                    transport: server,
                    alarms: alarms,
                    documents: MemoryDocuments()),
                permissions: DemoPermissions(),
                allowedServers: [Pairing.production],
                device: DemoDevice(arguments),
                weights: health.map {
                    WeightSync(
                        credentials: credentials, transport: server, reader: SeededHealth(health: $0),
                        documents: MemoryDocuments())
                },
                health: health)
        }

        static let morningID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        static let medicationID = UUID(uuidString: "00000000-0000-4000-8000-000000000031")!

        static let morning = Routine(
            id: morningID, label: "Morning", hour: 6, minute: 0, days: [1, 2, 3, 4, 5, 6, 7],
            steps: [
                RoutineStep(id: medicationID, label: "Take medication", offsetMinutes: 5),
                RoutineStep(
                    id: UUID(uuidString: "00000000-0000-4000-8000-000000000032")!, label: "Beauty care",
                    offsetMinutes: 5),
            ], updatedAt: Date(timeIntervalSinceNow: -30 * 86_400))

        /// The medication of the cycle before the one under way, checked off
        /// with a note and a photo.
        @MainActor static func yesterdaysPills() -> FakeAlertsServer.StoredCompletion {
            let now = Date()
            let current = RoutineCycle.around(morning, now: now, calendar: .current).current?.at ?? now
            let before = RoutineCycle.around(morning, now: current.addingTimeInterval(-60), calendar: .current).current
            return FakeAlertsServer.StoredCompletion(
                id: UUID(), routineId: morningID, stepId: medicationID, cycle: before?.stamp ?? "",
                completedAt: (before?.at ?? now).addingTimeInterval(360), note: "Vitamin D, 2000 IU",
                photo: samplePhoto)
        }

        /// A 64 by 64 green square as a JPEG.
        @MainActor static var samplePhoto: Data? {
            let size = CGSize(width: 64, height: 64)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemGreen.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            return image.jpegData(compressionQuality: 0.8)
        }

        /// Pills at the current minute, every day. Skip me and Take
        /// medication both ring 2 minutes after it.
        static func pills(now: Date) -> Routine {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
            return Routine(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, label: "Pills",
                hour: parts.hour ?? 0, minute: parts.minute ?? 0, days: [1, 2, 3, 4, 5, 6, 7],
                steps: [
                    RoutineStep(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000041")!, label: "Skip me",
                        offsetMinutes: 2),
                    RoutineStep(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000042")!, label: "Take medication",
                        offsetMinutes: 0),
                ], updatedAt: now.addingTimeInterval(-86_400))
        }

        /// Gym at the minute at least 80 s ahead, every day. Stretch rings
        /// with it.
        static func gym(now: Date) -> Routine {
            let ring = Calendar.current.dateInterval(of: .minute, for: now.addingTimeInterval(140))?.start ?? now
            let parts = Calendar.current.dateComponents([.hour, .minute], from: ring)
            return Routine(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!, label: "Gym",
                hour: parts.hour ?? 0, minute: parts.minute ?? 0, days: [1, 2, 3, 4, 5, 6, 7],
                steps: [
                    RoutineStep(
                        id: UUID(uuidString: "00000000-0000-4000-8000-000000000051")!, label: "Stretch",
                        offsetMinutes: 0)
                ], updatedAt: now.addingTimeInterval(-86_400))
        }

        static func state(now: Date, started: Bool = false) -> AlertsState {
            func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
            // A started event, only when asked: one more row pushes the last
            // row off a small screen, and the list drops it.
            let drill =
                started
                ? [
                    PlannedAlert(
                        key: "drill", title: "Fire drill", startsAt: at(-10), alertAt: at(-20), endsAt: at(20))
                ] : []
            return AlertsState(
                configured: true,
                timeZone: TimeZone.current.identifier,
                lastFetchAt: now,
                lastSuccessAt: now,
                alerts: drill + [
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
        private let realTimer: Bool

        init(_ arguments: [String]) {
            heard = Mutex(arguments.contains("-demo-unready") ? nil : Date(timeIntervalSinceNow: -86_400))
            refresh = !arguments.contains("-demo-refresh-off")
            realTimer = arguments.contains("-demo-real-timer")
        }

        @MainActor func read() -> DeviceReading {
            DeviceReading(backgroundRefresh: refresh, pushRegistered: true, lowPower: false, pushover: true)
        }

        var testHeardAt: Date? { heard.withLock { $0 } }
        func markTestHeard(_ at: Date) { heard.withLock { $0 = at } }
        func ringTest(sound: String) async -> Bool { true }

        private let timer = Mutex<Date?>(nil)
        private let label = Mutex("Timer")
        func startTimer(seconds: Int, label: String, sound: String) async -> Date? {
            self.label.withLock { $0 = label }
            if realTimer {
                do {
                    _ = try await AlarmManager.shared.requestAuthorization()
                } catch {
                    SystemDevice.log.error("alarm permission: \(String(describing: error), privacy: .public)")
                }
                return await SystemDevice().startTimer(seconds: seconds, label: label, sound: sound)
            }
            let endsAt = Date().addingTimeInterval(TimeInterval(seconds))
            timer.withLock { $0 = endsAt }
            return endsAt
        }
        func cancelTimer() async {
            if realTimer { await SystemDevice().cancelTimer() }
            timer.withLock { $0 = nil }
        }
        func timerEndsAt() async -> Date? {
            realTimer ? await SystemDevice().timerEndsAt() : timer.withLock { $0 }
        }
        func timerLabel() async -> String { label.withLock { $0 } }
    }

    /// AlarmKit, after asking once for permission to set alarms.
    struct AuthorizingScheduler: AlarmScheduling {
        let real = AlarmKitScheduler()

        func scheduledIDs() async throws -> Set<UUID> { try await real.scheduledIDs() }
        func schedule(_ alarm: DesiredAlarm) async throws {
            if AlarmManager.shared.authorizationState == .notDetermined {
                _ = try? await AlarmManager.shared.requestAuthorization()
            }
            try await real.schedule(alarm)
        }
        func cancel(_ id: UUID) async throws { try await real.cancel(id) }
        func ringingIDs() async throws -> Set<UUID> { try await real.ringingIDs() }
        func stop(_ id: UUID) async throws { try await real.stop(id) }
    }

    struct DemoPermissions: AlarmPermissions {
        func current() async -> AlarmPermission { .allowed }
        func request() async -> AlarmPermission { .allowed }
    }
#endif
