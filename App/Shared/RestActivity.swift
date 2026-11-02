import ActivityKit
import AppIntents
import Foundation

/// The rest timer on the Lock Screen and in the Dynamic Island. Shared with
/// the widget extension, which draws it.
struct RestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The full rest, in seconds.
        var length: Int
        /// When the running countdown reaches 0:00. Nil while none runs.
        var endsAt: Date?
    }
}

/// The Lock Screen's minus and plus buttons. iOS runs `perform` in the
/// app's process, woken in the background if it was not running. The
/// widget extension compiles this type for its buttons and never runs it.
struct AdjustRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Change the rest"
    static let isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET
            await RestModel.shared.adjust(by: seconds)
        #endif
        return .result()
    }
}

/// The Lock Screen's Restart button, and the Start rest control: counts
/// down the full rest again, and puts it on the Lock Screen when it is not.
struct RestartRestIntent: LiveActivityIntent, LiveActivityStartingIntent {
    static let title: LocalizedStringResource = "Restart the rest"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET
            await RestModel.shared.restart()
        #endif
        return .result()
    }
}
