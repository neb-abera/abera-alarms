import ActivityKit
import AppIntents
import Foundation

/// The workout clock on the Lock Screen and in the Dynamic Island, from
/// Start until Stop. Shared with the widget extension, which draws it.
struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The set the clock is timing, from 1.
        var set: Int
        /// When the running set's clock read 0:00. Nil while paused.
        var startedAt: Date?
        /// The clock while paused, in seconds.
        var held: TimeInterval
    }
}

/// The Start workout control: starts the clock, or resumes it, and puts it
/// on the Lock Screen. A running clock keeps running. iOS runs `perform` in
/// the app's process, woken in the background if it was not running. The
/// widget extension compiles these intents for its buttons and never runs
/// them.
struct StartWorkoutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start the workout"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET
            await WorkoutModel.shared.start()
            await WorkoutModel.shared.settled()
        #endif
        return .result()
    }
}

/// The Lock Screen's Pause and Resume button.
struct StartOrPauseWorkoutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start or pause the workout"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET
            await WorkoutModel.shared.startOrPause()
            await WorkoutModel.shared.settled()
        #endif
        return .result()
    }
}

/// The Lock Screen's Next set button: records the set and starts the next
/// at 0:00.
struct NextSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next set"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET
            await WorkoutModel.shared.nextSet()
            await WorkoutModel.shared.settled()
        #endif
        return .result()
    }
}

/// The Lock Screen's Stop button: records the set, stops the clock, and
/// takes the workout off the Lock Screen.
struct StopWorkoutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop the workout"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET
            await WorkoutModel.shared.stop()
            await WorkoutModel.shared.settled()
        #endif
        return .result()
    }
}
