import ActivityKit
import AlarmCore
import AlarmKit
import SwiftUI

/// The rest timer on the Timer tab: the countdown, minus and plus, Restart
/// and End. Restart puts it on the Lock Screen, where the same buttons work
/// with the phone locked.
struct RestPanel: View {
    var onScreen = true
    private let model = RestModel.shared

    var body: some View {
        let rest = model.rest
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: onScreen && rest.endsAt != nil ? 0.25 : 86_400)) { context in
                HStack(spacing: 12) {
                    step("minus", by: -Rest.step)
                    VStack(spacing: 0) {
                        Text(rest.running(at: context.date) ? "Rest" : rest.endsAt == nil ? "Rest length" : "Rest over")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(rest.clock(at: context.date))
                            .font(.system(size: 40, weight: .light).monospacedDigit())
                            .accessibilityIdentifier("rest-clock")
                    }
                    .frame(maxWidth: .infinity)
                    step("plus", by: Rest.step)
                }
            }
            HStack(spacing: 16) {
                Button {
                    Task { await model.restart() }
                } label: {
                    Text(rest.endsAt == nil ? "Start rest" : "Restart")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .accessibilityIdentifier("rest-restart")
                Button {
                    Task { await model.end() }
                } label: {
                    Text("End")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(rest.endsAt == nil && !model.onLockScreen)
                .accessibilityIdentifier("rest-end")
            }
            if let problem = model.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("rest-problem")
            }
        }
        .padding(.horizontal)
    }

    private func step(_ name: String, by seconds: Int) -> some View {
        Button {
            Task { await model.adjust(by: seconds) }
        } label: {
            Image(systemName: "\(name).circle.fill")
                .font(.system(size: 40))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.indigo)
        .accessibilityLabel(seconds < 0 ? "\(Rest.step) seconds less" : "\(Rest.step) seconds more")
        .accessibilityIdentifier("rest-\(name)")
    }
}

/// The rest timer's state, its alarm, and its Live Activity. One for the
/// app, so the Lock Screen's buttons and the Timer tab change the same rest.
@MainActor
@Observable
final class RestModel {
    static let shared = RestModel()
    static let key = "rest"
    /// The alarm that rings at 0:00. The alarm sync leaves it alone.
    nonisolated static let alarmID = UUID(uuidString: "5E57A1A2-7E57-4000-8000-000000000001")!

    private(set) var rest: Rest
    /// True while the rest is on the Lock Screen.
    private(set) var onLockScreen: Bool
    /// Why the rest is not on the Lock Screen, when Start rest could not
    /// put it there.
    private(set) var problem: String?
    @ObservationIgnored private let store: UserDefaults?
    /// Off in -demo mode: the UI tests ring nothing and show nothing.
    @ObservationIgnored private let system: Bool

    private init() {
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        store = demo ? nil : .standard
        system = !demo
        rest = store?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Rest.self, from: $0) } ?? Rest()
        onLockScreen = !demo && !Activity<RestAttributes>.activities.isEmpty
    }

    func adjust(by seconds: Int) async {
        rest.adjust(by: seconds, at: Date())
        await changed(show: false)
    }

    /// Counts down the full rest and puts it on the Lock Screen.
    func restart() async {
        rest.restart(at: Date())
        await changed(show: true)
    }

    /// Ends the countdown and puts the rest back to its 1:30 default.
    func resetToDefault() async {
        await end()
        rest = Rest()
        if let data = try? JSONEncoder().encode(rest) { store?.set(data, forKey: Self.key) }
    }

    /// Ends the countdown and takes it off the Lock Screen.
    func end() async {
        rest.end()
        if let data = try? JSONEncoder().encode(rest) { store?.set(data, forKey: Self.key) }
        guard system else { return }
        try? AlarmManager.shared.cancel(id: Self.alarmID)
        for activity in Activity<RestAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        onLockScreen = false
    }

    private func changed(show: Bool) async {
        if let data = try? JSONEncoder().encode(rest) { store?.set(data, forKey: Self.key) }
        guard system else { return }
        await ring()
        let content = ActivityContent(
            state: RestAttributes.ContentState(length: rest.length, endsAt: rest.endsAt),
            staleDate: rest.endsAt)
        if let activity = Activity<RestAttributes>.activities.first {
            await activity.update(content)
        } else if show {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                problem =
                    "Live Activities are off for Alarms, so the rest is not on the Lock Screen. Settings > Apps > Alarms > Live Activities."
                return
            }
            do {
                _ = try Activity.request(attributes: RestAttributes(), content: content)
                onLockScreen = true
                problem = nil
            } catch {
                problem = "The rest could not go on the Lock Screen: \(error.localizedDescription)"
            }
        }
    }

    /// Sets the alarm for 0:00, through the silent switch and Focus.
    private func ring() async {
        try? AlarmManager.shared.cancel(id: Self.alarmID)
        guard let endsAt = rest.endsAt, endsAt > Date() else { return }
        let alert = AlarmPresentation.Alert(title: "Rest over", secondaryButton: nil, secondaryButtonBehavior: nil)
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: AlarmInfo(key: "rest"),
            tintColor: .indigo)
        let configuration = AlarmManager.AlarmConfiguration<AlarmInfo>(
            countdownDuration: nil,
            schedule: .fixed(endsAt),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default)
        _ = try? await AlarmManager.shared.schedule(id: Self.alarmID, configuration: configuration)
    }
}
