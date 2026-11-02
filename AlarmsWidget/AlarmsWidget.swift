import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island: a snoozed alarm's countdown, which
/// AlarmKit needs to show it, and the Timer tab's workout clock and rest
/// countdown.
@main
struct AlarmsWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlarmCountdownActivity()
        WorkoutActivity()
        RestActivity()
        WorkoutControl()
        RestControl()
    }
}

/// Start workout as a Lock Screen or Control Center control. It starts the
/// clock and puts it on the Lock Screen, without opening the app.
struct WorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "tech.abera.alarms.workout") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Start workout", systemImage: "stopwatch")
            }
        }
        .displayName("Start workout")
        .description("Starts the workout timer on the Lock Screen.")
    }
}

/// The workout clock on the Lock Screen, with Pause or Resume, Next set and
/// Stop. The buttons work with the phone locked. The clock counts up on its
/// own, with no update from the app.
struct WorkoutActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "stopwatch")
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(WorkoutText.title(context.state))
                            .font(.headline)
                        WorkoutClock(state: context.state)
                            .font(.largeTitle.monospacedDigit())
                    }
                    Spacer()
                }
                WorkoutButtons(state: context.state)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(WorkoutText.title(context.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutClock(state: context.state)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutButtons(state: context.state)
                }
            } compactLeading: {
                Text("S\(context.state.set)")
            } compactTrailing: {
                WorkoutClock(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "stopwatch")
            }
        }
    }
}

enum WorkoutText {
    /// "Set 3", or "Set 3 · Paused".
    static func title(_ state: WorkoutAttributes.ContentState) -> String {
        state.startedAt == nil ? "Set \(state.set) · Paused" : "Set \(state.set)"
    }

    /// "0:42", or "1:02:03" past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        let (hours, minutes, secs) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Counts up from the set's start while it runs. Paused, it shows the held
/// time.
struct WorkoutClock: View {
    let state: WorkoutAttributes.ContentState

    var body: some View {
        if let startedAt = state.startedAt {
            Text(startedAt, style: .timer)
        } else {
            Text(WorkoutText.clock(state.held))
        }
    }
}

struct WorkoutButtons: View {
    let state: WorkoutAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: StartOrPauseWorkoutIntent()) {
                Label(
                    state.startedAt == nil ? "Resume" : "Pause",
                    systemImage: state.startedAt == nil ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .tint(state.startedAt == nil ? .green : .orange)
            Button(intent: NextSetIntent()) {
                Label("Next set", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.blue)
            Button(intent: StopWorkoutIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .buttonStyle(.borderedProminent)
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleOnly)
    }
}

/// Start rest as a Lock Screen or Control Center control. It counts down
/// the full rest and puts it on the Lock Screen, without opening the app.
struct RestControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "tech.abera.alarms.rest") {
            ControlWidgetButton(action: RestartRestIntent()) {
                Label("Start rest", systemImage: "timer")
            }
        }
        .displayName("Start rest")
        .description("Counts down your rest on the Lock Screen.")
    }
}

struct AlarmCountdownActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmInfo>.self) { context in
            HStack {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                    CountdownText(state: context.state)
                        .font(.title.monospacedDigit())
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state)
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "zzz")
            } compactTrailing: {
                CountdownText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }
}

struct CountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(countdown.fireDate, style: .timer)
        case .paused:
            Text("Paused")
        case .alert:
            Text("Ringing")
        @unknown default:
            Text("")
        }
    }
}

/// The rest countdown on the Lock Screen, with minus and plus 15 s and
/// Restart. The buttons work with the phone locked. At 0:00 the rest's
/// alarm rings, and the Lock Screen reads "Rest over" until Restart.
struct RestActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(RestText.title(context.state, stale: context.isStale))
                            .font(.headline)
                        RestClock(state: context.state, stale: context.isStale)
                            .font(.largeTitle.monospacedDigit())
                    }
                    Spacer()
                }
                RestButtons(state: context.state, stale: context.isStale)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(RestText.title(context.state, stale: context.isStale))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestClock(state: context.state, stale: context.isStale)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestButtons(state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
            } compactTrailing: {
                RestClock(state: context.state, stale: context.isStale)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

enum RestText {
    /// True while the countdown has time left. The stale date is 0:00.
    static func running(_ state: RestAttributes.ContentState, stale: Bool) -> Bool {
        guard let endsAt = state.endsAt else { return false }
        return !stale && endsAt > .now
    }

    static func title(_ state: RestAttributes.ContentState, stale: Bool) -> String {
        if running(state, stale: stale) { return "Rest" }
        return state.endsAt == nil ? "Rest length" : "Rest over"
    }

    /// "1:30".
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Counts down to 0:00 on its own, with no update from the app. While none
/// runs it shows the rest's length.
struct RestClock: View {
    let state: RestAttributes.ContentState
    let stale: Bool

    var body: some View {
        if RestText.running(state, stale: stale), let endsAt = state.endsAt {
            Text(timerInterval: Date.now...endsAt, countsDown: true)
        } else if state.endsAt == nil {
            Text(RestText.clock(state.length))
        } else {
            Text("0:00")
        }
    }
}

struct RestButtons: View {
    let state: RestAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: AdjustRestIntent(seconds: -15)) {
                Label("15 s", systemImage: "minus")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: AdjustRestIntent(seconds: 15)) {
                Label("15 s", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: RestartRestIntent()) {
                Label(
                    RestText.running(state, stale: stale) ? "Restart" : "Start",
                    systemImage: "arrow.counterclockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .tint(.indigo)
        }
        .buttonStyle(.borderedProminent)
        .font(.subheadline.weight(.semibold))
        .tint(.gray)
    }
}
