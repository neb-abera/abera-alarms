import ActivityKit
import AlarmCore
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

/// The phone's alarm system: AlarmKit. An alarm scheduled here rings at its
/// time through the silent switch and Focus, with or without a connection.
struct AlarmKitScheduler: AlarmScheduling {
    func scheduledIDs() async throws -> Set<UUID> {
        Set(try AlarmManager.shared.alarms.map(\.id))
    }

    func schedule(_ alarm: DesiredAlarm) async throws {
        if let routine = alarm.routine {
            try await scheduleRoutine(alarm, routine)
            return
        }
        let snoozeMinutes = alarm.snoozeMinutes ?? 9
        let alert = AlarmPresentation.Alert(
            title: "\(AlarmText.title(for: alarm))", secondaryButton: Self.snoozeButton,
            secondaryButtonBehavior: .countdown)
        let countdown = AlarmPresentation.Countdown(title: "\(alarm.title), snoozing", pauseButton: nil)
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: nil),
            metadata: AlarmInfo(key: alarm.key),
            tintColor: .accentColor)
        // Snooze rings again after the countdown. Only Stop acknowledges.
        let configuration = AlarmManager.AlarmConfiguration<AlarmInfo>(
            countdownDuration: .init(preAlert: nil, postAlert: TimeInterval(snoozeMinutes * 60)),
            schedule: .fixed(alarm.fireAt),
            attributes: attributes,
            stopIntent: AcknowledgeAlarmIntent(key: alarm.key),
            secondaryIntent: nil,
            sound: Self.sound(alarm.sound))
        _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
    }

    static let snoozeButton = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")

    /// A bundled sound, or the iPhone's own.
    static func sound(_ name: String) -> AlertConfiguration.AlertSound {
        name == "default" ? .default : .named("\(name).caf")
    }

    /// A Clock-style alarm: the time of day, the weekdays it repeats on, and
    /// Snooze, which counts down on the Lock Screen and rings again.
    private func scheduleRoutine(_ alarm: DesiredAlarm, _ routine: RoutineSchedule) async throws {
        let alert = AlarmPresentation.Alert(
            title: "\(alarm.title)", secondaryButton: Self.snoozeButton, secondaryButtonBehavior: .countdown)
        let countdown = AlarmPresentation.Countdown(title: "\(alarm.title), snoozing", pauseButton: nil)
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: nil),
            metadata: AlarmInfo(key: alarm.key),
            tintColor: .accentColor)
        let repeats: Alarm.Schedule.Relative.Recurrence =
            routine.days.isEmpty ? .never : .weekly(routine.days.compactMap(Self.weekday))
        let schedule = Alarm.Schedule.relative(
            .init(time: .init(hour: routine.hour, minute: routine.minute), repeats: repeats))
        let configuration = AlarmManager.AlarmConfiguration<AlarmInfo>(
            countdownDuration: .init(preAlert: nil, postAlert: TimeInterval(routine.snoozeMinutes * 60)),
            schedule: schedule,
            attributes: attributes,
            stopIntent: AcknowledgeRoutineIntent(routineID: alarm.id.uuidString),
            secondaryIntent: nil,
            sound: Self.sound(alarm.sound))
        _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
    }

    /// ISO weekday, Monday 1 to Sunday 7.
    static func weekday(_ iso: Int) -> Locale.Weekday? {
        switch iso {
        case 1: .monday
        case 2: .tuesday
        case 3: .wednesday
        case 4: .thursday
        case 5: .friday
        case 6: .saturday
        case 7: .sunday
        default: nil
        }
    }

    func cancel(_ id: UUID) async throws {
        try AlarmManager.shared.cancel(id: id)
    }

    func ringingIDs() async throws -> Set<UUID> {
        Set(
            try AlarmManager.shared.alarms.filter { alarm in
                switch alarm.state {
                case .alerting, .countdown, .paused: true
                case .scheduled: false
                @unknown default: false
                }
            }
            .map(\.id))
    }

    /// A repeating alarm is set again for its next time. A one-time alarm is removed.
    func stop(_ id: UUID) async throws {
        try AlarmManager.shared.stop(id: id)
    }
}

/// Whether the owner let this app ring alarms.
struct AlarmKitPermissions: AlarmPermissions {
    func current() async -> AlarmPermission {
        Self.map(AlarmManager.shared.authorizationState)
    }

    func request() async -> AlarmPermission {
        guard let state = try? await AlarmManager.shared.requestAuthorization() else { return .denied }
        return Self.map(state)
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlarmPermission {
        switch state {
        case .authorized: .allowed
        case .denied: .denied
        case .notDetermined: .notAsked
        @unknown default: .denied
        }
    }
}

/// The Stop button on a ringing alarm. The system runs it in the app's
/// process, woken in the background if it was not running.
struct AcknowledgeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Acknowledge alarm"
    static let isDiscoverable = false

    @Parameter(title: "Occurrence")
    var key: String

    init() {}

    init(key: String) {
        self.key = key
    }

    func perform() async throws -> some IntentResult {
        _ = await Dependencies.shared.sync.acknowledge(key: key)
        return .result()
    }
}

/// The Stop button on a ringing routine alarm. The ring stopped is worked
/// out in AlarmCore from the routine and the time, and acknowledged on
/// abera.tech so the browser and Pushover stop too.
struct AcknowledgeRoutineIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Acknowledge routine alarm"
    static let isDiscoverable = false

    @Parameter(title: "Routine")
    var routineID: String

    init() {}

    init(routineID: String) {
        self.routineID = routineID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: routineID) {
            _ = await Dependencies.shared.sync.acknowledgeRoutine(id: id)
        }
        return .result()
    }
}
