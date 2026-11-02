import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island: a snoozed alarm's countdown, which
/// AlarmKit needs to show it, and the Timer tab's rest countdown.
@main
struct AlarmsWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlarmCountdownActivity()
        RestActivity()
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
