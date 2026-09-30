import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island while a routine alarm is snoozed.
/// AlarmKit needs this to show a countdown.
@main
struct AlarmsWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlarmCountdownActivity()
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
