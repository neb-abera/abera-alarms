import ActivityKit
import AlarmCore
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

/// What an alarm carries back to the app when it rings.
struct AlarmInfo: AlarmMetadata {
    var key: String
}

/// The phone's alarm system: AlarmKit. An alarm scheduled here rings at its
/// time through the silent switch and Focus, with or without a connection.
struct AlarmKitScheduler: AlarmScheduling {
    func scheduledIDs() async throws -> Set<UUID> {
        Set(try AlarmManager.shared.alarms.map(\.id))
    }

    func schedule(_ alarm: DesiredAlarm) async throws {
        let alert = AlarmPresentation.Alert(
            title: "\(AlarmText.title(for: alarm))", secondaryButton: nil, secondaryButtonBehavior: nil)
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: AlarmInfo(key: alarm.key),
            tintColor: .accentColor)
        let configuration = AlarmManager.AlarmConfiguration<AlarmInfo>.alarm(
            schedule: .fixed(alarm.fireAt),
            attributes: attributes,
            stopIntent: AcknowledgeAlarmIntent(key: alarm.key),
            secondaryIntent: nil,
            sound: .default)
        _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
    }

    func cancel(_ id: UUID) async throws {
        try AlarmManager.shared.cancel(id: id)
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
